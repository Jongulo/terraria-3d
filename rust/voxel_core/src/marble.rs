//! Terraria's Marble caves (its Marble pass: MarbleBiome.Place), in 3D, and
//! the speleothems (stalactites, stalagmites) that the Marble and Granite
//! caves share (WorldGen.PlaceTight).
//!
//! - **How many:** 4 to 8, scaled with the world's area (Terraria's
//!   WorldGenRange "Count", ScaleWith WorldArea); its worlds are a 2D slice,
//!   so here that many go in each 640 x 640 blocks of the map, as the cabins
//!   do. Terraria spreads them across the world's width, one in each slice
//!   of it, never in the middle tenth (spawn); here one in each cell of a
//!   grid over the map, never in the middle tenth either way.
//! - **Where:** from 20 tiles under the cavern layer down to 200 above the
//!   world's bottom (the Underworld's top). Not within 50 tiles of granite,
//!   marble, snow, ice, glowing mushrooms or the desert's sandstone
//!   (WorldGen.BiomeTileCheck); a try that is turned down is tried again
//!   somewhere else.
//! - **The cave** is built of slabs, each 3 x 3 tiles (here 2 x 2 x 2
//!   blocks): (80-150) / 3 slabs across (here across x and z, each its own
//!   width) and (40-60) / 3 high. Each slab is solid or empty by its height
//!   in the cave and how far out it is: a hollow band through the middle
//!   (its height (40-60) - (20-30) tiles less the slab's distance out),
//!   marble floors and ceilings round it, and further out what was there
//!   turned to marble (a slab with any solid tile in it stays solid). Out at
//!   the edge (past 0.35-0.45 of the width) an empty slab stays empty.
//! - Each slab's corners are smoothed (MarbleBiome.SmoothSlope): a solid slab
//!   with only its floor under it is a half slab, one on a floor with
//!   open sides a step (Terraria's slopes, here a slab's top half kept only
//!   away from its open sides; under a ceiling the same upside down).
//! - The slabs are laid in an ellipsoid (Terraria's ellipse: as many slabs up
//!   and down each column as fit), the cave's floor wandering up and down
//!   across it (each column's offset, the sum of a slope that eases from
//!   one random value to another, along x and along z). Each slab's tiles
//!   spill a tile past its sides at random (ragged edges), ores in it are
//!   kept, and a quarter of the cells under a marble ceiling or on a marble
//!   floor get a marble stalactite or stalagmite (PlaceTight), large or
//!   small. The cave's box is kept from the structures after it.
//!
//! Terraria's tiles are 2/3 of a block here.

use crate::world::World;
use crate::worldgen::{Layers, Rng};

type P = (i32, i32, i32);

/// A Terraria tile, in blocks.
pub const TILE: f64 = 2.0 / 3.0;
/// A slab's side, in blocks (Terraria's 3 tiles).
const SLAB: i32 = 2;
/// A slab's cells (SLAB^3): bit lx + 2 ly + 4 lz, ly 0 at the bottom.
const SOLID: u8 = 0xff;
const EMPTY: u8 = 0;

/// The speleothems of one stone (Terraria's tile 165 frames for it): large
/// and small stalactites, large and small stalagmites.
#[derive(Clone, Copy, Default)]
pub struct Speleothems {
    pub stalactite: u16,
    pub small_stalactite: u16,
    pub stalagmite: u16,
    pub small_stalagmite: u16,
}

impl Speleothems {
    pub fn of(w: &World, stone: &str) -> Self {
        let id = |n: String| w.id_of(&n);
        Speleothems {
            stalactite: id(format!("{stone}_stalactite")),
            small_stalactite: id(format!("small_{stone}_stalactite")),
            stalagmite: id(format!("{stone}_stalagmite")),
            small_stalagmite: id(format!("small_{stone}_stalagmite")),
        }
    }

    /// Terraria's PlaceTight at an open cell: under a ceiling of `on` a
    /// stalactite, else on a floor of it a stalagmite; large or small half
    /// the time each (a large one needs the cell beyond it open too, in
    /// Terraria a second tile).
    pub fn place(&self, w: &mut World, rng: &mut Rng, (x, y, z): P, on: u16) {
        if w.get(x, y, z) != 0 || w.liquid_at(x, y, z).1 > 0 {
            return;
        }
        let small = rng.chance(0.5);
        let (b, beyond) = if w.get(x, y + 1, z) == on {
            (if small { self.small_stalactite } else { self.stalactite }, y - 1)
        } else if w.get(x, y - 1, z) == on {
            (if small { self.small_stalagmite } else { self.stalagmite }, y + 1)
        } else {
            return;
        };
        if b == 0 || (!small && w.get(x, beyond, z) != 0) {
            return;
        }
        let i = w.idx(x, y, z);
        w.blocks[i] = b;
    }
}

/// The blocks WorldGen.BiomeTileCheck turns a Marble or Granite cave away
/// from: granite, marble, snow, ice, glowing mushroom grass and the desert's
/// sandstone (Terraria's tiles 367, 368, 147, 161, 162, 70, 72, 396, 397).
pub fn biome_check_ids(w: &World) -> Vec<u16> {
    ["granite", "marble", "snow_block", "ice_block", "mushroom_grass", "glowing_mushroom", "sandstone", "hardened_sand"]
        .iter()
        .map(|n| w.id_of(n))
        .filter(|&b| b != 0)
        .collect()
}

/// WorldGen.BiomeTileCheck: any of `ids` within 50 tiles (here looked at
/// every other block).
pub fn biome_tile_check(w: &World, ids: &[u16], (x, y, z): P) -> bool {
    let r = (50.0 * TILE) as i32;
    for dy in (-r..=r).step_by(2) {
        for dz in (-r..=r).step_by(2) {
            for dx in (-r..=r).step_by(2) {
                let (px, py, pz) = (x + dx, y + dy, z + dz);
                if w.in_bounds(px, py, pz) && ids.contains(&w.get(px, py, pz)) {
                    return true;
                }
            }
        }
    }
    false
}

/// Where a pass spreads its caves (Terraria's one per slice of the world's
/// width): the `k`th of `n` cells of a grid over the map, keeping `margin`
/// from its edge; a spot in it, never in the middle tenth of the map either
/// way (spawn).
pub fn grid_spot(w: &World, rng: &mut Rng, k: usize, n: usize, margin: i32) -> (i32, i32) {
    let g = (n as f64).sqrt().ceil().max(1.0) as i32;
    let (cw, cd) = ((w.sx - 2 * margin) / g, (w.sz - 2 * margin) / g);
    let (gx, gz) = (k as i32 % g, (k as i32 / g) % g);
    loop {
        let x = margin + gx * cw + rng.range(0, cw.max(1));
        let z = margin + gz * cd + rng.range(0, cd.max(1));
        let mid = |v: i32, s: i32| v as f64 > s as f64 * 0.45 && (v as f64) < s as f64 * 0.55;
        if !(mid(x, w.sx) && mid(z, w.sz)) {
            return (x, z);
        }
    }
}

/// Terraria's tiles below its surface line -> this world's y (as the Dungeon's).
fn depth_y(l: &Layers, d: f64) -> i32 {
    crate::dungeon::depth_y(l, d)
}

pub struct Ids {
    pub marble: u16,
    pub check: Vec<u16>,
    /// Ores keep their place in the marble (TileID.Sets.Ore).
    pub ore: Vec<bool>,
    pub spel: Speleothems,
}

impl Ids {
    pub fn new(w: &World) -> Self {
        Ids {
            marble: w.id_of("marble"),
            check: biome_check_ids(w),
            ore: w.defs.iter().map(|d| d.name.ends_with("_ore")).collect(),
            spel: Speleothems::of(w, "marble"),
        }
    }
}

/// The world's Marble caves; returns their middles. `inland` keeps them from
/// under the sea.
pub fn marble_caves(w: &mut World, rng: &mut Rng, l: &Layers, inland: &dyn Fn(i32, i32) -> bool) -> Vec<P> {
    let ids = Ids::new(w);
    let mut placed = Vec::new();
    if ids.marble == 0 {
        return placed;
    }
    let per_world = rng.range(4, 9) as f64;
    let want = (per_world * w.sx as f64 * w.sz as f64 / (640.0 * 640.0)).round() as usize;
    // From 20 tiles under the cavern layer (Terraria's rockLayer is 130
    // under its surface line here) to 200 above the world's bottom.
    let (y_lo, y_hi) = (depth_y(l, 710.0), depth_y(l, 150.0));
    for k in 0..want {
        for _ in 0..200 {
            let (x, z) = grid_spot(w, rng, k, want, 60);
            let y = rng.range(y_lo, y_hi.max(y_lo + 1));
            if !inland(x, z) {
                continue;
            }
            if marble_cave(w, rng, &ids, (x, y, z), false) {
                placed.push((x, y, z));
                break;
            }
        }
    }
    placed
}

/// MarbleBiome.Place round `c`; `force` skips the check of what's near (the
/// test world's). False if it can't go there.
pub fn marble_cave(w: &mut World, rng: &mut Rng, ids: &Ids, c: P, force: bool) -> bool {
    if !force && biome_tile_check(w, &ids.check, c) {
        return false;
    }
    let nx = rng.range(80, 150) / 3;
    let nz = rng.range(80, 150) / 3;
    let ny = rng.range(40, 60) / 3;
    let n3 = (ny * 3 - rng.range(20, 30)) / 3;
    let (ox, oz) = (c.0 - nx * SLAB / 2, c.2 - nz * SLAB / 2);
    let top = c.1 + ny * SLAB / 2;
    // Room for its ragged edges and its floor's wandering.
    let reach = (nx.max(nz) as f64 * TILE) as i32 + 4;
    if ox < 3 || oz < 3 || ox + nx * SLAB + 3 >= w.sx || oz + nz * SLAB + 3 >= w.sz
        || top + reach >= w.sy || top - ny * SLAB - reach < 2 {
        return false;
    }
    // Slabs by (i, j, k), i and k across, j down from the top (Terraria's
    // y), each a ring of one round the cave.
    let (dx, dy, dz) = ((nx + 2) as usize, (ny + 2) as usize, (nz + 2) as usize);
    let at = |i: i32, j: i32, k: i32| ((i + 1) as usize * dy + (j + 1) as usize) * dz + (k + 1) as usize;
    let mut slabs = vec![EMPTY; dx * dy * dz];
    // A slab's lowest corner, in blocks.
    let corner = |i: i32, j: i32, k: i32| (ox + i * SLAB, top - (j + 1) * SLAB + 1, oz + k * SLAB);
    for i in -1..=nx {
        for k in -1..=nz {
            // How far out from the middle (Terraria's |x - 0.5| across).
            let (fx, fz) = ((i - nx / 2) as f64 / nx as f64, (k - nz / 2) as f64 / nz as f64);
            let out = (fx * fx + fz * fz).sqrt();
            let edge = ((0.5 - out) * 5.0) as i32 - 2;
            for j in -1..=ny {
                let group_solid = group_solid(w, corner(i, j, k));
                let band = (j - ny / 2).abs() - n3 / 4 + edge;
                let below_middle = j - ny / 2 > 0;
                let mut solid = if band > 3 {
                    group_solid
                } else if band > 0 {
                    below_middle || group_solid
                } else if band == 0 {
                    rng.chance(0.5) && (below_middle || group_solid)
                } else {
                    false
                };
                if out > 0.35 + rng.unit() * 0.1 && !group_solid {
                    solid = false;
                }
                slabs[at(i, j, k)] = if solid { SOLID } else { EMPTY };
            }
        }
    }
    // SmoothSlope, slab by slab in Terraria's order.
    for i in 0..nx {
        for j in 0..ny {
            for k in 0..nz {
                if slabs[at(i, j, k)] == EMPTY {
                    continue;
                }
                let s = |i: i32, j: i32, k: i32| slabs[at(i, j, k)] != EMPTY;
                let (up, down) = (s(i, j - 1, k), s(i, j + 1, k));
                // Open sides: +x, -x, +z, -z.
                let open = [!s(i + 1, j, k), !s(i - 1, j, k), !s(i, j, k + 1), !s(i, j, k - 1)];
                slabs[at(i, j, k)] = smooth(up, down, open);
            }
        }
    }
    // The floor's wander along x and along z (Terraria's num11), in tiles.
    let wander = |rng: &mut Rng, n: i32| -> Vec<f64> {
        let (a, b, c) = (rng.unit() * 2.0 - 1.0, rng.unit() * 2.0 - 1.0, rng.unit() * 2.0 - 1.0);
        let half = (n / 2).max(1) as f64;
        let mut acc = 0.0;
        (0..=n)
            .map(|m| {
                acc += if m >= n / 2 { b + (c - b) * (m as f64 / half - 1.0) } else { a + (b - a) * (m as f64 / half) };
                acc
            })
            .collect()
    };
    let (wx, wz) = (wander(rng, nx), wander(rng, nz));
    let (mx, my) = (nx / 2, ny / 2);
    let r2 = ((my + 1) * (my + 1)) as f64;
    for m in 0..=nx {
        for k in 0..=nz {
            // Terraria's ellipse, round in x and z (z scaled to x).
            let r = (((m - mx) as f64).powi(2) + ((k - nz / 2) as f64 * mx as f64 / (nz / 2).max(1) as f64).powi(2)).sqrt();
            let n12 = my as f64 / mx.max(1) as f64 * r;
            let n13 = (my as f64).min((r2 - n12 * n12).max(0.0).sqrt()) as i32;
            let lift = ((wx[m as usize] + wz[k as usize]) * 0.5 * TILE).round() as i32;
            for n in (my - n13)..=(my + n13) {
                let (x0, y0, z0) = corner(m, n, k);
                place_slab(w, rng, ids, slabs[at(m, n, k)], (x0, y0 + lift, z0));
            }
        }
    }
    // PlaceTight round the cave: a quarter of the open cells under its
    // ceilings and on its floors.
    let lo = (ox - 2, top - ny * SLAB - reach, oz - 2);
    let hi = (ox + nx * SLAB + 2, top + reach, oz + nz * SLAB + 2);
    decorate(w, rng, ids.marble, &ids.spel, lo, hi, 0.25);
    w.structures.push((lo, hi));
    true
}

/// IsGroupSolid: any solid cell in the slab (Terraria's scale / 4 * 3 is 0
/// for its 3, so one solid tile is enough).
fn group_solid(w: &World, (x0, y0, z0): P) -> bool {
    (0..SLAB).any(|lx| (0..SLAB).any(|ly| (0..SLAB).any(|lz| w.in_bounds(x0 + lx, y0 + ly, z0 + lz) && w.is_solid(x0 + lx, y0 + ly, z0 + lz))))
}

/// The cell bit in a slab (lx, ly, lz each 0 or 1; ly 0 at the bottom).
fn bit(lx: i32, ly: i32, lz: i32) -> u8 {
    1 << (lx + 2 * ly + 4 * lz)
}

/// MarbleBiome.SmoothSlope for one solid slab, by which of its neighbours
/// are solid (Terraria's four: above, below, left, right; here the four
/// across). Only its floor below: a half slab (HalfBrick). Floor below and
/// some sides open: its bottom half, and its top half away from the open
/// sides (Terraria's BottomLeft- and BottomRightFilled slopes). Ceiling
/// above and some sides open: the same upside down (TopLeft-, TopRightFilled).
/// Anything else stays solid.
fn smooth(up: bool, down: bool, open: [bool; 4]) -> u8 {
    let n_open = open.iter().filter(|&&o| o).count();
    if up == down || n_open == 0 {
        return SOLID;
    }
    if down && n_open == 4 {
        return layer(0);
    }
    if up && n_open == 4 {
        return SOLID;
    }
    // The half away from the open sides.
    let mut away = 0u8;
    for lx in 0..2 {
        for lz in 0..2 {
            let on_open = (open[0] && lx == 1) || (open[1] && lx == 0) || (open[2] && lz == 1) || (open[3] && lz == 0);
            if !on_open {
                away |= bit(lx, 0, lz);
            }
        }
    }
    if down { layer(0) | (away << 2) } else { layer(1) | away }
}

/// All four cells of a slab's layer (0 bottom, 1 top).
fn layer(ly: i32) -> u8 {
    bit(0, ly, 0) | bit(1, ly, 0) | bit(0, ly, 1) | bit(1, ly, 1)
}

/// MarbleBiome.PlaceSlab: the slab's cells, and a cell past its sides now
/// and then (each side column half the time, each column's rows a cell
/// further up or down half the time), marble where it's solid (ores kept)
/// and air where it isn't.
fn place_slab(w: &mut World, rng: &mut Rng, ids: &Ids, mask: u8, (x0, y0, z0): P) {
    for li in -1..=SLAB {
        for lk in -1..=SLAB {
            let side = li < 0 || li == SLAB || lk < 0 || lk == SLAB;
            if side && rng.chance(0.5) {
                continue;
            }
            let lo = if rng.chance(0.5) { -1 } else { 0 };
            let hi = if rng.chance(0.5) { SLAB + 1 } else { SLAB };
            for ly in lo..hi {
                let (x, y, z) = (x0 + li, y0 + ly, z0 + lk);
                if !w.in_bounds(x, y, z) || y < 2 {
                    continue;
                }
                let c = |v: i32| v.clamp(0, SLAB - 1);
                let solid = mask & bit(c(li), c(ly), c(lk)) != 0;
                let i = w.idx(x, y, z);
                let b = w.blocks[i];
                if solid {
                    if !ids.ore.get(b as usize).copied().unwrap_or(false) {
                        w.blocks[i] = ids.marble;
                    }
                    w.liquid[i] = 0;
                } else {
                    w.blocks[i] = 0;
                }
            }
        }
    }
}

/// PlaceTight through a box: `chance` of the open cells under a ceiling of
/// `on`, or on a floor of it, get one of its speleothems.
pub fn decorate(w: &mut World, rng: &mut Rng, on: u16, spel: &Speleothems, lo: P, hi: P, chance: f32) {
    for x in lo.0.max(1)..=hi.0.min(w.sx - 2) {
        for z in lo.2.max(1)..=hi.2.min(w.sz - 2) {
            for y in lo.1.max(2)..=hi.1.min(w.sy - 3) {
                if w.get(x, y, z) == 0 && (w.get(x, y + 1, z) == on || w.get(x, y - 1, z) == on) && rng.chance(chance) {
                    spel.place(w, rng, (x, y, z), on);
                }
            }
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE};

    /// The Marble and Granite caves' blocks, for a test world.
    pub fn add_cave_defs(w: &mut World) {
        for stone in ["granite", "marble"] {
            for name in [stone.to_string(), format!("smooth_{stone}")] {
                let id = w.defs.len() as u16;
                w.set_def(id, BlockDef { name, render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
            }
            for name in [format!("{stone}_stalactite"), format!("small_{stone}_stalactite"), format!("{stone}_stalagmite"), format!("small_{stone}_stalagmite")] {
                let id = w.defs.len() as u16;
                w.set_def(id, BlockDef { name, render: RENDER_CROSS, solid: false, opaque: false, variants: 1, ..Default::default() });
            }
        }
    }

    #[test]
    fn slabs_smooth_like_terrarias() {
        // Floor only: a half slab.
        assert_eq!(smooth(false, true, [true; 4]), layer(0));
        // Ceiling only, all sides open: solid (Terraria's case 8).
        assert_eq!(smooth(true, false, [true; 4]), SOLID);
        // On a floor, open to +x: a step, its top half on the -x side.
        let s = smooth(false, true, [true, false, false, false]);
        assert_eq!(s, layer(0) | bit(0, 1, 0) | bit(0, 1, 1));
        // Under a ceiling, open to -z: its bottom half on the +z side.
        let s = smooth(true, false, [false, false, false, true]);
        assert_eq!(s, layer(1) | bit(0, 0, 1) | bit(1, 0, 1));
        // Between floor and ceiling, or closed all round: solid.
        assert_eq!(smooth(true, true, [true; 4]), SOLID);
        assert_eq!(smooth(false, true, [false; 4]), SOLID);
    }

    /// A Marble cave dug into solid stone round a little cave: a hollow
    /// band of open space with marble floors and ceilings, stalactites and
    /// stalagmites, and nothing but marble (and ore) where it built.
    #[test]
    fn a_marble_cave_in_the_stone() {
        let mut w = World::new();
        w.set_def(1, BlockDef { name: "stone".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        w.set_def(2, BlockDef { name: "copper_ore".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        add_cave_defs(&mut w);
        w.resize(160, 120, 160);
        for b in w.blocks.iter_mut() {
            *b = 1;
        }
        // A pocket of air in the middle, as Terraria's caves leave.
        for x in 70..90 {
            for y in 55..65 {
                for z in 70..90 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 0;
                }
            }
        }
        let ids = Ids::new(&w);
        let mut rng = Rng::new(5);
        assert!(marble_cave(&mut w, &mut rng, &ids, (80, 60, 80), false));
        // Turned down near marble now.
        assert!(!marble_cave(&mut w, &mut rng, &ids, (80, 60, 80), false));
        let (marble, stone, spel) = (w.id_of("marble"), w.id_of("stone"), ids.spel);
        let (mut open, mut marbles, mut tites, mut mites) = (0, 0, 0, 0);
        for x in 0..160 {
            for z in 0..160 {
                for y in 0..120 {
                    let b = w.get(x, y, z);
                    if b == marble {
                        marbles += 1;
                    } else if b == spel.stalactite || b == spel.small_stalactite {
                        tites += 1;
                        assert_eq!(w.get(x, y + 1, z), marble, "a stalactite hangs from marble");
                    } else if b == spel.stalagmite || b == spel.small_stalagmite {
                        mites += 1;
                        assert_eq!(w.get(x, y - 1, z), marble, "a stalagmite stands on marble");
                    } else if b == 0 && (x - 80).abs() < 10 && (z - 80).abs() < 10 {
                        open += 1;
                    }
                }
            }
        }
        assert!(marbles > 20_000, "marble ({marbles})");
        assert!(open > 500, "open space in the middle ({open})");
        assert!(tites > 50 && mites > 50, "stalactites ({tites}) and stalagmites ({mites})");
        // Its middle column: marble floor under open space under a marble ceiling.
        let col: Vec<u16> = (0..120).map(|y| w.get(80, y, 80)).collect();
        let hollow = (1..119).any(|y| col[y] == 0 && col[..y].contains(&marble) && col[y..].contains(&marble));
        assert!(hollow, "open between a marble floor and ceiling: {col:?}");
        assert!(col.contains(&stone), "stone above and below it");
        assert!(!w.structures.is_empty(), "kept from the structures after it");
    }
}
