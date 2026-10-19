//! The Glowing Mushroom biome, like Terraria's (WorldGen's "Mushroom
//! Patches" pass: ShroomPatch, the mushroom grass spread over the world's mud
//! after it; GrowShroom and the small glowing mushrooms of its plant pass; the
//! mushroom vines of its vine pass), in 3D.
//!
//! - Terraria makes maxTilesX / 700 biomes (6 in a small world), each 500
//!   tiles from the others, between 20% and 80% of the world's width (after
//!   a quarter of its tries, anywhere), from 50 tiles below the cavern layer
//!   to 300 above the world's bottom; not within 100 tiles of the Jungle, the
//!   snow, marble, granite or the underground desert. Its worlds are a 2D
//!   slice, so here that many go in each 640 x 640 blocks of the map (as the
//!   cabins do), fewer as the patches grow with the world (Terraria's grow
//!   with its width: maxTilesX / 4200), kept 180 blocks apart (more in bigger
//!   worlds) and out of the ocean, the Dungeon and the big biomes.
//! - A biome is six ShroomPatches: one at its spot and five within 40 tiles.
//!   A patch is a chain of 20-25 steps, each a flattened ball (2.3 times as
//!   wide as tall) of mud about 80-100 tiles across, the top half of its
//!   middle fifth hollowed out, drifting a block sideways and half a block up
//!   each step and shrinking as it goes; the first step's lower half is
//!   filled with mud. Lava near it goes. Each step adds two blobs of mud
//!   (TileRunners) just below.
//! - Then every mud block below the surface that's open to the air turns to
//!   mushroom grass (Terraria's SpreadGrass over the whole world: the mud
//!   patches through the caverns get some too; not in the Jungle, whose mud
//!   is its own); the ground round it is smoothed (lone spikes knocked off,
//!   one-block pits filled with mud), and now and then a mud block within 20
//!   turns to mushroom grass inside the ground.
//! - On every mushroom grass block open above: a Giant Glowing Mushroom where
//!   GrowShroom fits one (mushroom grass on all four sides, nothing within 2
//!   blocks round its column from 3 to 13 above, nor within 1 below that; a
//!   stem 4-10 tall under its cap), else maybe a small Glowing Mushroom (one
//!   of Terraria's five styles; in clumps, not on every block as along
//!   Terraria's 2D ground, which on a 3D floor would be a grid). Under a
//!   fifth of the mushroom grass ceilings, 3 in 5 of those grow mushroom vines
//!   1-9 long.

use crate::world::{Decoration, World, LIQ_LAVA};
use crate::worldgen::{biome_regions, Layers, Rng, BIOME_DESERT, BIOME_JUNGLE, BIOME_SNOW};

/// The canopy style of a Giant Glowing Mushroom's cap (CanopyArt sheet 27,
/// Terraria's Shroom_Tops; its three frames).
pub const MUSHROOM_CAP: i32 = 270;

type P = (i32, i32, i32);

struct Ids {
    mud: u16,
    grass: u16,
    /// The small glowing mushrooms, Terraria's five styles of tile 71.
    plants: Vec<u16>,
    trunk: u16,
    vines: u16,
    /// Ground a patch turns to mud, and the smoothing reshapes.
    terrain: Vec<bool>,
    /// What keeps a biome away (Terraria: jungle grass, snow, ice, marble,
    /// granite, the underground desert).
    avoid: Vec<u16>,
}

impl Ids {
    fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        let natural = ["stone", "dirt", "clay", "sand", "silt", "slush", "grass", "mud", "mushroom_grass", "ebonstone", "crimstone"];
        let terrain = w.defs.iter().map(|d| natural.contains(&d.name.as_str()) || d.name.ends_with("_ore")).collect();
        let avoid = ["jungle_grass", "snow_block", "ice_block", "hardened_sand", "sandstone", "marble", "granite"]
            .iter()
            .map(|n| id(n))
            .filter(|&i| i != 0)
            .collect();
        Ids {
            mud: id("mud"),
            grass: id("mushroom_grass"),
            plants: ["glowing_mushroom", "glowing_mushroom_2", "glowing_mushroom_3", "glowing_mushroom_4", "glowing_mushroom_5"]
                .iter()
                .map(|n| id(n))
                .filter(|&i| i != 0)
                .collect(),
            trunk: id("mushroom_trunk"),
            vines: id("mushroom_vines"),
            terrain,
            avoid,
        }
    }

    fn is_terrain(&self, b: u16) -> bool {
        b != 0 && *self.terrain.get(b as usize).unwrap_or(&false)
    }
}

/// The biomes, the grass and the mushrooms. `scale`: Terraria's patch size
/// for the world (maxTilesX / 4200: the map's width over 768). `keep_out`:
/// spots to stay away from horizontally ((x, z, radius): the Dungeon).
/// Returns each biome's spot.
pub fn mushroom_biomes(w: &mut World, rng: &mut Rng, l: &Layers, inland: &dyn Fn(i32, i32) -> bool, keep_out: &[(i32, i32, i32)]) -> Vec<P> {
    let ids = Ids::new(w);
    let mut spots = Vec::new();
    if ids.mud == 0 || ids.grass == 0 {
        return spots;
    }
    let scale = w.sx.min(w.sz) as f64 / 768.0;
    let area = w.sx as f64 * w.sz as f64;
    let count = ((6.0 * area / (640.0 * 640.0) / scale).round() as usize).min(50);
    let apart = (180.0 * scale) as i32;
    let regions = biome_regions(w.sx, w.sz, w.seed);
    // Terraria: rockLayer + 50 down to maxTilesY - 300 (its tiles below the
    // surface: 130 to the cavern layer, then 580 to the Underworld).
    let (y_top, y_bottom) = (crate::dungeon::depth_y(l, 180.0), crate::dungeon::depth_y(l, 610.0));
    for _ in 0..count {
        let mut placed = false;
        for tries in 0..w.sx / 2 {
            let (lo, hi) = if tries > w.sx / 4 { (0.025, 0.975) } else { (0.2, 0.8) };
            let x = rng.range((w.sx as f64 * lo) as i32, (w.sx as f64 * hi) as i32);
            let z = rng.range((w.sz as f64 * lo) as i32, (w.sz as f64 * hi) as i32);
            let y = rng.range(y_bottom, y_top.max(y_bottom + 1));
            if !inland(x, z)
                || spots.iter().any(|&(sx, _, sz): &P| ((sx - x).pow(2) + (sz - z).pow(2)) < apart * apart)
                || keep_out.iter().any(|&(kx, kz, r)| (kx - x).pow(2) + (kz - z).pow(2) < r * r)
                || regions.iter().any(|&(b, rx, rz, r)| {
                    [BIOME_SNOW, BIOME_JUNGLE, BIOME_DESERT].contains(&b) && (rx - x).pow(2) + (rz - z).pow(2) < (r + 60).pow(2)
                })
                || near_avoided(w, &ids, (x, y, z))
            {
                continue;
            }
            shroom_patch(w, rng, &ids, (x, y, z), scale);
            for _ in 0..5 {
                let (dx, dy, dz) = (rng.range(-40, 41), rng.range(-40, 41), rng.range(-40, 41));
                shroom_patch(w, rng, &ids, (x + dx, y + dy / 2, z + dz), scale);
            }
            spots.push((x, y, z));
            placed = true;
            break;
        }
        if !placed {
            break;
        }
    }
    let all = (1, w.sx - 1, 1, w.sz - 1);
    spread_grass(w, rng, &ids, l, &regions, all);
    plant(w, rng, &ids, l, all);
    spots
}

/// One biome at `at` with its grass and mushrooms only within `r` blocks
/// round it (the test world's); without `patches` only the grass and the
/// mushrooms, on the mud already there.
pub fn biome_at(w: &mut World, seed: i32, l: &Layers, at: P, r: i32, patches: bool) {
    let ids = Ids::new(w);
    if ids.mud == 0 || ids.grass == 0 {
        return;
    }
    let mut rng = Rng::new(seed as u64);
    if patches {
        shroom_patch(w, &mut rng, &ids, at, 0.5);
        for _ in 0..2 {
            let (dx, dz) = (rng.range(-r / 3, r / 3 + 1), rng.range(-r / 3, r / 3 + 1));
            shroom_patch(w, &mut rng, &ids, (at.0 + dx, at.1, at.2 + dz), 0.5);
        }
    }
    let bounds = ((at.0 - r).max(1), (at.0 + r).min(w.sx - 1), (at.2 - r).max(1), (at.2 + r).min(w.sz - 1));
    spread_grass(w, &mut rng, &ids, l, &[], bounds);
    plant(w, &mut rng, &ids, l, bounds);
}

/// Terraria's check round a spot (every 3 tiles of 100 each way): any block
/// that keeps the biome away. Here every 6 blocks, 100 across and 60 up and
/// down.
fn near_avoided(w: &World, ids: &Ids, (x, y, z): P) -> bool {
    for dx in (-100..=100).step_by(6) {
        for dz in (-100..=100).step_by(6) {
            for dy in (-60..=60).step_by(6) {
                let (px, py, pz) = (x + dx, y + dy, z + dz);
                if !w.in_bounds(px, py, pz) {
                    continue;
                }
                if ids.avoid.contains(&w.get(px, py, pz)) {
                    return true;
                }
            }
        }
    }
    false
}

/// WorldGen.ShroomPatch at `at` (Terraria's y runs down: its "above the
/// middle" is up here, and its upward drift rises).
fn shroom_patch(w: &mut World, rng: &mut Rng, ids: &Ids, at: P, scale: f64) {
    let mut size = rng.range(80, 100) as f64 * scale;
    let mut steps = rng.range(20, 26) as f64 * scale;
    let first = steps - 1.0;
    let mut pos = (at.0 as f64, at.1 as f64 + steps * 0.3, at.2 as f64);
    // Sideways a block a step (Terraria: its x velocity, always +-0.5, added
    // twice), keeping much the same way; up half a block (more at first).
    let mut heading = rng.unit() * std::f64::consts::TAU;
    let mut rise = rng.range(100, 201) as f64 * 0.005;
    while size > 0.0 && steps > 0.0 {
        size -= rng.range(0, 3) as f64;
        steps -= 1.0;
        let half = size * 0.5;
        let reach = size * rng.range(80, 120) as f64 * 0.01;
        let (x0, x1) = ((pos.0 - half) as i32, (pos.0 + half) as i32);
        let (y0, y1) = ((pos.1 - half) as i32, (pos.1 + half) as i32);
        let (z0, z1) = ((pos.2 - half) as i32, (pos.2 + half) as i32);
        for x in x0.max(0)..x1.min(w.sx) {
            for z in z0.max(0)..z1.min(w.sz) {
                for y in y0.max(1)..y1.min(w.sy - 1) {
                    let (dx, dz, dy) = (x as f64 - pos.0, z as f64 - pos.2, (y as f64 - pos.1) * 2.3);
                    let d = (dx * dx + dz * dz + dy * dy).sqrt();
                    let i = w.idx(x, y, z);
                    if d < reach * 0.8 && crate::world::liq_unpack(w.liquid[i]).0 == LIQ_LAVA {
                        w.liquid[i] = 0;
                    }
                    let b = w.blocks[i];
                    if d < reach * 0.2 && (y as f64) > pos.1 {
                        if ids.is_terrain(b) {
                            w.blocks[i] = 0;
                        }
                    } else if d < reach * 0.4 * (0.95 + rng.unit() * 0.1) {
                        if ids.is_terrain(b) {
                            w.blocks[i] = ids.mud;
                        } else if b == 0 && steps == first && (y as f64) < pos.1 {
                            w.blocks[i] = ids.mud;
                            w.liquid[i] = 0;
                        }
                    }
                }
            }
        }
        pos.0 += heading.cos();
        pos.2 += heading.sin();
        pos.1 += rise;
        heading += (rng.unit() - 0.5) * 0.4;
        rise = 0.5;
        // Two blobs of mud just below, on the ground (TileRunner, 10-20 strong
        // and long).
        for _ in 0..2 {
            for _ in 0..50 {
                let p = (pos.0 as i32 + rng.range(-20, 20), pos.1 as i32 - rng.range(0, 20), pos.2 as i32 + rng.range(-20, 20));
                let b = w.get(p.0, p.1, p.2);
                if ids.is_terrain(b) {
                    let (strength, run) = (rng.range(10, 20) as f64, rng.range(10, 20));
                    mud_runner(w, rng, ids, p, strength, run);
                    break;
                }
            }
        }
    }
}

/// Terraria's TileRunner without adding tiles: a blob of the ground turned to
/// mud along a short wandering run, `strength` across at first, narrowing to
/// nothing over `run` steps.
fn mud_runner(w: &mut World, rng: &mut Rng, ids: &Ids, p: P, strength: f64, run: i32) {
    let mut pos = (p.0 as f64, p.1 as f64, p.2 as f64);
    let mut v = (rng.unit() * 2.0 - 1.0, rng.unit() * 2.0 - 1.0, rng.unit() * 2.0 - 1.0);
    for k in 0..run {
        let r = strength * (run - k) as f64 / run as f64 * 0.5;
        let ri = r.ceil() as i32;
        for x in pos.0 as i32 - ri..=pos.0 as i32 + ri {
            for y in pos.1 as i32 - ri..=pos.1 as i32 + ri {
                for z in pos.2 as i32 - ri..=pos.2 as i32 + ri {
                    let d = ((x as f64 - pos.0).powi(2) + (y as f64 - pos.1).powi(2) + (z as f64 - pos.2).powi(2)).sqrt();
                    if d < r * (0.8 + rng.unit() * 0.4) && w.in_bounds(x, y, z) {
                        let i = w.idx(x, y, z);
                        if ids.is_terrain(w.blocks[i]) {
                            w.blocks[i] = ids.mud;
                        }
                    }
                }
            }
        }
        pos = (pos.0 + v.0, pos.1 + v.1 * 0.5, pos.2 + v.2);
        v = ((v.0 + rng.unit() - 0.5).clamp(-1.0, 1.0), (v.1 + rng.unit() - 0.5).clamp(-1.0, 1.0), (v.2 + rng.unit() - 0.5).clamp(-1.0, 1.0));
    }
}

/// The column's ground: its highest block of terrain (not a tree).
fn ground_y(w: &World, ids: &Ids, x: i32, z: i32) -> i32 {
    (0..w.sy).rev().find(|&y| ids.is_terrain(w.get(x, y, z))).unwrap_or(0)
}

const SIDES: [P; 6] = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)];

/// Whether a cell is open (Terraria's inactive tile): no solid block there.
fn open(w: &World, x: i32, y: i32, z: i32) -> bool {
    w.in_bounds(x, y, z) && !w.is_solid(x, y, z)
}

/// Mud open to the air below the surface turns to mushroom grass (not in the
/// Jungle's region), the ground round it smoothed, and some mud near it turned
/// to mushroom grass inside the ground.
fn spread_grass(w: &mut World, rng: &mut Rng, ids: &Ids, l: &Layers, regions: &[(i32, i32, i32, i32)], (bx0, bx1, bz0, bz1): (i32, i32, i32, i32)) {
    let jungle: Vec<(i32, i32, i32)> = regions.iter().filter(|r| r.0 == BIOME_JUNGLE).map(|r| (r.1, r.2, r.3 + 30)).collect();
    let mut grown = Vec::new();
    for z in bz0..bz1 {
        for x in bx0..bx1 {
            if jungle.iter().any(|&(jx, jz, r)| (jx - x).pow(2) + (jz - z).pow(2) < r * r) {
                continue;
            }
            let top = (ground_y(w, ids, x, z) - 6).min(l.surface_base);
            for y in 1..top {
                let i = w.idx(x, y, z);
                if w.blocks[i] != ids.mud {
                    continue;
                }
                if SIDES.iter().any(|&(dx, dy, dz)| open(w, x + dx, y + dy, z + dz)) {
                    w.blocks[i] = ids.grass;
                    grown.push((x, y, z));
                }
            }
        }
    }
    // The ground round it smoothed (Terraria's 3 x 3 round each grass tile:
    // a tile with nothing either side goes, a gap with ground either side is
    // filled); here a block open on both sides along two axes is a spike, a
    // gap shut in along two axes a pit.
    let mut filled = Vec::new();
    for &(gx, gy, gz) in &grown {
        for dx in -1..=1 {
            for dy in -1..=1 {
                for dz in -1..=1 {
                    let (x, y, z) = (gx + dx, gy + dy, gz + dz);
                    if !w.in_bounds(x, y, z) || y < 1 || y >= w.sy - 1 {
                        continue;
                    }
                    let axes = [(1, 0, 0), (0, 1, 0), (0, 0, 1)];
                    let b = w.get(x, y, z);
                    if ids.is_terrain(b) {
                        let thin = axes.iter().filter(|&&(ax, ay, az)| open(w, x + ax, y + ay, z + az) && open(w, x - ax, y - ay, z - az)).count();
                        if thin >= 2 {
                            let i = w.idx(x, y, z);
                            w.blocks[i] = 0;
                        }
                    } else if b == 0 && w.liquid[w.idx(x, y, z)] == 0 {
                        let shut = axes.iter().filter(|&&(ax, ay, az)| !open(w, x + ax, y + ay, z + az) && !open(w, x - ax, y - ay, z - az)).count();
                        if shut >= 2 {
                            let i = w.idx(x, y, z);
                            w.blocks[i] = ids.mud;
                            filled.push((x, y, z));
                        }
                    }
                }
            }
        }
    }
    // Grass a fill has shut in goes back to mud; a filled cell open to the air
    // is grass itself.
    for &(fx, fy, fz) in &filled {
        for &(dx, dy, dz) in SIDES.iter().chain([(0, 0, 0)].iter()) {
            let (x, y, z) = (fx + dx, fy + dy, fz + dz);
            let b = w.get(x, y, z);
            if b != ids.grass && b != ids.mud {
                continue;
            }
            let exposed = SIDES.iter().any(|&(ex, ey, ez)| open(w, x + ex, y + ey, z + ez));
            let i = w.idx(x, y, z);
            w.blocks[i] = if exposed { ids.grass } else { ids.mud };
        }
    }
    // Now and then mud within 20 turns to mushroom grass (inside the ground).
    for &(gx, gy, gz) in &grown {
        if rng.range(0, 4) != 0 {
            continue;
        }
        let (x, y, z) = (gx + rng.range(-20, 21), gy + rng.range(-20, 21), gz + rng.range(-20, 21));
        if w.get(x, y, z) == ids.mud {
            let i = w.idx(x, y, z);
            w.blocks[i] = ids.grass;
        }
    }
}

/// The mushrooms on the mushroom grass and the vines under it. Terraria puts
/// a small glowing mushroom (one of its five styles) on every open grass tile
/// a giant one doesn't take, a row along its 2D ground; here, on a floor, that
/// would stand in a grid, so they grow in clumps (a noise field: thick in
/// places, sparse between) of any of the five.
fn plant(w: &mut World, rng: &mut Rng, ids: &Ids, l: &Layers, (bx0, bx1, bz0, bz1): (i32, i32, i32, i32)) {
    let clumps = crate::worldgen::noise(w.seed + 71, 0.12, 2);
    for z in bz0.max(2)..bz1.min(w.sz - 2) {
        for x in bx0.max(2)..bx1.min(w.sx - 2) {
            let top = (ground_y(w, ids, x, z) - 6).min(l.surface_base);
            for y in 2..top {
                if w.get(x, y, z) != ids.grass {
                    continue;
                }
                let above = w.idx(x, y + 1, z);
                if w.blocks[above] == 0 && w.liquid[above] == 0 && !ids.plants.is_empty() && !grow_shroom(w, rng, ids, (x, y, z)) {
                    let thick = clumps.get_noise_3d(x as f32, y as f32, z as f32);
                    if rng.unit() < (0.06 + 0.7 * (thick as f64 + 0.05)).clamp(0.06, 0.65) {
                        w.blocks[above] = ids.plants[rng.range(0, ids.plants.len() as i32) as usize];
                    }
                }
                let below = w.idx(x, y - 1, z);
                if ids.vines != 0 && w.blocks[below] == 0 && w.liquid[below] == 0 && rng.range(0, 5) == 0 && rng.range(0, 5) < 3 {
                    for k in 1..=rng.range(1, 10) {
                        let i = w.idx(x, y - k, z);
                        if y - k < 1 || w.blocks[i] != 0 || w.liquid[i] != 0 {
                            break;
                        }
                        w.blocks[i] = ids.vines;
                    }
                }
            }
        }
    }
}

/// WorldGen.GrowShroom on the mushroom grass at `p`: mushroom grass on all
/// four sides, no lava just above, nothing (but small glowing mushrooms)
/// within 2 blocks round its column from 3 to 13 above and within 1 from 1 to
/// 3 above; a stem 4-10 tall (its top cell the cap). Whether it grew.
fn grow_shroom(w: &mut World, rng: &mut Rng, ids: &Ids, p: P) -> bool {
    let (x, y, z) = p;
    if ids.trunk == 0 || w.get(x, y, z) != ids.grass {
        return false;
    }
    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        if w.get(x + dx, y, z + dz) != ids.grass || w.liquid_at(x + dx, y + 1, z + dz).0 == LIQ_LAVA {
            return false;
        }
    }
    let empty = |w: &World, r: i32, lo: i32, hi: i32| {
        for dy in lo..=hi {
            for dx in -r..=r {
                for dz in -r..=r {
                    let (px, py, pz) = (x + dx, y + dy, z + dz);
                    if !w.in_bounds(px, py, pz) {
                        return false;
                    }
                    let b = w.get(px, py, pz);
                    if (b != 0 && !ids.plants.contains(&b)) || w.liquid_at(px, py, pz).1 > 0 {
                        return false;
                    }
                }
            }
        }
        true
    };
    if !empty(w, 2, 3, 13) || !empty(w, 1, 1, 3) {
        return false;
    }
    let h = rng.range(4, 11);
    for k in 1..h {
        let i = w.idx(x, y + k, z);
        w.blocks[i] = ids.trunk;
    }
    w.decorations.push(Decoration {
        kind: "tree_top".into(),
        pos: (x, y + h, z),
        style: MUSHROOM_CAP + rng.range(0, 3),
    });
    true
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE, RENDER_CUTOUT};

    /// The biome's blocks, for worlds built in tests.
    pub(crate) fn add_mushroom_defs(w: &mut World) {
        let mut id = w.defs.len() as u16;
        for (name, render, solid) in [("stone", RENDER_CUBE, true), ("mud", RENDER_CUBE, true), ("mushroom_grass", RENDER_CUBE, true),
                ("glowing_mushroom", RENDER_CROSS, false), ("glowing_mushroom_2", RENDER_CROSS, false), ("glowing_mushroom_3", RENDER_CROSS, false),
                ("glowing_mushroom_4", RENDER_CROSS, false), ("glowing_mushroom_5", RENDER_CROSS, false), ("mushroom_trunk", RENDER_CUTOUT, true),
                ("mushroom_vines", RENDER_CROSS, false)] {
            if w.id_of(name) != 0 {
                continue;
            }
            w.set_def(id, BlockDef { name: name.into(), render, solid, opaque: solid && render == RENDER_CUBE, variants: 1, ..Default::default() });
            id += 1;
        }
    }

    fn world(sx: i32, sy: i32, sz: i32) -> World {
        let mut w = World::new();
        add_mushroom_defs(&mut w);
        w.resize(sx, sy, sz);
        w
    }

    #[test]
    fn a_patch_hollows_mud_and_a_shroom_grows_on_grass() {
        let mut w = world(96, 64, 96);
        let stone = w.id_of("stone");
        for i in 0..w.blocks.len() {
            w.blocks[i] = stone;
        }
        let ids = Ids::new(&w);
        let mut rng = Rng::new(3);
        shroom_patch(&mut w, &mut rng, &ids, (48, 30, 48), 0.5);
        let count = |w: &World, id: u16| w.blocks.iter().filter(|&&b| b == id).count();
        assert!(count(&w, ids.mud) > 2000, "a patch turns the rock round it to mud ({})", count(&w, ids.mud));
        assert!(count(&w, 0) > 100, "and hollows out its middle ({} open)", count(&w, 0));
        // A flat floor of mushroom grass with room above: a mushroom grows.
        let mut w = world(32, 32, 32);
        let ids = Ids::new(&w);
        for x in 0..32 {
            for z in 0..32 {
                let i = w.idx(x, 4, z);
                w.blocks[i] = ids.grass;
            }
        }
        assert!(grow_shroom(&mut w, &mut rng, &ids, (16, 4, 16)), "on open mushroom grass a Giant Glowing Mushroom grows");
        assert_eq!(w.get(16, 5, 16), ids.trunk, "its stem");
        assert!(w.decorations.iter().any(|d| d.kind == "tree_top" && d.style >= MUSHROOM_CAP && d.style < MUSHROOM_CAP + 3), "under its cap");
        assert!(!grow_shroom(&mut w, &mut rng, &ids, (17, 4, 16)), "not right beside another");
        let mut w2 = world(32, 32, 32);
        let i = w2.idx(16, 4, 16);
        w2.blocks[i] = ids.grass;
        assert!(!grow_shroom(&mut w2, &mut rng, &ids, (16, 4, 16)), "nor without mushroom grass round it");
    }
}
