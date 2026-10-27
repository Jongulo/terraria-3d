//! Terraria's ocean caves (its Create Ocean Caves pass: WorldGen.oceanCave)
//! and Water Chests (its Water Chests pass), in 3D.
//!
//! - **Ocean caves:** for each ocean but the Dungeon's (here each side of
//!   the island but the one nearest the Dungeon), 1 in 3, from the sea floor
//!   55-95 tiles in from the world's edge (here as far into this world's
//!   narrower sea: 15-25% across it). A burrow 17-24 tiles round (Terraria's
//!   strength), 600-800 steps long, heads inland and down (0.25-0.5 tiles a
//!   step across, 0.4-0.65 down, turning a little each step) till it's a
//!   third of the way from the surface to the cavern layer and 30 under its
//!   start, then runs on level a fifth of the way down. Where it goes it
//!   opens its middle (half its size), turns the rock round its upper half
//!   ahead of it to sand and hardened sand, builds sand under it ahead of
//!   its start, with a bank of sand and hardened sand under it each step,
//!   and fills itself with water. 50 tiles short of the shore (here as far
//!   short of this world's) it shrinks fast (4% a step) and ends. Where it
//!   last was big, a Water Chest of the ocean caves' treasures. Where it
//!   broke into a dry cave it's sealed with sand (3D caves all join, so
//!   else the sea would drain into the caverns).
//! - **Water Chests:** maxTilesX / 4200 x 9 rounds, here that many in each
//!   640 x 640 blocks of the map, as the cabins do: one chest anywhere in
//!   deep water (mostly the sea), one in water underground; on the floor
//!   under it, not within 30 tiles of another chest.
//!
//! Terraria's tiles are 2/3 of a block here.

use crate::world::{Decoration, World, LIQ_LAVA, LIQ_MAX, LIQ_WATER};
use crate::worldgen::{Coast, Layers, Rng};
use std::collections::HashSet;

type P = (i32, i32, i32);

/// A Terraria tile, in blocks.
const TILE: f64 = 2.0 / 3.0;
/// The Water Chest's loot (Chests.LOOT: "water_chest"), and an ocean cave's
/// ("water_chest_ocean").
pub const WATER_CHEST_LOOT: i32 = 31;
pub const OCEAN_CHEST_LOOT: i32 = 32;

pub struct Ids {
    sand: u16,
    hardened: u16,
    chest: u16,
    /// What a cave keeps out of (badOceanCaveTiles: the Dungeon's, the evil's
    /// blocks).
    keep: Vec<u16>,
}

impl Ids {
    pub fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        Ids {
            sand: id("sand"),
            hardened: id("hardened_sand"),
            chest: id("water_chest"),
            keep: ["blue_brick", "green_brick", "pink_brick", "cracked_blue_brick", "cracked_green_brick", "cracked_pink_brick", "ebonstone",
                "crimstone", "demon_altar", "crimson_altar"]
                .iter()
                .map(|n| id(n))
                .filter(|&i| i != 0)
                .collect(),
        }
    }
}

/// The ocean caves: one 1 in 3 on each side of the island but the one
/// nearest `dungeon`. Returns their treasure spots (for the Water Chests).
pub fn ocean_caves(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast, dungeon: Option<(i32, i32)>) -> Vec<P> {
    let ids = Ids::new(w);
    let mut spots = Vec::new();
    if ids.sand == 0 || ids.hardened == 0 {
        return spots;
    }
    let sea = coast.ocean;
    // The sides: their edge's inland direction.
    let sides: [(f64, f64); 4] = [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)];
    let near_dungeon = dungeon.map(|(x, z)| {
        let d = [x, w.sx - 1 - x, z, w.sz - 1 - z];
        (0..4).min_by_key(|&k| d[k]).unwrap()
    });
    for (k, &dir) in sides.iter().enumerate() {
        if Some(k) == near_dungeon || rng.range(0, 3) != 0 {
            continue;
        }
        // 55-95 tiles in from the edge of Terraria's ~380-tile ocean: as far
        // across this one.
        let into = (sea.width as f64 * rng.range(55, 96) as f64 / 380.0).round() as i32;
        let along = rng.range(w.sx.min(w.sz) * 3 / 10, w.sx.min(w.sz) * 7 / 10);
        let (x, z) = match k {
            0 => (into, along),
            1 => (w.sx - 1 - into, along),
            2 => (along, into),
            _ => (along, w.sz - 1 - into),
        };
        let y = w.surface_y(x, z);
        w.decorations.push(Decoration { kind: "ocean_cave".into(), pos: (x, y, z), style: k as i32 });
        if let Some(spot) = ocean_cave(w, rng, &ids, l, coast, (x, y, z), dir) {
            spots.push(spot);
        }
    }
    spots
}

fn bad(w: &World, ids: &Ids, p: P) -> bool {
    !w.in_bounds(p.0, p.1, p.2) || ids.keep.contains(&w.get(p.0, p.1, p.2))
}

/// oceanCave from the sea floor at `start`, heading inland along `dir`.
/// Returns where it was last big (its treasure spot).
fn ocean_cave(w: &mut World, rng: &mut Rng, ids: &Ids, l: &Layers, coast: &Coast, start: P, dir: (f64, f64)) -> Option<P> {
    let sea = coast.ocean;
    // Position in tiles (x, z across, y up), as Terraria counts.
    let s = (start.0 as f64 / TILE, start.1 as f64 / TILE, start.2 as f64 / TILE);
    let mut pos = s;
    let across = 0.25 + rng.unit() * 0.25;
    let mut vel = (dir.0 * across, -(0.4 + rng.unit() * 0.25), dir.1 * across);
    let mut size = rng.range(17, 25) as f64;
    let mut steps = rng.range(600, 800) as f64;
    let min = 4.0;
    let mut descending = true;
    let mut spot = None;
    // A third and a fifth of the way from the surface to the cavern layer.
    let third = crate::dungeon::depth_y(l, 130.0 / 3.0) as f64 / TILE;
    let fifth = crate::dungeon::depth_y(l, 130.0 / 5.0) as f64 / TILE;
    // 50 tiles short of the shore, in this world's sea.
    let shrink_at = sea.width as f64 * (1.0 - 50.0 / 380.0);
    let start_y = s.1;
    // Its opened middle, which its later steps never fill again (Terraria
    // marks those tiles).
    let mut opened: HashSet<P> = HashSet::new();
    let mut wet: HashSet<P> = HashSet::new();
    while size > min && steps > 0.0 {
        let here = (pos.0 * TILE, pos.1 * TILE, pos.2 * TILE);
        if coast.inland(here.0 as i32, here.2 as i32) as f64 > shrink_at {
            size *= 0.96;
            steps *= 0.96;
        }
        let big = size >= min + 2.0 && steps >= 20.0;
        if descending {
            size -= 0.01 + rng.unit() * 0.01;
            steps -= 0.5;
        } else {
            size -= 0.02 + rng.unit() * 0.02;
            steps -= 1.0;
        }
        if big {
            spot = Some((here.0 as i32, here.1 as i32, here.2 as i32));
        }
        carve(w, rng, ids, &mut opened, &mut wet, pos, size, big, (vel.0, vel.2), s, start_y, steps);
        pos = (pos.0 + vel.0, pos.1 + vel.1, pos.2 + vel.2);
        vel.0 += rng.unit() * 0.1 - 0.05;
        vel.1 += rng.unit() * 0.1 - 0.05;
        vel.2 += rng.unit() * 0.1 - 0.05;
        if descending {
            if pos.1 < third && pos.1 < start_y - 30.0 {
                descending = false;
            }
            vel.1 = vel.1.clamp(-1.0, -0.1);
        } else {
            // On inland, up to half a tile a step.
            let inland = vel.0 * dir.0 + vel.2 * dir.1;
            if inland < 0.5 {
                vel.0 += dir.0 * 0.02;
                vel.2 += dir.1 * 0.02;
            }
            if !big {
                if vel.1 > 0.0 {
                    vel.1 *= 0.95;
                }
                vel.1 -= 0.04;
            } else if pos.1 > fifth {
                if vel.1 > 0.0 {
                    vel.1 *= 0.97;
                }
                vel.1 -= 0.02;
            } else if vel.1 < 0.1 {
                vel.1 *= 0.99;
                vel.1 += 0.01;
            }
            vel.1 = vel.1.clamp(-1.0, 1.0);
        }
        // Never back out to sea.
        let inland = vel.0 * dir.0 + vel.2 * dir.1;
        if inland < 0.1 {
            vel.0 += dir.0 * (0.1 - inland);
            vel.2 += dir.1 * (0.1 - inland);
        }
    }
    // Sealed where it broke into a dry cave (3D caves all join; Terraria's
    // seldom do), so the sea doesn't drain into the caverns.
    for &c in &wet {
        for d in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
            let n = (c.0 + d.0, c.1 + d.1, c.2 + d.2);
            if !bad(w, ids, n) && !w.is_solid(n.0, n.1, n.2) && w.liquid_at(n.0, n.1, n.2).1 == 0 {
                let i = w.idx(n.0, n.1, n.2);
                w.blocks[i] = ids.sand;
            }
        }
    }
    spot
}

/// One step of the cave at `pos` (tiles), its size `size`; the cells it
/// fills with water go in `wet`.
#[allow(clippy::too_many_arguments)]
fn carve(w: &mut World, rng: &mut Rng, ids: &Ids, opened: &mut HashSet<P>, wet: &mut HashSet<P>, pos: (f64, f64, f64), size: f64, big: bool, ahead: (f64, f64), start: (f64, f64, f64), start_y: f64, steps: f64) {
    let reach = size * 1.5 + 1.0;
    let (lo, hi) = ((pos.0 - reach, pos.1 - reach, pos.2 - reach), (pos.0 + reach, pos.1 + reach, pos.2 + reach));
    let b = |t: f64| (t * TILE).floor() as i32;
    let ahead_len = (ahead.0 * ahead.0 + ahead.1 * ahead.1).sqrt().max(1e-6);
    let (ax, az) = (ahead.0 / ahead_len, ahead.1 / ahead_len);
    for z in b(lo.2)..=b(hi.2) {
        for y in b(lo.1)..=b(hi.1) {
            for x in b(lo.0)..=b(hi.0) {
                if bad(w, ids, (x, y, z)) {
                    continue;
                }
                let t = (x as f64 / TILE, y as f64 / TILE, z as f64 / TILE);
                let d = ((t.0 - pos.0).powi(2) + (t.1 - pos.1).powi(2) + (t.2 - pos.2).powi(2)).sqrt();
                let i = w.idx(x, y, z);
                if big && d < size * 0.5 + 1.0 {
                    // Its middle: open.
                    w.blocks[i] = 0;
                    opened.insert((x, y, z));
                } else if d < size * 1.5 + 1.0 && !opened.contains(&(x, y, z)) {
                    if t.1 > pos.1 {
                        // Over it, ahead of it: its rock to hardened sand, then sand.
                        if (t.0 - pos.0) * ax + (t.2 - pos.2) * az > 0.0 && w.is_solid(x, y, z) {
                            w.blocks[i] = if d < size * 1.1 + 1.0 { ids.hardened } else { ids.sand };
                        }
                    } else if (t.0 - start.0) * ax + (t.2 - start.2) * az > 0.0 {
                        // Under it, ahead of its start: sand.
                        w.blocks[i] = ids.sand;
                        w.liquid[i] = 0;
                    }
                }
                // Water in it, below 10 tiles over its start.
                if d < size * 1.3 + 1.0 && t.1 < start_y + 10.0 && !w.is_solid(x, y, z) && w.liquid_at(x, y, z).0 != LIQ_LAVA {
                    w.liquid[i] = crate::world::liq_pack(LIQ_WATER, LIQ_MAX);
                    wet.insert((x, y, z));
                }
            }
        }
    }
    // The bank under it each step: sand ahead of it (43 tiles down, the
    // last of 50 hardened sand), 20 tiles across, smaller as it ends.
    let mut deep = (50 + rng.range(0, 3)) as f64;
    let mut sandy = (43 + rng.range(0, 3)) as f64;
    let mut wide = (20 + rng.range(0, 3)) as f64;
    if steps < 100.0 {
        let k = steps / 100.0;
        deep *= k;
        sandy *= k;
        wide *= k;
    }
    if size < 9.0 {
        let k = (size - 4.0) / 5.0;
        deep *= k;
        sandy *= k;
        wide *= k;
    }
    let (cx, cy, cz) = (pos.0, pos.1, pos.2);
    let r = (wide / 2.0 * TILE).ceil() as i32;
    for dz in -r..=r {
        for dx in -r..=r {
            let (x, z) = (b(cx) + dx, b(cz) + dz);
            // Ahead of its middle, within half its width.
            if (dx as f64 * ax + dz as f64 * az) < 0.0 || ((dx * dx + dz * dz) as f64).sqrt() > wide / 2.0 * TILE {
                continue;
            }
            for k in 0..(deep * TILE) as i32 {
                let y = b(cy) - k;
                if bad(w, ids, (x, y, z)) {
                    break;
                }
                let i = w.idx(x, y, z);
                if (k as f64) < sandy * TILE {
                    if k as f64 >= size * 0.5 * TILE {
                        w.blocks[i] = ids.sand;
                        w.liquid[i] = 0;
                    }
                } else if w.is_solid(x, y, z) || w.blocks[i] == ids.sand {
                    w.blocks[i] = ids.hardened;
                } else {
                    break;
                }
            }
        }
    }
}

/// The Water Chests: an ocean cave's at each of `spots` (the caves'
/// treasures), then the Water Chests pass's rounds through the world's water.
pub fn water_chests(w: &mut World, rng: &mut Rng, l: &Layers, spots: &[P]) {
    let ids = Ids::new(w);
    if ids.chest == 0 {
        return;
    }
    for &s in spots {
        // Out from its spot, a little further each try, till one lands.
        let mut reach = 2.0;
        while reach < 50.0 {
            reach += 0.1;
            let r = (reach * TILE) as i32;
            let p = (s.0 + rng.range(-r, r + 1), s.1 + rng.range(-r / 2, r / 2 + 1), s.2 + rng.range(-r, r + 1));
            if deep_water(w, p) && bury(w, &ids, p, OCEAN_CHEST_LOOT) {
                break;
            }
        }
    }
    let per_area = w.sx as f64 * w.sz as f64 / (640.0 * 640.0);
    let rounds = (9.0 * per_area).round() as usize;
    let surface = crate::dungeon::depth_y(l, 0.0);
    for _ in 0..rounds {
        for top in [w.sy - 2, surface] {
            for _ in 0..10000 {
                let p = (rng.range(25, w.sx - 25), rng.range(l.underworld_top, top), rng.range(25, w.sz - 25));
                if deep_water(w, p) && bury(w, &ids, p, WATER_CHEST_LOOT) {
                    break;
                }
            }
        }
    }
}

/// A cell of water at least 250 of 255 deep (Terraria's liquid >= 250).
fn deep_water(w: &World, p: P) -> bool {
    let (t, a) = w.liquid_at(p.0, p.1, p.2);
    t == LIQ_WATER && a as f64 >= LIQ_MAX as f64 * 250.0 / 255.0 && !w.is_solid(p.0, p.1, p.2)
}

/// AddBuriedChest for a Water Chest: down from `p` to the floor, a chest on
/// it, not within 30 tiles of another chest. Whether one went in.
fn bury(w: &mut World, ids: &Ids, p: P, loot: i32) -> bool {
    let mut y = p.1;
    while y > 1 && !w.is_solid(p.0, y - 1, p.2) {
        y -= 1;
    }
    if y <= 1 || w.get(p.0, y, p.2) != 0 || bad(w, ids, (p.0, y - 1, p.2)) {
        return false;
    }
    let near = (30.0 * TILE) as i32;
    if w.decorations.iter().any(|d| d.kind == "chest" && (d.pos.0 - p.0).abs() <= near && (d.pos.1 - y).abs() <= near && (d.pos.2 - p.2).abs() <= near) {
        return false;
    }
    let i = w.idx(p.0, y, p.2);
    w.blocks[i] = ids.chest;
    w.liquid[i] = 0;
    w.decorations.push(Decoration { kind: "chest".into(), pos: (p.0, y, p.2), style: loot });
    true
}
