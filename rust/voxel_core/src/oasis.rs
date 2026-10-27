//! Terraria's oases (its Oasis pass: WorldGen.PlaceOasis; and the oasis
//! part of its planting pass: palm trees, sea oats and oasis plants round
//! them, PlantSeaOat, GrowSeaOat, PlaceOasisPlant), in 3D.
//!
//! - **How many:** maxTilesX / 2100 plus 0 or 1 (2-3 in a small world, 3-4
//!   medium, 4-5 large), each tried up to maxTilesX x 2 times at a spot on
//!   the surface inland of the beaches.
//! - **Where:** on sand, with nothing but sand round it (Terraria looks 50
//!   tiles past the pond each way, 20 up and 24 down; sandstone anywhere, or
//!   hardened sand near the middle, turns it down; here down to under its
//!   bed, a 3D desert's sand being shallower), no water there, and far
//!   enough from another oasis (Terraria's 350 tiles; a 3D world's desert
//!   is far narrower than its, so here just past where one's banks reach,
//!   and the box round it 6 past the pond). Clear of the Pyramids and the
//!   Jungle Temple.
//! - **The pond:** 45-60 tiles across the spot (here across both ways): an
//!   ellipse 0.7 across to 1.35 up (its radius 0.53-0.57 of half that), its
//!   top at the ground: sand out of it, water in it from the ground down
//!   (the top layer half full). Its banks above slope back (wider the higher
//!   up), and under it the sand is filled in round it, so it holds.
//! - **Round it** (1.5 of its width each way, 20 tiles up and down): palm
//!   trees on the sand, a palm closer than 8 tiles to another 13 in 100 of
//!   the time; sea oats on the sand by the water (each growing on once or
//!   twice, half the time each); and oasis plants (3 tiles wide) on sand by
//!   enough water, over the sea oats. Terraria tries every tile of that
//!   line, a palm wherever none is within 8 tiles (else 13 in 100); round a
//!   3D pond that would be a forest, so here palms 18 blocks apart (about as
//!   many as Terraria's), and sea oats and oasis plants (3 blocks apart)
//!   along its shore.
//!
//! Terraria's tiles are 2/3 of a block here.

use crate::world::{liq_pack, Decoration, World, LIQ_MAX, LIQ_WATER};
use crate::worldgen::{Coast, Rng};

type P = (i32, i32, i32);

/// A Terraria tile, in blocks.
const TILE: f64 = 2.0 / 3.0;
/// How far apart oases are (blocks): past where one's banks clear the sand
/// (three of its widths), so one never digs into another. Terraria's 350
/// tiles is more again; a 3D world's desert is narrower.
const APART: f64 = 125.0;
/// How far round the pond the ground must be all sand (blocks).
const SAND_ROUND: i32 = 6;
/// The sand rim round a pond up to its water (tiles), where the ground's lower.
const RIM: f64 = 3.0;
/// 20 tiles' worth of water, in cells (a tile is about 3.4 of them).
const WATER_NEAR: i32 = 68;
/// Round a pond: palms this far apart (blocks), closer this often a cell;
/// sea oats and oasis plants within SHORE blocks of its water, the plants
/// PLANTS_APART apart. Terraria plants along a line, every 8 tiles a palm,
/// every 3 an oasis plant; round a 3D pond that would be a forest, so here
/// about as many as Terraria's.
const PALMS_APART: f64 = 18.0;
const PALMS_CLOSER: f64 = 0.0;
const SHORE: f64 = 6.0;
const PLANTS_APART: f64 = 3.0;

pub struct Ids {
    sand: u16,
    hardened: u16,
    sandstone: u16,
    palm: u16,
    oats: [u16; 3],
    plant: u16,
}

impl Ids {
    pub fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        Ids {
            sand: id("sand"),
            hardened: id("hardened_sand"),
            sandstone: id("sandstone"),
            palm: id("palm_trunk"),
            oats: [id("sea_oats"), id("sea_oats_grown"), id("sea_oats_tall")],
            plant: id("oasis_plant"),
        }
    }
}

/// An oasis made: its middle (on the ground) and its width (tiles).
pub struct Oasis {
    pub x: i32,
    pub y: i32,
    pub z: i32,
    pub width: i32,
}

/// The world's oases; `clear(x, z, by)` is whether a spot keeps `by` blocks
/// clear of the structures before them (the Pyramids, the Jungle Temple).
pub fn oases(w: &mut World, rng: &mut Rng, coast: &Coast, clear: &dyn Fn(i32, i32, i32) -> bool) -> Vec<Oasis> {
    let ids = Ids::new(w);
    let mut made: Vec<Oasis> = Vec::new();
    if ids.sand == 0 {
        return made;
    }
    let size = w.sx.min(w.sz) as f64 / 768.0;
    let count = (2.0 * size).round() as i32 + rng.range(0, 2);
    let sea = coast.ocean;
    for _ in 0..count {
        for _ in 0..(4200.0 * size * 2.0) as i32 {
            let (x, z) = (rng.range(20, w.sx - 20), rng.range(20, w.sz - 20));
            // Inland of the beaches (Terraria's beachDistance + 300).
            if coast.inland(x, z) < sea.width + sea.beach + 30.0 {
                continue;
            }
            let width = rng.range(45, 61);
            let reach = pond_reach(width);
            if !clear(x, z, reach.0.ceil() as i32 + SAND_ROUND)
                || made.iter().any(|o| (((o.x - x).pow(2) + (o.z - z).pow(2)) as f64).sqrt() < APART)
            {
                continue;
            }
            let y = w.surface_y(x, z);
            if let Some(o) = place(w, rng, &ids, (x, y, z), width) {
                made.push(o);
                break;
            }
        }
    }
    made
}

/// The pond's reach across and down (blocks) for a width (tiles): its
/// ellipse 0.7 across to 1.35 up, radius 0.55 of half the width.
fn pond_reach(width: i32) -> (f64, f64) {
    let r = width as f64 / 2.0 * 0.55;
    (r / 0.7 * TILE, r / 1.35 * TILE)
}

/// PlaceOasis at the ground `g`, if it's sand with only sand round it.
fn place(w: &mut World, rng: &mut Rng, ids: &Ids, g: P, width: i32) -> Option<Oasis> {
    let (x0, y0, z0) = g;
    if w.get(x0, y0, z0) != ids.sand || w.liquid_at(x0, y0 + 1, z0).1 > 0 {
        return None;
    }
    let (rx, ry) = pond_reach(width);
    let box_r = rx.ceil() as i32 + SAND_ROUND;
    // Terraria looks 24 tiles down; a 3D world's desert has its sandstone
    // nearer the top, so here down to under the pond's bed.
    let (up, down) = ((20.0 * TILE) as i32, ry.ceil() as i32 + 3);
    let inner = ((width as f64 * TILE) as i32, (10.0 * TILE) as i32);
    for z in z0 - box_r..=z0 + box_r {
        for x in x0 - box_r..=x0 + box_r {
            for y in y0 - down..=y0 + up {
                if !w.in_bounds(x, y, z) {
                    return None;
                }
                let b = w.get(x, y, z);
                if w.liquid_at(x, y, z).1 > 0 && (x - x0).abs() < inner.0 && (z - z0).abs() < inner.0 && (y - y0).abs() < inner.1 {
                    return None;
                }
                if !w.is_solid(x, y, z) || b == ids.sand || w.def(b).name.starts_with("cactus") {
                    continue;
                }
                if b == ids.hardened && !((x - x0).abs() < inner.0 && (z - z0).abs() < inner.0 && (y - y0).abs() < inner.1) {
                    continue;
                }
                return None;
            }
        }
    }
    // Cacti on the ground it takes go first (they'd be left in the air).
    for z in z0 - box_r..=z0 + box_r {
        for x in x0 - box_r..=x0 + box_r {
            for y in y0 - down..=y0 + up {
                let b = w.get(x, y, z);
                if b != 0 && w.def(b).name.starts_with("cactus") {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 0;
                }
            }
        }
    }
    // The pond, its banks and its bed (Terraria's metric: across x 0.7, up
    // 1.35; its banks widen by (1 - across / 3 widths) x 2.3, to the 4th).
    let r = width as f64 / 2.0 * (0.53 + rng.unit() * 0.04);
    let span = 3.0 * width as f64;
    let (reach_x, reach_up, reach_down) = ((3 * width) as f64 * TILE, (4 * 20) as f64 * TILE, (3 * 20) as f64 * TILE);
    let (rxi, rui, rdi) = (reach_x.ceil() as i32, reach_up.ceil() as i32, reach_down.ceil() as i32);
    for z in z0 - rxi..=z0 + rxi {
        for x in x0 - rxi..=x0 + rxi {
            let across_tiles = (((x - x0).pow(2) + (z - z0).pow(2)) as f64).sqrt() / TILE;
            let ax = across_tiles * 0.7;
            let mut k = (1.0 - across_tiles / span) * 2.3;
            k = k * k;
            k = k * k;
            for y in y0 - rdi..=y0 + rui {
                if !w.in_bounds(x, y, z) {
                    continue;
                }
                let dy_tiles = (y - y0) as f64 / TILE;
                let ay = dy_tiles.abs() * 1.35;
                let i = w.idx(x, y, z);
                if (ax * ax + ay * ay).sqrt() < r {
                    // In the pond: open, water from the ground down.
                    w.blocks[i] = 0;
                    w.liquid[i] = match y.cmp(&y0) {
                        std::cmp::Ordering::Equal => liq_pack(LIQ_WATER, LIQ_MAX / 2),
                        std::cmp::Ordering::Less => liq_pack(LIQ_WATER, LIQ_MAX),
                        _ => 0,
                    };
                } else if y > y0 {
                    // Its banks: the sand over it sloping back.
                    if ax < r + dy_tiles.abs() * 3.0 * k && w.blocks[i] == ids.sand {
                        w.blocks[i] = 0;
                    }
                } else if ax < r + dy_tiles.abs() * k && !w.is_solid(x, y, z) {
                    // Its bed: sand filled in round it.
                    w.blocks[i] = ids.sand;
                    w.liquid[i] = 0;
                }
            }
        }
    }
    // A rim round it up to its water where the ground falls away (Terraria
    // picks ground solid on both sides; a 3D dune slopes): sand from its
    // water's level down to the ground, so none of it falls.
    for z in z0 - rxi..=z0 + rxi {
        for x in x0 - rxi..=x0 + rxi {
            let ax = (((x - x0).pow(2) + (z - z0).pow(2)) as f64).sqrt() / TILE * 0.7;
            if ax < r || ax >= r + RIM {
                continue;
            }
            let mut y = y0;
            while y > 0 && !w.is_solid(x, y, z) && y0 - y < 40 {
                let i = w.idx(x, y, z);
                w.blocks[i] = ids.sand;
                w.liquid[i] = 0;
                y -= 1;
            }
        }
    }
    w.decorations.push(Decoration { kind: "oasis".into(), pos: (x0, y0, z0), style: width });
    Some(Oasis { x: x0, y: y0, z: z0, width })
}

/// Round each oasis: palm trees on the sand, sea oats by the water (grown on
/// once or twice, half the time each) and oasis plants over them.
pub fn plant(w: &mut World, rng: &mut Rng, oases: &[Oasis]) {
    let ids = Ids::new(w);
    if ids.sand == 0 {
        return;
    }
    for o in oases {
        let (rx, _) = pond_reach(o.width);
        let reach = (o.width as f64 * 1.5 * TILE).ceil() as i32;
        let band = (20.0 * TILE) as i32;
        // The ring round it, in a random order (Terraria goes along its line).
        let mut cells: Vec<(i32, i32)> = Vec::new();
        for z in o.z - reach..=o.z + reach {
            for x in o.x - reach..=o.x + reach {
                let d = (((x - o.x).pow(2) + (z - o.z).pow(2)) as f64).sqrt();
                if d > rx - 1.0 && d <= reach as f64 && w.in_bounds(x, o.y, z) {
                    cells.push((x, z));
                }
            }
        }
        for i in (1..cells.len()).rev() {
            let j = rng.range(0, i as i32 + 1) as usize;
            cells.swap(i, j);
        }
        let mut palms: Vec<P> = Vec::new();
        let mut plants: Vec<P> = Vec::new();
        for (x, z) in cells {
            let d = (((x - o.x).pow(2) + (z - o.z).pow(2)) as f64).sqrt();
            // The ground there: sand under open air, within 20 tiles of the pond's.
            let Some(y) = ground(w, ids.sand, x, z, o.y - band, o.y + band) else { continue };
            let at = (x, y + 1, z);
            if w.get(at.0, at.1, at.2) != 0 || w.liquid_at(at.0, at.1, at.2).1 > 0 {
                continue;
            }
            let near = |list: &[P], within: f64| list.iter().any(|p| (((p.0 - x).pow(2) + (p.2 - z).pow(2)) as f64).sqrt() < within);
            let palm_close = near(&palms, PALMS_APART);
            if ids.palm != 0 && (!palm_close || rng.unit() < PALMS_CLOSER) && crate::worldgen::grow_palm(w, rng, (x, y, z), ids.palm) {
                palms.push(at);
                continue;
            }
            if d > rx + SHORE || !near_water(w, at) {
                continue;
            }
            // An oasis plant (3 tiles wide: 2 blocks apart), else sea oats.
            if ids.plant != 0 && !near(&plants, PLANTS_APART) {
                let i = w.idx(at.0, at.1, at.2);
                w.blocks[i] = ids.plant;
                plants.push(at);
                continue;
            }
            if ids.oats[0] != 0 {
                let mut stage = 0;
                for _ in 0..2 {
                    if rng.range(0, 2) == 0 {
                        stage += 1;
                    }
                }
                let i = w.idx(at.0, at.1, at.2);
                w.blocks[i] = ids.oats[stage];
            }
        }
    }
}

/// The highest sand under open air in column (x, z) between `lo` and `hi`.
fn ground(w: &World, sand: u16, x: i32, z: i32, lo: i32, hi: i32) -> Option<i32> {
    (lo..=hi).rev().find(|&y| w.get(x, y, z) == sand && w.get(x, y + 1, z) == 0)
}

/// OasisPlantWaterCheck / SeaOatWaterCheck: 20 tiles' worth of water within
/// 45 across and 20 up or down (every other cell looked at).
fn near_water(w: &World, at: P) -> bool {
    let (across, updown) = ((45.0 * TILE) as i32, (20.0 * TILE) as i32);
    let mut water = 0;
    for dz in (-across..=across).step_by(2) {
        for dx in (-across..=across).step_by(2) {
            for dy in (-updown..=updown).step_by(2) {
                let (t, a) = w.liquid_at(at.0 + dx, at.1 + dy, at.2 + dz);
                if t == LIQ_WATER && a > 0 {
                    water += 8;
                    if water >= WATER_NEAR {
                        return true;
                    }
                }
            }
        }
    }
    false
}
