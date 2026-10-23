//! Chunk meshing: culled cube faces with smooth per-vertex light and ambient
//! occlusion, plus crossed quads for plants/torches.
//!
//! Vertex layout consumed by `shaders/voxel.gdshader`:
//! - COLOR = (block red, block green, block blue, sun) light in 0..1
//! - UV    = face texture coordinates
//! - UV2   = (texture array layer, ambient occlusion 0..1)

use crate::world::{ramp_height, CS, RAMP_STEPS, SHAPE_CEILING, SHAPE_FULL, SHAPE_HALF, SHAPE_RAMP, LIQ_HONEY, LIQ_LAVA, LIQ_MAX, LIQ_WATER, RENDER_CROSS, RENDER_CUBE, RENDER_CUTOUT, RENDER_NONE, World, unpack_light};

/// Texture layer meaning "don't draw this face" (sprite furniture tops).
pub const NO_TEX: u16 = u16::MAX;

#[derive(Default)]
pub struct Surface {
    pub verts: Vec<[f32; 3]>,
    pub normals: Vec<[f32; 3]>,
    pub colors: Vec<[f32; 4]>,
    pub uvs: Vec<[f32; 2]>,
    pub uv2s: Vec<[f32; 2]>,
    pub indices: Vec<i32>,
}

impl Surface {
    pub fn is_empty(&self) -> bool {
        self.indices.is_empty()
    }

    fn quad(&mut self, v: [[f32; 3]; 4], n: [f32; 3], light: [[f32; 4]; 4], uv: [[f32; 2]; 4], layer: f32, ao: [f32; 4]) {
        let base = self.verts.len() as i32;
        for k in 0..4 {
            self.verts.push(v[k]);
            self.normals.push(n);
            self.colors.push(light[k]);
            self.uvs.push(uv[k]);
            self.uv2s.push([layer, ao[k]]);
        }
        // Corners arrive counter-clockwise seen from outside; Godot front faces
        // are clockwise. Flip the split diagonal to avoid AO anisotropy.
        if ao[0] + ao[2] >= ao[1] + ao[3] {
            self.indices.extend_from_slice(&[base, base + 2, base + 1, base, base + 3, base + 2]);
        } else {
            self.indices.extend_from_slice(&[base + 1, base + 3, base + 2, base + 1, base, base + 3]);
        }
    }
}

pub struct ChunkMesh {
    pub opaque: Surface,
    pub cutout: Surface,
    pub water: Surface,
    pub lava: Surface,
    pub honey: Surface,
}

/// (normal, tangent1, tangent2) with tangent1 x tangent2 = normal.
const FACES: [([i32; 3], [i32; 3], [i32; 3]); 6] = [
    ([1, 0, 0], [0, 1, 0], [0, 0, 1]),
    ([-1, 0, 0], [0, 0, 1], [0, 1, 0]),
    ([0, 1, 0], [0, 0, 1], [1, 0, 0]),
    ([0, -1, 0], [1, 0, 0], [0, 0, 1]),
    ([0, 0, 1], [1, 0, 0], [0, 1, 0]),
    ([0, 0, -1], [0, 1, 0], [1, 0, 0]),
];

fn hash3(x: i32, y: i32, z: i32) -> u32 {
    let mut h = (x as u32).wrapping_mul(0x8da6b343)
        ^ (y as u32).wrapping_mul(0xd8163841)
        ^ (z as u32).wrapping_mul(0xcb1ab31f);
    h ^= h >> 13;
    h = h.wrapping_mul(0x5bd1e995);
    h ^ (h >> 15)
}

fn light_f(l: u16) -> [f32; 4] {
    let [s, r, g, b] = unpack_light(l);
    [r as f32 / 15.0, g as f32 / 15.0, b as f32 / 15.0, s as f32 / 15.0]
}

pub fn mesh_chunk(w: &World, cx: i32, cy: i32, cz: i32) -> ChunkMesh {
    let mut opaque = Surface::default();
    let mut cutout = Surface::default();
    let mut water = Surface::default();
    let mut lava = Surface::default();
    let mut honey = Surface::default();
    let (ox, oy, oz) = (cx * CS, cy * CS, cz * CS);

    for lz in 0..CS {
        for lx in 0..CS {
            for ly in 0..CS {
                let (x, y, z) = (ox + lx, oy + ly, oz + lz);
                if !w.in_bounds(x, y, z) {
                    continue;
                }
                let i = w.idx(x, y, z);
                if w.liquid[i] != 0 {
                    let (t, _) = crate::world::liq_unpack(w.liquid[i]);
                    let surf = match t {
                        LIQ_LAVA => &mut lava,
                        LIQ_HONEY => &mut honey,
                        _ => &mut water,
                    };
                    add_liquid(w, surf, (x, y, z), [lx as f32, ly as f32, lz as f32], t);
                }
                let id = w.blocks[i];
                if id == 0 {
                    continue;
                }
                let def = w.def(id);
                let variant = if def.variants > 1 {
                    (hash3(x, y, z) % def.variants as u32) as u16
                } else {
                    0
                };
                let p = [lx as f32, ly as f32, lz as f32];
                match def.render {
                    RENDER_NONE => {}
                    RENDER_CROSS => {
                        let l = light_f(w.light_at(x, y, z));
                        let layer = (def.tex[1] + variant) as f32;
                        // Plants and debris ("vary"): mirrored in about half the cells.
                        let flip = def.vary && (hash3(x, y, z) >> 9) & 1 == 1;
                        add_cross(&mut cutout, p, l, layer, flip);
                    }
                    RENDER_CUBE if w.shape_at(x, y, z) != SHAPE_FULL => {
                        add_shaped(w, &mut opaque, (x, y, z), p, w.shape_at(x, y, z), def.tex, variant);
                    }
                    RENDER_CUBE | RENDER_CUTOUT => {
                        let surf = if def.render == RENDER_CUBE {
                            &mut opaque
                        } else {
                            &mut cutout
                        };
                        for (f, (n, t1, t2)) in FACES.iter().enumerate() {
                            let (nx, ny, nz) = (x + n[0], y + n[1], z + n[2]);
                            if w.is_opaque(nx, ny, nz) || (def.render == RENDER_CUTOUT && w.get(nx, ny, nz) == id) {
                                continue;
                            }
                            let tex = match f {
                                2 => def.tex[0],
                                3 => def.tex[2],
                                // Better Grass: the same grass a step down beside it.
                                _ if def.better_grass && w.get(nx, ny - 1, nz) == id => def.tex[0],
                                _ => def.tex[1],
                            };
                            if tex == NO_TEX {
                                continue;
                            }
                            add_face(w, surf, (x, y, z), p, *n, *t1, *t2, (tex + variant) as f32);
                        }
                    }
                    _ => {}
                }
            }
        }
    }
    ChunkMesh { opaque, cutout, water, lava, honey }
}

/// Liquid pouring through open space: nothing solid below and the cell below
/// isn't already full of the same liquid.
pub fn is_falling(w: &World, x: i32, y: i32, z: i32, t: u8) -> bool {
    if y == 0 || w.is_solid(x, y - 1, z) {
        return false;
    }
    let (bt, ba) = w.liquid_at(x, y - 1, z);
    ba < LIQ_MAX || bt != t
}

/// A falling stream: a column whose width follows the flow, with UV.y = world
/// height so the waterfall texture scrolls seamlessly down the whole fall.
/// UV2.x = 3 for stream sides, 4 for its top.
fn add_falling(w: &World, s: &mut Surface, (x, y, z): (i32, i32, i32), p: [f32; 3], t: u8) {
    let (_, a) = w.liquid_at(x, y, z);
    let half = (0.18 + 0.32 * (a as f32 / LIQ_MAX as f32).sqrt()).min(0.5);
    let (x0, x1, z0, z1) = (p[0] + 0.5 - half, p[0] + 0.5 + half, p[2] + 0.5 - half, p[2] + 0.5 + half);
    let (y0, y1) = (p[1], p[1] + 1.0);
    let wy = y as f32;
    let light = [light_f(w.light_at(x, y, z)); 4];
    let uv = [[0.0, wy], [1.0, wy], [1.0, wy + 1.0], [0.0, wy + 1.0]];
    let sides: [([f32; 3], [[f32; 3]; 4]); 4] = [
        ([1.0, 0.0, 0.0], [[x1, y0, z0], [x1, y0, z1], [x1, y1, z1], [x1, y1, z0]]),
        ([-1.0, 0.0, 0.0], [[x0, y0, z1], [x0, y0, z0], [x0, y1, z0], [x0, y1, z1]]),
        ([0.0, 0.0, 1.0], [[x1, y0, z1], [x0, y0, z1], [x0, y1, z1], [x1, y1, z1]]),
        ([0.0, 0.0, -1.0], [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0]]),
    ];
    for (n, v) in sides {
        s.quad(v, n, light, uv, 3.0, [1.0; 4]);
    }
    if liquid_height(w, x, y + 1, z, t).is_none() {
        let v = [[x0, y1, z0], [x0, y1, z1], [x1, y1, z1], [x1, y1, z0]];
        s.quad(v, [0.0, 1.0, 0.0], light, [[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [1.0, 0.0]], 4.0, [1.0; 4]);
    }
}

/// Surface height (0..1) of a liquid cell; 1 when the same liquid sits above it.
fn liquid_height(w: &World, x: i32, y: i32, z: i32, t: u8) -> Option<f32> {
    let (lt, a) = w.liquid_at(x, y, z);
    if a == 0 || lt != t {
        return None;
    }
    if w.liquid_at(x, y + 1, z) .0 == t && w.liquid_at(x, y + 1, z).1 > 0 {
        return Some(1.0);
    }
    Some((a as f32 / LIQ_MAX as f32).max(0.08) * 0.94)
}

/// Height at a top corner: the average over the (up to) four cells sharing it,
/// so neighbouring levels join into a smooth sloped surface. Empty cells pull
/// the corner down (edges of falls); solid ones, and those past the world's
/// edge (the sea goes on there), are ignored.
fn corner_height(w: &World, x: i32, y: i32, z: i32, cx: i32, cz: i32, t: u8) -> f32 {
    let mut sum = 0.0;
    let mut n = 0.0;
    for dx in [cx - 1, cx] {
        for dz in [cz - 1, cz] {
            let (nx, nz) = (x + dx, z + dz);
            if !w.in_bounds(nx, y, nz) {
                continue;
            }
            match liquid_height(w, nx, y, nz, t) {
                Some(h) => {
                    if h >= 1.0 {
                        return 1.0;
                    }
                    sum += h;
                    n += 1.0;
                }
                None => {
                    if !w.is_solid(nx, y, nz) && w.liquid_at(nx, y, nz).1 == 0 {
                        n += 1.0;
                    }
                }
            }
        }
    }
    if n == 0.0 { 0.0 } else { sum / n }
}

/// Liquid faces for one cell. UV.y on sides is depth below the liquid surface
/// (0 at the surface) so the shader can draw Terraria's surface band only at the
/// top; UV2 = (face: 0 top, 1 side, 2 bottom, unused).
fn add_liquid(w: &World, s: &mut Surface, (x, y, z): (i32, i32, i32), p: [f32; 3], t: u8) {
    let Some(h) = liquid_height(w, x, y, z, t) else { return };
    if is_falling(w, x, y, z, t) {
        add_falling(w, s, (x, y, z), p, t);
        return;
    }
    let light = light_f(w.light_at(x, y, z));
    let lights = [light; 4];
    // Corners never sag below 60% of the cell's own level, so edges slope at
    // drops without small puddles collapsing flat.
    let ch = |cx: i32, cz: i32| if h >= 1.0 { 1.0 } else { corner_height(w, x, y, z, cx, cz, t).max(h * 0.6) };
    let c00 = ch(0, 0);
    let c10 = ch(1, 0);
    let c11 = ch(1, 1);
    let c01 = ch(0, 1);
    // How far below the surface this cell's top is (stacked liquid above).
    let mut depth = 0.0;
    let mut yy = y + 1;
    while depth < 8.0 && liquid_height(w, x, yy, z, t).is_some() {
        depth += 1.0;
        yy += 1;
    }
    let above_same = liquid_height(w, x, y + 1, z, t).is_some();
    if !above_same && !(h >= 1.0 && w.is_opaque(x, y + 1, z)) {
        let v = [[p[0], p[1] + c00, p[2]], [p[0], p[1] + c01, p[2] + 1.0], [p[0] + 1.0, p[1] + c11, p[2] + 1.0], [p[0] + 1.0, p[1] + c10, p[2]]];
        let uv = [[p[0], p[2]], [p[0], p[2] + 1.0], [p[0] + 1.0, p[2] + 1.0], [p[0] + 1.0, p[2]]];
        s.quad(v, [0.0, 1.0, 0.0], lights, uv, 0.0, [1.0; 4]);
    }
    // Sides: (normal, corner a, corner b) going counter-clockwise seen from outside.
    let sides: [((i32, i32), [f32; 2], [f32; 2], f32, f32); 4] = [
        ((1, 0), [1.0, 0.0], [1.0, 1.0], c10, c11),
        ((-1, 0), [0.0, 1.0], [0.0, 0.0], c01, c00),
        ((0, 1), [1.0, 1.0], [0.0, 1.0], c11, c01),
        ((0, -1), [0.0, 0.0], [1.0, 0.0], c00, c10),
    ];
    for ((dx, dz), a, b, ha, hb) in sides {
        let (nx, nz) = (x + dx, z + dz);
        // No wall at the world's edge: the sea carries on past it (the game
        // draws the open sea out there).
        if w.is_opaque(nx, y, nz) || !w.in_bounds(nx, y, nz) {
            continue;
        }
        let bottom = match liquid_height(w, nx, y, nz, t) {
            Some(nh) => nh,
            None => 0.0,
        };
        if bottom >= ha.min(hb) - 0.001 {
            continue;
        }
        let va = [p[0] + a[0], p[2] + a[1]];
        let vb = [p[0] + b[0], p[2] + b[1]];
        let v = [[va[0], p[1] + bottom, va[1]], [vb[0], p[1] + bottom, vb[1]], [vb[0], p[1] + hb, vb[1]], [va[0], p[1] + ha, va[1]]];
        let u0 = if dx != 0 { a[1] } else { a[0] };
        let u1 = if dx != 0 { b[1] } else { b[0] };
        let uv = [[u0, depth + h - bottom], [u1, depth + h - bottom], [u1, depth + h - hb], [u0, depth + h - ha]];
        s.quad(v, [dx as f32, 0.0, dz as f32], lights, uv, 1.0, [1.0; 4]);
    }
    // Underside when hanging over air (falling liquid).
    if !w.is_solid(x, y - 1, z) && liquid_height(w, x, y - 1, z, t).is_none() {
        let v = [[p[0], p[1], p[2]], [p[0] + 1.0, p[1], p[2]], [p[0] + 1.0, p[1], p[2] + 1.0], [p[0], p[1], p[2] + 1.0]];
        let uv = [[p[0], p[2]], [p[0] + 1.0, p[2]], [p[0] + 1.0, p[2] + 1.0], [p[0], p[2] + 1.0]];
        s.quad(v, [0.0, -1.0, 0.0], lights, uv, 2.0, [1.0; 4]);
    }
    let _ = LIQ_WATER;
}

#[allow(clippy::too_many_arguments)]
fn add_face(w: &World, s: &mut Surface, (x, y, z): (i32, i32, i32), p: [f32; 3], n: [i32; 3], t1: [i32; 3], t2: [i32; 3], layer: f32) {
    let f = (x + n[0], y + n[1], z + n[2]);
    let face_light = w.light_at(f.0, f.1, f.2);
    let mut verts = [[0f32; 3]; 4];
    let mut uvs = [[0f32; 2]; 4];
    let mut lights = [[0f32; 4]; 4];
    let mut aos = [0f32; 4];
    let plane = [n[0].max(0), n[1].max(0), n[2].max(0)];

    for (k, (a, b)) in [(0, 0), (1, 0), (1, 1), (0, 1)].into_iter().enumerate() {
        let mut c = [0f32; 3];
        for i in 0..3 {
            c[i] = (plane[i] + a * t1[i] + b * t2[i]) as f32;
        }
        verts[k] = [p[0] + c[0], p[1] + c[1], p[2] + c[2]];
        uvs[k] = if n[1] != 0 {
            [c[0], c[2]]
        } else if n[0] != 0 {
            [c[2], 1.0 - c[1]]
        } else {
            [c[0], 1.0 - c[1]]
        };

        // Neighbours in the plane in front of the face, toward this corner.
        let su = if a == 1 { 1 } else { -1 };
        let sv = if b == 1 { 1 } else { -1 };
        let s1 = (f.0 + su * t1[0], f.1 + su * t1[1], f.2 + su * t1[2]);
        let s2 = (f.0 + sv * t2[0], f.1 + sv * t2[1], f.2 + sv * t2[2]);
        let cr = (s1.0 + sv * t2[0], s1.1 + sv * t2[1], s1.2 + sv * t2[2]);
        let o1 = w.is_opaque(s1.0, s1.1, s1.2);
        let o2 = w.is_opaque(s2.0, s2.1, s2.2);
        let oc = w.is_opaque(cr.0, cr.1, cr.2);
        let ao = if o1 && o2 { 0 } else { 3 - (o1 as i32 + o2 as i32 + oc as i32) };
        aos[k] = 0.4 + 0.6 * ao as f32 / 3.0;

        // Smooth light: average of the transparent cells around the corner.
        let mut sum = light_f(face_light);
        let mut count = 1.0;
        for (open, pos) in [(!o1, s1), (!o2, s2), (!oc && !(o1 && o2), cr)] {
            if open {
                let l = light_f(w.light_at(pos.0, pos.1, pos.2));
                for i in 0..4 {
                    sum[i] += l[i];
                }
                count += 1.0;
            }
        }
        lights[k] = sum.map(|v| v / count);
    }
    // An actuated block is drawn dark (Terraria draws inactive tiles dimmed).
    if w.is_inactive(x, y, z) {
        aos = aos.map(|a| a * INACTIVE_SHADE);
    }
    let nf = [n[0] as f32, n[1] as f32, n[2] as f32];
    s.quad(verts, nf, lights, uvs, layer, aos);
}

/// How bright an actuated block is drawn.
const INACTIVE_SHADE: f32 = 0.45;

/// A hammered block (Terraria's half blocks and slopes) in its own shape, with
/// its block's textures, lit flat by its own cell's light (it lets light in).
/// Faces against an opaque neighbour are skipped.
fn add_shaped(w: &World, s: &mut Surface, (x, y, z): (i32, i32, i32), p: [f32; 3], shape: u8, tex: [u16; 3], variant: u16) {
    let lit = |dx: i32, dy: i32, dz: i32| {
        let a = light_f(w.light_at(x, y, z));
        let b = light_f(w.light_at(x + dx, y + dy, z + dz));
        [a[0].max(b[0]), a[1].max(b[1]), a[2].max(b[2]), a[3].max(b[3])]
    };
    let layer = |t: u16| (t + variant) as f32;
    let open = |dx: i32, dy: i32, dz: i32| !w.is_opaque(x + dx, y + dy, z + dz);
    let at = |v: [f32; 3]| [p[0] + v[0], p[1] + v[1], p[2] + v[2]];
    // One face: corners (cell-local, counter-clockwise seen from outside; a
    // triangle repeats its last corner), uv from the face's own axes.
    let face = |s: &mut Surface, c: [[f32; 3]; 4], n: [f32; 3], t: u16, l: [f32; 4]| {
        let uv = c.map(|v| {
            if n[1].abs() > 0.99 {
                [v[0], v[2]]
            } else if n[0].abs() > n[2].abs() && n[1].abs() < 0.5 {
                [v[2], 1.0 - v[1]]
            } else if n[1].abs() < 0.5 {
                [v[0], 1.0 - v[1]]
            } else {
                [v[0], v[2]] // a slope: its top texture, seen from above
            }
        });
        s.quad(c.map(at), n, [l; 4], uv, layer(t), [1.0; 4]);
    };
    let (top, side, bottom) = (tex[0], tex[1], tex[2]);
    if shape == SHAPE_HALF {
        let h = 0.5;
        face(s, [[0.0, h, 0.0], [0.0, h, 1.0], [1.0, h, 1.0], [1.0, h, 0.0]], [0.0, 1.0, 0.0], top, lit(0, 1, 0));
        if open(0, -1, 0) {
            face(s, [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 0.0, 1.0], [0.0, 0.0, 1.0]], [0.0, -1.0, 0.0], bottom, lit(0, -1, 0));
        }
        if open(1, 0, 0) {
            face(s, [[1.0, 0.0, 0.0], [1.0, h, 0.0], [1.0, h, 1.0], [1.0, 0.0, 1.0]], [1.0, 0.0, 0.0], side, lit(1, 0, 0));
        }
        if open(-1, 0, 0) {
            face(s, [[0.0, 0.0, 1.0], [0.0, h, 1.0], [0.0, h, 0.0], [0.0, 0.0, 0.0]], [-1.0, 0.0, 0.0], side, lit(-1, 0, 0));
        }
        if open(0, 0, 1) {
            face(s, [[1.0, 0.0, 1.0], [1.0, h, 1.0], [0.0, h, 1.0], [0.0, 0.0, 1.0]], [0.0, 0.0, 1.0], side, lit(0, 0, 1));
        }
        if open(0, 0, -1) {
            face(s, [[0.0, 0.0, 0.0], [0.0, h, 0.0], [1.0, h, 0.0], [1.0, 0.0, 0.0]], [0.0, 0.0, -1.0], side, lit(0, 0, -1));
        }
        return;
    }
    // Ramps: pixel staircases (RAMP_STEPS steps, Terraria's slopes in 3D),
    // built for direction 0 (u across = x, v up = y, t along = z, rising toward
    // +t), then turned. A ceiling ramp is the same shape flipped upside down.
    let ceiling = shape >= SHAPE_CEILING;
    let dir = if ceiling { shape - SHAPE_CEILING } else { shape - SHAPE_RAMP };
    let turn = |c: [f32; 3]| -> [f32; 3] {
        let (u, v, t) = (c[0], if ceiling { 1.0 - c[1] } else { c[1] }, c[2]);
        match dir {
            0 => [u, v, t],
            1 => [t, v, 1.0 - u],
            2 => [1.0 - u, v, 1.0 - t],
            _ => [1.0 - t, v, u],
        }
    };
    let turn_n = |n: [f32; 3]| -> [f32; 3] {
        let n = if ceiling { [n[0], -n[1], n[2]] } else { n };
        match dir {
            0 => n,
            1 => [n[2], n[1], -n[0]],
            2 => [-n[0], n[1], -n[2]],
            _ => [-n[2], n[1], n[0]],
        }
    };
    let ni = |n: [f32; 3]| (n[0].round() as i32, n[1].round() as i32, n[2].round() as i32);
    // The staircase's own surfaces (treads, risers) take the top texture (the
    // bottom one under a ceiling ramp); the flat face opposite takes the other.
    let (surface, flat) = if ceiling { (bottom, top) } else { (top, bottom) };
    // Emits a face given in the dir-0 frame: corners counter-clockwise seen
    // from outside, with their uvs. The ceiling mirror reverses the winding.
    let emit = |s: &mut Surface, c: [[f32; 3]; 4], uv: [[f32; 2]; 4], n: [f32; 3], t: u16, l: [f32; 4]| {
        let mut c = c.map(turn).map(at);
        let mut uv = uv;
        if ceiling {
            c.reverse();
            uv.reverse();
        }
        s.quad(c, turn_n(n), [l; 4], uv, layer(t), [1.0; 4]);
    };
    // Light for a face along a dir-0 normal (its neighbour, if outside the cell).
    let lit_n = |n: [f32; 3]| {
        let (dx, dy, dz) = ni(turn_n(n));
        lit(dx, dy, dz)
    };
    // uv for a horizontal point: the cell's own x/z after turning (so the top
    // texture lines up with the neighbouring blocks' tops).
    let huv = |u: f32, t: f32| {
        let p = turn([u, 0.0, t]);
        [p[0], p[2]]
    };
    // uv for a point on a face across the ramp (a riser): the cell's own
    // horizontal coordinate along it, and its height.
    let vuv = |u: f32, v: f32, t: f32| {
        let p = turn([u, v, t]);
        [if dir % 2 == 0 { p[0] } else { p[2] }, 1.0 - p[1]]
    };
    let n_steps = RAMP_STEPS as i32;
    let up = lit_n([0.0, 1.0, 0.0]);
    let toward_low = lit_n([0.0, 0.0, -1.0]);
    let mut prev = 0.0;
    for k in 0..n_steps {
        let (t0, t1) = (k as f32 / RAMP_STEPS, (k + 1) as f32 / RAMP_STEPS);
        let h = ramp_height(t0);
        // Tread.
        emit(s, [[0.0, h, t0], [0.0, h, t1], [1.0, h, t1], [1.0, h, t0]],
                [huv(0.0, t0), huv(0.0, t1), huv(1.0, t1), huv(1.0, t0)], [0.0, 1.0, 0.0], surface, up);
        // Riser up from the step below (the first one is the ramp's low lip),
        // textured like a block side: across, and by height.
        emit(s, [[0.0, prev, t0], [0.0, h, t0], [1.0, h, t0], [1.0, prev, t0]],
                [vuv(0.0, prev, t0), vuv(0.0, h, t0), vuv(1.0, h, t0), vuv(1.0, prev, t0)], [0.0, 0.0, -1.0], surface, toward_low);
        // The step's column on each side; the side texture follows the slope
        // (its top edge along the stair), so a grass edge runs up the ramp.
        let (sx1, sy1, sz1) = ni(turn_n([1.0, 0.0, 0.0]));
        if open(sx1, sy1, sz1) {
            emit(s, [[1.0, 0.0, t0], [1.0, h, t0], [1.0, h, t1], [1.0, 0.0, t1]],
                    [[t0, h], [t0, 0.0], [t1, 0.0], [t1, h]], [1.0, 0.0, 0.0], side, lit(sx1, sy1, sz1));
        }
        let (sx0, sy0, sz0) = ni(turn_n([-1.0, 0.0, 0.0]));
        if open(sx0, sy0, sz0) {
            emit(s, [[0.0, 0.0, t1], [0.0, h, t1], [0.0, h, t0], [0.0, 0.0, t0]],
                    [[1.0 - t1, h], [1.0 - t1, 0.0], [1.0 - t0, 0.0], [1.0 - t0, h]], [-1.0, 0.0, 0.0], side, lit(sx0, sy0, sz0));
        }
        prev = h;
    }
    // The flat underside (top for a ceiling ramp) and the tall back face.
    let (bx, by, bz) = ni(turn_n([0.0, -1.0, 0.0]));
    if open(bx, by, bz) {
        emit(s, [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 0.0, 1.0], [0.0, 0.0, 1.0]],
                [huv(0.0, 0.0), huv(1.0, 0.0), huv(1.0, 1.0), huv(0.0, 1.0)], [0.0, -1.0, 0.0], flat, lit(bx, by, bz));
    }
    let (hx, hy, hz) = ni(turn_n([0.0, 0.0, 1.0]));
    if open(hx, hy, hz) {
        emit(s, [[1.0, 0.0, 1.0], [1.0, 1.0, 1.0], [0.0, 1.0, 1.0], [0.0, 0.0, 1.0]],
                [[0.0, 1.0], [0.0, 0.0], [1.0, 0.0], [1.0, 1.0]], [0.0, 0.0, 1.0], side, lit(hx, hy, hz));
    }
}

fn add_cross(s: &mut Surface, p: [f32; 3], l: [f32; 4], layer: f32, flip: bool) {
    let (a, b) = (0.15, 0.85);
    let quads = [
        [[a, 0.0, a], [b, 0.0, b], [b, 1.0, b], [a, 1.0, a]],
        [[b, 0.0, a], [a, 0.0, b], [a, 1.0, b], [b, 1.0, a]],
    ];
    let uv = if flip {
        [[1.0, 1.0], [0.0, 1.0], [0.0, 0.0], [1.0, 0.0]]
    } else {
        [[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]]
    };
    for q in quads {
        let v = q.map(|c| [p[0] + c[0], p[1] + c[1], p[2] + c[2]]);
        s.quad(v, [0.0, 1.0, 0.0], [l; 4], uv, layer, [1.0; 4]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::tests::test_world;

    #[test]
    fn flat_ground_only_meshes_top_layer_and_world_walls() {
        let w = test_world();
        // Chunk (0,0,0) is fully solid with ground top at y=31 -> top faces
        // (32*32) plus the world-edge walls on -x and -z sides (32*32 each).
        let m = mesh_chunk(&w, 0, 0, 0);
        assert_eq!(m.opaque.indices.len() / 6, 32 * 32 * 3);
        // Chunk above is empty.
        assert!(mesh_chunk(&w, 0, 1, 0).opaque.is_empty());
    }

    #[test]
    fn better_grass_sides_turn_to_grass_down_a_slope() {
        let mut w = test_world();
        w.set_def(5, crate::world::BlockDef { name: "grass".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1,
            tex: [7, 8, 9], better_grass: true, ..Default::default() });
        // A step: grass at (10, 32) beside grass a block lower at (11, 31)
        // (in the ground). Its +x side looks down onto grass; its -x side onto stone.
        w.set(10, 32, 10, 5);
        w.set(11, 31, 10, 5);
        let m = mesh_chunk(&w, 0, 1, 0);
        let s = &m.opaque;
        let layer_facing = |n: [f32; 3]| -> Vec<f32> {
            (0..s.verts.len()).filter(|&i| s.normals[i] == n).map(|i| s.uv2s[i][0]).collect()
        };
        assert!(layer_facing([1.0, 0.0, 0.0]).iter().all(|&l| l == 7.0), "the side down onto grass shows the top");
        assert!(layer_facing([-1.0, 0.0, 0.0]).iter().all(|&l| l == 8.0), "the side down onto stone stays a side");
        assert!(layer_facing([0.0, 0.0, 1.0]).iter().all(|&l| l == 8.0));
    }

    #[test]
    fn plants_that_vary_are_mirrored_in_some_cells() {
        let mut w = test_world();
        let vary = |w: &mut World, id: u16, vary: bool| w.set_def(id, crate::world::BlockDef { name: format!("plant{id}"), render: RENDER_CROSS, solid: false, opaque: false, variants: 1, vary, ..Default::default() });
        vary(&mut w, 7, true);
        vary(&mut w, 8, false);
        let mut flips = |id: u16| {
            let mut n = 0;
            for x in 0..32 {
                w.set(x, 32, 3, id);
            }
            let m = mesh_chunk(&w, 0, 1, 0);
            // Each cell's first quad: its first corner's u is 1 when mirrored.
            for q in (0..m.cutout.uvs.len()).step_by(8) {
                if m.cutout.uvs[q][0] == 1.0 {
                    n += 1;
                }
            }
            n
        };
        let mirrored = flips(7);
        assert!(mirrored > 4 && mirrored < 28, "about half of a row of plants mirrored ({mirrored} of 32)");
        assert_eq!(flips(8), 0, "the rest never");
    }

    #[test]
    fn single_block_has_six_faces_and_corner_ao() {
        let mut w = test_world();
        w.set(10, 32, 10, 1);
        let m = mesh_chunk(&w, 0, 1, 0);
        assert_eq!(m.opaque.indices.len() / 6, 5); // bottom face touches ground
        // Ground faces next to the block get occluded.
        let g = mesh_chunk(&w, 0, 0, 0);
        assert!(g.opaque.uv2s.iter().any(|uv| uv[1] < 1.0));
    }

    #[test]
    fn hammered_shapes_mesh_in_their_shape_facing_out() {
        for shape in 1..crate::world::SHAPE_COUNT {
            let mut w = test_world();
            w.set(10, 32, 10, 1);
            assert!(w.set_shape(10, 32, 10, shape));
            let m = mesh_chunk(&w, 0, 1, 0);
            let s = &m.opaque;
            assert!(!s.is_empty(), "shape {shape} meshes");
            // Godot front faces are clockwise: each triangle's winding normal
            // points against the face normal (degenerate ones are zero).
            for t in s.indices.chunks(3) {
                let (a, b, c) = (s.verts[t[0] as usize], s.verts[t[1] as usize], s.verts[t[2] as usize]);
                let e1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
                let e2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
                let cr = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
                let n = s.normals[t[0] as usize];
                assert!(cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] <= 1e-6, "shape {shape}: a face is wound inside out");
            }
            let top = s.verts.iter().map(|v| v[1]).fold(0.0f32, f32::max);
            if shape == crate::world::SHAPE_HALF {
                assert!((top - 0.5).abs() < 1e-5, "a half block is half height");
            } else {
                assert!((top - 1.0).abs() < 1e-5);
                // A pixel staircase: treads at every step's height.
                let mut treads: Vec<i32> = s.verts.iter().zip(&s.normals).filter(|(_, n)| n[1].abs() > 0.99)
                    .map(|(v, _)| (v[1] * 16.0).round() as i32).collect();
                treads.sort();
                treads.dedup();
                assert!(treads.len() >= 16, "shape {shape} is a staircase ({} heights)", treads.len());
                assert!(s.normals.iter().all(|n| n.iter().filter(|c| c.abs() > 0.01).count() == 1), "every face is axis-aligned (voxel faces)");
            }
            // Every face maps a real piece of its texture (no UV collapsed to a
            // line, which smears one texel row across it and shimmers).
            for q in 0..s.uvs.len() / 4 {
                let uv = &s.uvs[q * 4..q * 4 + 4];
                let (a, b, c) = (uv[0], uv[1], uv[2]);
                let area = ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])).abs();
                let uv2 = &s.uvs[q * 4..q * 4 + 4];
                let area2 = ((uv2[2][0] - uv2[0][0]) * (uv2[3][1] - uv2[0][1]) - (uv2[2][1] - uv2[0][1]) * (uv2[3][0] - uv2[0][0])).abs();
                assert!(area > 1e-6 || area2 > 1e-6, "shape {shape}: face {q} has a degenerate uv {uv:?}");
            }
        }
    }

    #[test]
    fn liquids_mesh_into_their_own_surfaces() {
        let mut w = test_world();
        w.set_liquid(10, 32, 10, LIQ_WATER, LIQ_MAX);
        w.set_liquid(12, 32, 10, LIQ_LAVA, LIQ_MAX / 2);
        let m = mesh_chunk(&w, 0, 1, 0);
        // Top + 4 sides each (on solid ground: no bottom).
        assert_eq!(m.water.indices.len() / 6, 5);
        assert_eq!(m.lava.indices.len() / 6, 5);
        let top = m.lava.verts.iter().map(|v| v[1]).fold(0.0f32, f32::max);
        assert!(top < 1.0 && top > 0.2, "half-full lava is lower: {top}");
    }

    #[test]
    fn falling_liquid_meshes_as_a_stream_column() {
        let mut w = test_world();
        // A trickle in mid-air above the ground.
        for y in 35..38 {
            w.set_liquid(10, y, 10, LIQ_WATER, 20);
        }
        let m = mesh_chunk(&w, 0, 1, 0);
        assert!(m.water.uv2s.iter().all(|uv| uv[0] >= 3.0), "all stream faces");
        // Narrower than a block, and UV.y follows world height.
        let xs: Vec<f32> = m.water.verts.iter().map(|v| v[0]).collect();
        let width = xs.iter().cloned().fold(f32::MIN, f32::max) - xs.iter().cloned().fold(f32::MAX, f32::min);
        assert!(width < 0.9 && width > 0.3, "stream width {width}");
        assert!(m.water.uvs.iter().any(|uv| uv[1] >= 37.0));
    }

    #[test]
    fn cross_blocks_go_to_cutout_surface() {
        let mut w = test_world();
        w.set(10, 32, 10, 2);
        let m = mesh_chunk(&w, 0, 1, 0);
        assert!(m.opaque.is_empty());
        assert_eq!(m.cutout.indices.len() / 6, 2);
    }
}
