//! Far terrain (level of detail): a tile of the world `CS` cells across (and
//! the world's full height) at `2^level` blocks a cell, meshed coarsely in each
//! block's average colour, for the distance beyond the full-detail chunks.
//!
//! - A cell is solid when at least half of its sampled blocks are opaque (all
//!   of them for 2-block cells, 8 spread through bigger ones); its colour is
//!   the topmost block in its middle column (top faces take that block's top
//!   colour, the sides its side colour).
//! - Water that's mostly in a cell shows as its top surface.
//! - Trees aren't here: they're block models (trunks) and decorations
//!   (canopies), which the game draws far off as sprites (FarTrees).
//! - Only faces something could see are made: a face below the ground's
//!   surface (`World::lod_cave_level`) whose outside has no light at all (a
//!   dark cave) is skipped. Above it they're all kept: a floating island's
//!   underside is in the dark, but you see it from below.
//!
//! Vertex layout consumed by `shaders/lod.gdshader`:
//! - COLOR = (albedo red, green, blue (face shade baked in), sun light 0..1)
//! - UV    = (block light 0..1, 0)

use crate::mesher::Surface;
use std::sync::RwLock;
use crate::world::{unpack_light, World, CS, LIQ_WATER};

/// How bright each face direction is (+x, -x, +y, -y, +z, -z).
const SHADE: [f32; 6] = [0.8, 0.8, 1.0, 0.55, 0.7, 0.7];
const DIRS: [[i32; 3]; 6] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
const WATER_COLOR: [f32; 3] = [0.16, 0.36, 0.78];

#[derive(Clone, Copy, PartialEq)]
enum Cell {
    Air,
    /// Solid ground: top colour, side colour.
    Solid([f32; 3], [f32; 3]),
    Water,
}

fn rgb(c: [u8; 3]) -> [f32; 3] {
    [c[0] as f32 / 255.0, c[1] as f32 / 255.0, c[2] as f32 / 255.0]
}

/// The cell at cell coordinates (cx, cy, cz) of a level with `s`-block cells.
fn sample_cell(w: &World, s: i32, (cx, cy, cz): (i32, i32, i32)) -> Cell {
    let (bx, by, bz) = (cx * s, cy * s, cz * s);
    if !w.in_bounds(bx, 0, bz) && !w.in_bounds(bx + s - 1, 0, bz + s - 1) {
        return Cell::Air;
    }
    // Sample points within the cell.
    let offs: Vec<i32> = if s <= 2 { (0..s).collect() } else { vec![s / 4, 3 * s / 4] };
    let (mut opaque, mut water, mut total) = (0, 0, 0);
    for &dy in &offs {
        for &dz in &offs {
            for &dx in &offs {
                let (x, y, z) = (bx + dx, by + dy, bz + dz);
                total += 1;
                if w.is_opaque(x, y, z) {
                    opaque += 1;
                } else {
                    let (t, amount) = w.liquid_at(x, y, z);
                    if t == LIQ_WATER && amount > 0 {
                        water += 1;
                    }
                }
            }
        }
    }
    if opaque * 2 >= total && opaque > 0 {
        // The topmost opaque block in the middle column gives the colour.
        let (mx, mz) = (bx + s / 2, bz + s / 2);
        let mut id = 0u16;
        for y in (by..by + s).rev() {
            if w.is_opaque(mx, y, mz) {
                id = w.get(mx, y, mz);
                break;
            }
        }
        if id == 0 {
            // The middle column's open: any opaque sample.
            'find: for &dy in offs.iter().rev() {
                for &dz in &offs {
                    for &dx in &offs {
                        if w.is_opaque(bx + dx, by + dy, bz + dz) {
                            id = w.get(bx + dx, by + dy, bz + dz);
                            break 'find;
                        }
                    }
                }
            }
        }
        let d = w.def(id);
        // Better Grass: far grass hillsides are green down their sides too.
        let side = if d.better_grass { d.color_top } else { d.color_side };
        return Cell::Solid(rgb(d.color_top), rgb(side));
    }
    if water * 2 >= total && water > 0 {
        return Cell::Water;
    }
    Cell::Air
}

/// The light on a face: the brightest open block in the cell outside it (a
/// coarse cell doesn't follow the ground, so a single block just outside the
/// face is often inside it, and dark). Samples a few points across the
/// outside cell and through its depth; only if every one is solid or dark is
/// the face dark.
fn face_light(w: &World, s: i32, (cx, cy, cz): (i32, i32, i32), d: [i32; 3]) -> [f32; 4] {
    let offs: Vec<i32> = if s <= 2 { (0..s).collect() } else { vec![0, s / 2, s - 1] };
    let base = [(cx + d[0]) * s, (cy + d[1]) * s, (cz + d[2]) * s];
    let mut best = [0f32; 4];
    let mut best_sum = -1.0f32;
    for &a in &offs {
        for &b in &offs {
            for &c in &offs {
                let (x, y, z) = (base[0] + a, base[1] + b, base[2] + c);
                if w.is_opaque(x, y, z) {
                    continue;
                }
                // Past the world's edge (sides; not under it) is open sky.
                let l = if !w.in_bounds(x, y.max(0), z) && y >= 0 {
                    [0.0, 0.0, 0.0, 1.0]
                } else {
                    let [sun, r, g, bl] = unpack_light(w.light_at(x, y, z));
                    [r as f32 / 15.0, g as f32 / 15.0, bl as f32 / 15.0, sun as f32 / 15.0]
                };
                let sum = l[0] + l[1] + l[2] + l[3] * 1.5;
                if sum > best_sum {
                    best_sum = sum;
                    best = l;
                }
            }
        }
    }
    best
}

/// Mesh of LOD tile (tx, tz) at `level` (cells of 2^level blocks), with
/// vertices relative to the tile's corner (tx, 0, tz) * CS * 2^level. The
/// world is read-locked one layer of cells at a time.
pub fn mesh_lod(world: &RwLock<World>, level: u32, tx: i32, tz: i32) -> Surface {
    let s = 1i32 << level;
    let n = CS;
    let ny = (world.read().unwrap().sy + s - 1) / s;
    let (ox, oz) = (tx * n, tz * n); // cell origin
    // Cells of the tile plus a border of one.
    let (gx, gy, gz) = (n + 2, ny + 2, n + 2);
    let idx = |x: i32, y: i32, z: i32| ((x + 1) + (z + 1) * gx + (y + 1) * gx * gz) as usize;
    let mut cells = vec![Cell::Air; (gx * gy * gz) as usize];
    for y in 0..ny {
        let w = world.read().unwrap();
        for z in -1..=n {
            for x in -1..=n {
                cells[idx(x, y, z)] = sample_cell(&w, s, (ox + x, y, oz + z));
            }
        }
    }
    let mut out = Surface::default();
    let sf = s as f32;
    for y in 0..ny {
        let w = world.read().unwrap();
        let w = &*w;
        for z in 0..n {
            for x in 0..n {
                let cell = cells[idx(x, y, z)];
                let global = (ox + x, y, oz + z);
                match cell {
                    Cell::Air => {}
                    Cell::Solid(top, side) => {
                        for (k, d) in DIRS.iter().enumerate() {
                            if matches!(cells[idx(x + d[0], y + d[1], z + d[2])], Cell::Solid(..)) {
                                continue;
                            }
                            let l = face_light(w, s, global, *d);
                            if l[0] + l[1] + l[2] + l[3] <= 0.0 && (y + d[1]) * s < w.lod_cave_level {
                                continue; // nobody sees a cave's face in the dark
                            }
                            let base = if d[1] > 0 { top } else { side };
                            let c = [base[0] * SHADE[k], base[1] * SHADE[k], base[2] * SHADE[k]];
                            add_face(&mut out, [x as f32 * sf, y as f32 * sf, z as f32 * sf], sf, *d, c, l);
                        }
                    }
                    Cell::Water => {
                        if cells[idx(x, y + 1, z)] == Cell::Air {
                            let l = face_light(w, s, global, [0, 1, 0]);
                            add_face(&mut out, [x as f32 * sf, (y as f32 + 0.85) * sf, z as f32 * sf], sf, [0, 1, 0], WATER_COLOR, l);
                        }
                    }
                }
            }
        }
    }
    out
}

/// One face of a cube `size` across at corner `p`, facing `d`.
fn add_face(s: &mut Surface, p: [f32; 3], size: f32, d: [i32; 3], c: [f32; 3], l: [f32; 4]) {
    // Corners in the face's plane, counter-clockwise seen from outside.
    let axis = d.iter().position(|&v| v != 0).unwrap();
    let (u, v) = ((axis + 1) % 3, (axis + 2) % 3);
    let plane = if d[axis] > 0 { size } else { 0.0 };
    let mut corners = [[0f32; 3]; 4];
    for (k, (a, b)) in [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)].into_iter().enumerate() {
        let mut q = p;
        q[axis] += plane;
        q[u] += a * size;
        q[v] += b * size;
        corners[k] = q;
    }
    if d[axis] < 0 {
        corners.reverse();
    }
    let base = s.verts.len() as i32;
    let n = [d[0] as f32, d[1] as f32, d[2] as f32];
    let block = l[0].max(l[1]).max(l[2]);
    for q in corners {
        s.verts.push(q);
        s.normals.push(n);
        s.colors.push([c[0], c[1], c[2], l[3]]);
        s.uvs.push([block, 0.0]);
        s.uv2s.push([0.0, 0.0]);
    }
    // Godot's front faces are clockwise.
    s.indices.extend_from_slice(&[base, base + 2, base + 1, base, base + 3, base + 2]);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::tests::test_world;

    #[test]
    fn far_terrain_meshes_the_ground_coarsely() {
        let w = RwLock::new(test_world());
        for level in 1..=3 {
            let m = mesh_lod(&w, level, 0, 0);
            assert!(!m.is_empty(), "level {level} has faces");
            let s = (1 << level) as f32;
            // Every vertex is on the level's cell grid, and the ground's top
            // (y 32) is there.
            assert!(m.verts.iter().all(|v| (v[0] / s).fract() == 0.0 && (v[2] / s).fract() == 0.0));
            assert!(m.verts.iter().any(|v| (v[1] - 32.0).abs() < s), "level {level}: the ground's top");
            // Upward faces are lit by the sun.
            assert!(m.normals.iter().zip(&m.colors).any(|(n, c)| n[1] > 0.5 && c[3] > 0.9));
        }
    }

    #[test]
    fn a_hills_faces_out_in_the_open_are_lit() {
        // A stepped hill on the ground (steps that don't line up with the
        // cells): every face of it is out in the open, so none may be dark.
        let mut w = test_world();
        let stone = w.get(10, 31, 10);
        for x in 3..40 {
            for z in 3..40 {
                let h = 32 + ((x / 3 + z / 5) % 7);
                for y in 32..h {
                    w.set(x, y, z, stone);
                }
            }
        }
        w.compute_all_light();
        w.lod_cave_level = 20;
        let w = RwLock::new(w);
        for level in 1..=3 {
            let m = mesh_lod(&w, level, 0, 0);
            let dark = m.colors.iter().zip(&m.verts).filter(|(c, v)| v[1] >= 32.0 && c[3] <= 0.0).count();
            assert_eq!(dark, 0, "level {level}: {dark} vertices of the hill are dark");
        }
    }
}
