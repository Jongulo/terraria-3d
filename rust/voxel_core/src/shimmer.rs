//! Terraria's Shimmer pass (WorldGen.ShimmerMakeBiome, its openings and
//! ShimmerCleanUp): the Aether, in 3D.
//!
//! - **Where:** on the Jungle's side of the world (Terraria's is the side
//!   away from the Dungeon, within 11% of the world's width from its edge,
//!   200 tiles in); here toward the Jungle from the middle, under the land
//!   near the coast. Its middle is 115-450 tiles under the surface (Terraria:
//!   from halfway between its surface and rock layers less 50 tiles, to 460
//!   tiles over the bottom), as dungeon::depth_y measures them.
//! - **What:** a ball of stone 105-125 tiles round (squashed: a fifth under
//!   its middle, two fifths over it). Through its middle a level gap 9-13
//!   tiles high opens over its floor, the whole ball across; over the middle
//!   a dome 0.6 (or 0.55) of its radius across and 1/1.3 (or 1/2) of that
//!   high; and in its floor a bowl 0.3 of its radius across and half that
//!   deep, full of shimmer (its top row half full). Half the time (the
//!   flatter dome) cones of stone hang from the dome's roof, 9-14 tiles
//!   apart: 5-10 tiles round, narrowing as they go down. Each side, a tunnel
//!   as high as the gap runs out level from the ball (stepping up or down a
//!   tile now and then) till it breaks into open cave, up to 100 tiles.
//!   Gem trees grow on the floor near the middle (500 tries, within 70 tiles:
//!   in a small world 7 of them, about 8.5 tiles apart). Here a dozen at
//!   most, spread round the pool.
//! - **After:** its middle 200 tiles across are kept from later structures
//!   (Terraria's AddProtectedStructure). At the end (ShimmerCleanUp), within
//!   150 tiles any other liquid goes, within 120 the evil's ores turn to
//!   stone, moss to stone, and cobwebs, obsidian, honey and Aetherium go;
//!   within 90 (squashed as the ball is) the evil's blocks are purified; then
//!   the pool is filled again from its middle down.
//!
//! In 3D the ball and its gap, dome and bowl are round; the two tunnels run
//! toward the island's middle and away from it; the ball's stone is squashed
//! further to stay between the Underworld and the ground over it. Terraria's
//! tiles are 2/3 of a block here.

use crate::world::{liq_pack, liq_unpack, Decoration, World, LIQ_MAX, LIQ_NONE, LIQ_SHIMMER};
use crate::worldgen::{Coast, Layers, Rng, GEMS, GEM_CANOPY, GEM_TOP_ROOM};
use std::collections::{HashSet, VecDeque};

type P = (i32, i32, i32);

/// A Terraria tile, in blocks.
const TILE: f64 = 2.0 / 3.0;
/// Terraria's protected box round its middle: 200 tiles across.
const PROTECTED: f64 = 100.0;
/// How far apart its gem trees stand (blocks), and how many at most: Terraria's
/// 7 along its floor, here round a floor that goes all the way round.
const TREE_APART: i32 = 14;
pub const MAX_TREES: usize = 12;

/// The Aether made: its middle (the pool's top row) and the ball's radius.
#[derive(Clone, Copy, Debug)]
pub struct Aether {
    pub center: P,
    pub radius: i32,
}

/// Tiles to blocks.
fn b(t: f64) -> i32 {
    (t * TILE).round() as i32
}

/// The Aether, toward `toward` (the Jungle's middle) from the world's: tries
/// spots there till one fits (out of the structures so far, under the
/// ground), then anywhere near the coast. Records it as an "aether"
/// decoration (pos its middle, style its radius) and keeps its middle from
/// later structures.
pub fn aether(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast, toward: (i32, i32)) -> Option<Aether> {
    let stone = w.id_of("stone");
    if stone == 0 {
        return None;
    }
    let (cx, cz) = (w.sx as f64 / 2.0, w.sz as f64 / 2.0);
    let dir = (toward.1 as f64 - cz).atan2(toward.0 as f64 - cx);
    for attempt in 0..4000 {
        let shape = Shape::roll(rng);
        let r = b(shape.radius);
        // Its middle: toward the Jungle (any way after a while), under the
        // land a little in from the shore.
        let spread = if attempt < 2000 { 0.6 } else { std::f64::consts::PI };
        let a = dir + (rng.unit() * 2.0 - 1.0) * spread;
        let reach = (cx.min(cz) - coast.ocean.width as f64).max(1.0);
        let d = reach - r as f64 * (0.3 + rng.unit() * 1.2);
        let (x, z) = ((cx + a.cos() * d) as i32, (cz + a.sin() * d) as i32);
        if x - r < 4 || z - r < 4 || x + r >= w.sx - 4 || z + r >= w.sz - 4 {
            continue;
        }
        let inland = coast.inland(x, z) - coast.ocean.width;
        if inland < r as f32 * 0.3 || inland > r as f32 * 1.6 {
            continue;
        }
        let t = 115.0 + rng.unit() * 335.0;
        let y = crate::dungeon::depth_y(l, t);
        let Some(fit) = fit(w, l, (x, y, z), &shape) else { continue };
        let center = (x, y, z);
        make(w, rng, center, &shape, &fit, stone);
        let p = b(PROTECTED);
        w.structures.push(((x - p, y - fit.below, z - p), (x + p, y + fit.above, z + p)));
        w.decorations.push(Decoration { kind: "aether".into(), pos: center, style: r });
        return Some(Aether { center, radius: r });
    }
    None
}

/// ShimmerMakeBiome's rolls, in tiles.
pub struct Shape {
    /// The ball's radius (l4: 105-125).
    pub radius: f64,
    /// The gap's height (l7: 9-13).
    gap: f64,
    /// The dome: radius across (l4 l1) and how much flatter it is (l2).
    dome: f64,
    dome_flat: f64,
    /// The bowl's radius (l4 l3).
    bowl: f64,
    /// The flatter dome with cones hanging (l0 == 0).
    cones: bool,
}

impl Shape {
    pub fn roll(rng: &mut Rng) -> Shape {
        let cones = rng.range(0, 2) == 0;
        let (mut l1, mut l2, mut l3) = if cones { (0.55, 2.0, 0.3) } else { (0.6, 1.3, 0.3) };
        l1 *= 1.05 - rng.unit() * 0.1;
        l2 *= 1.05 - rng.unit() * 0.1;
        l3 *= 1.0 - rng.unit() * 0.1;
        let radius = rng.range(105, 125) as f64;
        let gap = rng.range(9, 13) as f64;
        Shape { radius, gap, dome: radius * l1, dome_flat: l2, bowl: radius * l3, cones }
    }
}

/// How far the ball's stone reaches under and over its middle, in blocks.
pub struct Fit {
    below: i32,
    above: i32,
}

/// Whether the Aether fits at `c`: in the world, out of the structures so
/// far, its dome and tunnels under the ground over it, its bowl over the
/// Underworld. Its stone is squashed to fit between them.
fn fit(w: &World, l: &Layers, c: P, s: &Shape) -> Option<Fit> {
    let r = b(s.radius);
    let (x, y, z) = c;
    let dome_top = y + 1 + b(s.dome / s.dome_flat).max(b(s.gap));
    let bowl_bottom = y - b(s.bowl / 2.0) - 1;
    if bowl_bottom - 8 <= l.underworld_top {
        return None;
    }
    // The ground: the lowest top over the ball (sampled).
    let mut ground = i32::MAX;
    for dz in (-r..=r).step_by(4) {
        for dx in (-r..=r).step_by(4) {
            if dx * dx + dz * dz > r * r {
                continue;
            }
            let (px, pz) = (x + dx, z + dz);
            let mut top = w.sy - 1;
            while top > 0 && !w.is_solid(px, top, pz) {
                top -= 1;
            }
            ground = ground.min(top);
        }
    }
    if dome_top + 12 > ground {
        return None;
    }
    let below = b(s.radius / 1.2).min(y - l.underworld_top - 6);
    let above = b(s.radius / 1.4).min(ground - 8 - y);
    if below <= y - bowl_bottom || above <= dome_top - y {
        return None;
    }
    let (lo, hi) = ((x - r, y - below, z - r), (x + r, y + above, z + r));
    if w.structures.iter().any(|&(a, bb)| lo.0 <= bb.0 && a.0 <= hi.0 && lo.1 <= bb.1 && a.1 <= hi.1 && lo.2 <= bb.2 && a.2 <= hi.2) {
        return None;
    }
    Some(Fit { below, above })
}

/// Builds it: the ball, its gap, dome, bowl and cones, its tunnels and gem trees.
fn make(w: &mut World, rng: &mut Rng, c: P, s: &Shape, fit: &Fit, stone: u16) {
    let (cx, cy, cz) = c;
    let r = b(s.radius);
    // The gap's floor and roof rows wander a tile (l12, l13), row by row in
    // Terraria; here by the cell, from a noise of its own.
    let seed = rng.next();
    let jitter = |p: P, k: u64| -> f64 { hash01(seed ^ k, p) };
    let gap_top = cy + b(s.gap);
    let mut pool: Vec<(usize, u8)> = Vec::new();
    for x in cx - r..=cx + r {
        for z in cz - r..=cz + r {
            let (dx, dz) = ((x - cx) as f64 / TILE, (z - cz) as f64 / TILE);
            let h = (dx * dx + dz * dz).sqrt();
            if h > s.radius + 1.0 {
                continue;
            }
            for y in cy - fit.below..=cy + fit.above {
                if !w.in_bounds(x, y, z) {
                    continue;
                }
                let i = w.idx(x, y, z);
                w.liquid[i] = 0;
                let p = (x, y, z);
                // The stone: squashed to fit (Terraria's 1.2 under, 1.4 over).
                let up = y > cy;
                let squash = if up { s.radius / (fit.above as f64 / TILE) } else { s.radius / (fit.below as f64 / TILE) };
                let v = (y - cy) as f64 / TILE;
                let d = (h * h + (v * squash).powi(2)).sqrt() * (1.0 + jitter(p, 1) * 0.02);
                if d < s.radius && h < s.radius - 5.0 - jitter(p, 2) * 2.0 {
                    w.blocks[i] = stone;
                }
                // The gap: from the floor (this row stays) to its roof.
                let roof = gap_top - (jitter(p, 3) < 0.25) as i32;
                let floor = cy + (jitter(p, 4) < 0.25) as i32;
                if y > floor && y < roof && h <= s.radius {
                    w.blocks[i] = 0;
                }
                // The dome over it.
                let d2 = (h * h + (v * s.dome_flat).powi(2)).sqrt() * (1.0 + jitter(p, 5) * 0.02);
                if y > cy && d2 < s.dome * (1.0 + jitter(p, 6) * 0.02) {
                    w.blocks[i] = 0;
                }
                // The bowl, full of shimmer under its floor row.
                let d3 = (h * h + (v * 2.0).powi(2)).sqrt() * (1.0 + jitter(p, 7) * 0.02);
                if y <= cy + 1 && d3 < s.bowl * (1.0 + jitter(p, 8) * 0.025) {
                    let rim = y < cy - 2 && (d3 - (s.bowl - 1.0)).abs() < 0.5 && jitter(p, 9) < 0.5;
                    if !rim {
                        w.blocks[i] = 0;
                    }
                    if y <= cy && w.blocks[i] == 0 {
                        pool.push((i, if y == cy { LIQ_MAX / 2 } else { LIQ_MAX }));
                    }
                }
            }
        }
    }
    for (i, a) in pool {
        w.liquid[i] = liq_pack(LIQ_SHIMMER, a);
    }
    if s.cones {
        cones(w, rng, c, s, stone);
    }
    // The tunnels: toward the island's middle and away.
    let a = ((w.sz / 2 - cz) as f64).atan2((w.sx / 2 - cx) as f64);
    for k in 0..2 {
        let ang = a + k as f64 * std::f64::consts::PI;
        opening(w, rng, c, (ang.cos(), ang.sin()), r, s.gap);
    }
    gem_trees(w, rng, c);
}

/// The cones hanging from a flat dome's roof: 9-14 tiles apart over its
/// middle (0.3 of the ball's radius, and 5-15 tiles more).
fn cones(w: &mut World, rng: &mut Rng, (cx, cy, cz): P, s: &Shape, stone: u16) {
    let reach = s.radius * 0.3 + rng.range(5, 16) as f64;
    let mut spots = Vec::new();
    let mut z = -reach;
    while z <= reach {
        let mut x = -reach;
        while x <= reach {
            let (jx, jz) = (x + rng.range(-2, 3) as f64, z + rng.range(-2, 3) as f64);
            if jx * jx + jz * jz <= reach * reach {
                spots.push((cx + b(jx), cz + b(jz)));
            }
            x += rng.range(9, 14) as f64;
        }
        z += rng.range(9, 14) as f64;
    }
    for (x, z) in spots {
        // Up from the gap to the roof, then 4 tiles into it.
        let mut y = cy + b(3.0);
        while y < w.sy - 1 && !w.is_solid(x, y, z) {
            y += 1;
        }
        let top = y + b(4.0);
        // Its rows (tiles): radius, narrowing as Terraria's do.
        let mut radii: Vec<(f64, f64, f64)> = Vec::new();
        let (mut rad, mut len) = (rng.range(5, 11) as f64, rng.range(15, 21));
        let (mut ox, mut oz, mut run) = (0.0, 0.0, 0);
        while rad > 0.0 {
            radii.push((rad, ox, oz));
            run += 1;
            if rng.range(0, 3) < run {
                run = 0;
                rad -= 1.0;
                ox += rng.range(-1, 2) as f64;
                oz += rng.range(-1, 2) as f64;
            }
            if len <= 0 {
                rad -= 1.0;
            }
            len -= 1;
        }
        let rows = radii.len() as f64;
        let bottom = top - b(rows);
        for yy in (bottom..=top).rev() {
            let row = (((top - yy) as f64 / TILE) as usize).min(radii.len() - 1);
            let (rad, ox, oz) = radii[row];
            let rb = rad * TILE;
            let ri = rb.ceil() as i32;
            for dz in -ri..=ri {
                for dx in -ri..=ri {
                    let (fx, fz) = (dx as f64 - ox * TILE, dz as f64 - oz * TILE);
                    if fx * fx + fz * fz <= rb * rb {
                        put(w, (x + dx, yy, z + dz), stone);
                    }
                }
            }
        }
        // Its tip: a column of stone 3-4 tiles under the last row.
        let (_, ox, oz) = radii[radii.len() - 1];
        let (tx, tz) = (x + b(ox), z + b(oz));
        for k in 1..=b(rng.range(3, 5) as f64) {
            put(w, (tx, bottom - k, tz), stone);
        }
    }
}

fn put(w: &mut World, p: P, id: u16) {
    if w.in_bounds(p.0, p.1, p.2) {
        let i = w.idx(p.0, p.1, p.2);
        w.blocks[i] = id;
        w.liquid[i] = 0;
    }
}

/// ShimmerMakeBiomeOpening: a tunnel out from the ball's edge as high as the
/// gap (less 2 tiles, from a tile over the floor), level but for a tile up
/// or down now and then, till the 3 tiles ahead are open cave or it's 100
/// tiles out. Here as wide as it's high.
fn opening(w: &mut World, rng: &mut Rng, (cx, cy, cz): P, (ux, uz): (f64, f64), r: i32, gap: f64) {
    let h = b(gap - 2.0).max(3);
    let half = h / 2;
    let mut floor = cy + 1;
    let (mut fx, mut fz) = (cx as f64 + ux * r as f64, cz as f64 + uz * r as f64);
    let (px, pz) = (-uz, ux);
    let cells = |fx: f64, fz: f64, floor: i32| -> Vec<P> {
        let mut out = Vec::new();
        for k in -half..=half {
            let (x, z) = ((fx + px * k as f64).round() as i32, (fz + pz * k as f64).round() as i32);
            for y in floor + 1..=floor + h {
                out.push((x, y, z));
            }
        }
        out
    };
    for step in 0..b(100.0) {
        let (x, z) = (fx.round() as i32, fz.round() as i32);
        if x < 4 || z < 4 || x >= w.sx - 4 || z >= w.sz - 4 {
            break;
        }
        // Open ahead: 3 tiles of it, the whole height.
        let open = (1..=b(3.0).max(2)).all(|k| cells(fx + ux * k as f64, fz + uz * k as f64, floor).iter().all(|&(x, y, z)| !w.is_solid(x, y, z)));
        for (x, y, z) in cells(fx, fz, floor) {
            if w.in_bounds(x, y, z) {
                let i = w.idx(x, y, z);
                w.blocks[i] = 0;
            }
        }
        if open && step > 0 {
            break;
        }
        if rng.range(0, 2) == 0 && rng.range(0, 2) == 0 {
            floor += rng.range(-1, 2);
        }
        fx += ux;
        fz += uz;
    }
}

/// Gem trees on the floor near the middle: 500 tries along Terraria's 140
/// tiles, here as many over each tile of the floor within 70 tiles; each on
/// stone, with room over it, well apart, and no more than MAX_TREES.
fn gem_trees(w: &mut World, rng: &mut Rng, (cx, cy, cz): P) {
    let trunks: Vec<u16> = GEMS.iter().map(|g| w.id_of(&format!("{}_tree_trunk", g))).collect();
    let stone = w.id_of("stone");
    if trunks.iter().any(|&t| t == 0) {
        return;
    }
    let reach = b(70.0);
    let tries = (500.0 / 140.0 * std::f64::consts::PI * 70.0 * 70.0 * TILE) as usize;
    let mut placed: Vec<(i32, i32)> = Vec::new();
    for _ in 0..tries {
        if placed.len() >= MAX_TREES {
            break;
        }
        let (dx, dz) = (rng.range(-reach, reach + 1), rng.range(-reach, reach + 1));
        if dx * dx + dz * dz > reach * reach {
            continue;
        }
        let (x, z) = (cx + dx, cz + dz);
        let y = cy + rng.range(-1, 2);
        if w.get(x, y, z) != stone || w.get(x, y + 1, z) != 0 || w.liquid_at(x, y + 1, z).1 > 0 {
            continue;
        }
        if placed.iter().any(|&(px, pz)| (px - x).pow(2) + (pz - z).pow(2) < TREE_APART * TREE_APART) {
            continue;
        }
        let h = rng.range(7, 13);
        let room = (1..=h + GEM_TOP_ROOM).all(|k| w.get(x, y + k, z) == 0 && w.liquid_at(x, y + k, z).1 == 0);
        let round = (1..=3).all(|k| [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().all(|&(ex, ez)| w.get(x + ex, y + k, z + ez) == 0));
        if !room || !round {
            continue;
        }
        let gem = rng.range(0, 7) as usize;
        for k in 1..=h {
            let i = w.idx(x, y + k, z);
            w.blocks[i] = trunks[gem];
        }
        w.decorations.push(Decoration { kind: "tree_top".into(), pos: (x, y + h + 1, z), style: (GEM_CANOPY + gem as i32) * 10 + rng.range(0, 3) });
        placed.push((x, z));
    }
}

/// ShimmerCleanUp, at the end of the world's making.
pub fn clean_up(w: &mut World, l: &Layers, a: &Aether) {
    let (cx, cy, cz) = a.center;
    let ids = |names: &[&str]| -> Vec<u16> { names.iter().map(|n| w.id_of(n)).filter(|&i| i != 0).collect() };
    let stone = w.id_of("stone");
    let to_stone = ids(&["demonite_ore", "crimtane_ore", "green_moss", "brown_moss", "red_moss", "blue_moss", "purple_moss", "lava_moss",
        "krypton_moss", "xenon_moss", "argon_moss", "violet_moss"]);
    let gone: Vec<u16> = (0..w.defs.len() as u16)
        .filter(|&i| {
            let n = &w.defs[i as usize].name;
            n.starts_with("cobweb") || n.starts_with("long_moss_") || ["obsidian", "honey_block", "crispy_honey_block", "aetherium_block"].contains(&n.as_str())
        })
        .collect();
    let purify: Vec<(u16, u16)> = [("ebonstone", "stone"), ("crimstone", "stone"), ("ebonsand", "sand"), ("crimsand", "sand"),
        ("corrupt_grass", "grass"), ("crimson_grass", "grass"), ("purple_ice_block", "ice_block"), ("red_ice_block", "ice_block"),
        ("corrupt_sandstone", "sandstone"), ("crimson_sandstone", "sandstone"), ("corrupt_hardened_sand", "hardened_sand"),
        ("crimson_hardened_sand", "hardened_sand"), ("corrupt_jungle_grass", "jungle_grass"), ("crimson_jungle_grass", "jungle_grass")]
        .iter()
        .map(|(f, t)| (w.id_of(f), w.id_of(t)))
        .filter(|&(f, t)| f != 0 && t != 0)
        .collect();
    // ShimmerRemoveWater: within 150 tiles, from 150 over its middle to 75
    // under, every other liquid (here under the sea floor, so it doesn't
    // take the sea).
    let reach = b(150.0);
    let top = (cy + reach).min(l.surface_base - 30);
    for x in cx - reach..=cx + reach {
        for z in cz - reach..=cz + reach {
            if (x - cx).pow(2) + (z - cz).pow(2) > reach * reach {
                continue;
            }
            for y in cy - b(75.0)..=top {
                if !w.in_bounds(x, y, z) || !dries(l, a, (x, y, z)) {
                    continue;
                }
                let i = w.idx(x, y, z);
                let (t, _) = liq_unpack(w.liquid[i]);
                if t != LIQ_NONE && t != LIQ_SHIMMER {
                    w.liquid[i] = 0;
                }
            }
        }
    }
    // And the streams that poured it (waterfall decorations: Terraria's
    // falls are its liquid, gone with it).
    w.decorations.retain(|d| d.kind != "waterfall" || !dries(l, a, d.pos));
    // The blocks: within 120 tiles, and purified within 90 (squashed).
    let (r1, r2) = (120.0, 90.0);
    let rb = b(r1);
    for x in cx - rb..=cx + rb {
        for z in cz - rb..=cz + rb {
            for y in cy - rb..=cy + rb {
                if !w.in_bounds(x, y, z) {
                    continue;
                }
                let (dx, dy, dz) = ((x - cx) as f64 / TILE, (y - cy) as f64 / TILE, (z - cz) as f64 / TILE);
                let d = (dx * dx + dy * dy + dz * dz).sqrt();
                if d >= r1 {
                    continue;
                }
                let i = w.idx(x, y, z);
                let id = w.blocks[i];
                if to_stone.contains(&id) {
                    w.blocks[i] = stone;
                } else if gone.contains(&id) {
                    w.blocks[i] = 0;
                }
                let squash = if dy > 0.0 { 1.4 } else { 1.2 };
                if (dx * dx + (dy * squash).powi(2) + dz * dz).sqrt() < r2 {
                    if let Some(&(_, to)) = purify.iter().find(|&&(f, _)| f == w.blocks[i]) {
                        w.blocks[i] = to;
                    }
                }
            }
        }
    }
    // The pool again: from its middle's row (half full) down, outward till
    // stone, while its middle is open.
    let mut y = cy;
    while y > 0 && !w.is_solid(cx, y, cz) {
        let amount = if y == cy { LIQ_MAX / 2 } else { LIQ_MAX };
        let mut seen = HashSet::new();
        let mut q = VecDeque::from([(cx, cz)]);
        seen.insert((cx, cz));
        while let Some((x, z)) = q.pop_front() {
            let i = w.idx(x, y, z);
            if w.liquid_at(x, y, z).1 < amount {
                w.liquid[i] = liq_pack(LIQ_SHIMMER, amount);
            }
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let (nx, nz) = (x + dx, z + dz);
                if (nx - cx).pow(2) + (nz - cz).pow(2) <= a.radius * a.radius && !w.is_solid(nx, y, nz) && seen.insert((nx, nz)) {
                    q.push_back((nx, nz));
                }
            }
        }
        y -= 1;
    }
    // No tree stands in shimmer.
    let trunks: Vec<u16> = GEMS.iter().map(|g| w.id_of(&format!("{}_tree_trunk", g))).chain([w.id_of("tree_trunk")]).filter(|&i| i != 0).collect();
    let mut dead = Vec::new();
    for d in &w.decorations {
        if d.kind == "tree_top" && (d.pos.0 - cx).abs() <= a.radius && (d.pos.2 - cz).abs() <= a.radius {
            let (x, z) = (d.pos.0, d.pos.2);
            let mut y = d.pos.1 - 1;
            let mut wet = false;
            while y > 0 && trunks.contains(&w.get(x, y, z)) {
                wet |= w.liquid_at(x, y, z).0 == LIQ_SHIMMER;
                y -= 1;
            }
            if wet {
                dead.push(d.pos);
            }
        }
    }
    for p in dead {
        let mut y = p.1 - 1;
        while y > 0 && trunks.contains(&w.get(p.0, y, p.2)) {
            let i = w.idx(p.0, y, p.2);
            w.blocks[i] = 0;
            y -= 1;
        }
        w.decorations.retain(|d| !(d.kind == "tree_top" && d.pos == p));
    }
}

/// Whether ShimmerRemoveWater takes the liquid at `p`: within 150 tiles of
/// the Aether's middle, from 150 over it (but under the sea floor) to 75 under.
pub fn dries(l: &Layers, a: &Aether, p: P) -> bool {
    let (cx, cy, cz) = a.center;
    let reach = b(150.0);
    p.1 >= cy - b(75.0) && p.1 <= (cy + reach).min(l.surface_base - 30)
        && (p.0 - cx).pow(2) + (p.1 - cy).pow(2) + (p.2 - cz).pow(2) <= reach * reach
}

fn hash01(seed: u64, p: P) -> f64 {
    let mut z = seed ^ (p.0 as u64).wrapping_mul(0x9e37_79b9_7f4a_7c15) ^ (p.1 as u64).wrapping_mul(0xc2b2_ae3d_27d4_eb4f) ^ (p.2 as u64).wrapping_mul(0x1656_67b1_9e37_79f9);
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    ((z ^ (z >> 31)) >> 11) as f64 / (1u64 << 53) as f64
}

/// The Aether a world was made with (its "aether" decoration).
pub fn of(w: &World) -> Option<Aether> {
    w.decorations.iter().find(|d| d.kind == "aether").map(|d| Aether { center: d.pos, radius: d.style })
}
