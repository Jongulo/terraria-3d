//! Terraria's Granite caves (its Granite pass: GraniteBiome.Place), in 3D.
//!
//! - **How many:** 4 to 8, scaled with the world's width (Terraria's
//!   WorldGenRange "Count", ScaleWith WorldWidth); here that many in each
//!   640 x 640 blocks of the map, as the cabins do, one in each cell of a
//!   grid over it and never in the middle tenth either way (Terraria: one in
//!   each slice of the world's width, never in its middle tenth).
//! - **Where:** from 20 tiles under the cavern layer down to 200 above the
//!   world's bottom, in an open cell (CanPlace: not in a block), not within
//!   50 tiles of granite, marble, snow, ice, glowing mushrooms or the
//!   desert's sandstone (WorldGen.BiomeTileCheck). All the spots are picked
//!   first, then the caves made.
//! - **Magma:** a cube 200 tiles across (here 134 blocks) round the spot
//!   holds a "magma" pressure and resistance per cell: resistance 1 in the
//!   open, 4 in a block. Pressure 25 is let in at the middle for 2 steps,
//!   then for 300 steps (here 400: the 3D front creeps out slower, and this
//!   gives caves Terraria's size, 60-70 blocks across) each flowing
//!   cell takes its neighbours' mean pressure: where that's over its
//!   resistance it flows, with new pressure (mean - push - own)+ + push +
//!   own x 0.875 - resistance (push: the length of its neighbours' summed
//!   pressure vectors over the count), wearing its resistance down by 0.02 of
//!   that; a flowing cell with pressure over 0.01 sets its still neighbours
//!   flowing. (Terraria's 8 neighbours in its plane; here the 6 face
//!   neighbours, whose mean behaves like Terraria's: a mean over all 26
//!   dilutes the start too much to flow at all.)
//! - **Granite:** each cell the magma reached turns to granite where
//!   max(1 - (sin(y x 0.4) x 0.7 + 1.2) x (0.2 + 0.5 / sqrt(pressure -
//!   resistance)), pressure / 15) is over 0.35 (0.85 in the open; y in
//!   tiles, which bands it in layers), ores kept; else where its resistance
//!   wore away to under 0.01 it's dug out. (Terraria turns water in it to
//!   lava below its lava line; here the caves' water comes after, so there's
//!   none yet.)
//! - **Clean up:** a granite block with fewer than 3 solid cells round it
//!   (of its 3 x 3 in Terraria, counting itself; here of its 3 x 3 x 3) is
//!   dug out.
//! - **Decorations:** in 1 cell in 8 of what it reached, a stalactite under
//!   a granite ceiling, or a stalagmite on a granite floor (large or small;
//!   Terraria's PlaceUncheckedStalactite); Terraria slopes half the blocks'
//!   corners, which isn't done here. Its box is kept from the structures
//!   after it.
//!
//! Terraria's tiles are 2/3 of a block here.

use crate::marble::{biome_check_ids, biome_tile_check, grid_spot, Speleothems, TILE};
use crate::world::World;
use crate::worldgen::{Layers, Rng};
use rayon::prelude::*;

type P = (i32, i32, i32);

/// The magma's cube, in blocks a side (Terraria's 200 tiles).
const SIZE: i32 = 134;
/// Its steps (Terraria's 300; the magma's front creeps out slower in 3D).
const STEPS: usize = 400;
const NEIGHBOURS: [P; 6] = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)];

pub struct Ids {
    pub granite: u16,
    pub check: Vec<u16>,
    pub ore: Vec<bool>,
    pub spel: Speleothems,
}

impl Ids {
    pub fn new(w: &World) -> Self {
        Ids {
            granite: w.id_of("granite"),
            check: biome_check_ids(w),
            ore: w.defs.iter().map(|d| d.name.ends_with("_ore")).collect(),
            spel: Speleothems::of(w, "granite"),
        }
    }
}

/// The world's Granite caves; returns their middles. `inland` keeps them from
/// under the sea.
pub fn granite_caves(w: &mut World, rng: &mut Rng, l: &Layers, inland: &dyn Fn(i32, i32) -> bool) -> Vec<P> {
    let ids = Ids::new(w);
    let mut spots = Vec::new();
    if ids.granite == 0 {
        return spots;
    }
    let per_world = rng.range(4, 9) as f64;
    let want = (per_world * w.sx as f64 * w.sz as f64 / (640.0 * 640.0)).round() as usize;
    let (y_lo, y_hi) = (crate::dungeon::depth_y(l, 710.0), crate::dungeon::depth_y(l, 150.0));
    // Terraria picks every spot before it makes any cave.
    for k in 0..want {
        for _ in 0..200 {
            let (x, z) = grid_spot(w, rng, k, want, 60);
            let y = rng.range(y_lo, y_hi.max(y_lo + 1));
            if inland(x, z) && w.get(x, y, z) == 0 && !biome_tile_check(w, &ids.check, (x, y, z)) {
                spots.push((x, y, z));
                break;
            }
        }
    }
    for &s in &spots {
        granite_cave(w, rng, &ids, s);
    }
    spots
}

/// A magma cell (GraniteBiome.Magma).
#[derive(Clone, Copy, Default)]
struct Magma {
    pressure: f32,
    resistance: f32,
    active: bool,
}

fn at(x: i32, y: i32, z: i32) -> usize {
    ((x * SIZE + y) * SIZE + z) as usize
}

/// One step of SimulatePressure for the cell at `i` (x, y, z): what it
/// becomes from `src`. A flowing cell flows on if its neighbours' mean
/// pressure is over its resistance; a still one starts flowing (as it was)
/// when a neighbour flowing with pressure over 0.01 reaches it.
fn step_cell(src: &[Magma], (x, y, z): P) -> Magma {
    let c = src[at(x, y, z)];
    if !c.active {
        let reached = NEIGHBOURS.iter().any(|&(dx, dy, dz)| {
            let n = src[at(x + dx, y + dy, z + dz)];
            n.active && n.pressure > 0.01
        });
        return Magma { active: c.active || reached, ..c };
    }
    let (mut sum, mut push) = (0.0f32, (0.0f32, 0.0f32, 0.0f32));
    for &(dx, dy, dz) in &NEIGHBOURS {
        let q = src[at(x + dx, y + dy, z + dz)].pressure;
        sum += q;
        push = (push.0 + q * dx as f32, push.1 + q * dy as f32, push.2 + q * dz as f32);
    }
    let k = NEIGHBOURS.len() as f32;
    let mean = sum / k;
    if mean <= c.resistance {
        return c;
    }
    let push = (push.0 * push.0 + push.1 * push.1 + push.2 * push.2).sqrt() / k;
    let v = ((mean - push - c.pressure).max(0.0) + push + c.pressure * 0.875 - c.resistance).max(0.0);
    Magma { pressure: v, resistance: (c.resistance - v * 0.02).max(0.0), active: true }
}

/// GraniteBiome.Place at `c` (an open cell): the magma, the granite, its
/// cleanup and decorations. False if `c` is in a block.
pub fn granite_cave(w: &mut World, rng: &mut Rng, ids: &Ids, c: P) -> bool {
    if w.get(c.0, c.1, c.2) != 0 {
        return false;
    }
    let o = (c.0 - SIZE / 2, c.1 - SIZE / 2, c.2 - SIZE / 2);
    let cell = |x: i32, y: i32, z: i32| (o.0 + x, o.1 + y, o.2 + z);
    let plane = (SIZE * SIZE) as usize;
    // BuildMagmaMap: resistance 1 in the open, 4 in a block.
    let mut src = vec![Magma::default(); plane * SIZE as usize];
    src.par_chunks_mut(plane).enumerate().for_each(|(x, cells)| {
        for y in 0..SIZE {
            for z in 0..SIZE {
                let (wx, wy, wz) = cell(x as i32, y, z);
                let solid = w.in_bounds(wx, wy, wz) && w.is_solid(wx, wy, wz);
                cells[(y * SIZE + z) as usize].resistance = if solid { 4.0 } else { 1.0 };
            }
        }
    });
    let mut dst = src.clone();
    // SimulatePressure, in the box the magma has reached (and a cell round
    // it), each step's cells worked out from the last's.
    let m = SIZE / 2;
    let (mut lo, mut hi) = ((m, m, m), (m, m, m));
    for step in 0..STEPS {
        let (l0, h0) = ((lo.0 - 1).max(1), (hi.0 + 1).min(SIZE - 2));
        let (ylo, yhi, zlo, zhi) = ((lo.1 - 1).max(1), (hi.1 + 1).min(SIZE - 2), (lo.2 - 1).max(1), (hi.2 + 1).min(SIZE - 2));
        let s = &src;
        let reach: Vec<Option<(P, P)>> = dst
            .par_chunks_mut(plane)
            .enumerate()
            .skip(l0 as usize)
            .take((h0 - l0 + 1) as usize)
            .map(|(x, cells)| {
                let x = x as i32;
                let mut b: Option<(P, P)> = None;
                for y in ylo..=yhi {
                    for z in zlo..=zhi {
                        let n = step_cell(s, (x, y, z));
                        cells[(y * SIZE + z) as usize] = n;
                        if n.active {
                            let p = (x, y, z);
                            b = Some(b.map_or((p, p), |(a, c)| ((a.0.min(x), a.1.min(y), a.2.min(z)), (c.0.max(x), c.1.max(y), c.2.max(z)))));
                        }
                    }
                }
                b
            })
            .collect();
        for (a, b) in reach.into_iter().flatten() {
            lo = (lo.0.min(a.0), lo.1.min(a.1), lo.2.min(a.2));
            hi = (hi.0.max(b.0), hi.1.max(b.1), hi.2.max(b.2));
        }
        if step < 2 {
            dst[at(m, m, m)] = Magma { pressure: 25.0, resistance: 0.0, active: true };
        }
        std::mem::swap(&mut src, &mut dst);
    }
    // The cells round the box are never worked out; the box's walls are a
    // cell in from the cube's.
    let (lo, hi) = ((lo.0.max(1), lo.1.max(1), lo.2.max(1)), (hi.0.min(SIZE - 2), hi.1.min(SIZE - 2), hi.2.min(SIZE - 2)));
    // PlaceGranite.
    let mut reached = Vec::new();
    for x in lo.0..=hi.0 {
        for y in lo.1..=hi.1 {
            for z in lo.2..=hi.2 {
                let mg = src[at(x, y, z)];
                if !mg.active {
                    continue;
                }
                let (wx, wy, wz) = cell(x, y, z);
                if !w.in_bounds(wx, wy, wz) || wx < 4 || wz < 4 || wx >= w.sx - 4 || wz >= w.sz - 4 || wy < 4 || wy >= w.sy - 4 {
                    continue;
                }
                reached.push((wx, wy, wz));
                let (p, r) = (mg.pressure as f64, mg.resistance as f64);
                let band = (wy as f64 / TILE * 0.4).sin() * 0.7 + 1.2;
                let over = p - r;
                let wear = if over > 0.0 { 0.2 + 0.5 / over.sqrt() } else { f64::INFINITY };
                let solid = w.is_solid(wx, wy, wz);
                let j = w.idx(wx, wy, wz);
                if (1.0 - (band * wear).max(0.0)).max(p / 15.0) > 0.35 + if solid { 0.0 } else { 0.5 } {
                    let b = w.blocks[j];
                    if !ids.ore.get(b as usize).copied().unwrap_or(false) {
                        w.blocks[j] = ids.granite;
                    }
                    w.liquid[j] = 0;
                } else if r < 0.01 {
                    w.blocks[j] = 0;
                }
            }
        }
    }
    // CleanupTiles: granite with fewer than 3 solid cells round it (itself
    // counted) goes.
    let lonely: Vec<P> = reached
        .iter()
        .copied()
        .filter(|&(x, y, z)| {
            w.get(x, y, z) == ids.granite && {
                let mut n = 0;
                for dx in -1..=1 {
                    for dy in -1..=1 {
                        for dz in -1..=1 {
                            if w.is_solid(x + dx, y + dy, z + dz) {
                                n += 1;
                            }
                        }
                    }
                }
                n < 3
            }
        })
        .collect();
    for (x, y, z) in lonely {
        let j = w.idx(x, y, z);
        w.blocks[j] = 0;
    }
    // PlaceDecorations: 1 in 8 of the cells it reached.
    for &(x, y, z) in &reached {
        if rng.range(0, 8) == 0 {
            for p in [(x, y - 1, z), (x, y + 1, z)] {
                if w.get(x, y, z) == ids.granite {
                    ids.spel.place(w, rng, p, ids.granite);
                }
            }
        }
    }
    if let (Some(a), Some(b)) = (reached.iter().copied().reduce(|a, b| (a.0.min(b.0), a.1.min(b.1), a.2.min(b.2))), reached.iter().copied().reduce(|a, b| (a.0.max(b.0), a.1.max(b.1), a.2.max(b.2)))) {
        w.structures.push((a, b));
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CUBE};

    fn stone_world(seed: u64) -> World {
        let mut w = World::new();
        w.set_def(1, BlockDef { name: "stone".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        crate::marble::tests::add_cave_defs(&mut w);
        w.resize(200, 160, 200);
        for b in w.blocks.iter_mut() {
            *b = 1;
        }
        // Winding tunnels through the stone, as Terraria's caves leave.
        let mut rng = Rng::new(seed);
        for _ in 0..8 {
            let (mut x, mut y, mut z) = (rng.range(70, 130) as f64, rng.range(60, 100) as f64, rng.range(70, 130) as f64);
            let (mut dx, mut dy, mut dz) = (rng.unit() - 0.5, (rng.unit() - 0.5) * 0.4, rng.unit() - 0.5);
            for _ in 0..90 {
                let r = 1.5 + rng.unit() * 2.0;
                for ix in -4..=4 {
                    for iy in -4..=4 {
                        for iz in -4..=4 {
                            if ((ix * ix + iy * iy + iz * iz) as f64) < r * r {
                                let (px, py, pz) = (x as i32 + ix, y as i32 + iy, z as i32 + iz);
                                if w.in_bounds(px, py, pz) {
                                    let i = w.idx(px, py, pz);
                                    w.blocks[i] = 0;
                                }
                            }
                        }
                    }
                }
                let n = (dx * dx + dy * dy + dz * dz).sqrt().max(1e-6);
                x += dx / n;
                y += dy / n;
                z += dz / n;
                dx += rng.unit() * 0.6 - 0.3;
                dy += (rng.unit() * 0.6 - 0.3) * 0.3;
                dz += rng.unit() * 0.6 - 0.3;
            }
        }
        for x in 95..105 {
            for y in 75..85 {
                for z in 95..105 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 0;
                }
            }
        }
        w
    }

    /// A Granite cave round a cave in the stone: layered granite through the
    /// magma's reach, hollows where it wore the stone away, speleothems, and
    /// its box kept.
    #[test]
    fn a_granite_cave_in_the_stone() {
        let mut w = stone_world(3);
        let ids = Ids::new(&w);
        let t = std::time::Instant::now();
        assert!(granite_cave(&mut w, &mut Rng::new(9), &ids, (100, 80, 100)));
        let took = t.elapsed();
        let (granite, spel) = (ids.granite, ids.spel);
        let (mut g, mut tites, mut mites) = (0, 0, 0);
        for i in 0..w.blocks.len() {
            let b = w.blocks[i];
            if b == granite {
                g += 1;
            } else if b == spel.stalactite || b == spel.small_stalactite {
                tites += 1;
            } else if b == spel.stalagmite || b == spel.small_stalagmite {
                mites += 1;
            }
        }
        assert!(g > 5_000, "granite ({g})");
        assert!(tites + mites > 20, "speleothems ({tites}, {mites})");
        assert_eq!(w.structures.len(), 1);
        // Not in a block: nothing.
        assert!(!granite_cave(&mut w, &mut Rng::new(9), &ids, (0, 0, 0)));
        assert!(took.as_secs_f64() < 5.0, "took {took:?}");
    }

    #[test]
    #[ignore]
    fn dump_granite() {
        let seed: u64 = std::env::var("SEED").map(|s| s.parse().unwrap()).unwrap_or(3);
        let mut w = stone_world(seed);
        let ids = Ids::new(&w);
        let t = std::time::Instant::now();
        granite_cave(&mut w, &mut Rng::new(9), &ids, (100, 80, 100));
        println!("took {:?} structures {:?}", t.elapsed(), w.structures);
        for zz in [100, 90] {
            println!("z={zz}");
            for y in (20..140).rev() {
                let s: String = (20..180).map(|x| { let b = w.get(x, y, zz); if b == 0 { ' ' } else if b == 1 { '.' } else if b == ids.granite { '#' } else { 'v' } }).collect();
                println!("{s}");
            }
        }
    }
}
