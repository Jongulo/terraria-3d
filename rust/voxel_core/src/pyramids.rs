//! Terraria's Dunes and Pyramids, in 3D.
//!
//! - **Dunes** (the "Dunes" pass, DunesBiome): 1-2 patches per 4200 tiles of
//!   width (here: 1-2 in a small world, 1-3 medium, 2-4 large, by its area as
//!   the cabins count it), inland, away from spawn, the mountains and the big
//!   biomes. Each is two single dunes side by side along the wind, 150-250
//!   tiles long each (here x `scale`: two thirds in a small world), overlapping
//!   by 60. A single dune is 8-10 hills along it, the middle ones the tallest
//!   (35 tiles x 0.2-0.5), and 1-2 big ones (35 x 0.8) half its length, round
//!   its middle; a hill's peak leans downwind (a quarter to a sixteenth of its
//!   half), each side a curve bowed up. Sand fills from the hills' line down
//!   to sqrt(half length - distance from its middle) x 3 under the ground, and
//!   10 above it is cleared of anything but sand. Here the line runs across
//!   the patch, tapering to nothing at its sides (an ellipse a bit over half
//!   as wide as it's long), its crests wavering. Each dune has a 0.8 chance of
//!   a Pyramid (ChanceOfPyramid), a spot in its middle. Cacti grow on it.
//! - **Pyramids** (the "Pyramids" pass, WorldGen.Pyramid), after the Dungeon:
//!   at the spot, where the sand still goes 20 down (else none), at least 220
//!   (x `scale`) from another Pyramid, and not within 15% of the world's width
//!   of the Dungeon; here also out of the structures before it. Its tip 1-7
//!   above the sand 20 down (13-19 under the dune), a solid square pyramid of
//!   Sandstone Brick 75-124 rows down, each row one wider each way. Inside,
//!   in one upright plane (Terraria's 2D) three wide:
//!   - the entrance: 9-12 down and 9-12 to one side, 6-8 tall, dug out
//!     through the brick to the face; where sand lies over it outside, it's
//!     filled with sand;
//!   - a corridor from there down a block a step, across 20-29 steps, back
//!     15-19, then the treasure room, on 10-14, and back and forth 20-39 at a
//!     time to near the bottom;
//!   - the treasure room, 23-27 long, 8-13 tall with its ends' ceilings
//!     stepped down, and here 9-13 across: a Gold Chest against a wall
//!     (Pharaoh's Mask and Robe 1 time in 9, else Sandstorm in a Bottle or
//!     the Flying Carpet; Chests' "pyramid" loot), 1-9 coin stashes, a
//!     Pyramid pot on every other floor cell (here off the walkway along its
//!     middle) and four banners (Ankh, Snake, Omega) by its ceiling's ends;
//!   - below it a shaft as wide as the corridor is tall, leaning a block
//!     a row, swinging back every 10-49 rows, lined with 5-9 of brick, at
//!     least 100-199 rows long and then until it opens into a cave below
//!     (at most 500-799). Terraria's rows below its rock layer are about a
//!     fifth of a block here (dungeon::depth_y), so here they're scaled so.

use std::collections::HashSet;

use crate::world::{Decoration, World};
use crate::worldgen::{Coast, Layers, Ocean, Rng, FACING};

type P = (i32, i32, i32);
type Box3 = (P, P);

/// A dune patch: its middle, the wind's direction (a unit vector across the
/// map), its half length along it and half width across it.
#[derive(Clone, Copy, Debug)]
pub struct Dunes {
    pub x: i32,
    pub z: i32,
    pub wind: (f64, f64),
    pub half_len: f64,
    pub half_wide: f64,
    /// Rolled at the Dunes pass (ChanceOfPyramid), built after the Dungeon.
    pub pyramid: bool,
    /// The structure box it was given (not one a Pyramid keeps out of).
    pub area: Box3,
}

const CHANCE_OF_PYRAMID: f64 = 0.8;
/// Its width across the wind as a share of its length.
const ACROSS: f64 = 0.55;
/// A Pyramid's widest reach from its middle (124 rows + 7 above).
const PYRAMID_REACH: i32 = 131;

/// Dunes' sizes for this world's size: Terraria's in a large world, half
/// in a small one (its biomes are as much smaller).
fn scale(w: &World) -> f64 {
    (w.sx.min(w.sz) as f64 / 1536.0).min(1.0)
}

/// The Dunes pass. Returns the patches made.
pub fn dunes(w: &mut World, rng: &mut Rng, coast: &Coast, sea: &Ocean, peaks: &[(i32, i32)], l: &Layers) -> Vec<Dunes> {
    let mut out = Vec::new();
    let (sand, cactus) = (w.id_of("sand"), w.id_of("cactus"));
    if sand == 0 {
        return out;
    }
    let sf = scale(w);
    let d = w.sx.min(w.sz);
    // Terraria's count, scaled with the width (WorldGenRange, ScaleWith WorldWidth).
    let s = ((w.sx as f64 * w.sz as f64).sqrt() / 640.0).max(1.0);
    let count = rng.range(((1.0 * s) as i32).max(1), (2.0 * s) as i32 + 1);
    let regions = crate::worldgen::biome_regions(w.sx, w.sz, w.seed);
    for _ in 0..count {
        let w1 = rng.range(150, 251) as f64 * sf;
        let w2 = rng.range(150, 251) as f64 * sf;
        let half_len = (w1 + w2) / 2.0 - 30.0 * sf;
        let half_wide = half_len * ACROSS;
        // One that will hold a Pyramid stays far enough from the world's
        // edges for it (Terraria's: 300 tiles; its worlds are far wider).
        let pyramid = rng.unit() < CHANCE_OF_PYRAMID;
        let a = if pyramid { PYRAMID_REACH + 4 + (half_len * 0.3) as i32 } else { half_len as i32 + 4 };
        let mut site = None;
        for _ in 0..400 {
            let (x, z) = (rng.range(a, (w.sx - a).max(a + 1)), rng.range(a, (w.sz - a).max(a + 1)));
            let d2 = |px: i32, pz: i32| (((px - x) * (px - x) + (pz - z) * (pz - z)) as f64).sqrt();
            // (Its ends taper away, so most of it clear is enough.)
            let clear = half_len * 0.6;
            if (coast.inland(x, z) as f64) < (sea.width + sea.beach) as f64 + clear + 10.0
                || d2(w.sx / 2, w.sz / 2) < clear + (d / 10) as f64
                || regions.iter().any(|&(_, bx, bz, br)| d2(bx, bz) < br as f64 + clear + 10.0)
                || peaks.iter().any(|&(px, pz)| d2(px, pz) < clear + 20.0)
                || out.iter().any(|o: &Dunes| d2(o.x, o.z) < o.half_len + half_len)
            {
                continue;
            }
            site = Some((x, z));
            break;
        }
        let Some((x, z)) = site else { continue };
        let ang = rng.unit() * std::f64::consts::TAU;
        let wind = (ang.cos(), ang.sin());
        // The line along the wind: the two singles side by side.
        let len = half_len.ceil() as i32 + 2;
        let mut bump = vec![0.0f64; (2 * len + 1) as usize];
        let mut depth = vec![0.0f64; (2 * len + 1) as usize];
        // (Terraria's at X - w1/2 + 30 and X + w2/2 - 30; centred here.)
        let mid = (w2 - w1) / 2.0;
        for (c, wd) in [(-w1 / 2.0 + 30.0 * sf - mid, w1), (w2 / 2.0 - 30.0 * sf - mid, w2)] {
            single(rng, sf, c, wd, len, &mut bump, &mut depth);
        }
        // Crests wavering across it, and its sides a little uneven.
        let (wave_amp, wave_len, wave_ph) = (6.0 * sf, 14.0 * sf + 6.0, rng.unit() * 6.28);
        let edge_ph = rng.unit() * 6.28;
        let reach = (half_len + 2.0) as i32;
        let (mut lo_y, mut hi_y) = (i32::MAX, i32::MIN);
        let mut tops: Vec<(i32, i32, i32)> = Vec::new();
        for gz in (z - reach)..=(z + reach) {
            for gx in (x - reach)..=(x + reach) {
                if !w.in_bounds(gx, 0, gz) {
                    continue;
                }
                let (dx, dz) = ((gx - x) as f64, (gz - z) as f64);
                let u = dx * wind.0 + dz * wind.1;
                let v = -dx * wind.1 + dz * wind.0;
                let edge = half_wide * (1.0 + 0.12 * (u / (half_len * 0.3) + edge_ph).sin());
                let f2 = 1.0 - (v / edge).powi(2);
                if f2 <= 0.0 {
                    continue;
                }
                let f = f2.sqrt();
                let uw = u + wave_amp * (v / wave_len + wave_ph).sin();
                let k = (uw.round() as i32 + len).clamp(0, 2 * len) as usize;
                let (b, dp) = (bump[k] * f, depth[k] * f);
                if dp < 0.5 && b < 0.5 {
                    continue;
                }
                let base = w.surface_y(gx, gz);
                if base <= 0 {
                    continue;
                }
                let top = (base + b.round() as i32).min(w.sy - 12);
                let bottom = (base - dp.round() as i32).max(l.underworld_top + 4);
                for y in bottom..=top {
                    let i = w.idx(gx, y, gz);
                    w.blocks[i] = sand;
                    w.liquid[i] = 0;
                }
                // Cleared above it (but sand).
                for y in top + 1..=(top + 10).min(w.sy - 1) {
                    let i = w.idx(gx, y, gz);
                    if w.blocks[i] != sand {
                        w.blocks[i] = 0;
                    }
                    w.liquid[i] = 0;
                }
                lo_y = lo_y.min(bottom);
                hi_y = hi_y.max(top);
                tops.push((gx, top, gz));
            }
        }
        if tops.is_empty() {
            continue;
        }
        // Cacti on it, as the desert's.
        if cactus != 0 {
            for &(cx, top, cz) in &tops {
                if (cx % 9 == 0 && cz % 9 == 0) && rng.chance(0.45) && w.get(cx, top + 1, cz) == 0 && top + 9 < w.sy {
                    for k in 1..=rng.range(3, 8) {
                        let i = w.idx(cx, top + k, cz);
                        w.blocks[i] = cactus;
                    }
                }
            }
        }
        let area = ((x - reach, lo_y.min(hi_y - 60), z - reach), (x + reach, hi_y + 10, z + reach));
        w.structures.push(area);
        out.push(Dunes { x, z, wind, half_len, half_wide, pyramid, area });
    }
    out
}

/// DunesBiome.PlaceSingle along the line: a single dune `wd` long round `c`.
fn single(rng: &mut Rng, sf: f64, c: f64, wd: f64, len: i32, bump: &mut [f64], depth: &mut [f64]) {
    let left = c - wd / 2.0;
    let downwind = if rng.range(0, 2) == 0 { 1.0 } else { -1.0 };
    let n = rng.range(0, 3) + 8;
    for i in 0..n - 1 {
        let hw = 2.0 / n as f64 * wd;
        let mid = i as f64 / n as f64 * wd + left + hw * 2.0 / 5.0 + rng.range(-5, 6) as f64 * sf;
        let t = i as f64 / (n - 2) as f64;
        let peak = 1.0 - (t - 0.5).abs() * 2.0;
        hill(rng, sf, mid - hw / 2.0, mid + hw / 2.0, peak * 0.3 + 0.2, downwind, len, bump);
    }
    for _ in 0..rng.range(0, 2) + 1 {
        let hw = wd / 2.0;
        let mid = c + rng.range(-10, 11) as f64 * sf;
        hill(rng, sf, mid - hw / 2.0, mid + hw / 2.0, 0.8, downwind, len, bump);
    }
    // The sand's depth: sqrt(half length - distance from its middle) x 3
    // (Terraria's tiles: as deep at the same share of the way along).
    for k in 0..bump.len() {
        let u = k as f64 - len as f64;
        let room = wd / 2.0 - (u - c).abs();
        if room > 0.0 {
            depth[k] = depth[k].max((room / sf).sqrt() * 3.0);
        }
    }
}

/// DunesBiome.PlaceHill from `a` to `b`, `h` its height (x 35): the peak
/// leaning downwind, each side a curve (quadratic, its middle bowed up 6 x h).
fn hill(rng: &mut Rng, sf: f64, a: f64, b: f64, h: f64, downwind: f64, len: i32, bump: &mut [f64]) {
    let mid = (a + b) / 2.0;
    let half = b - mid;
    let lean = rng.range((half / 16.0) as i32, (half / 4.0) as i32 + 1) as f64;
    let peak = (mid + lean * downwind, 35.0 * h * sf);
    let bow = 6.0 * h * sf;
    for (p0, p2) in [((a, 0.0), peak), (peak, (b, 0.0))] {
        let ctrl = ((p0.0 + p2.0) / 2.0, (p0.1 + p2.1) / 2.0 + bow);
        let steps = ((p2.0 - p0.0).abs() * 2.0).max(2.0) as i32;
        for s in 0..=steps {
            let t = s as f64 / steps as f64;
            let q = (1.0 - t) * (1.0 - t);
            let (m, r) = (2.0 * (1.0 - t) * t, t * t);
            let (u, y) = (q * p0.0 + m * ctrl.0 + r * p2.0, q * p0.1 + m * ctrl.1 + r * p2.1);
            let k = u.round() as i32 + len;
            if k >= 0 && (k as usize) < bump.len() {
                bump[k as usize] = bump[k as usize].max(y);
            }
        }
    }
}

pub struct Ids {
    brick: u16,
    sand: u16,
    cactus: u16,
    chest: u16,
    pots: [u16; 3],
    stashes: [u16; 3],
    banners: [u16; 3],
    dungeon_bricks: [u16; 3],
}

impl Ids {
    pub fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        Ids {
            brick: id("sandstone_brick"),
            sand: id("sand"),
            cactus: id("cactus"),
            chest: id("gold_chest"),
            pots: ["pyramid_pot", "pyramid_pot_2", "pyramid_pot_3"].map(id),
            stashes: ["copper_coin_stash", "silver_coin_stash", "gold_coin_stash"].map(id),
            banners: ["ankh_banner", "snake_banner", "omega_banner"].map(id),
            dungeon_bricks: ["blue_brick", "green_brick", "pink_brick"].map(id),
        }
    }
}

/// Chests' loot table for a Pyramid's chest (Chests.LOOT).
pub const PYRAMID_LOOT: i32 = 29;
/// A Pyramid's widest reach from its middle, for what keeps out of it.
pub const REACH: i32 = PYRAMID_REACH;

/// A Pyramid built: its middle, what it dug out, and what it put there (for
/// `restore`).
pub struct Built {
    pub x: i32,
    pub z: i32,
    pub chest: Option<P>,
    opened: Vec<P>,
    own: Vec<(P, u16)>,
    decs: Vec<Decoration>,
}

/// The Pyramids pass: one in each dune patch that rolled one, where it can
/// go. `dungeon` is the Dungeon's entrance (x, z). Here it comes before the
/// caves' structures (marble, granite, mushrooms), which keep out of it.
pub fn pyramids(w: &mut World, rng: &mut Rng, l: &Layers, dunes: &[Dunes], dungeon: Option<(i32, i32)>) -> Vec<Built> {
    let ids = Ids::new(w);
    let mut out = Vec::new();
    if ids.brick == 0 || ids.sand == 0 {
        return out;
    }
    let sf = scale(w);
    let d = w.sx.min(w.sz);
    let mut built: Vec<(i32, i32)> = Vec::new();
    for dn in dunes.iter().filter(|dn| dn.pyramid) {
        // A spot in its middle.
        let (u, v) = ((rng.unit() - 0.5) * dn.half_len * 0.5, (rng.unit() - 0.5) * dn.half_wide * 0.3);
        let x = dn.x + (u * dn.wind.0 - v * dn.wind.1).round() as i32;
        let z = dn.z + (u * dn.wind.1 + v * dn.wind.0).round() as i32;
        if x < PYRAMID_REACH + 4 || z < PYRAMID_REACH + 4 || x >= w.sx - PYRAMID_REACH - 4 || z >= w.sz - PYRAMID_REACH - 4 {
            continue;
        }
        if built.iter().any(|&(bx, bz)| (((bx - x).pow(2) + (bz - z).pow(2)) as f64).sqrt() < 220.0 * sf) {
            continue;
        }
        if dungeon.map_or(false, |(gx, gz)| (((gx - x).pow(2) + (gz - z).pow(2)) as f64).sqrt() < d as f64 * 0.15) {
            continue;
        }
        let mut top = w.surface_y(x, z);
        while top > 0 && w.get(x, top, z) == ids.cactus {
            top -= 1;
        }
        // The sand 20 down (Terraria's PyrY: the ground + 20, then one up).
        if top < 30 || w.get(x, top - 20, z) != ids.sand {
            continue;
        }
        let j = top - 19;
        let reach = PYRAMID_REACH;
        let bx = ((x - reach, j - 125, z - reach), (x + reach, j + 7, z + reach));
        let others: Vec<Box3> = w.structures.iter().copied().filter(|b| !dunes.iter().any(|o| o.area == *b)).collect();
        if others.iter().any(|&(a, b)| bx.0 .0 <= b.0 && a.0 <= bx.1 .0 && bx.0 .1 <= b.1 && a.1 <= bx.1 .1 && bx.0 .2 <= b.2 && a.2 <= bx.1 .2) {
            continue;
        }
        let b = pyramid_at(w, rng, &ids, l, (x, j, z));
        built.push((x, z));
        out.push(b);
        w.structures.push(bx);
    }
    out
}

/// The passes between the Pyramids and the Dungeon don't keep out of them
/// (pots, chests, pools, waterfalls, webs): what they put in a Pyramid's
/// passages goes, and its own things are put back.
pub fn restore(w: &mut World, built: &[Built]) {
    for b in built {
        let opened: HashSet<P> = b.opened.iter().copied().collect();
        for &(x, y, z) in &b.opened {
            put(w, x, y, z, 0);
        }
        for &((x, y, z), id) in &b.own {
            put(w, x, y, z, id);
        }
        w.decorations.retain(|d| !opened.contains(&d.pos) || d.kind == "pyramid");
        w.decorations.extend(b.decs.iter().cloned());
    }
}

/// WorldGen.Pyramid with its rows' j at `at` = (x, j, z) (y up).
pub fn pyramid_at(w: &mut World, rng: &mut Rng, ids: &Ids, l: &Layers, at: P) -> Built {
    let (cx, j, cz) = at;
    // The corridors' plane: along x or z, heading one way first.
    let along_x = rng.range(0, 2) == 0;
    let mut dir = if rng.range(0, 2) == 0 { 1 } else { -1 };
    let to_world = move |u: i32, v: i32| if along_x { (cx + u, cz + v) } else { (cx + v, cz + u) };
    // Terraria's row r below j is y = j - r.
    let y_of = |r: i32| j - r;

    let l2 = rng.range(9, 13);
    let bottom_r = rng.range(75, 125);
    let top_r = -rng.range(0, 7);
    // The body: row k from its tip k + 1 cells to each side (2k + 1 across).
    let mut half = 0;
    for r in top_r..bottom_r {
        let y = y_of(r);
        if y >= 0 && y < w.sy {
            for dz in -half..=half {
                for dx in -half..=half {
                    put(w, cx + dx, y, cz + dz, ids.brick);
                }
            }
        }
        half += 1;
    }
    let (body_top, body_bottom) = (y_of(top_r), y_of(bottom_r - 1));
    let inside_body = move |x: i32, y: i32, z: i32| y <= body_top && y >= body_bottom && (x - cx).abs().max((z - cz).abs()) <= body_top - y;

    const HW: i32 = 1; // the corridors' half width across their plane
    let mut opened: Vec<P> = Vec::new();
    let mut own: Vec<(P, u16)> = Vec::new();
    let l8 = rng.range(5, 8);
    let mut l7 = l2; // the corridor's top row (rows below j)
    // The entrance: out from l2 to the side through the brick; sand over it
    // outside falls in.
    let mut u = -l2 * dir;
    loop {
        let mut any = false;
        for v in -HW..=HW {
            let (x, z) = to_world(u, v);
            let mut sand_over = false;
            for r in l7..=l7 + l8 {
                let y = y_of(r);
                if w.get(x, y + 1, z) == ids.sand {
                    sand_over = true;
                }
                if w.get(x, y, z) == ids.brick {
                    put(w, x, y, z, 0);
                    any = true;
                    if !sand_over {
                        opened.push((x, y, z));
                    }
                }
                if sand_over {
                    put(w, x, y, z, ids.sand);
                }
            }
        }
        u -= dir;
        if !any || u.abs() > PYRAMID_REACH {
            break;
        }
    }
    // The corridor down, the treasure room on it.
    u = -l2 * dir;
    let mut l10 = rng.range(20, 30);
    let (mut first, mut roomed) = (true, false);
    let mut chest = None;
    let mut decs: Vec<Decoration> = Vec::new();
    loop {
        for v in -HW..=HW {
            let (x, z) = to_world(u, v);
            for r in l7..=l7 + l8 {
                put(w, x, y_of(r), z, 0);
                opened.push((x, y_of(r), z));
            }
        }
        u += dir;
        l7 += 1;
        l10 -= 1;
        if l7 >= bottom_r - l8 * 2 {
            l10 = 10;
        }
        if l10 <= 0 {
            let mut room_now = false;
            if !first && !roomed {
                roomed = true;
                room_now = true;
                chest = treasure_room(w, rng, ids, &mut decs, &mut opened, &mut own, &to_world, &y_of, &mut u, dir, l7, l8);
            }
            if first {
                first = false;
                dir = -dir;
                l10 = rng.range(15, 20);
            } else if room_now {
                l10 = rng.range(10, 15);
            } else {
                dir = -dir;
                l10 = rng.range(20, 40);
            }
        }
        if l7 >= bottom_r - l8 {
            break;
        }
    }
    // The shaft below, lined with brick, until it opens into a cave.
    let mut shaft: HashSet<P> = HashSet::new();
    let rows = |rng: &mut Rng, lo: i32, hi: i32| ((rng.range(lo, hi) as f64) * shaft_scale(l)).round().max(4.0) as i32;
    let mut min_rows = rows(rng, 100, 200);
    let mut max_rows = rows(rng, 500, 800);
    let l15 = l8;
    let mut l10 = rng.range(10, 50);
    if dir == 1 {
        u -= l15;
    }
    let l16 = rng.range(5, 10);
    loop {
        min_rows -= 1;
        max_rows -= 1;
        l10 -= 1;
        let y = y_of(l7);
        if y <= l.underworld_top + 6 {
            break;
        }
        let (a, b) = (u - l16 - rng.range(0, 2), u + l15 + l16 + rng.range(0, 2));
        for uu in a..=b {
            for v in -(HW + l16)..=(HW + l16) {
                let (x, z) = to_world(uu, v);
                if !w.in_bounds(x, y, z) || ids.dungeon_bricks.contains(&w.get(x, y, z)) && w.get(x, y, z) != 0 {
                    continue;
                }
                let open = uu >= u && uu <= u + l15 && v.abs() <= HW;
                put(w, x, y, z, if open { 0 } else { ids.brick });
                shaft.insert((x, y, z));
                if open {
                    opened.push((x, y, z));
                }
            }
        }
        l7 += 1;
        u += dir;
        let mut go = true;
        if min_rows <= 0 {
            // On while the row below it isn't all open.
            let below = y_of(l7);
            go = ((u + 1)..=(u + l15 - 1)).any(|uu| (-HW..=HW).any(|v| {
                let (x, z) = to_world(uu, v);
                w.get(x, below, z) != 0
            }));
        }
        if l10 < 0 {
            l10 = rng.range(10, 50);
            dir = -dir;
        }
        if max_rows <= 0 || !go {
            break;
        }
    }
    // What was there before goes (a chest's loot, a waterfall's mouth, a
    // tree's top); then its own.
    w.decorations.retain(|d| {
        let (x, y, z) = d.pos;
        !(inside_body(x, y, z) || shaft.contains(&d.pos))
    });
    w.decorations.extend(decs.iter().cloned());
    w.decorations.push(Decoration { kind: "pyramid".into(), pos: (cx, body_top, cz), style: 0 });
    Built { x: cx, z: cz, chest, opened, own, decs }
}

/// The treasure room from the corridor at `u` (moving it to the room's far
/// end), its floor the corridor's bottom row. Returns its chest's cell.
#[allow(clippy::too_many_arguments)]
fn treasure_room(w: &mut World, rng: &mut Rng, ids: &Ids, decs: &mut Vec<Decoration>, opened: &mut Vec<P>, own: &mut Vec<(P, u16)>, to_world: &dyn Fn(i32, i32) -> (i32, i32), y_of: &dyn Fn(i32) -> i32,
                 u: &mut i32, dir: i32, l7: i32, l8: i32) -> Option<P> {
    let tall = rng.range(7, 13);
    let long = rng.range(23, 28);
    let wide = rng.range(4, 7); // half width across: 9-13
    let start = *u;
    let floor_r = l7 + l8;
    let top_r = l7 - tall + l8;
    // Its ends' ceilings (and here its sides') stepped down.
    let step = |k: i32, n: i32| if k == 0 || k == n - 1 { 2 } else if k == 1 || k == n - 2 || k == 2 || k == n - 3 { 1 } else { 0 };
    let lowered = |i: i32, v: i32| step(i, long).max(if v.abs() == wide { 2 } else if v.abs() == wide - 1 { 1 } else { 0 });
    for i in 0..long {
        for v in -wide..=wide {
            let (x, z) = to_world(*u, v);
            for r in (top_r + lowered(i, v))..=floor_r {
                put(w, x, y_of(r), z, 0);
                opened.push((x, y_of(r), z));
            }
        }
        *u += dir;
    }
    let end = *u - dir;
    let (lo, hi) = (start.min(end), start.max(end));
    let floor = y_of(floor_r);
    let on_floor = |w: &World, x: i32, z: i32| w.get(x, floor, z) == 0 && w.get(x, floor - 1, z) != 0;
    // The chest, against a side wall half way along, facing in.
    let side = if rng.range(0, 2) == 0 { 1 } else { -1 };
    let (chx, chz) = to_world((lo + hi) / 2, -side * wide);
    let mut chest = None;
    if ids.chest != 0 && on_floor(w, chx, chz) {
        put(w, chx, floor, chz, ids.chest);
        own.push(((chx, floor, chz), ids.chest));
        decs.push(Decoration { kind: "chest".into(), pos: (chx, floor, chz), style: PYRAMID_LOOT });
        let face = local_dir(to_world, 0, side);
        let facing = FACING.iter().position(|&f| f == face).unwrap_or(0) as i32;
        decs.push(Decoration { kind: "rotation".into(), pos: (chx, floor, chz), style: facing });
        chest = Some((chx, floor, chz));
    }
    // 1-9 coin stashes about the floor.
    for _ in 0..rng.range(1, 10) {
        let (x, z) = to_world(rng.range(lo, hi + 1), rng.range(-wide, wide + 1));
        let s = ids.stashes[rng.range(0, 3) as usize];
        if s != 0 && on_floor(w, x, z) {
            put(w, x, floor, z, s);
            own.push(((x, floor, z), s));
        }
    }
    // Pots on every other cell, off the walkway down its middle.
    for uu in lo..=hi {
        for v in -wide..=wide {
            if v.abs() <= 1 || (uu + v).rem_euclid(2) != 0 {
                continue;
            }
            let (x, z) = to_world(uu, v);
            let p = ids.pots[rng.range(0, 3) as usize];
            if p != 0 && on_floor(w, x, z) {
                put(w, x, floor, z, p);
                own.push(((x, floor, z), p));
            }
        }
    }
    // Banners by the ceiling near its ends, on the side walls.
    for (k, uu) in [lo + 2, lo + 3, hi - 2, hi - 3].into_iter().enumerate() {
        let side = if k % 2 == 0 { 1 } else { -1 };
        let i = (uu - start) * dir;
        let ceiling = y_of(top_r + lowered(i, side * wide));
        let (x, z) = to_world(uu, side * wide);
        let (wx, wz) = to_world(uu, side * (wide + 1));
        let at = ceiling - 1;
        let b = ids.banners[rng.range(0, 3) as usize];
        if b == 0 || w.get(x, at, z) != 0 || w.get(x, at - 1, z) != 0 || w.get(wx, at, wz) != ids.brick {
            continue;
        }
        put(w, x, at, z, b);
        own.push(((x, at, z), b));
        let out = local_dir(to_world, 0, -side);
        let style = FACING.iter().position(|&f| f == out).unwrap_or(0) as i32;
        decs.push(Decoration { kind: "rotation".into(), pos: (x, at, z), style });
    }
    chest
}

/// The world direction (x, z) of a step `(du, dv)` in the corridors' plane.
fn local_dir(to_world: &dyn Fn(i32, i32) -> (i32, i32), du: i32, dv: i32) -> (i32, i32) {
    let (ox, oz) = to_world(0, 0);
    let (x, z) = to_world(du, dv);
    (x - ox, z - oz)
}

/// Terraria's rows below its rock layer, as rows here (dungeon::depth_y's).
fn shaft_scale(l: &Layers) -> f64 {
    (l.cavern_top - l.underworld_top) as f64 / 580.0
}

fn put(w: &mut World, x: i32, y: i32, z: i32, id: u16) {
    if w.in_bounds(x, y, z) {
        let i = w.idx(x, y, z);
        w.blocks[i] = id;
        w.liquid[i] = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dune_hills_rise_and_the_sand_deepens_toward_the_middle() {
        let mut rng = Rng::new(3);
        let len = 120;
        let (mut bump, mut depth) = (vec![0.0; 241], vec![0.0; 241]);
        single(&mut rng, 1.0, 0.0, 200.0, len, &mut bump, &mut depth);
        let at = |u: i32| (u + len) as usize;
        assert!(bump.iter().cloned().fold(0.0, f64::max) > 20.0, "big hills (35 x 0.8 tall)");
        assert!(depth[at(0)] > depth[at(80)] && depth[at(80)] > 0.0 && depth[at(110)] == 0.0, "deepest in the middle: {} {} {}", depth[at(0)], depth[at(80)], depth[at(110)]);
        assert!((depth[at(0)] - 30.0).abs() < 0.5, "sqrt(100) x 3 under its middle");
    }
}
