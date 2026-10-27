//! Terraria's Underground Desert (its Full Desert pass: DesertBiome.Place,
//! with DesertDescription, SandMound, the four entrances and DesertHive), in
//! 3D, under the Desert's region.
//!
//! - **Where:** Terraria's hive is 320 tiles across under 370 of the
//!   Desert's surface sand (a small world's); here 0.86 of the Desert's
//!   radius each way round its middle. Its top 40-60 tiles under the middle
//!   of the Desert's ground (between its average and its lowest), and it's
//!   2 x (1.5-2 x 170) tiles tall, here in Terraria's depths (as far down as
//!   that, short of the Underworld).
//! - **The sand mound:** sand from the Desert's ground down to the hive's
//!   middle, a dome (its top falls off as 1 - d^4 under the edges); over its
//!   middle the ground above it goes (from 10 tiles under, past half way out,
//!   to 10 over at the edge), so the Desert's top is flat.
//! - **An entrance,** 1 in 3: one of Terraria's four. Chambers (2-3 caves
//!   in turn either side of a sand drift, joined by a winding passage from
//!   the surface), anthills (2-3 sand mounds, a burrow down each from its
//!   crater), larva holes (2-3 funnels with a burrow down from each) or a pit
//!   (a shaft down the middle, narrowing to half, lined with hardened sand).
//!   The burrows go down to the hive's top, lined with hardened sand.
//! - **The hive:** ClusterGroup: a grid of cells 4 tiles across and 2 tall
//!   (here also 4 deep) over its ellipsoid, each 1 in 2 set; from half of
//!   them a cluster of the set cells within 2 steps (3 or more); clusters
//!   that touch either swallow or wipe out the other, and those under 4
//!   cells go. Each cell is a point, jittered a quarter cell. Then every
//!   block in it (and 20 tiles round it) sums 1 / d^2 to the points of each
//!   cluster and adds the two biggest sums: over 3.5 it's open (but 1 cluster
//!   in 15 is a lump of Desert Fossil), over 1.8 sandstone, else sand (1 in 3
//!   hardened). Within 0.8 of the way out it's built whatever was there; past
//!   that only what was solid changes (and under 0.7 only 0.25-0.7 of the way
//!   to it), so the caves round it stay.
//! - **AddTileVariance:** sand with no ground under it (or the next one
//!   down) turns to hardened sand, so it holds; on the sandstone round the
//!   caves, stalactites under 1 in 5 of its ceilings and stalagmites on 15
//!   in 100 of its floors (Terraria's other 5 in 100, Antlion Eggs, and its
//!   Rolling Cactus and piles aren't here yet).
//!
//! Terraria's tiles are 2/3 of a block here.

use crate::world::{Decoration, World};
use crate::worldgen::{noise, Coast, Layers, Rng};
use rayon::prelude::*;
use std::collections::HashSet;

type P = (i32, i32, i32);
type V = (f64, f64, f64);

/// A Terraria tile, in blocks.
const TILE: f64 = 2.0 / 3.0;
/// The hive's half width, of the Desert's radius.
pub const HIVE_OF_DESERT: f64 = 0.86;
/// How far (in cells) a cluster's points count; Terraria counts them all,
/// but past this they add little (1 / d^2).
const REACH: f64 = 4.5;
/// Over this (the two nearest clusters' sums) a block is open; over the
/// next sandstone, over the last sand; past 0.8 of the way out, from the
/// last a chance of sand. Terraria's are 3.5, 1.8, 0.7 and 0.25; a block
/// in 3D has more points round it, so here they're higher, to open as much
/// of it (41%) and wall as much in sandstone (26%) as Terraria's 2D hive.
const OPEN: f64 = 3.5 * 2.1;
const SANDSTONE: f64 = 1.8 * 2.6;
const SAND: f64 = 0.7 * 2.6;
const MAYBE_SAND: f64 = 0.25 * 2.6;
/// How far round the hive it reaches (Terraria's 20 tiles), in blocks.
const ROUND: f64 = 20.0 * TILE;

/// The Underground Desert: round `center`, `half` across each way, from
/// `top` down to `bottom`; `ground` the Desert's ground (Terraria's
/// Desert.Top).
#[derive(Clone, Copy, Debug)]
pub struct Hive {
    pub center: (i32, i32),
    pub half: f64,
    pub top: i32,
    pub bottom: i32,
    pub ground: i32,
}

impl Hive {
    /// The world's, from its "desert_hive" decoration (its middle at its top;
    /// its style its bottom) and the Desert's region.
    pub fn of(w: &World) -> Option<Hive> {
        let d = w.decorations.iter().find(|d| d.kind == "desert_hive")?;
        let r = crate::worldgen::biome_regions(w.sx, w.sz, w.seed).iter().find(|r| r.0 == crate::worldgen::BIOME_DESERT)?.3;
        Some(Hive { center: (d.pos.0, d.pos.2), half: r as f64 * HIVE_OF_DESERT, top: d.pos.1, bottom: d.style, ground: 0 })
    }

    /// What it keeps the structures after it out of (Terraria's
    /// AddStructure: from the sky down to 20 tiles over its bottom, 10
    /// tiles round).
    pub fn protected(&self, sy: i32) -> (P, P) {
        let r = (self.half + 10.0 * TILE).ceil() as i32;
        let low = self.bottom + (10.0 * TILE).round() as i32;
        ((self.center.0 - r, low, self.center.1 - r), (self.center.0 + r, sy - 1, self.center.1 + r))
    }

    /// Whether `p` is in it (its ellipsoid).
    pub fn contains(&self, p: P) -> bool {
        let b = (self.top - self.bottom) as f64 / 2.0;
        let (dx, dz) = ((p.0 - self.center.0) as f64 / self.half, (p.2 - self.center.1) as f64 / self.half);
        let dy = (p.1 as f64 - (self.top + self.bottom) as f64 / 2.0) / b;
        dx * dx + dy * dy + dz * dz < 1.0
    }
}

struct Ids {
    sand: u16,
    hardened: u16,
    sandstone: u16,
    fossil: u16,
    stalactites: [u16; 2],
    stalagmites: [u16; 2],
}

impl Ids {
    fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        Ids {
            sand: id("sand"),
            hardened: id("hardened_sand"),
            sandstone: id("sandstone"),
            fossil: id("desert_fossil"),
            stalactites: [id("sandstone_stalactite"), id("small_sandstone_stalactite")],
            stalagmites: [id("sandstone_stalagmite"), id("small_sandstone_stalagmite")],
        }
    }
}

/// How many of Terraria's tiles `y` is under the surface (depth_y the other
/// way round).
fn tiles_below(l: &Layers, y: f64) -> f64 {
    let (s, c, u) = (l.surface_base as f64, l.cavern_top as f64, l.underworld_top as f64);
    if y >= c {
        (s - y) * 130.0 / (s - c)
    } else {
        130.0 + (c - y) * 580.0 / (c - u)
    }
}

/// The ground in a column: its highest solid block.
fn ground(w: &World, x: i32, z: i32) -> i32 {
    w.surface_y(x, z)
}

fn clear(w: &mut World, p: P) {
    if w.in_bounds(p.0, p.1, p.2) && p.1 > 0 {
        let i = w.idx(p.0, p.1, p.2);
        w.blocks[i] = 0;
        w.liquid[i] = 0;
    }
}

fn put(w: &mut World, p: P, b: u16) {
    if w.in_bounds(p.0, p.1, p.2) && p.1 > 0 {
        let i = w.idx(p.0, p.1, p.2);
        w.blocks[i] = b;
        w.liquid[i] = 0;
    }
}

/// A hash of a block, in [0, 1) (Terraria's FastRandom.WithModifier per tile).
fn hash01(seed: u64, p: P) -> f64 {
    let mut z = seed ^ (p.0 as u64).wrapping_mul(0x9e37_79b9_7f4a_7c15) ^ (p.1 as u64).wrapping_mul(0xc2b2_ae3d_27d4_eb4f) ^ (p.2 as u64).wrapping_mul(0x1656_67b1_9e37_79f9);
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    ((z ^ (z >> 31)) >> 11) as f64 / (1u64 << 53) as f64
}

/// The cells within an ellipsoid round `c` (`rh` across, `rv` up and down).
fn ellipsoid(c: V, rh: f64, rv: f64) -> Vec<P> {
    let mut out = Vec::new();
    let (rh, rv) = (rh.max(0.5), rv.max(0.5));
    for y in (c.1 - rv).floor() as i32..=(c.1 + rv).ceil() as i32 {
        for z in (c.2 - rh).floor() as i32..=(c.2 + rh).ceil() as i32 {
            for x in (c.0 - rh).floor() as i32..=(c.0 + rh).ceil() as i32 {
                let (dx, dy, dz) = ((x as f64 + 0.5 - c.0) / rh, (y as f64 + 0.5 - c.1) / rv, (z as f64 + 0.5 - c.2) / rh);
                if dx * dx + dy * dy + dz * dz <= 1.0 {
                    out.push((x, y, z));
                }
            }
        }
    }
    out
}

/// Terraria's Full Desert pass under the Desert round `center` (`radius`
/// its region's). Returns the hive.
pub fn underground_desert(w: &mut World, seed: i32, l: &Layers, center: (i32, i32), radius: i32, coast: Option<&Coast>) -> Option<Hive> {
    let ids = Ids::new(w);
    if ids.sand == 0 || ids.hardened == 0 || ids.sandstone == 0 {
        return None;
    }
    let mut rng = Rng::new(seed as u64 ^ 0xde5e_27_41fe);
    let half = radius as f64 * HIVE_OF_DESERT;
    let (cx, cz) = center;
    let land = |x: i32, z: i32| coast.map_or(true, |c| c.inland(x, z) >= c.ocean.width + c.ocean.beach + 4.0);
    // DesertDescription: the ground over it (its width and 5 tiles each
    // side), its average and its lowest.
    let mound = half + 5.0 * TILE;
    let (mut sum, mut n, mut low) = (0i64, 0i64, i32::MAX);
    let r = mound.ceil() as i32;
    for dz in -r..=r {
        for dx in -r..=r {
            let (x, z) = (cx + dx, cz + dz);
            if ((dx * dx + dz * dz) as f64) > mound * mound || !w.in_bounds(x, 0, z) || !land(x, z) {
                continue;
            }
            let g = ground(w, x, z);
            if g > 0 {
                sum += g as i64;
                n += 1;
                low = low.min(g);
            }
        }
    }
    if n == 0 {
        return None;
    }
    let mid = ((sum / n) as i32 + low) / 2;
    let top_t = tiles_below(l, mid as f64) + rng.range(40, 60) as f64;
    let rows = ((rng.unit() * 0.5 + 1.5) * 170.0) as i32;
    let bottom_t = (top_t + 2.0 * rows as f64).min(690.0);
    let hive = Hive { center, half, top: crate::dungeon::depth_y(l, top_t), bottom: crate::dungeon::depth_y(l, bottom_t), ground: mid };
    if hive.top - hive.bottom < 8 {
        return None;
    }
    sand_mound(w, seed, &ids, &hive, &land);
    if rng.unit() <= 0.3333 {
        // (Its "desert_entrance" decoration's style: which, there.)
        let kind = rng.range(0, 4);
        let at = match kind {
            0 => chambers(w, &mut rng, &ids, &hive),
            1 => anthills(w, &mut rng, &ids, &hive),
            2 => larva_holes(w, &mut rng, &ids, &hive),
            _ => pit(w, &mut rng, &ids, &hive),
        };
        w.decorations.push(Decoration { kind: "desert_entrance".into(), pos: at, style: kind });
    }
    carve_hive(w, &mut rng, seed, &ids, &hive);
    variance(w, &mut rng, &ids, &hive);
    Some(hive)
}

/// SandMound.Place: sand from the Desert's top down to the hive's middle.
fn sand_mound(w: &mut World, seed: i32, ids: &Ids, h: &Hive, land: &dyn Fn(i32, i32) -> bool) {
    let n_top = noise(seed ^ 0x5a4d, 0.06, 1);
    let n_cut = noise(seed ^ 0x5a4e, 0.09, 1);
    let mid_y = (h.top + h.bottom) / 2;
    // Its dome: as high as the hive's top half (Terraria's Hive.Height / 2).
    let dome = (h.top - h.bottom) as f64 / 2.0;
    let radius = h.half + 5.0 * TILE;
    let r = radius.ceil() as i32;
    for dz in -r..=r {
        for dx in -r..=r {
            let (x, z) = (h.center.0 + dx, h.center.1 + dz);
            let d = ((dx * dx + dz * dz) as f64).sqrt() / radius;
            if d > 1.0 || !w.in_bounds(x, 0, z) || !land(x, z) {
                continue;
            }
            let (fx, fz) = (x as f32, z as f32);
            let top = h.ground as f64 - dome * (1.0 - (1.0 - d.powi(4)).max(0.0).sqrt()) + n_top.get_noise_2d(fx, fz) as f64 * 2.0;
            let top = top.round() as i32;
            if d < 1.0 {
                // Over its middle the ground goes down to 10 tiles under its
                // top; past half way out less, to 10 tiles over at the edge.
                let s = ((d - 0.5) / 0.3).clamp(0.0, 1.0);
                let s = s * s * (3.0 - 2.0 * s);
                let cut = h.ground as f64 - (10.0 - s * s * s * 20.0) * TILE + n_cut.get_noise_2d(fx, fz) as f64 * 2.0;
                let cut = (cut.round() as i32).max(top);
                for y in cut + 1..(h.ground + 40).min(w.sy) {
                    if w.get(x, y, z) != 0 || w.liquid_at(x, y, z).1 > 0 {
                        clear(w, (x, y, z));
                    }
                }
            }
            for y in mid_y + 1..=top.min(w.sy - 1) {
                put(w, (x, y, z), ids.sand);
            }
        }
    }
}

/// Where along a line across the Desert the i-th of `n` goes (Terraria's
/// (i + 1) / (n + 1) of the way across), on the ground.
fn across(w: &World, h: &Hive, dir: (f64, f64), i: i32, n: i32) -> P {
    let t = ((i + 1) as f64 / (n + 1) as f64 * 2.0 - 1.0) * (h.half + 5.0 * TILE);
    let (x, z) = ((h.center.0 as f64 + dir.0 * t).round() as i32, (h.center.1 as f64 + dir.1 * t).round() as i32);
    (x, ground(w, x, z), z)
}

fn random_dir(rng: &mut Rng) -> (f64, f64) {
    let a = rng.unit() * std::f64::consts::TAU;
    (a.cos(), a.sin())
}

/// Where a burrow from the ground at `y` ends: the hive's top, as far under
/// it again as `y` is under the Desert's top, and 12 tiles more.
fn burrow_end(h: &Hive, y: i32) -> i32 {
    h.top - 2 * (h.ground - y).max(0) - (12.0 * TILE).round() as i32
}

/// A burrow's step at `p`: it (and a blotch round it) cleared, the solid
/// ground 2 tiles round (3 up and down) to hardened sand.
fn burrow(w: &mut World, rng: &mut Rng, ids: &Ids, p: P, walled: &mut HashSet<P>) {
    clear(w, p);
    walled.insert(p);
    for d in [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)] {
        if rng.unit() < 0.3 {
            let q = (p.0 + d.0, p.1, p.2 + d.2);
            clear(w, q);
            walled.insert(q);
        }
    }
    let c = (p.0 as f64 + 0.5, p.1 as f64 + 0.5, p.2 as f64 + 0.5);
    for q in ellipsoid(c, 2.0 * TILE + 0.5, 3.0 * TILE + 0.5) {
        if w.in_bounds(q.0, q.1, q.2) && w.is_solid(q.0, q.1, q.2) {
            put(w, q, ids.hardened);
            walled.insert(q);
        }
    }
}

/// A burrow down from `p` to `end`, wandering a block every 3 tiles.
fn dig_down(w: &mut World, rng: &mut Rng, ids: &Ids, mut p: P, end: i32, walled: &mut HashSet<P>, mut each: impl FnMut(&mut World, &mut Rng, P, &mut HashSet<P>)) {
    let step = (3.0 * TILE).round().max(1.0) as i32;
    while p.1 > end && p.1 > 1 {
        burrow(w, rng, ids, p, walled);
        if p.1 % step == 0 {
            match rng.range(0, 3) {
                0 => {}
                k => {
                    let s = if k == 1 { -1 } else { 1 };
                    if rng.chance(0.5) {
                        p.0 += s;
                    } else {
                        p.2 += s;
                    }
                }
            }
            burrow(w, rng, ids, p, walled);
            each(w, rng, p, walled);
        }
        p.1 -= 1;
    }
}

/// LarvaHoleEntrance: 2-3 funnels 13-15 tiles round across the Desert, a
/// burrow down from each.
fn larva_holes(w: &mut World, rng: &mut Rng, ids: &Ids, h: &Hive) -> P {
    let n = rng.range(2, 4);
    let dir = random_dir(rng);
    let mut first = None;
    for i in 0..n {
        let r = rng.range(13, 16) as f64 * TILE;
        let p = across(w, h, dir, i, n);
        let ri = r.ceil() as i32;
        for dz in -ri..=ri {
            for dx in -ri..=ri {
                let d = ((dx * dx + dz * dz) as f64).sqrt();
                // The air over it (2 x its size up), then a funnel 1.5 x its
                // size deep narrowing to the burrow.
                if dx.abs() as f64 <= r && dz.abs() as f64 <= r {
                    for y in p.1 + 1..=(p.1 + (2.0 * r) as i32).min(w.sy - 1) {
                        clear(w, (p.0 + dx, y, p.2 + dz));
                    }
                }
                let deep = 1.5 * r * (1.0 - d / r);
                for k in 0..=deep.floor() as i32 {
                    clear(w, (p.0 + dx, p.1 - k, p.2 + dz));
                }
            }
        }
        let start = (p.0, p.1 - (1.5 * r) as i32, p.2);
        let mut walled = HashSet::new();
        dig_down(w, rng, ids, start, burrow_end(h, p.1), &mut walled, |_, _, _, _| {});
        first.get_or_insert(p);
    }
    first.unwrap()
}

/// AnthillEntrance: 2-3 cones of sand 15-17 tiles round across the Desert,
/// a crater on each, a burrow down from it in a column of sand.
fn anthills(w: &mut World, rng: &mut Rng, ids: &Ids, h: &Hive) -> P {
    let n = rng.range(2, 4);
    let dir = random_dir(rng);
    let mut first = None;
    for i in 0..n {
        let a = rng.range(15, 18) as f64;
        let r = a * TILE;
        let p = across(w, h, dir, i, n);
        // Its cone from 6 tiles under the ground, 1.5 x its size up.
        let base = p.1 - (6.0 * TILE).round() as i32;
        let tall = 1.5 * r;
        let ri = r.ceil() as i32;
        for dz in -ri..=ri {
            for dx in -ri..=ri {
                let d = ((dx * dx + dz * dz) as f64).sqrt();
                if d > r {
                    continue;
                }
                let up = (tall * (1.0 - d / r)).floor() as i32;
                for k in 0..=up {
                    put(w, (p.0 + dx, base + k, p.2 + dz), ids.sand);
                }
            }
        }
        let mut walled = HashSet::new();
        // From over its top down: below the ground every 3 tiles, 5 tiles
        // under it on, a disc of sand round it (but the burrow's cells).
        let start = (p.0, p.1 + ((a + 3.0) * TILE).round() as i32, p.2);
        let ground_y = p.1;
        let deep = p.1 - (5.0 * TILE).round() as i32;
        let sand = ids.sand;
        dig_down(w, rng, ids, start, burrow_end(h, p.1), &mut walled, move |w, _, q, walled| {
            if q.1 > ground_y || q.1 > deep {
                return;
            }
            let c = (q.0 as f64 + 0.5, q.1 as f64 + 0.5, q.2 as f64 + 0.5);
            for s in ellipsoid(c, r, 3.0 * TILE) {
                if !walled.contains(&s) {
                    put(w, s, sand);
                }
            }
            for s in ellipsoid(c, r - 2.0 * TILE, 3.0 * TILE) {
                walled.insert(s);
            }
        });
        // The crater at its top.
        let c = (p.0 as f64 + 0.5, (base as f64 + tall - 3.0 * TILE) + 0.5, p.2 as f64 + 0.5);
        for s in ellipsoid(c, a / 2.0 * TILE + 1.0, a / 3.0 * TILE + 1.0) {
            clear(w, s);
        }
        first.get_or_insert(p);
    }
    first.unwrap()
}

/// PitEntrance: a shaft 6-8 tiles round down the Desert's middle to 10
/// tiles into the hive, from 60% of the way down narrowing to half; past a
/// third of the way down 3 tiles of hardened sand round it; a funnel at
/// its top.
fn pit(w: &mut World, rng: &mut Rng, ids: &Ids, h: &Hive) -> P {
    let a = rng.range(6, 9) as f64;
    let r = (a + 3.0) * TILE;
    let ri = r.ceil() as i32 + 1;
    let (cx, cz) = h.center;
    let at = (cx, ground(w, cx, cz), cz);
    let span = (h.ground - h.top).max(1) as f64;
    let end = h.top - (10.0 * TILE).round() as i32;
    let scale = |t: f64| {
        if t < 0.6 {
            1.0
        } else {
            let s = (t - 0.6) / 0.4;
            let s = 1.0 - (s * std::f64::consts::PI).cos() * 0.5 - 0.5;
            (1.0 - s) * 0.5 + 0.5
        }
    };
    for dz in -ri..=ri {
        for dx in -ri..=ri {
            let (x, z) = (cx + dx, cz + dz);
            let d = ((dx * dx + dz * dz) as f64).sqrt() / TILE;
            let g = ground(w, x, z);
            for y in (end..=g).rev() {
                let t = ((g - y) as f64 / span).clamp(0.0, 1.0);
                let hole = scale(t) * a;
                if d < hole {
                    clear(w, (x, y, z));
                } else if d < hole + 3.0 && t > 0.35 {
                    put(w, (x, y, z), ids.hardened);
                }
            }
        }
    }
    // The funnel: down from the ground min(10, (size + 4 - out)^2) tiles.
    let f = a + 4.0;
    let fi = (f * TILE).ceil() as i32;
    for dz in -fi..=fi {
        for dx in -fi..=fi {
            let d = ((dx * dx + dz * dz) as f64).sqrt() / TILE;
            if d >= f {
                continue;
            }
            let deep = ((f - d) * (f - d)).min(10.0) * TILE;
            let (x, z) = (cx + dx, cz + dz);
            let g = ground(w, x, z);
            for k in 0..deep.round() as i32 {
                clear(w, (x, g - k, z));
            }
        }
    }
    at
}

/// ChambersEntrance: a drift of sand (24 tiles round, 12 deep) near the
/// Desert's middle; 2-3 caves (18-28 tiles across, 6 tall) under it in turn
/// either side, the last at the hive's top; a winding passage (2 tiles
/// wide, 4 tall) from the surface through each; sand round them hardened.
fn chambers(w: &mut World, rng: &mut Rng, ids: &Ids, h: &Hive) -> P {
    let off = random_dir(rng);
    let k = rng.unit() * 40.0 * TILE;
    let (x, z) = ((h.center.0 as f64 + off.0 * k).round() as i32, (h.center.1 as f64 + off.1 * k).round() as i32);
    let g = ground(w, x, z);
    let o = (x as f64 + 0.5, g as f64 - 2.0 * TILE + 0.5, z as f64 + 0.5);
    for s in ellipsoid(o, 24.0 * TILE, 12.0 * TILE) {
        if rng.unit() < 0.95 {
            put(w, s, ids.sand);
        }
    }
    // Along a line across (u), in tiles from the drift's middle.
    let u = random_dir(rng);
    let at = |along: f64, down: f64| (o.0 + u.0 * along * TILE, o.1 - down * TILE, o.2 + u.1 * along * TILE);
    let depth = (g - h.top) as f64 / TILE;
    let mut side = if rng.chance(0.5) { 1.0 } else { -1.0 };
    // (where along, how far down, which way it leaves)
    let mut joins: Vec<(f64, f64, f64)> = vec![(-side * 26.0, -8.0 - 2.0, side)];
    let mut open: Vec<P> = Vec::new();
    let n = rng.range(2, 4);
    for i in 0..n {
        let down = (i + 1) as f64 / n as f64 * depth + rng.range(-8, 9) as f64;
        let along = side * rng.range(20, 41) as f64;
        let wide = rng.range(18, 29) as f64;
        for s in ellipsoid(at(along, down), wide / 2.0 * TILE, 3.0 * TILE) {
            if w.in_bounds(s.0, s.1, s.2) && w.is_solid(s.0, s.1, s.2) {
                clear(w, s);
            }
            open.push(s);
        }
        joins.push((along - wide / 2.0 * side, down, -side));
        side = -side;
    }
    // The passages: Terraria's curve from each join to the next, bowing out
    // the way each leaves (1.5 x the way between them).
    for i in 1..joins.len() {
        let (a, b) = (joins[i - 1], joins[i]);
        let bow = (b.0 - a.0).abs() * 1.5;
        let mut t = 0.0;
        while t <= 1.0 {
            let lerp = |p: (f64, f64), q: (f64, f64), t: f64| (p.0 + (q.0 - p.0) * t, p.1 + (q.1 - p.1) * t);
            let p19 = (b.0 + b.2 * bow * (1.0 - t), b.1);
            let p20 = lerp((a.0, a.1), (b.0, b.1), t);
            let p21 = lerp(p20, p19, t);
            let p = lerp(lerp((a.0 + a.2 * bow * t, a.1), p20, t), p21, t);
            // A 2 x 2 x 4 tile box down from it.
            let c = at(p.0, p.1);
            for dy in 0..(4.0 * TILE).ceil() as i32 {
                for dz in 0..(2.0 * TILE).ceil() as i32 {
                    for dx in 0..(2.0 * TILE).ceil() as i32 {
                        let s = (c.0.floor() as i32 + dx, c.1.floor() as i32 - dy, c.2.floor() as i32 + dz);
                        if w.in_bounds(s.0, s.1, s.2) && w.is_solid(s.0, s.1, s.2) {
                            clear(w, s);
                        }
                        open.push(s);
                    }
                }
            }
            t += 0.02;
        }
    }
    // Their outline's sand to hardened sand.
    let opened: HashSet<P> = open.iter().copied().collect();
    for &p in &open {
        for d in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
            let q = (p.0 + d.0, p.1 + d.1, p.2 + d.2);
            if !opened.contains(&q) && w.in_bounds(q.0, q.1, q.2) && w.get(q.0, q.1, q.2) == ids.sand {
                put(w, q, ids.hardened);
            }
        }
    }
    let p = at(joins[0].0, joins[0].1);
    (p.0 as i32, p.1 as i32, p.2 as i32)
}

/// ClusterGroup.Generate in 3D: the clusters' points, in cells.
fn clusters(rng: &mut Rng, cols: i32, rows: i32) -> Vec<Vec<V>> {
    let (nx, ny, nz) = (cols.max(1), rows.max(1), cols.max(1));
    let at = |x: i32, y: i32, z: i32| ((y * nz + z) * nx + x) as usize;
    let mut set = vec![false; (nx * ny * nz) as usize];
    let (l1, l2) = (cols / 2 - 1, rows / 2 - 1);
    if l1 < 1 || l2 < 1 {
        return Vec::new();
    }
    let l3 = ((l1 + 1) * (l1 + 1)) as f64;
    for y in 0..=2 * l2 {
        let l8 = l1 as f64 / l2 as f64 * (y - l2) as f64;
        let rr = l3 - l8 * l8;
        if rr < 0.0 {
            continue;
        }
        let r = (l1 as f64).min(rr.sqrt().floor());
        for z in 0..nz {
            for x in 0..nx {
                let (dx, dz) = ((x - l1) as f64, (z - l1) as f64);
                if dx * dx + dz * dz <= r * r && y < ny {
                    set[at(x, y, z)] = rng.range(0, 2) == 0;
                }
            }
        }
    }
    const NB: [P; 6] = [(-1, 0, 0), (1, 0, 0), (0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1)];
    let inside = |p: P| p.0 >= 0 && p.0 < nx && p.1 >= 0 && p.1 < ny && p.2 >= 0 && p.2 < nz;
    fn search(set: &mut [bool], at: &dyn Fn(i32, i32, i32) -> usize, inside: &dyn Fn(P) -> bool, p: P, out: &mut Vec<P>, depth: i32) {
        out.push(p);
        set[at(p.0, p.1, p.2)] = false;
        if depth - 1 == -1 {
            return;
        }
        for d in NB {
            let q = (p.0 + d.0, p.1 + d.1, p.2 + d.2);
            if inside(q) && set[at(q.0, q.1, q.2)] {
                search(set, at, inside, q, out, depth - 1);
            }
        }
    }
    let mut groups: Vec<Vec<P>> = Vec::new();
    for x in 0..nx {
        for y in 0..ny {
            for z in 0..nz {
                if set[at(x, y, z)] && rng.range(0, 2) == 0 {
                    let mut out = Vec::new();
                    search(&mut set, &at, &inside, (x, y, z), &mut out, 2);
                    if out.len() > 2 {
                        groups.push(out);
                    }
                }
            }
        }
    }
    // Clusters that touch: one swallows or wipes out the other.
    let mut owner = vec![-1i32; (nx * ny * nz) as usize];
    for (i, g) in groups.iter().enumerate() {
        for &p in g {
            owner[at(p.0, p.1, p.2)] = i as i32;
        }
    }
    for i in 0..groups.len() {
        for k in 0..groups[i].len() {
            let p = groups[i][k];
            let me = owner[at(p.0, p.1, p.2)];
            if me == -1 {
                break;
            }
            for d in NB {
                let q = (p.0 + d.0, p.1 + d.1, p.2 + d.2);
                if !inside(q) {
                    continue;
                }
                let o = owner[at(q.0, q.1, q.2)];
                if o != -1 && o != me {
                    let v = if rng.range(0, 2) == 0 { -1 } else { me };
                    for &s in &groups[o as usize] {
                        owner[at(s.0, s.1, s.2)] = v;
                    }
                }
            }
        }
    }
    let mut lists: Vec<Vec<P>> = vec![Vec::new(); groups.len()];
    for x in 0..nx {
        for y in 0..ny {
            for z in 0..nz {
                let o = owner[at(x, y, z)];
                if o != -1 {
                    lists[o as usize].push((x, y, z));
                }
            }
        }
    }
    lists
        .into_iter()
        .filter(|c| c.len() >= 4)
        .map(|c| {
            c.iter()
                .map(|p| (p.0 as f64 + (rng.unit() - 0.5) * 0.5, p.1 as f64 + (rng.unit() - 0.5) * 0.5, p.2 as f64 + (rng.unit() - 0.5) * 0.5))
                .collect()
        })
        .collect()
}

/// DesertHive.PlaceClustersArea: the hive's caves, sandstone and sand.
fn carve_hive(w: &mut World, rng: &mut Rng, seed: i32, ids: &Ids, h: &Hive) {
    let cols = ((2.0 * h.half / TILE) / 4.0).round() as i32;
    let rows = (((h.top - h.bottom) as f64 / TILE) / 2.0).round() as i32;
    let cl = clusters(rng, cols, rows);
    if cl.is_empty() {
        return;
    }
    let (x0, z0) = (h.center.0 as f64 - h.half, h.center.1 as f64 - h.half);
    // A block's place in cells (Terraria's (tile - scale / 2) / scale).
    let gx = |x: f64| ((x + 0.5 - x0) / TILE - 2.0) / 4.0;
    let gz = |z: f64| ((z + 0.5 - z0) / TILE - 2.0) / 4.0;
    let gy = |y: f64| ((h.top as f64 + 0.5 - y) / TILE - 1.0) / 2.0;
    // Each cluster's box (cells).
    let boxes: Vec<(V, V)> = cl
        .iter()
        .map(|c| {
            let mut lo = (f64::MAX, f64::MAX, f64::MAX);
            let mut hi = (f64::MIN, f64::MIN, f64::MIN);
            for p in c {
                lo = (lo.0.min(p.0), lo.1.min(p.1), lo.2.min(p.2));
                hi = (hi.0.max(p.0), hi.1.max(p.1), hi.2.max(p.2));
            }
            ((lo.0 - REACH, lo.1 - REACH, lo.2 - REACH), (hi.0 + REACH, hi.1 + REACH, hi.2 + REACH))
        })
        .collect();
    let bx0 = (x0 - ROUND).floor() as i32;
    let bx1 = (x0 + 2.0 * h.half + ROUND).ceil() as i32;
    let bz0 = (z0 - ROUND).floor() as i32;
    let bz1 = (z0 + 2.0 * h.half + ROUND).ceil() as i32;
    let by0 = ((h.bottom as f64 - ROUND).floor() as i32).max(1);
    let by1 = ((h.top as f64 + ROUND).ceil() as i32).min(w.sy - 1);
    let (nx, nz) = ((bx1 - bx0 + 1) as usize, (bz1 - bz0 + 1) as usize);
    let tseed = seed as u64 ^ 0xdead;
    let world = &*w;
    let changes: Vec<(usize, u16)> = (by0..=by1)
        .into_par_iter()
        .flat_map_iter(|y| {
            let cy = gy(y as f64);
            let mut best = vec![0.0f64; nx * nz];
            let mut second = vec![0.0f64; nx * nz];
            let mut who = vec![-1i32; nx * nz];
            for (i, c) in cl.iter().enumerate() {
                let (lo, hi) = boxes[i];
                if cy < lo.1 || cy > hi.1 {
                    continue;
                }
                // Its blocks' range.
                let xa = ((x0 + (4.0 * lo.0 + 2.0) * TILE).floor() as i32).max(bx0);
                let xb = ((x0 + (4.0 * hi.0 + 2.0) * TILE).ceil() as i32).min(bx1);
                let za = ((z0 + (4.0 * lo.2 + 2.0) * TILE).floor() as i32).max(bz0);
                let zb = ((z0 + (4.0 * hi.2 + 2.0) * TILE).ceil() as i32).min(bz1);
                if xa > xb || za > zb {
                    continue;
                }
                let pts: Vec<(f64, f64, f64)> = c.iter().filter(|p| (p.1 - cy).abs() < REACH).map(|p| (p.0, (p.1 - cy) * (p.1 - cy), p.2)).collect();
                if pts.is_empty() {
                    continue;
                }
                for z in za..=zb {
                    let cz = gz(z as f64);
                    for x in xa..=xb {
                        let cx = gx(x as f64);
                        let mut s = 0.0;
                        for p in &pts {
                            let d2 = (p.0 - cx) * (p.0 - cx) + p.1 + (p.2 - cz) * (p.2 - cz);
                            if d2 < REACH * REACH {
                                s += 1.0 / d2.max(1e-6);
                            }
                        }
                        let k = (z - bz0) as usize * nx + (x - bx0) as usize;
                        if s > best[k] {
                            second[k] = best[k].max(second[k]);
                            best[k] = s;
                            who[k] = i as i32;
                        } else if s > second[k] {
                            second[k] = s;
                        }
                    }
                }
            }
            let mut out = Vec::new();
            let ny = 2.0 * cy / rows as f64 - 1.0;
            for z in bz0..=bz1 {
                for x in bx0..=bx1 {
                    if !world.in_bounds(x, y, z) {
                        continue;
                    }
                    let k = (z - bz0) as usize * nx + (x - bx0) as usize;
                    let tot = best[k] + second[k];
                    let (nxx, nzz) = (2.0 * gx(x as f64) / cols as f64 - 1.0, 2.0 * gz(z as f64) / cols as f64 - 1.0);
                    let inner = (nxx * nxx + ny * ny + nzz * nzz).sqrt() < 0.8;
                    let i = world.idx(x, y, z);
                    let solid = world.blocks[i] != 0;
                    let p = (x, y, z);
                    let sand = if hash01(tseed, p) < 1.0 / 3.0 { ids.hardened } else { ids.sand };
                    let b = if tot > OPEN {
                        if who[k] % 15 == 2 && ids.fossil != 0 {
                            Some(ids.fossil)
                        } else {
                            Some(0)
                        }
                    } else if tot > SANDSTONE {
                        (inner || solid).then_some(ids.sandstone)
                    } else if tot > SAND || inner {
                        (inner || solid).then_some(sand)
                    } else if tot > MAYBE_SAND && solid && hash01(tseed ^ 0x77, p) < (tot - MAYBE_SAND) / (SAND - MAYBE_SAND) {
                        Some(sand)
                    } else {
                        None
                    };
                    if let Some(b) = b {
                        out.push((i, b));
                    }
                }
            }
            out
        })
        .collect();
    for (i, b) in changes {
        w.blocks[i] = b;
        w.liquid[i] = 0;
    }
}

/// DesertHive.AddTileVariance: sand that would fall to hardened sand; the
/// sandstone's stalactites and stalagmites.
fn variance(w: &mut World, rng: &mut Rng, ids: &Ids, h: &Hive) {
    let r = (h.half + ROUND).ceil() as i32;
    let (y0, y1) = (((h.bottom as f64 - ROUND) as i32).max(3), ((h.top as f64 + ROUND) as i32).min(w.sy - 4));
    let (cx, cz) = h.center;
    for x in cx - r..=cx + r {
        for z in cz - r..=cz + r {
            if !w.in_bounds(x, 0, z) {
                continue;
            }
            for y in (y0..=y1).rev() {
                if w.get(x, y, z) == ids.sand && (!w.is_solid(x, y - 1, z) || !w.is_solid(x, y - 2, z)) {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = ids.hardened;
                }
            }
        }
    }
    for x in cx - r..=cx + r {
        for z in cz - r..=cz + r {
            if !w.in_bounds(x, 0, z) {
                continue;
            }
            for y in (y0..=y1).rev() {
                if w.get(x, y, z) != ids.sandstone {
                    continue;
                }
                let up = (1..=3).all(|k| w.get(x, y + k, z) == 0);
                let down = (1..=3).all(|k| w.get(x, y - k, z) == 0);
                // Antlion Eggs (1 in 20 on the floor) and Rolling Cactus (1 in
                // 5 of the rest) take their turns, though not here yet.
                if up && rng.range(0, 20) == 0 {
                    continue;
                }
                if up && rng.range(0, 5) == 0 {
                    continue;
                }
                if (up ^ down) && rng.range(0, 5) == 0 {
                    let small = rng.range(0, 2) == 0;
                    let (kinds, at) = if up { (ids.stalagmites, y + 1) } else { (ids.stalactites, y - 1) };
                    let b = kinds[small as usize];
                    if b != 0 {
                        let i = w.idx(x, at, z);
                        w.blocks[i] = b;
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CUBE};
    use std::collections::VecDeque;

    /// Sand to y 150 in a world 192 tall, over a hive from 40 to 120.
    fn sand_world() -> (World, Hive) {
        let mut w = World::new();
        for (i, n) in ["sand", "hardened_sand", "sandstone", "desert_fossil"].iter().enumerate() {
            w.set_def(i as u16 + 1, BlockDef { name: (*n).into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        }
        w.resize(200, 192, 200);
        for x in 0..200 {
            for z in 0..200 {
                for y in 0..=150 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 1;
                }
            }
        }
        (w, Hive { center: (100, 100), half: 60.0, top: 120, bottom: 40, ground: 150 })
    }

    /// The lowest open cell reached from the air over the Desert.
    fn lowest_reached(w: &World) -> i32 {
        let mut seen = vec![false; w.blocks.len()];
        let mut queue = VecDeque::new();
        for x in 40..160 {
            for z in 40..160 {
                let y = 175;
                seen[w.idx(x, y, z)] = true;
                queue.push_back((x, y, z));
            }
        }
        let mut low = 175;
        while let Some(p) = queue.pop_front() {
            low = low.min(p.1);
            for d in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                let q = (p.0 + d.0, p.1 + d.1, p.2 + d.2);
                if q.0 < 30 || q.0 > 170 || q.2 < 30 || q.2 > 170 || q.1 < 1 || q.1 > 180 {
                    continue;
                }
                let i = w.idx(q.0, q.1, q.2);
                if !seen[i] && w.blocks[i] == 0 {
                    seen[i] = true;
                    queue.push_back(q);
                }
            }
        }
        low
    }

    /// Terraria's four ways into the Underground Desert: each opens a way
    /// from the surface down to the hive's top, and its sand holds.
    #[test]
    fn the_four_entrances() {
        for kind in 0..4 {
            let (mut w, h) = sand_world();
            let ids = Ids::new(&w);
            let mut rng = Rng::new(kind as u64 + 7);
            let at = match kind {
                0 => chambers(&mut w, &mut rng, &ids, &h),
                1 => anthills(&mut w, &mut rng, &ids, &h),
                2 => larva_holes(&mut w, &mut rng, &ids, &h),
                _ => pit(&mut w, &mut rng, &ids, &h),
            };
            let low = lowest_reached(&w);
            let hardened = w.blocks.iter().filter(|&&b| b == ids.hardened).count();
            eprintln!("entrance {kind} at {at:?}: down to {low}, {hardened} hardened sand");
            assert!(low <= h.top + 2, "entrance {kind} reaches the hive's top ({low})");
            assert!(hardened > 100, "entrance {kind} lined with hardened sand ({hardened})");
            if kind == 1 {
                assert!((151..175).any(|y| w.get(at.0, y, at.2) == ids.sand || w.get(at.0 + 3, y, at.2) == ids.sand), "an anthill of sand over the ground");
            }
        }
    }
}
