//! Terraria's Enchanted Sword Shrines (Terraria.GameContent.Biomes.
//! EnchantedSwordBiome.Place, placed by its Micro Biomes pass), with its 2D
//! shapes spun round the vertical axis into 3D:
//!
//! - **Where:** SwordShrineAttempts tries (1 to 2 in a small world; here that
//!   many in each 640 x 640 blocks, as the cabins count), each skipped half the time
//!   (SwordShrinePlacementChance). A try picks spots 50 to 99 below the
//!   world's surface line, in the outer part of the map (Terraria: its outer
//!   30% each side; here away from the middle 40% either way), until one fits.
//! - **Fits:** the 50 x 50 round it is at least half dirt and stone, there's
//!   open sky above (50 open blocks over the surface), no sand straight
//!   above, and neither the room nor the shaft runs into a structure
//!   (chests, cabins, living trees, dungeon brick).
//! - **The room:** a slime-shaped cave (Shapes.Slime: radius 20, 0.8 to 1.3
//!   as wide, its lower half squashed to half), 20 below the spot, its edge
//!   roughened (Blotches); a dirt mound 14 tall and 14 to each side
//!   (Shapes.Mound, a parabola) rises in it, 30 below the spot. The room's
//!   edge is lined with grass (InnerOutline), the lower half's open space
//!   filled with water (pools round the mound), flower vines hang in clumps
//!   from the grass ceiling, grass plants grow on the mound, and the sword in
//!   stone (LargePiles2 style 17) stands on its top.
//! - **The shaft:** a 1-wide shaft (its edge roughened) from the room's top up
//!   through the surface (sand beside it hardened). Terraria's skips living
//!   wood; here living trees keep a shrine away instead, so nothing caps it.
//!   Terraria digs it 1 time in 3 (its ChanceOfEntrance) and stops 10 below
//!   the surface; here every shrine has one, open to the sky, so a shrine can
//!   be found in a 3D world: its top 8 blocks widen to a round mouth 5 across,
//!   with a wall torch on each side just under the ground.

use crate::world::{Decoration, World, LIQ_MAX, LIQ_WATER};
use crate::worldgen::{Layers, Rng, FACING};
use std::collections::HashSet;

/// How often a shrine has a shaft (Terraria's ChanceOfEntrance is 1/3; here
/// always, so they can be found).
pub const SHAFT_CHANCE: f64 = 1.0;
/// The shaft's mouth: how far down from the surface it is wide, and its
/// radius (squared: 5 makes it 5 across, its corners cut).
pub const MOUTH_DEPTH: i32 = 8;
const MOUTH_R2: i32 = 5;

struct Ids {
    dirt: u16,
    stone: u16,
    grass: u16,
    sand: u16,
    hardened_sand: u16,
    vine: u16,
    plants: [u16; 2],
    sword: u16,
    wall_torch: u16,
    /// Blocks a shrine mustn't be built into (Terraria's protected structures).
    blacklist: Vec<bool>,
}

impl Ids {
    fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        let mut blacklist = vec![false; w.defs.len()];
        for (i, d) in w.defs.iter().enumerate() {
            let n = d.name.as_str();
            blacklist[i] = n.ends_with("_brick") && !n.starts_with("sandstone") && !n.starts_with("ice")
                || n.contains("trunk")
                || n.starts_with("living_")
                || n.contains("chest")
                || n.ends_with("_wall")
                || n.ends_with("_beam")
                || n.ends_with("_column")
                || n.starts_with("sunplate")
                || n == "cloud"
                || n == "sword_in_stone";
        }
        Ids {
            dirt: id("dirt"),
            stone: id("stone"),
            grass: id("grass"),
            sand: id("sand"),
            hardened_sand: id("hardened_sand"),
            vine: id("vine_flowers"),
            plants: [id("tall_grass"), id("flowers")],
            sword: id("sword_in_stone"),
            wall_torch: id("wall_torch"),
            blacklist,
        }
    }
}

/// Places the world's shrines; returns how many.
pub fn sword_shrines(w: &mut World, rng: &mut Rng, l: &Layers) -> usize {
    let ids = Ids::new(w);
    if ids.sword == 0 || ids.grass == 0 || ids.dirt == 0 {
        return 0;
    }
    let attempts = (rng.range(1, 3) as f32 * (w.sx * w.sz) as f32 / (640.0 * 640.0)).round() as i32;
    let mut placed = 0;
    for _ in 0..attempts {
        if rng.unit() < 0.5 {
            continue;
        }
        for _ in 0..w.sx.max(w.sz) {
            let y = l.surface_base - rng.range(50, 100);
            let (x, z) = outer_spot(w, rng);
            if let Some((sword, shaft)) = place(w, rng, &ids, (x, y, z)) {
                w.decorations.push(Decoration { kind: "sword_shrine".into(), pos: sword, style: shaft as i32 });
                placed += 1;
                break;
            }
        }
    }
    placed
}

/// A spot away from the middle of the map (Terraria's outer 30% each side).
fn outer_spot(w: &World, rng: &mut Rng) -> (i32, i32) {
    let (cx, cz) = (w.sx as f32 * 0.5, w.sz as f32 * 0.5);
    loop {
        let x = rng.range(50.min(w.sx / 4), w.sx - 50.min(w.sx / 4));
        let z = rng.range(50.min(w.sz / 4), w.sz - 50.min(w.sz / 4));
        let off = ((x as f32 - cx).abs() / cx).max((z as f32 - cz).abs() / cz);
        if off >= 0.4 {
            return (x, z);
        }
    }
}

/// Blotches: with `chance`, an action reaches a little box round the cell
/// (each way: -1 or 0 to 0 or +1 for a scale of 2; y only `ys`), else just it.
fn blotch(rng: &mut Rng, p: (i32, i32, i32), xs: i32, ys: i32, chance: f64) -> Vec<(i32, i32, i32)> {
    if rng.unit() >= chance {
        return vec![p];
    }
    let span = |rng: &mut Rng, s: i32| (rng.range(1 - s, 1), rng.range(0, s));
    let (x0, x1) = span(rng, xs);
    let (y0, y1) = span(rng, ys);
    let (z0, z1) = span(rng, xs);
    let mut out = Vec::new();
    for x in x0..=x1 {
        for y in y0..=y1 {
            for z in z0..=z1 {
                out.push((p.0 + x, p.1 + y, p.2 + z));
            }
        }
    }
    out
}

/// EnchantedSwordBiome.Place: the shrine at `o` (the top of its room), or
/// None where it doesn't fit. Returns the sword's cell and whether it has a
/// shaft.
fn place(w: &mut World, rng: &mut Rng, ids: &Ids, o: (i32, i32, i32)) -> Option<((i32, i32, i32), bool)> {
    let (ox, oy, oz) = o;
    // At least half of the 50 x 50 round it dirt or stone (sampled every other
    // block each way).
    let (mut ground, mut total) = (0, 0);
    for x in (ox - 25..ox + 25).step_by(2) {
        for y in (oy - 25..oy + 25).step_by(2) {
            for z in (oz - 25..oz + 25).step_by(2) {
                total += 1;
                let b = w.get(x, y, z);
                if b == ids.dirt || b == ids.stone {
                    ground += 1;
                }
            }
        }
    }
    if ground * 2 < total {
        return None;
    }
    // The surface above: the first block with 50 open ones over it.
    let mut open = 0;
    let mut surface = -1;
    for y in oy + 1..w.sy - 55 {
        if w.is_solid(ox, y, oz) {
            open = 0;
        } else {
            open += 1;
            if open == 50 {
                surface = y - 50;
                break;
            }
        }
    }
    if surface < oy {
        return None;
    }
    if (oy..=surface).any(|y| w.get(ox, y, oz) == ids.sand) {
        return None;
    }
    let scale = 0.8 + rng.unit() * 0.5;
    let room = (ox, oy - 20, oz);
    let base = (ox, oy - 30, oz);
    // Neither the room's box nor the shaft (2 blocks round) may run into a
    // structure.
    let reach = (20.0 * scale) as i32;
    let blocked = |w: &World, x0: i32, x1: i32, y0: i32, y1: i32, z0: i32, z1: i32| {
        w.structures.iter().any(|&(lo, hi)| x0 <= hi.0 && lo.0 <= x1 && y0 <= hi.1 && lo.1 <= y1 && z0 <= hi.2 && lo.2 <= z1)
            || (x0..=x1).any(|x| (y0..=y1).any(|y| (z0..=z1).any(|z| ids.blacklist[w.get(x, y, z) as usize])))
    };
    if blocked(w, ox - reach, ox + reach, room.1 - 20, room.1 + 20, oz - reach, oz + reach)
        || blocked(w, ox - 2, ox + 2, oy - 2, surface + 2, oz - 2, oz + 2)
        || blocked(w, ox - 4, ox + 4, surface - MOUTH_DEPTH, surface + 2, oz - 4, oz + 4)
    {
        return None;
    }
    // The room: Shapes.Slime(20, scale, 1), roughened (Blotches 2, 0.4), cleared.
    let mut cave: HashSet<(i32, i32, i32)> = HashSet::new();
    for dy in -9..=20 {
        // Above the middle a circle; below it squashed to half.
        let d = if dy >= 0 { dy as f64 } else { -dy as f64 * 2.0 };
        let half = (20.0 * scale).min(scale * (21.0f64 * 21.0 - d * d).max(0.0).sqrt()) as i32;
        for dx in -half..=half {
            for dz in -half..=half {
                if dx * dx + dz * dz > half * half {
                    continue;
                }
                for p in blotch(rng, (room.0 + dx, room.1 + dy, room.2 + dz), 2, 2, 0.4) {
                    if w.in_bounds(p.0, p.1, p.2) && cave.insert(p) {
                        w.set(p.0, p.1, p.2, 0);
                        w.set_liquid(p.0, p.1, p.2, LIQ_WATER, 0);
                    }
                }
            }
        }
    }
    // The mound: Shapes.Mound(14, 14), a parabola, roughened sideways (Blotches 2, 1, 0.8).
    let mut mound: HashSet<(i32, i32, i32)> = HashSet::new();
    for dx in -14i32..=14 {
        for dz in -14i32..=14 {
            let r2 = (dx * dx + dz * dz) as f64;
            if r2 > 196.0 {
                continue;
            }
            let h = (14.0f64).min(15.0 / 196.0 * (196.0 - r2)) as i32;
            for j in 0..h {
                for p in blotch(rng, (base.0 + dx, base.1 + j, base.2 + dz), 2, 1, 0.8) {
                    if w.in_bounds(p.0, p.1, p.2) && mound.insert(p) {
                        w.set(p.0, p.1, p.2, ids.dirt);
                    }
                }
            }
        }
    }
    // Plants left on ground the mound reached past the room (a glowing
    // mushroom on what is now dirt) go.
    for p in &mound {
        let above = (p.0, p.1 + 1, p.2);
        let b = w.get(above.0, above.1, above.2);
        if b != 0 && !w.def(b).solid && !mound.contains(&above) {
            w.set(above.0, above.1, above.2, 0);
        }
    }
    cave.retain(|p| !mound.contains(p));
    // Its edge lined with grass (InnerOutline, diagonals too); in order, so
    // the vines' random numbers come out the same every time.
    let mut edge: Vec<(i32, i32, i32)> = cave
        .iter()
        .filter(|p| {
            (-1..=1).any(|x| (-1..=1).any(|y| (-1..=1).any(|z| !cave.contains(&(p.0 + x, p.1 + y, p.2 + z)))))
        })
        .copied()
        .collect();
    edge.sort_unstable();
    for p in &edge {
        w.set(p.0, p.1, p.2, ids.grass);
    }
    // Water in the lower half's open space (pools round the mound).
    for p in &cave {
        if p.1 <= room.1 && w.get(p.0, p.1, p.2) == 0 {
            w.set_liquid(p.0, p.1, p.2, LIQ_WATER, LIQ_MAX);
        }
    }
    // Flower vines from the grass ceiling (ActionVines 3, 5, 382). Terraria
    // hangs one 3 to 5 long from every tile of its ceiling, a single row seen
    // side on; spread over a 3D ceiling that's a forest of them in a grid, so
    // here they grow in clumps (noise across the ceiling), half the cells in a
    // clump's heart hung and few at its edge, longer in the heart (up to 7)
    // and shorter (1 or 2) toward the bare ceiling between.
    if ids.vine != 0 {
        let clumps = crate::worldgen::noise(rng.range(0, i32::MAX), 0.16, 2);
        for p in &edge {
            if w.get(p.0, p.1 - 1, p.2) != 0 {
                continue;
            }
            let n = clumps.get_noise_2d(p.0 as f32, p.2 as f32);
            let heart = ((n + 0.15) / 0.65).clamp(0.0, 1.0) as f64;
            if heart <= 0.0 || rng.unit() > 0.1 + heart * 0.45 {
                continue;
            }
            let len = 1 + (heart * (3.0 + rng.unit() * 3.5)).round() as i32;
            for k in 1..=len {
                if w.get(p.0, p.1 - k, p.2) != 0 || w.liquid_at(p.0, p.1 - k, p.2).1 > 0 {
                    break;
                }
                w.set(p.0, p.1 - k, p.2, ids.vine);
            }
        }
    }
    // The shaft, from the room's top up through the surface.
    let shaft = rng.unit() < SHAFT_CHANCE;
    if shaft {
        let mut cut: HashSet<(i32, i32, i32)> = HashSet::new();
        for y in oy..=surface {
            for p in blotch(rng, (ox, y, oz), 2, 2, 0.2) {
                if w.in_bounds(p.0, p.1, p.2) {
                    w.set(p.0, p.1, p.2, 0);
                    cut.insert(p);
                }
            }
        }
        // Its mouth: wide from MOUTH_DEPTH under the surface up through each
        // column's own ground (a hillside too), leaving any tree alone.
        for dx in -2i32..=2 {
            for dz in -2i32..=2 {
                if dx * dx + dz * dz > MOUTH_R2 {
                    continue;
                }
                let (x, z) = (ox + dx, oz + dz);
                for y in surface - MOUTH_DEPTH..=surface + 15 {
                    let b = w.get(x, y, z);
                    // Open above the ground (the shaft's rough edge below doesn't count).
                    if y >= surface - 1 && b == 0 && w.get(x, y + 1, z) == 0 || ids.blacklist[b as usize] {
                        break;
                    }
                    w.set(x, y, z, 0);
                    w.set_liquid(x, y, z, LIQ_WATER, 0);
                    cut.insert((x, y, z));
                }
            }
        }
        // A wall torch on each side, as high as there's wall behind it, leaning
        // in over the shaft.
        if ids.wall_torch != 0 {
            for (fx, fz) in FACING {
                let (x, z) = (ox - fx * 2, oz - fz * 2);
                let at = (surface - MOUTH_DEPTH + 2..surface)
                    .rev()
                    .find(|&y| w.get(x, y, z) == 0 && w.is_solid(x - fx, y, z - fz));
                if let Some(y) = at {
                    w.set(x, y, z, ids.wall_torch);
                    let style = FACING.iter().position(|&d| d == (fx, fz)).unwrap_or(0) as i32;
                    w.decorations.push(Decoration { kind: "rotation".into(), pos: (x, y, z), style });
                }
            }
        }
        // Sand beside it hardens (Expand 1, sand -> hardened sand).
        if ids.hardened_sand != 0 {
            for p in &cut {
                for (x, y, z) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                    let q = (p.0 + x, p.1 + y, p.2 + z);
                    if w.get(q.0, q.1, q.2) == ids.sand {
                        w.set(q.0, q.1, q.2, ids.hardened_sand);
                    }
                }
            }
        }
    }
    // The sword in stone on the mound's top (Terraria: 15 above its base).
    let sword = (base.0, base.1 + 15, base.2);
    w.set(sword.0, sword.1, sword.2, ids.sword);
    w.set_liquid(sword.0, sword.1, sword.2, LIQ_WATER, 0);
    // Grass plants on the mound (ActionGrass, on the grass over it).
    if ids.plants[0] != 0 {
        let mut tops: Vec<(i32, i32)> = mound.iter().map(|p| (p.0, p.2)).collect::<HashSet<_>>().into_iter().collect();
        tops.sort_unstable();
        for (x, z) in tops {
            let top = mound.iter().filter(|p| p.0 == x && p.2 == z).map(|p| p.1).max().unwrap_or(base.1);
            let (gy, py) = (top + 1, top + 2);
            if w.get(x, gy, z) == ids.grass && w.get(x, py, z) == 0 && w.liquid_at(x, py, z).1 == 0 && (x, py, z) != sword {
                let plant = ids.plants[if rng.range(0, 3) == 0 && ids.plants[1] != 0 { 1 } else { 0 }];
                w.set(x, py, z, plant);
            }
        }
    }
    Some((sword, shaft))
}
