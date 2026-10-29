//! Terraria's micro biomes (its Micro Biomes pass: Terraria.GameContent.
//! Biomes) and its FragileIceOverIceBiomeWater pass, in 3D. Terraria's tiles
//! are 2/3 of a block here; its counts (Configuration.json's) are a small
//! world's, here that many in each 640 x 640 blocks, as the cabins count.
//! (The Enchanted Sword Shrines are shrines.rs.)
//!
//! - **Dead Man's Chests** (DeadMansChestBiome: 10-20): gold chests under the
//!   ground with room round them become Dead Man's Chests, wired to traps
//!   (traps.rs: Dart Traps, boulders, Explosives) that opening them sets off;
//!   1 in 3 holds a Dead Man's Sweater.
//! - **Thin ice** (ThinIceBiome: 3-5): under the snow (50 x 50 tiles round
//!   the spot more snow than mud, and than dirt and stone, and no hive), a
//!   column of balls of Thin Ice, 10-14 tiles round and smaller as it goes
//!   down: the snow, ice, slush, dirt, stone and water in them.
//! - **Campsites** (CampsiteBiome: 6-11): in solid rock under the ground, a
//!   hollow 6-9 tiles round (its sand over it hardened), and on its floor an
//!   unlit campfire, a skeleton and a few stacks of Gold Coins, each 9 in 10.
//! - **Mining explosives** (MiningExplosivesBiome: 14-29): from a cave floor
//!   in the rock layer, a vein of one of the world's metals running down into
//!   the rock, a pocket cut over it, and Explosives in the vein wired to a
//!   Detonator on the pocket's floor.
//! - **Lava traps** (placeLavaTrap: 0.02 a tile of the width): under a pool of
//!   lava (50 of its 11 x 11 tiles round full), its floor, if a cave 4 tiles
//!   high and more is under it (within 40 tiles of the lava), gets actuators,
//!   wired to an orange pressure plate on the cave floor: step on it and the
//!   lava pours through.
//! - **Fragile ice** (FragileIceOverIceBiomeWater): under the surface, water
//!   lying on snow or ice freezes over: its top, and the top of the water
//!   joined to it, Thin Ice.

use crate::dungeon::depth_y;
use crate::world::{Decoration, World, LIQ_LAVA, LIQ_MAX, LIQ_WATER, RENDER_CUBE};
use crate::worldgen::{Coast, Layers, Rng};
use std::collections::{HashSet, VecDeque};

type P = (i32, i32, i32);

/// Terraria's tiles to blocks here, rounded.
fn b(tiles: i32) -> i32 {
    (tiles as f64 * 2.0 / 3.0).round() as i32
}

/// Small worlds' worth of area (640 x 640 blocks each).
fn worlds(w: &World) -> f64 {
    (w.sx as f64 * w.sz as f64) / (640.0 * 640.0)
}

/// Terraria's count from its range, here for the world's area.
fn count(w: &World, rng: &mut Rng, lo: i32, hi: i32) -> usize {
    (rng.range(lo, hi + 1) as f64 * worlds(w)).round() as usize
}

fn put(w: &mut World, (x, y, z): P, id: u16) {
    if w.in_bounds(x, y, z) {
        let i = w.idx(x, y, z);
        w.blocks[i] = id;
        if id != 0 && w.def(id).solid {
            w.liquid[i] = 0;
        }
    }
}

/// A whole solid cube.
fn solid(w: &World, (x, y, z): P) -> bool {
    w.in_bounds(x, y, z) && w.is_solid(x, y, z) && w.def(w.get(x, y, z)).render == RENDER_CUBE
}

fn in_structure(w: &World, (x, y, z): P, pad: i32) -> bool {
    w.structures.iter().any(|&(lo, hi)| x >= lo.0 - pad && x <= hi.0 + pad && y >= lo.1 - pad && y <= hi.1 + pad && z >= lo.2 - pad && z <= hi.2 + pad)
}

/// A per-cell roughness for a blob's edge (Terraria's Blotches), 0..1.
fn rough(seed: u64, (x, y, z): P) -> f64 {
    let mut h = (x as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ (y as u64).wrapping_mul(0xC2B2_AE3D_27D4_EB4F) ^ (z as u64).wrapping_mul(0x1656_67B1_9E37_79F9) ^ seed;
    h ^= h >> 31;
    h = h.wrapping_mul(0xBF58_476D_1CE4_E5B9);
    h ^= h >> 29;
    (h % 10_000) as f64 / 10_000.0
}

/// After a hollow's cut (from `lo` to `hi`): the plants and debris round it
/// left with nothing under or over them go (Terraria's tile framing breaks
/// them).
fn drop_unsupported(w: &mut World, lo: P, hi: P) {
    for x in lo.0 - 1..=hi.0 + 1 {
        for z in lo.2 - 1..=hi.2 + 1 {
            for y in lo.1 - 1..=hi.1 + 1 {
                let t = w.get(x, y, z);
                if t != 0 && !w.def(t).solid && w.def(t).render != RENDER_CUBE && !w.is_solid(x, y - 1, z) && !w.is_solid(x, y + 1, z) {
                    put(w, (x, y, z), 0);
                }
            }
        }
    }
}

/// Terraria's Dead Man's Chests: up to 10-20 of the gold chests.
pub fn dead_mans_chests(w: &mut World, rng: &mut Rng, l: &Layers, dungeon_at: Option<(i32, i32)>) -> usize {
    let (gold, dead) = (w.id_of("gold_chest"), w.id_of("dead_mans_chest"));
    if gold == 0 || dead == 0 {
        return 0;
    }
    let mut ids = crate::traps::TrapIds::of(w);
    ids.dungeon_at = dungeon_at;
    if !ids.ready() {
        return 0;
    }
    // Not the Pyramids' (on their brick), which Terraria keeps protected.
    let brick = w.id_of("sandstone_brick");
    let mut chests: Vec<usize> = w.decorations.iter().enumerate()
        .filter(|(_, d)| d.kind == "chest" && w.get(d.pos.0, d.pos.1, d.pos.2) == gold && d.pos.1 < l.surface_base - 4
            && (brick == 0 || w.get(d.pos.0, d.pos.1 - 1, d.pos.2) != brick))
        .map(|(i, _)| i).collect();
    let wired: HashSet<P> = w.decorations.iter().filter(|d| d.kind == "wire").map(|d| d.pos).collect();
    let want = count(w, rng, 10, 20);
    let mut made = 0;
    for _ in 0..3000 {
        if made >= want || chests.is_empty() {
            break;
        }
        let k = rng.range(0, chests.len() as i32) as usize;
        let i = chests.swap_remove(k);
        let c = w.decorations[i].pos;
        // No wire within 20 tiles; room round it (40 open cells of Terraria's
        // countTiles).
        let r = b(20);
        if wired.iter().any(|q| (q.0 - c.0).abs() <= r && (q.1 - c.1).abs() <= r && (q.2 - c.2).abs() <= r) {
            continue;
        }
        // Not near mushroom grass (as the Traps pass keeps its boulders off
        // it: their pocket's rock turns to stone).
        let shroom = w.id_of("mushroom_grass");
        if shroom != 0 && (-r..=r).any(|dx| (-r..=r).any(|dy| (-r..=r).any(|dz| w.get(c.0 + dx, c.1 + dy, c.2 + dz) == shroom))) {
            continue;
        }
        let open = (-3..=3).flat_map(|dx| (0..3).flat_map(move |dy| (-3..=3).map(move |dz| (dx, dy, dz))))
            .filter(|&(dx, dy, dz)| w.get(c.0 + dx, c.1 + dy, c.2 + dz) == 0).count();
        if open < 40 || !crate::traps::dead_mans_traps(w, rng, &ids, c) {
            continue;
        }
        put(w, c, dead);
        // 1 in 3: a Dead Man's Sweater in its second slot (chests.gd).
        if rng.range(0, 3) == 0 {
            w.decorations[i].style |= DEAD_MANS_SWEATER;
        }
        made += 1;
    }
    made
}

/// A chest decoration's style bit: a Dead Man's Sweater in its second slot.
pub const DEAD_MANS_SWEATER: i32 = 128;

/// Terraria's Thin Ice micro biomes.
pub fn thin_ice(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast) -> usize {
    let thin = w.id_of("thin_ice");
    if thin == 0 {
        return 0;
    }
    let id = |n: &str| w.id_of(n);
    let (dirt, stone, mud, snow, hive) = (id("dirt"), id("stone"), id("mud"), id("snow_block"), id("hive"));
    let turn: Vec<u16> = [snow, id("ice_block"), id("slush"), dirt, stone].into_iter().filter(|&t| t != 0).collect();
    let want = count(w, rng, 3, 5);
    let (mut made, mut fails) = (0, 0);
    // From 20 tiles under the surface to the Underworld.
    let (y_hi, y_lo) = (depth_y(l, 20.0), l.underworld_top);
    while made < want {
        let p = (rng.range(b(50), w.sx - b(50)), rng.range(y_lo, y_hi), rng.range(b(50), w.sz - b(50)));
        let ok = coast.inland(p.0, p.2) > coast.ocean.width && !in_structure(w, p, 0) && {
            let r = b(25);
            let (mut s, mut m, mut ds, mut h) = (0, 0, 0, 0);
            for x in (p.0 - r..p.0 + r).step_by(2) {
                for y in (p.1 - r..p.1 + r).step_by(2) {
                    for z in (p.2 - r..p.2 + r).step_by(2) {
                        let t = w.get(x, y, z);
                        if t == 0 {
                            continue;
                        }
                        if t == snow {
                            s += 1;
                        } else if t == mud {
                            m += 1;
                        } else if t == dirt || t == stone {
                            ds += 1;
                        } else if t == hive {
                            h += 1;
                        }
                    }
                }
            }
            h == 0 && s > m && s > ds
        };
        if !ok {
            fails += 1;
            if fails > 1000 {
                made += 1;
                fails = 0;
            }
            continue;
        }
        fails = 0;
        let seed = rng.next();
        let (mut down, mut r) = (0, rng.range(10, 15));
        while r > 5 {
            let c = (p.0 + b(rng.range(-5, 5)), p.1 - b(down), p.2 + b(rng.range(-5, 5)));
            let rb = r as f64 * 2.0 / 3.0;
            let reach = rb.ceil() as i32;
            for dx in -reach..=reach {
                for dy in -reach..=reach {
                    for dz in -reach..=reach {
                        let q = (c.0 + dx, c.1 + dy, c.2 + dz);
                        let d = ((dx * dx + dy * dy + dz * dz) as f64).sqrt();
                        if !w.in_bounds(q.0, q.1, q.2) || d > rb * (1.0 - 0.3 * rough(seed, q)) {
                            continue;
                        }
                        let t = w.get(q.0, q.1, q.2);
                        if turn.contains(&t) || (t == 0 && w.liquid_at(q.0, q.1, q.2).1 > 0) {
                            put(w, q, thin);
                        }
                    }
                }
            }
            down += r - 2;
            r -= 1;
        }
        w.structures.push(((p.0 - b(25), p.1 - b(25) - b(down), p.2 - b(25)), (p.0 + b(25), p.1 + b(25), p.2 + b(25))));
        made += 1;
    }
    made
}

/// Terraria's FragileIceOverIceBiomeWater: under the surface, the top of
/// water lying on snow or ice, and the top of the water joined to it, turns
/// to Thin Ice.
pub fn fragile_ice(w: &mut World, l: &Layers) -> usize {
    let thin = w.id_of("thin_ice");
    let icy: Vec<u16> = ["snow_block", "ice_block"].iter().map(|n| w.id_of(n)).filter(|&t| t != 0).collect();
    if thin == 0 || icy.is_empty() {
        return 0;
    }
    let top = |w: &World, (x, y, z): P| {
        let (t, a) = w.liquid_at(x, y, z);
        w.get(x, y, z) == 0 && a > 0 && t == LIQ_WATER && w.get(x, y + 1, z) == 0 && w.liquid_at(x, y + 1, z).1 == 0
    };
    let mut seeds = Vec::new();
    for z in 1..w.sz - 1 {
        for x in 1..w.sx - 1 {
            let mut y = l.surface_base.min(w.sy - 2);
            while y > 2 {
                if top(w, (x, y, z)) {
                    // Down through the water to what it lies on.
                    let mut f = y;
                    while f > 1 && w.get(x, f, z) == 0 && w.liquid_at(x, f, z).1 > 0 {
                        f -= 1;
                    }
                    if icy.contains(&w.get(x, f, z)) {
                        seeds.push((x, y, z));
                    }
                    y = f;
                }
                y -= 1;
            }
        }
    }
    let mut seen: HashSet<P> = HashSet::new();
    let mut queue: VecDeque<P> = seeds.into_iter().collect();
    let mut n = 0;
    while let Some(p) = queue.pop_front() {
        if !seen.insert(p) || !top(w, p) {
            continue;
        }
        put(w, p, thin);
        n += 1;
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            queue.push_back((p.0 + dx, p.1, p.2 + dz));
        }
    }
    n
}

/// Terraria's campsites.
pub fn campsites(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast) -> usize {
    let id = |n: &str| w.id_of(n);
    let (fire, bones, coins, sand, hard) = (id("campfire_off"), id("bone_pile"), id("gold_coin_pile"), id("sand"), id("hardened_sand"));
    let avoid: Vec<u16> = w.defs.iter().enumerate()
        .filter(|(_, d)| d.name.ends_with("chest") || d.name.ends_with("_brick") && ["blue", "green", "pink", "lihzahrd"].iter().any(|k| d.name.starts_with(k))
            || d.name.ends_with("altar"))
        .map(|(i, _)| i as u16).collect();
    let want = count(w, rng, 6, 11);
    let mut made = 0;
    for _ in 0..1000 {
        if made >= want {
            break;
        }
        let p = (rng.range(b(60), w.sx - b(60)), rng.range(l.underworld_top + b(20), l.surface_base - 6), rng.range(b(60), w.sz - b(60)));
        if coast.inland(p.0, p.2) < coast.ocean.width + coast.ocean.beach || w.surface_y(p.0, p.2) - p.1 < b(20) {
            continue;
        }
        // In solid rock: all but 5 of a ball 10 tiles round.
        let rr = b(10);
        let (mut all, mut hard_cells) = (0, 0);
        for dx in -rr..=rr {
            for dy in -rr..=rr {
                for dz in -rr..=rr {
                    if dx * dx + dy * dy + dz * dz <= rr * rr {
                        all += 1;
                        if w.is_solid(p.0 + dx, p.1 + dy, p.2 + dz) {
                            hard_cells += 1;
                        }
                    }
                }
            }
        }
        if hard_cells < all - 5 * 3 {
            continue;
        }
        let r = b(rng.range(6, 10));
        if in_structure(w, p, r) {
            continue;
        }
        let near = r + b(3);
        if (-near..=near).any(|dx| (-near..=near).any(|dy| (-near..=near).any(|dz| avoid.contains(&w.get(p.0 + dx, p.1 + dy, p.2 + dz))))) {
            continue;
        }
        // The hollow: a dome (Terraria's Slime shape), rough-edged; the sand
        // over it hardened first.
        let seed = rng.next();
        let inside = |q: P| {
            let (dx, dy, dz) = ((q.0 - p.0) as f64, (q.1 - p.1) as f64, (q.2 - p.2) as f64);
            let ry = if dy > 0.0 { r as f64 } else { r as f64 * 0.5 };
            dx * dx / (r * r) as f64 + dz * dz / (r * r) as f64 + dy * dy / (ry * ry) < 1.0 - 0.3 * rough(seed, q)
        };
        for dx in -r - 1..=r + 1 {
            for dy in -r..=r + 2 {
                for dz in -r - 1..=r + 1 {
                    let q = (p.0 + dx, p.1 + dy, p.2 + dz);
                    if inside((q.0, q.1 - 1, q.2)) && w.get(q.0, q.1, q.2) == sand && hard != 0 {
                        put(w, q, hard);
                    }
                }
            }
        }
        for dx in -r..=r {
            for dy in -r..=r {
                for dz in -r..=r {
                    let q = (p.0 + dx, p.1 + dy, p.2 + dz);
                    if w.in_bounds(q.0, q.1, q.2) && inside(q) {
                        put(w, q, 0);
                        let i = w.idx(q.0, q.1, q.2);
                        w.liquid[i] = 0;
                    }
                }
            }
        }
        drop_unsupported(w, (p.0 - r, p.1 - r, p.2 - r), (p.0 + r, p.1 + r, p.2 + r));
        // Its floor under the middle.
        let mut f = p.1;
        while f > p.1 - b(10) && !w.is_solid(p.0, f - 1, p.2) {
            f -= 1;
        }
        if !w.is_solid(p.0, f - 1, p.2) {
            continue;
        }
        let dir = if rng.range(0, 2) == 0 { (1, 0) } else { (0, 1) };
        let s = if rng.range(0, 2) == 0 { 1 } else { -1 };
        let along = |k: i32| (p.0 + dir.0 * k * s, p.2 + dir.1 * k * s);
        let on_floor = |w: &World, (x, z): (i32, i32)| -> Option<i32> {
            let mut y = f + 2;
            while y > f - 3 && w.get(x, y - 1, z) == 0 {
                y -= 1;
            }
            (w.get(x, y, z) == 0 && w.is_solid(x, y - 1, z)).then_some(y)
        };
        // Stacks of Gold Coins: 1-3 of 1-2, 4 tiles off.
        if rng.range(0, 10) != 0 && coins != 0 {
            for k in 0..rng.range(1, 4) {
                let (x, z) = along(b(4) - k);
                if let Some(y) = on_floor(w, (x, z)) {
                    for h in 0..rng.range(1, 3) {
                        put(w, (x, y + h, z), coins);
                    }
                }
            }
        }
        // A skeleton (a big pile of bones) beside the fire.
        if rng.range(0, 10) != 0 && bones != 0 {
            let (x, z) = along(-1);
            if let Some(y) = on_floor(w, (x, z)) {
                put(w, (x, y, z), bones);
            }
        }
        if rng.range(0, 10) != 0 && fire != 0 {
            if let Some(y) = on_floor(w, (p.0, p.2)) {
                put(w, (p.0, y, p.2), fire);
            }
        }
        w.structures.push(((p.0 - r, p.1 - r, p.2 - r), (p.0 + r, p.1 + r, p.2 + r)));
        w.decorations.push(Decoration { kind: "campsite".into(), pos: (p.0, f, p.2), style: 0 });
        made += 1;
    }
    made
}

/// Terraria's mining explosives: a vein of one of the world's metals with
/// Explosives in it, wired to a Detonator.
pub fn mining_explosives(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast) -> usize {
    let id = |n: &str| w.id_of(n);
    let (explosives, detonator, stone) = (id("explosives"), id("detonator"), id("stone"));
    if explosives == 0 || detonator == 0 {
        return 0;
    }
    // The world's metals (one of each pair: the "ores" decoration's bits, as
    // the chests read it).
    let bits = w.decorations.iter().find(|d| d.kind == "ores").map_or(0, |d| d.style);
    let ores: Vec<u16> = [("copper_ore", "tin_ore"), ("iron_ore", "lead_ore"), ("silver_ore", "tungsten_ore"), ("gold_ore", "platinum_ore")]
        .iter().enumerate().map(|(k, (a, bb))| id(if bits & (1 << k) != 0 { bb } else { a })).filter(|&o| o != 0).collect();
    if ores.is_empty() {
        return 0;
    }
    let desert: Vec<u16> = ["hardened_sand", "sandstone", "sand"].iter().map(|n| id(n)).collect();
    let want = count(w, rng, 14, 29);
    let mut made = 0;
    for _ in 0..3000 {
        if made >= want {
            break;
        }
        let p = (rng.range(b(60), w.sx - b(60)), rng.range(l.underworld_top + b(30), l.cavern_top), rng.range(b(60), w.sz - b(60)));
        if coast.inland(p.0, p.2) < coast.ocean.width || w.is_solid(p.0, p.1, p.2) || w.get(p.0, p.1, p.2) != 0 {
            continue;
        }
        // Down to the cave's floor (80 tiles at most).
        let mut y = p.1;
        while y > p.1 - b(80) && !w.is_solid(p.0, y - 1, p.2) {
            y -= 1;
        }
        let floor = (p.0, y - 1, p.2);
        if !solid(w, floor) || desert.contains(&w.get(floor.0, floor.1, floor.2)) || in_structure(w, floor, b(15)) {
            continue;
        }
        // The vein: a worm 20 steps from the floor down into the rock
        // (ShapeRunner 10, 20), at least half of it in rock.
        let ore = ores[rng.range(0, ores.len() as i32) as usize];
        let dir = if rng.range(0, 2) == 0 { (1, 0) } else { (0, 1) };
        let lean = rng.unit() * 2.0 - 1.0;
        let mut vein = Vec::new();
        let (mut cx, mut cy, mut cz) = (floor.0 as f64, floor.1 as f64, floor.2 as f64);
        for step in 0..20 {
            let rad = 1.0 + 2.0 * (1.0 - step as f64 / 20.0);
            let reach = rad.ceil() as i32;
            for dx in -reach..=reach {
                for dy in -reach..=reach {
                    for dz in -reach..=reach {
                        if ((dx * dx + dy * dy + dz * dz) as f64) < rad * rad {
                            vein.push((cx as i32 + dx, cy as i32 + dy, cz as i32 + dz));
                        }
                    }
                }
            }
            cx += lean * dir.0 as f64 * 0.66;
            cz += lean * dir.1 as f64 * 0.66;
            cy -= 0.66;
        }
        vein.sort();
        vein.dedup();
        let rock = vein.iter().filter(|&&q| w.is_solid(q.0, q.1, q.2)).count();
        if rock * 2 < vein.len() {
            continue;
        }
        for &q in &vein {
            if w.is_solid(q.0, q.1, q.2) && w.def(w.get(q.0, q.1, q.2)).render == RENDER_CUBE {
                put(w, q, ore);
            }
        }
        // A pocket over the vein's start (a ball 5 tiles round, 5 up and
        // over), its floor stone; the Detonator on it 3 tiles from the
        // Explosives, which go in the vein under the floor.
        let s = if lean > 0.0 { -1 } else { 1 };
        let pc = (floor.0 + dir.0 * s * b(5), floor.1 + b(5), floor.2 + dir.1 * s * b(5));
        let pr = b(5);
        for dx in -pr..=pr {
            for dy in -pr..=pr {
                for dz in -pr..=pr {
                    let q = (pc.0 + dx, pc.1 + dy, pc.2 + dz);
                    if dx * dx + dy * dy + dz * dz <= pr * pr && w.in_bounds(q.0, q.1, q.2) && w.get(q.0, q.1, q.2) != 0 && w.is_solid(q.0, q.1, q.2) {
                        put(w, q, 0);
                    }
                }
            }
        }
        drop_unsupported(w, (pc.0 - pr, pc.1 - pr, pc.2 - pr), (pc.0 + pr, pc.1 + pr, pc.2 + pr));
        let det = (floor.0 + dir.0 * s * b(3), floor.1, floor.2 + dir.1 * s * b(3));
        let mut dy = det.1 + 3;
        while dy > det.1 - 4 && !w.is_solid(det.0, dy - 1, det.2) {
            dy -= 1;
        }
        let det = (det.0, dy, det.2);
        let blast = (floor.0, floor.1 - 1, floor.2);
        if !w.is_solid(det.0, det.1 - 1, det.2) || !solid(w, blast) {
            continue;
        }
        for k in 0..4 {
            put(w, (det.0, det.1 + k, det.2), 0);
        }
        if stone != 0 && !solid(w, (det.0, det.1 - 1, det.2)) {
            put(w, (det.0, det.1 - 1, det.2), stone);
        }
        put(w, det, detonator);
        put(w, blast, explosives);
        crate::wires::lay(w, det, blast, crate::wires::RED);
        w.structures.push(((floor.0 - b(15), floor.1 - b(10), floor.2 - b(15)), (floor.0 + b(15), floor.1 + b(10), floor.2 + b(15))));
        made += 1;
    }
    made
}

/// Terraria's lava traps: 0.02 a tile of its width (84 in a small world).
pub fn lava_traps(w: &mut World, rng: &mut Rng, l: &Layers) -> usize {
    let plate = w.id_of("orange_pressure_plate");
    if plate == 0 {
        return 0;
    }
    let keep: Vec<u16> = ["blue_brick", "green_brick", "pink_brick", "hive", "lihzahrd_brick", "thin_ice"].iter().map(|n| w.id_of(n)).filter(|&t| t != 0).collect();
    let wired: HashSet<P> = w.decorations.iter().filter(|d| d.kind == "wire").map(|d| d.pos).collect();
    let want = (84.0 * worlds(w)).round() as usize;
    let lava_full = |w: &World, (x, y, z): P| w.get(x, y, z) == 0 && w.liquid_at(x, y, z) == (LIQ_LAVA, LIQ_MAX);
    let (lo, hi) = (l.underworld_top + b(10), (l.cavern_top + l.underworld_top) / 2);
    let mut made = 0;
    for _ in 0..want {
        for _ in 0..10_150 / 10 {
            let p = (rng.range(b(200), w.sx - b(200)), rng.range(lo, hi), rng.range(b(200), w.sz - b(200)));
            if !lava_full(w, p) {
                continue;
            }
            // 50 of 121 tiles round it full of lava: here that share of a
            // 7 x 7 x 7 box.
            let full = (-3..=3).flat_map(|dx| (-3..=3).flat_map(move |dy| (-3..=3).map(move |dz| (dx, dy, dz))))
                .filter(|&(dx, dy, dz)| lava_full(w, (p.0 + dx, p.1 + dy, p.2 + dz))).count();
            if full * 121 < 50 * 343 {
                continue;
            }
            // Down through the lava to its floor (the rock: from `top`), on
            // through it to the cave under it (from `under`), to that cave's
            // floor.
            let (x, z) = (p.0, p.2);
            let mut y = p.1;
            while y > 2 && !w.is_solid(x, y, z) {
                y -= 1;
            }
            let top = y;
            let r = b(20);
            if wired.iter().any(|q| (q.0 - x).abs() <= r && (q.1 - top).abs() <= r && (q.2 - z).abs() <= r) {
                continue;
            }
            while y > 2 && solid(w, (x, y, z)) {
                y -= 1;
            }
            if keep.contains(&w.get(x, y + 1, z)) || w.get(x, y, z) != 0 {
                continue;
            }
            let under = y;
            while y > 2 && w.get(x, y, z) == 0 && w.liquid_at(x, y, z).1 == 0 {
                y -= 1;
            }
            if !solid(w, (x, y, z)) || keep.contains(&w.get(x, y, z)) {
                continue;
            }
            let at = y + 1;
            if top - at > b(40) || under - at < b(4) {
                continue;
            }
            put(w, (x, at, z), plate);
            for k in under + 1..=top {
                crate::wires::actuator(w, (x, k, z));
            }
            crate::wires::lay(w, (x, at, z), (x, top, z), crate::wires::RED);
            made += 1;
            break;
        }
    }
    made
}
