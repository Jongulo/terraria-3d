//! Terraria-inspired world generation, adapted to 3D.
//!
//! Passes: terrain columns (surface/underground/cavern/underworld layers,
//! caves, ores) -> grass & plants -> trees -> the world evil (Corruption or
//! Crimson patches) -> floating islands -> pots, life crystals, chests, altars
//! -> liquids -> waterfalls.

use crate::world::{Decoration, LIQ_LAVA, LIQ_MAX, LIQ_WATER, RENDER_CUBE, SHAPE_CEILING, SHAPE_HALF, World};
use fastnoise_lite::{FastNoiseLite, FractalType, NoiseType};
use rayon::prelude::*;
use std::sync::atomic::{AtomicU32, Ordering};

#[derive(Clone, Copy)]
pub struct Layers {
    pub underworld_top: i32,
    pub cavern_top: i32,
    pub surface_base: i32,
    /// Where Terraria's Space layer (the floating islands, harpies) begins:
    /// above the highest mountain (surface_base + HILLS + MOUNTAINS = +35), so
    /// standing on a peak is never "in Space".
    pub space_top: i32,
}

/// Terrain height above surface_base: rolling hills (+-HILLS) and mountain
/// chains (up to +MOUNTAINS).
const HILLS: f32 = 9.0;
const MOUNTAINS: f32 = 26.0;
pub const SPACE_ABOVE_SURFACE: i32 = 42;

pub fn layers(sy: i32) -> Layers {
    Layers {
        // About the bottom eighth, like Terraria's (30 in a 256 tall world).
        underworld_top: (sy as f32 * 0.118) as i32,
        cavern_top: (sy as f32 * 0.42) as i32,
        surface_base: (sy as f32 * 0.68) as i32,
        space_top: (sy as f32 * 0.68) as i32 + SPACE_ABOVE_SURFACE,
    }
}

/// Terraria's oceans, here on every side so the world is an island: past a
/// sand beach the ground drops under the sea and keeps deepening to the
/// world's edge. Sizes follow the world's width (Terraria's oceans are a
/// similar share of theirs).
#[derive(Clone, Copy)]
pub struct Ocean {
    /// From the edge to the shoreline, in blocks.
    pub width: f32,
    /// The beach inland of the shoreline (sand, sloping up to the land).
    pub beach: f32,
    /// The sea's surface: the top water cells.
    pub sea_level: i32,
    /// How far the sea floor drops below the sea at the world's edge.
    pub depth: f32,
}

pub fn ocean(sx: i32, sy: i32, sz: i32) -> Ocean {
    let width = sx.min(sz) as f32 * 0.075;
    Ocean { width, beach: width * 0.4, sea_level: layers(sy).surface_base - 6, depth: width * 0.45 }
}

/// Where the coast lies: the distance from the world's edge (corners rounded
/// off) plus a noisy coastline. Below `ocean.width` is sea.
pub struct Coast {
    pub ocean: Ocean,
    sx: i32,
    sz: i32,
    n: FastNoiseLite,
}

impl Coast {
    pub fn new(seed: i32, sx: i32, sy: i32, sz: i32) -> Coast {
        Coast { ocean: ocean(sx, sy, sz), sx, sz, n: noise(seed + 22, 0.008, 2) }
    }

    /// Distance inland from the world's edge (blocks, coastline noise included).
    pub fn inland(&self, x: i32, z: i32) -> f32 {
        let round = self.ocean.width * 2.0;
        let ix = x.min(self.sx - 1 - x) as f32;
        let iz = z.min(self.sz - 1 - z) as f32;
        let d = if ix < round && iz < round {
            round - ((round - ix).powi(2) + (round - iz).powi(2)).sqrt()
        } else {
            ix.min(iz)
        };
        d + self.n.get_noise_2d(x as f32, z as f32) * self.ocean.width * 0.3
    }
}

pub fn noise(seed: i32, freq: f32, octaves: i32) -> FastNoiseLite {
    let mut n = FastNoiseLite::with_seed(seed);
    n.set_noise_type(Some(NoiseType::OpenSimplex2));
    n.set_frequency(Some(freq));
    if octaves > 1 {
        n.set_fractal_type(Some(FractalType::FBm));
        n.set_fractal_octaves(Some(octaves));
    }
    n
}

/// Small deterministic RNG (splitmix64).
pub struct Rng(u64);
impl Rng {
    pub fn new(seed: u64) -> Self {
        Self(seed ^ 0x9e3779b97f4a7c15)
    }
    pub fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }
    pub fn range(&mut self, lo: i32, hi: i32) -> i32 {
        lo + (self.next() % (hi - lo).max(1) as u64) as i32
    }
    /// Uniform in [0, 1).
    pub fn unit(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1u64 << 53) as f64
    }
    pub fn chance(&mut self, p: f32) -> bool {
        (self.next() % 1_000_000) as f32 / 1_000_000.0 < p
    }
}

/// The world's tree tops, like Terraria's (TreeTopsInfo / WorldGen.RandomizeTreeStyle):
/// the forest is split into zones across the world's width (2 in a small world,
/// 3 in a medium, 4 in a large; the borders wander a little here), each with its
/// own leaf style, all different; the snow and the jungle get one style each.
/// A canopy decoration's style is sheet * 10 + frame (0-2), sheet indexing the
/// game's CanopyArt.SHEETS:
///   0 Tree_Tops_0 (forest)   1 Tree_Tops_1 (Corruption)   2 Tree_Tops_5 (Crimson)
///   3 Tree_Tops_17 (snowy pine)   4 Tree_Tops_2 (jungle)
///   5-9 Tree_Tops_6-10 (forest)   10 Tree_Tops_12, 11 Tree_Tops_16, 12 Tree_Tops_18,
///   13 Tree_Tops_4 (snow)   14 Tree_Tops_11 (jungle)
pub struct TreeTops {
    /// Where each forest zone after the first starts (x), and each zone's style (0-5).
    borders: Vec<i32>,
    forest: Vec<i32>,
    snow: i32,
    jungle: i32,
    sx: i32,
    seed: i32,
}

/// The forest sheets for Terraria's tree styles 0-5 (Tree_Tops_0, 6, 7, 8, 9, 10).
pub const FOREST_SHEETS: [i32; 6] = [0, 5, 6, 7, 8, 9];
/// Terraria's snow background (and tree) styles, which the snow's tree tops follow.
const SNOW_STYLES: [i32; 14] = [0, 1, 2, 21, 22, 3, 31, 32, 4, 41, 42, 5, 6, 7];

impl TreeTops {
    pub fn new(seed: i32, sx: i32) -> Self {
        // Its own RNG, so the rest of worldgen is unchanged.
        let mut rng = Rng::new(seed as u64 ^ 0x7ee7_0b5e);
        let zones = if sx < 1000 { 2 } else if sx < 1400 { 3 } else { 4 };
        let w = sx as f32;
        let at = |rng: &mut Rng, mid: f32, spread: f32| rng.range((w * (mid - spread)) as i32, (w * (mid + spread)) as i32);
        let borders: Vec<i32> = match zones {
            2 => vec![at(&mut rng, 0.5, 0.25)],
            3 => vec![at(&mut rng, 0.334, 0.2), at(&mut rng, 0.667, 0.2)],
            _ => vec![at(&mut rng, 0.25, 0.15), at(&mut rng, 0.5, 0.15), at(&mut rng, 0.75, 0.15)],
        };
        // Every zone's style differs from the ones before it; a plain one (0)
        // mostly turns into style 4, like Terraria's.
        let mut forest: Vec<i32> = Vec::new();
        for _ in 0..zones {
            let mut st = rng.range(0, 6);
            while forest.contains(&st) {
                st = rng.range(0, 6);
            }
            forest.push(st);
        }
        for st in forest.iter_mut() {
            if *st == 0 && rng.range(0, 3) != 0 {
                *st = 4;
            }
        }
        let snow = SNOW_STYLES[rng.range(0, SNOW_STYLES.len() as i32) as usize];
        let jungle = rng.range(0, 6);
        Self { borders, forest, snow, jungle, sx, seed }
    }

    pub fn of(w: &World) -> Self {
        Self::new(w.seed, w.sx)
    }

    /// The forest zone at (x, z) (0 = the first).
    pub fn zone(&self, x: i32, z: i32) -> usize {
        // The borders wander up to ~24 blocks as you go along z.
        let k = self.seed as f32 * 0.37;
        let wobble = ((z as f32 * 0.011 + k).sin() * 16.0 + (z as f32 * 0.029 + k * 1.7).sin() * 8.0) as i32;
        self.borders.iter().filter(|&&b| x + wobble >= b).count()
    }

    pub fn forest_style(&self, x: i32, z: i32) -> i32 {
        self.forest[self.zone(x, z)]
    }

    /// A forest canopy at (x, z) with `frame` (0-2).
    pub fn forest(&self, x: i32, z: i32, frame: i32) -> i32 {
        FOREST_SHEETS[self.forest_style(x, z) as usize] * 10 + frame
    }

    /// A snow canopy, as Terraria picks it (GetCommonTreeFoliageData): style 0
    /// round snowy trees (every tenth column snowier), most others pines, snowy
    /// on one side of the world, green on the other; the rest bare branches.
    pub fn snow(&self, x: i32, frame: i32) -> i32 {
        let st = self.snow;
        let sheet = if st == 0 {
            if x % 10 == 0 { 12 } else { 10 }
        } else if [2, 3, 32, 4, 42, 5, 7].contains(&st) {
            let west = x < self.sx / 2;
            let green = if st % 2 == 0 { west } else { x > self.sx / 2 };
            if green { 11 } else { 3 }
        } else {
            13
        };
        sheet * 10 + frame
    }

    /// A jungle canopy: one world in six has the other leaves (Tree_Tops_11).
    pub fn jungle(&self, frame: i32) -> i32 {
        (if self.jungle == 1 { 14 } else { 4 }) * 10 + frame
    }
}

/// The canopy sheet of palm trees (Tree_Tops_15, CanopyArt.SHEETS 15).
pub const PALM_CANOPY: i32 = 15;

/// Palm trees on the beach, like Terraria's (WorldGen.GrowPalmTree): on sand
/// above the sea with room overhead, 10-20 cells of "palm_trunk" under a palm
/// canopy (the game draws the trunk's curve, PalmArt). Returns how many grew.
pub fn palms(w: &mut World, seed: i32, coast: &Coast, sand: u16) -> usize {
    let palm = w.id_of("palm_trunk");
    if palm == 0 || sand == 0 {
        return 0;
    }
    // Its own RNG, so the rest of the world is unchanged.
    let mut rng = Rng::new(seed as u64 ^ 0xbeac_4a1d);
    let sea = coast.ocean;
    let cell = 7;
    let mut n = 0;
    for gz in 0..w.sz / cell {
        for gx in 0..w.sx / cell {
            if !rng.chance(0.22) {
                continue;
            }
            let (x, z) = (gx * cell + rng.range(0, cell), gz * cell + rng.range(0, cell));
            let inland = coast.inland(x, z);
            if inland < sea.width + 2.0 || inland > sea.width + sea.beach {
                continue;
            }
            let y = w.surface_y(x, z);
            if y <= sea.sea_level || w.get(x, y, z) != sand || w.liquid_at(x, y + 1, z).1 > 0 {
                continue;
            }
            let height = rng.range(10, 21);
            if y + height + 6 >= w.sy || (1..=height + 2).any(|k| w.get(x, y + k, z) != 0) {
                continue;
            }
            for k in 1..=height {
                let i = w.idx(x, y + k, z);
                w.blocks[i] = palm;
            }
            w.decorations.push(Decoration { kind: "tree_top".into(), pos: (x, y + height + 1, z), style: PALM_CANOPY * 10 + rng.range(0, 3) });
            n += 1;
        }
    }
    n
}

/// Gem trees' canopy sheets: CanopyArt.SHEETS 16-22 (Tree_Tops_22-28), in
/// Terraria's order (tiles 583-589).
pub const GEM_CANOPY: i32 = 16;
/// Clear cells a gem tree needs above its trunk, for its top.
const GEM_TOP_ROOM: i32 = 7;
pub const GEMS: [&str; 7] = ["topaz", "amethyst", "sapphire", "emerald", "ruby", "diamond", "amber"];

/// Gem trees in the caves, like Terraria's ("Speleothems and Gem Trees"): every
/// floor of stone (or ebonstone, crimstone) below the surface layer gets a 1 in
/// 5 try, if no water lies on it, at one of the seven gem trees at random;
/// one grows (TryGrowingTreeByType, the GemTree profiles) 7-12 cells tall
/// where that is clear above, and room for its top (Terraria asks for 4 cells;
/// the 96 px top is 6, which in 3D would sink into the cave's roof), the trunk not hard against a
/// wall, no other tree right beside it and no waterfall pouring within 3 cells
/// (its stream would run through the tree). Floors are visited down sample
/// columns (one in each 2 x 2 cells; Terraria's 2D visits every column).
/// "<gem>_tree_trunk" cells under a canopy of the gem's sheet. Returns how many.
pub fn gem_trees(w: &mut World, seed: i32, l: &Layers) -> usize {
    let trunks: Vec<u16> = GEMS.iter().map(|g| w.id_of(&format!("{}_tree_trunk", g))).collect();
    if trunks.iter().any(|&t| t == 0) {
        return 0;
    }
    let grounds: Vec<u16> = ["stone", "ebonstone", "crimstone"].iter().map(|n| w.id_of(n)).filter(|&i| i != 0).collect();
    // Its own RNG, so the rest of the world is unchanged.
    let mut rng = Rng::new(seed as u64 ^ 0x6e37_7ee5);
    // Waterfalls' streams: (x, z, mouth height).
    let falls: Vec<(i32, i32, i32)> = w.decorations.iter().filter(|d| d.kind == "waterfall").map(|d| (d.pos.0, d.pos.2, d.pos.1)).collect();
    let near_fall = |x: i32, y: i32, z: i32| falls.iter().any(|&(fx, fz, fy)| fy > y && (fx - x).abs() <= 3 && (fz - z).abs() <= 3);
    let cell = 2;
    let mut n = 0;
    for gz in 0..w.sz / cell {
        for gx in 0..w.sx / cell {
            let (x, z) = (gx * cell + rng.range(0, cell), gz * cell + rng.range(0, cell));
            if x < 3 || z < 3 || x >= w.sx - 3 || z >= w.sz - 3 {
                continue;
            }
            let mut y = l.surface_base - 8;
            while y > l.underworld_top + 2 {
                if grounds.contains(&w.get(x, y, z)) && w.get(x, y + 1, z) == 0 && rng.range(0, 5) == 0 && w.liquid_at(x, y + 1, z).1 == 0 {
                    let gem = rng.range(0, 7) as usize;
                    let h = rng.range(7, 13);
                    let clear_above = (1..=h + GEM_TOP_ROOM).all(|k| w.get(x, y + k, z) == 0 && w.liquid_at(x, y + k, z).1 == 0);
                    let room_round = (1..=3).all(|k| [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().all(|&(dx, dz)| w.get(x + dx, y + k, z + dz) == 0));
                    let alone = (-2..=2).all(|dx: i32| (-2..=2).all(|dz: i32| !trunks.contains(&w.get(x + dx, y + 1, z + dz))));
                    if clear_above && room_round && alone && !near_fall(x, y, z) {
                        for k in 1..=h {
                            let i = w.idx(x, y + k, z);
                            w.blocks[i] = trunks[gem];
                        }
                        w.decorations.push(Decoration { kind: "tree_top".into(), pos: (x, y + h + 1, z), style: (GEM_CANOPY + gem as i32) * 10 + rng.range(0, 3) });
                        n += 1;
                        y -= 1;
                        continue;
                    }
                }
                y -= 1;
            }
        }
    }
    n
}

/// Vanity trees' canopy sheets (CanopyArt.SHEETS 23 Sakura, 24 Yellow Willow:
/// Tree_Tops_29-30) and the ash trees' (25: Tree_Tops_31).
pub const SAKURA_CANOPY: i32 = 23;
pub const WILLOW_CANOPY: i32 = 24;
pub const ASH_CANOPY: i32 = 25;

/// Vanity trees in the forest, like Terraria's (WorldGen.AddTrees): of the
/// trees on grass, 1 in 20 grows as a vanity tree instead, a Yellow Willow or
/// a Sakura (half each), 7-12 cells tall (the VanityTree profiles). Run once
/// the biomes are down: a forest tree still standing on grass is regrown as
/// one ("sakura_trunk" / "willow_trunk" under its canopy). Returns how many.
pub fn vanity_trees(w: &mut World, seed: i32, grass: u16) -> usize {
    let (trunk, sakura, willow) = (w.id_of("tree_trunk"), w.id_of("sakura_trunk"), w.id_of("willow_trunk"));
    if trunk == 0 || sakura == 0 || willow == 0 || grass == 0 {
        return 0;
    }
    let mut rng = Rng::new(seed as u64 ^ 0x5a4b_0a11);
    let mut n = 0;
    for i in 0..w.decorations.len() {
        let d = &w.decorations[i];
        if d.kind != "tree_top" || !is_forest_canopy(d.style) || w.get(d.pos.0, d.pos.1 - 1, d.pos.2) != trunk {
            continue;
        }
        let (x, top, z) = d.pos;
        let mut g = top - 1;
        while w.get(x, g, z) == trunk {
            g -= 1;
        }
        if w.get(x, g, z) != grass || rng.range(0, 20) != 0 {
            continue;
        }
        let willow_tree = rng.range(0, 2) == 0;
        let h = rng.range(7, 13);
        // Room for the new trunk and its top (the old tree's cells are cleared first).
        if (top..=g + h + GEM_TOP_ROOM).any(|y| w.get(x, y, z) != 0) || !w.in_bounds(x, g + h + GEM_TOP_ROOM, z) {
            continue;
        }
        for y in g + 1..top {
            let j = w.idx(x, y, z);
            w.blocks[j] = 0;
        }
        for k in 1..=h {
            let j = w.idx(x, g + k, z);
            w.blocks[j] = if willow_tree { willow } else { sakura };
        }
        let frame = w.decorations[i].style % 10;
        w.decorations[i].pos = (x, g + h + 1, z);
        w.decorations[i].style = (if willow_tree { WILLOW_CANOPY } else { SAKURA_CANOPY }) * 10 + frame;
        n += 1;
    }
    n
}

/// Whether (x, z) is in the Underworld's ash forests: Terraria keeps them to
/// the outer 17% of the world at each end; here, the outer ring.
pub fn in_ash_ring(w: &World, x: i32, z: i32) -> bool {
    let (cx, cz) = (w.sx / 2, w.sz / 2);
    (x - cx).abs().max((z - cz).abs()) as f32 > w.sx.min(w.sz) as f32 * 0.33
}

/// The Underworld's ash forests, like Terraria's (the Underworld pass): in the
/// outer ring, ash open to the air above turns to ash grass, and ash trees
/// grow on it ("ash_trunk", 7-12 cells, the Tree_Ash profile): Terraria tries
/// every ash grass tile with air above 1 in 3; here one spot in each 5 x 5
/// cells (a 3D floor is a whole area, not a line), with room for the top, no
/// lava on it, nor another tree beside it. Returns how many trees.
pub fn ash_forest(w: &mut World, seed: i32, l: &Layers) -> usize {
    let (ash, ash_grass, ash_trunk) = (w.id_of("ash"), w.id_of("ash_grass"), w.id_of("ash_trunk"));
    if ash == 0 || ash_grass == 0 {
        return 0;
    }
    for z in 0..w.sz {
        for x in 0..w.sx {
            if !in_ash_ring(w, x, z) {
                continue;
            }
            for y in 1..l.underworld_top {
                if w.get(x, y, z) == ash && w.get(x, y + 1, z) == 0 && w.liquid_at(x, y + 1, z).1 == 0 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = ash_grass;
                }
            }
        }
    }
    if ash_trunk == 0 {
        return 0;
    }
    let mut rng = Rng::new(seed as u64 ^ 0xa54f_0e57);
    let cell = 5;
    let mut n = 0;
    for gz in 0..w.sz / cell {
        for gx in 0..w.sx / cell {
            let (x, z) = (gx * cell + rng.range(0, cell), gz * cell + rng.range(0, cell));
            if x < 3 || z < 3 || x >= w.sx - 3 || z >= w.sz - 3 || !in_ash_ring(w, x, z) {
                continue;
            }
            for y in 1..l.underworld_top {
                if w.get(x, y, z) != ash_grass || w.get(x, y + 1, z) != 0 || rng.range(0, 3) != 0 {
                    continue;
                }
                let h = rng.range(7, 13);
                let clear_above = (1..=h + GEM_TOP_ROOM).all(|k| w.get(x, y + k, z) == 0 && w.liquid_at(x, y + k, z).1 == 0);
                let room_round = (1..=3).all(|k| [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().all(|&(dx, dz)| w.get(x + dx, y + k, z + dz) == 0));
                let alone = (-2..=2).all(|dx: i32| (-2..=2).all(|dz: i32| w.get(x + dx, y + 1, z + dz) != ash_trunk));
                if clear_above && room_round && alone {
                    for k in 1..=h {
                        let i = w.idx(x, y + k, z);
                        w.blocks[i] = ash_trunk;
                    }
                    w.decorations.push(Decoration { kind: "tree_top".into(), pos: (x, y + h + 1, z), style: ASH_CANOPY * 10 + rng.range(0, 3) });
                    n += 1;
                    break;
                }
            }
        }
    }
    n
}

/// Living Mahogany trees, Terraria's MahoganyTreeBiome (placed by the "Micro
/// Biomes" pass, LivingTreeCount 6-11 per Small world, scaling with its
/// width): at random points in the underground jungle (where mud and jungle
/// grass outweigh everything else round about), in a cave 30-65 tall. Ours
/// are seldom that tall, so where there's no such cave one is hollowed out
/// (a jungle cavern: jungle grass floor, mud round it). Returns how many.
pub fn mahogany_trees(w: &mut World, seed: i32, l: &Layers, chest: u16) -> usize {
    let (wood, leaves) = (w.id_of("living_mahogany"), w.id_of("mahogany_leaves"));
    let (mud, jgrass) = (w.id_of("mud"), w.id_of("jungle_grass"));
    if wood == 0 || leaves == 0 || mud == 0 || jgrass == 0 {
        return 0;
    }
    let Some(&(_, jx, jz, jr)) = biome_regions(w.sx, w.sz, seed).iter().find(|r| r.0 == BIOME_JUNGLE) else { return 0 };
    let mut rng = Rng::new(seed as u64 ^ 0x3a40_4a0e);
    let scale = w.sx as f32 / 768.0;
    let target = ((rng.range(6, 12) as f32) * scale).round() as i32;
    let mut sites: Vec<(i32, i32, i32)> = Vec::new();
    let mut n = 0;
    for _ in 0..4000 {
        if n >= target {
            break;
        }
        let a = rng.range(0, 628) as f32 / 100.0;
        let d = (rng.range(0, 1000) as f32 / 1000.0).sqrt() * jr as f32 * 0.85;
        let (x, z) = (jx + (a.cos() * d) as i32, jz + (a.sin() * d) as i32);
        let y = rng.range(l.underworld_top + 20, l.surface_base - 50);
        if x < 25 || z < 25 || x >= w.sx - 25 || z >= w.sz - 25 || y < 10 {
            continue;
        }
        if sites.iter().any(|&(sx, sy, sz)| (sx - x).pow(2) + (sz - z).pow(2) < 40 * 40 && (sy - y).abs() < 70) {
            continue;
        }
        // Mostly jungle round about (Terraria's 50 x 50 scan).
        let (mut jungle, mut other) = (0, 0);
        for dz in (-24..=24).step_by(4) {
            for dx in (-24..=24).step_by(4) {
                for dy in (-24..=24).step_by(4) {
                    match w.get(x + dx, y + dy, z + dz) {
                        0 => {}
                        b if b == mud || b == jgrass => jungle += 1,
                        _ => other += 1,
                    }
                }
            }
        }
        if jungle < 50 || jungle <= other {
            continue;
        }
        let (floor, height) = match mahogany_cave(w, x, y, z) {
            Some(c) => c,
            None => {
                let h = rng.range(32, 50);
                if y + h + 6 >= l.surface_base - 6 {
                    continue;
                }
                hollow_jungle_cavern(w, &mut rng, (x, y, z), h, mud, jgrass);
                (y, h)
            }
        };
        grow_mahogany_tree(w, &mut rng, (x, floor, z), height, wood, leaves, chest);
        sites.push((x, floor, z));
        n += 1;
    }
    n as usize
}

/// A cave 30-65 tall over (x, y, z) as Terraria wants one: (floor, height).
fn mahogany_cave(w: &World, x: i32, y: i32, z: i32) -> Option<(i32, i32)> {
    if w.is_solid(x, y, z) {
        return None;
    }
    let mut floor = y;
    while floor > 2 && !w.is_solid(x, floor, z) {
        floor -= 1;
    }
    let mut top = floor + 1;
    while top < w.sy - 1 && !w.is_solid(x, top, z) {
        top += 1;
    }
    let h = top - floor - 1;
    (30..=65).contains(&h).then_some((floor, h))
}

/// Hollows a tall jungle cavern standing on (x, y, z), `h` tall: a lumpy
/// upright egg, its floor jungle grass on mud, mud all round it.
fn hollow_jungle_cavern(w: &mut World, rng: &mut Rng, base: (i32, i32, i32), h: i32, mud: u16, jgrass: u16) {
    let (bx, by, bz) = base;
    let rh = rng.range(13, 18) as f32;
    let rv = h as f32 * 0.5;
    let cy = by as f32 + rv;
    let n = noise(rng.range(0, 1 << 20), 0.08, 2);
    let reach = rh as i32 + 3;
    for dy in -1..=h + 3 {
        for dz in -reach..=reach {
            for dx in -reach..=reach {
                let (x, y, z) = (bx + dx, by + dy, bz + dz);
                if !w.in_bounds(x, y, z) || y < 3 {
                    continue;
                }
                let (fx, fy, fz) = (dx as f32, y as f32 + 0.5 - cy, dz as f32);
                // Wider low down, like Terraria's caverns.
                let width = rh * (1.0 - (fy / rv).max(0.0) * 0.35);
                let e = (fx * fx + fz * fz) / (width * width) + fy * fy / (rv * rv);
                let lump = n.get_noise_3d(x as f32, y as f32, z as f32) * 0.25;
                let i = w.idx(x, y, z);
                if e < 1.0 + lump && dy >= 1 {
                    w.blocks[i] = 0;
                    w.liquid[i] = 0;
                } else if e < 1.35 + lump && w.blocks[i] != 0 {
                    w.blocks[i] = mud;
                }
            }
        }
    }
    // The floor: jungle grass where it's open above.
    for dz in -reach..=reach {
        for dx in -reach..=reach {
            let (x, z) = (bx + dx, bz + dz);
            for y in by - 1..by + h {
                if w.in_bounds(x, y + 1, z) && w.is_solid(x, y, z) && w.get(x, y + 1, z) == 0 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = jgrass;
                    break;
                }
            }
        }
    }
}

/// One Living Mahogany tree, Terraria's MahoganyTreeBiome.Place in 3D, on the
/// cave floor at (x, floor, z) under a cave `height` tall:
///   trunk   (height - 9) / 5 segments of 5: each a round of living mahogany
///           6 across and 7 tall, swaying from the last along a sine
///           (Terraria's sin((i + 1) / 12 x f x pi) x a, f 1-2, a 2-3 blocks),
///           hollow inside (2 across), an Ivy Chest at its foot.
///   branches every other segment, from alternate sides, a branch 12-15 long
///           angled up about 45 degrees; at the top two more, 16-21 long, up
///           and out either way (Terraria's -0.69 and -2.46 radians); each
///           ends in a blotchy ball of mahogany leaves, radius 4.
///   roots   four from the foot, out and down (33-71 degrees below level, a
///           way each), 40-59 long, 4 thick thinning to 1.
pub fn grow_mahogany_tree(w: &mut World, rng: &mut Rng, base: (i32, i32, i32), height: i32, wood: u16, leaves: u16, chest: u16) {
    let (bx, floor, bz) = base;
    let segs = ((height - 9) / 5).max(3);
    let freq = 1.0 + rng.range(0, 1000) as f32 / 1000.0;
    let amp = (2.0 + rng.range(0, 1000) as f32 / 1000.0) * if rng.range(0, 2) == 0 { -1.0 } else { 1.0 };
    let yaw = rng.range(0, 628) as f32 / 100.0;
    let (sx, sz) = (yaw.cos(), yaw.sin());
    let round = |w: &mut World, cx: f32, cz: f32, y0: i32, rows: i32, r: f32, b: u16| {
        let reach = r.ceil() as i32 + 1;
        for y in y0..y0 + rows {
            for dz in -reach..=reach {
                for dx in -reach..=reach {
                    let (x, z) = (cx.floor() as i32 + dx, cz.floor() as i32 + dz);
                    let (ox, oz) = (x as f32 + 0.5 - cx, z as f32 + 0.5 - cz);
                    if ox * ox + oz * oz <= r * r && w.in_bounds(x, y, z) && y > 2 {
                        let i = w.idx(x, y, z);
                        w.blocks[i] = b;
                        if b != 0 {
                            w.liquid[i] = 0;
                        }
                    }
                }
            }
        }
    };
    let centre = |i: i32| -> (f32, f32) {
        let off = ((i + 1) as f32 / 12.0 * freq * std::f32::consts::PI).sin() * amp;
        (bx as f32 + 0.5 + sx * off, bz as f32 + 0.5 + sz * off)
    };
    // The trunk, then its hollow.
    for i in 0..segs {
        let (cx, cz) = centre(i);
        let (px, pz) = if i > 0 { centre(i - 1) } else { (cx, cz) };
        for t in 0..=2 {
            let f = t as f32 / 2.0;
            round(w, px + (cx - px) * f, pz + (cz - pz) * f, floor + 1 + i * 5, 7, 3.0, wood);
        }
    }
    for i in 0..segs {
        let (cx, cz) = centre(i);
        let (px, pz) = if i > 0 { centre(i - 1) } else { (cx, cz) };
        for t in 0..=2 {
            let f = t as f32 / 2.0;
            round(w, px + (cx - px) * f, pz + (cz - pz) * f, floor + 2 + i * 5, 5, 1.0, 0);
        }
    }
    let top = floor + 1 + segs * 5;
    // Branches: (start, direction, length).
    let mut ends: Vec<(f32, f32, f32)> = Vec::new();
    let branch = |w: &mut World, rng: &mut Rng, from: (f32, f32, f32), dir: (f32, f32, f32), len: i32, ends: &mut Vec<(f32, f32, f32)>| {
        let mut p = from;
        let mut d = dir;
        for k in 0..len {
            p = (p.0 + d.0, p.1 + d.1, p.2 + d.2);
            let r = if k < len / 3 { 1.0 } else { 0.6 };
            round(w, p.0, p.2, p.1 as i32, 1, r, wood);
            // A fork now and then (Terraria's ShapeBranch puts out a few ends).
            if k > len / 2 && k < len - 2 && rng.range(0, 6) == 0 {
                let side = rng.range(-60, 61) as f32 / 100.0;
                let fd = (d.0 * side.cos() - d.2 * side.sin(), d.1 + 0.2, d.0 * side.sin() + d.2 * side.cos());
                let mut q = p;
                for _ in 0..rng.range(3, 6) {
                    q = (q.0 + fd.0, q.1 + fd.1, q.2 + fd.2);
                    round(w, q.0, q.2, q.1 as i32, 1, 0.6, wood);
                }
                ends.push(q);
            }
            let wobble = rng.range(-10, 11) as f32 / 100.0;
            d = (d.0 * wobble.cos() - d.2 * wobble.sin(), d.1, d.0 * wobble.sin() + d.2 * wobble.cos());
        }
        ends.push(p);
    };
    let mut side = rng.range(0, 2);
    for i in 1..segs {
        if i % 2 != 0 {
            continue;
        }
        let (cx, cz) = centre(i);
        let a = yaw + if side == 0 { 0.0 } else { std::f32::consts::PI } + rng.range(-50, 51) as f32 / 100.0;
        let up = (std::f32::consts::FRAC_PI_4 + rng.range(-20, 21) as f32 / 100.0).sin();
        let flat = up.asin().cos();
        let dir = (a.cos() * flat, up, a.sin() * flat);
        let from = (cx + a.cos() * 3.0, (floor + 1 + i * 5 + 3) as f32, cz + a.sin() * 3.0);
        let len = rng.range(12, 16);
        branch(w, rng, from, dir, len, &mut ends);
        side ^= 1;
    }
    let (tx, tz) = centre(segs - 1);
    for (k, angle) in [0.6854f32, std::f32::consts::PI - 0.6854].iter().enumerate() {
        let a = yaw + if k == 0 { 0.0 } else { std::f32::consts::PI } + rng.range(-30, 31) as f32 / 100.0;
        let up = (std::f32::consts::PI - angle).min(*angle).sin();
        let flat = up.asin().cos();
        let dir = (a.cos() * flat, up, a.sin() * flat);
        let len = rng.range(16, 22);
        branch(w, rng, (tx, (top - 2) as f32, tz), dir, len, &mut ends);
    }
    // Leaves: a blotchy ball, radius 4, at each branch end (into the open only).
    for &(px, py, pz) in &ends {
        let blot = rng.next();
        for dy in -6..=6 {
            for dz in -6..=6 {
                for dx in -6..=6 {
                    let d2 = (dx * dx + dy * dy + dz * dz) as f32;
                    let h = blot ^ ((dx as u64 & 0xff) << 16 | (dy as u64 & 0xff) << 8 | (dz as u64 & 0xff));
                    let j = (Rng::new(h).next() % 1000) as f32 / 1000.0;
                    if d2 > (4.0 + (j - 0.5) * 2.4).powi(2) {
                        continue;
                    }
                    let (x, y, z) = (px.floor() as i32 + dx, py as i32 + dy, pz.floor() as i32 + dz);
                    if w.in_bounds(x, y, z) && w.get(x, y, z) == 0 && w.liquid_at(x, y, z).1 == 0 {
                        let i = w.idx(x, y, z);
                        w.blocks[i] = leaves;
                    }
                }
            }
        }
    }
    // Roots: four out and down from the foot, thinning as they go.
    for k in 0..4 {
        let a = yaw + std::f32::consts::FRAC_PI_4 + k as f32 * std::f32::consts::FRAC_PI_2;
        let down = (if k % 2 == 0 { 0.57f32 } else { 1.24f32 }).sin();
        let flat = down.asin().cos();
        let len = rng.range(40, 60);
        let mut p = (bx as f32 + 0.5, floor as f32, bz as f32 + 0.5);
        for s in 0..len {
            p = (p.0 + a.cos() * flat, p.1 - down, p.2 + a.sin() * flat);
            let r = 2.0 - 1.5 * s as f32 / len as f32;
            round(w, p.0, p.2, p.1 as i32, 1, r, wood);
            if p.1 < 4.0 {
                break;
            }
        }
    }
    // The Ivy Chest at the trunk's foot, in the hollow (style 2: jungle loot).
    let ivy = w.id_of("ivy_chest");
    let chest = if ivy != 0 { ivy } else { chest };
    if chest != 0 {
        let (cx, cz) = centre(0);
        let (x, y, z) = (cx.floor() as i32, floor + 2, cz.floor() as i32);
        if w.in_bounds(x, y, z) {
            let below = w.idx(x, y - 1, z);
            w.blocks[below] = wood;
            let i = w.idx(x, y, z);
            w.blocks[i] = chest;
            w.decorations.push(Decoration { kind: "chest".into(), pos: (x, y, z), style: if ivy != 0 { 2 } else { 0 } });
        }
    }
}

/// The underground jungle's mahogany trees' canopy sheet (CanopyArt.SHEETS 26:
/// Tree_Tops_13, with its vines).
pub const JUNGLE_CAVE_CANOPY: i32 = 26;

/// Mahogany trees in the underground jungle, like Terraria's (the "Jungle
/// Trees" pass, GrowUndergroundTree): every jungle grass floor below the
/// surface layer gets a 1 in 10 try; a tree grows 5-15 cells tall where that
/// and 7 more are clear above it, the trunk isn't hard against a wall (its
/// bottom 3 cells clear round it: our caves are lower than Terraria's, whose
/// EmptyTileCheck wants a tile clear either side all the way up), and no
/// other tree is right beside it. Terraria draws them with the underground
/// jungle's own trunk (Tiles_5_5), top (Tree_Tops_13) and branches. Floors are
/// visited down sample columns (one in each 2 x 2 cells; Terraria's 2D visits
/// every column). Returns how many grew.
pub fn jungle_cave_trees(w: &mut World, seed: i32, l: &Layers) -> usize {
    let (jgrass, trunk) = (w.id_of("jungle_grass"), w.id_of("jungle_cave_trunk"));
    if jgrass == 0 || trunk == 0 {
        return 0;
    }
    let mut rng = Rng::new(seed as u64 ^ 0x3a40_9a11);
    let cell = 2;
    let mut n = 0;
    for gz in 0..w.sz / cell {
        for gx in 0..w.sx / cell {
            let (x, z) = (gx * cell + rng.range(0, cell), gz * cell + rng.range(0, cell));
            if x < 3 || z < 3 || x >= w.sx - 3 || z >= w.sz - 3 {
                continue;
            }
            let mut y = l.surface_base - 8;
            while y > l.underworld_top + 4 {
                // Open: air or the jungle's plants and vines (not solid, no water).
                let open = |w: &World, x: i32, y: i32, z: i32| !w.is_solid(x, y, z) && w.liquid_at(x, y, z).1 == 0;
                if w.get(x, y, z) == jgrass && open(w, x, y + 1, z) && rng.range(0, 10) == 0 {
                    let h = rng.range(5, 15);
                    let clear_above = (1..=h + 7).all(|k| open(w, x, y + k, z));
                    let room_round = (1..=3).all(|k| [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().all(|&(dx, dz)| open(w, x + dx, y + k, z + dz)));
                    let alone = (-2..=2).all(|dx: i32| (-2..=2).all(|dz: i32| w.get(x + dx, y + 1, z + dz) != trunk));
                    if clear_above && room_round && alone {
                        for k in 1..=h {
                            let i = w.idx(x, y + k, z);
                            w.blocks[i] = trunk;
                        }
                        w.decorations.push(Decoration { kind: "tree_top".into(), pos: (x, y + h + 1, z), style: JUNGLE_CAVE_CANOPY * 10 + rng.range(0, 3) });
                        n += 1;
                    }
                }
                y -= 1;
            }
        }
    }
    n
}

/// Terraria's giant living trees (the "Living Trees" pass and GrowLivingTree),
/// in groves on the forest's grass: 0-2 groves on a Small world (Terraria:
/// Next(0, 2 x size + 1), a 0 made 1 half the time), between 15% and 85% of
/// the way across, under open sky and well apart; each a first tree with a
/// passage down to a root room, and 1-3 more trees 13-30 blocks on from the
/// one before. Ordinary trees under them are cleared first. Returns how many
/// trees grew.
pub fn living_trees(w: &mut World, seed: i32, grass: u16, chest: u16) -> usize {
    let (wood, leaves) = (w.id_of("living_wood"), w.id_of("leaf_block"));
    if wood == 0 || leaves == 0 || grass == 0 {
        return 0;
    }
    let mut rng = Rng::new(seed as u64 ^ 0x11f1_7ee5);
    let scale = w.sx as f32 / 768.0;
    let mut groves = rng.range(0, (2.0 * scale) as i32 + 1);
    if groves == 0 && rng.chance(0.5) {
        groves = 1;
    }
    let (cx, cz) = (w.sx / 2, w.sz / 2);
    let mut sites: Vec<(i32, i32)> = Vec::new();
    let mut n = 0;
    for _ in 0..groves {
        for _attempt in 0..300 {
            let x = rng.range((w.sx as f32 * 0.15) as i32, (w.sx as f32 * 0.85) as i32);
            let z = rng.range((w.sz as f32 * 0.15) as i32, (w.sz as f32 * 0.85) as i32);
            // Off the spawn, away from other groves, under open sky.
            if (x - cx).pow(2) + (z - cz).pow(2) < 45 * 45 || sites.iter().any(|&(sx, sz)| (x - sx).pow(2) + (z - sz).pow(2) < 120 * 120) {
                continue;
            }
            if !living_tree_site(w, x, z, grass) {
                continue;
            }
            sites.push((x, z));
            let mut at = (x, z);
            let extra = rng.range(1, 4);
            for k in 0..=extra {
                if k > 0 {
                    let a = rng.range(0, 628) as f32 / 100.0;
                    let d = rng.range(13, 31) as f32;
                    let next = (at.0 + (a.cos() * d) as i32, at.1 + (a.sin() * d) as i32);
                    if !living_tree_site(w, next.0, next.1, grass) {
                        continue;
                    }
                    at = next;
                }
                let g = w.surface_y(at.0, at.1);
                clear_trees_near(w, at.0, at.1, 22);
                grow_living_tree(w, &mut rng, (at.0, g, at.1), wood, leaves);
                if k == 0 {
                    living_tree_passage(w, &mut rng, (at.0, g, at.1), wood, chest);
                }
                n += 1;
            }
            break;
        }
    }
    n
}

/// Whether a living tree can stand at (x, z): grass, room round it and open
/// sky above (Terraria's checks the sky over +-50 tiles is empty).
fn living_tree_site(w: &World, x: i32, z: i32, grass: u16) -> bool {
    if x < 30 || z < 30 || x >= w.sx - 30 || z >= w.sz - 30 {
        return false;
    }
    let g = w.surface_y(x, z);
    if g < 0 || w.get(x, g, z) != grass || g + 95 >= w.sy {
        return false;
    }
    for dz in (-20..=20).step_by(4) {
        for dx in (-20..=20).step_by(4) {
            let h = w.surface_y(x + dx, z + dz);
            if h > g + 10 || h < g - 12 {
                return false;
            }
        }
    }
    true
}

/// Removes the ordinary trees (trunk cells and canopies) within `r` of (x, z).
fn clear_trees_near(w: &mut World, x: i32, z: i32, r: i32) {
    let trunks: Vec<u16> = ["tree_trunk", "sakura_trunk", "willow_trunk"].iter().map(|n| w.id_of(n)).filter(|&i| i != 0).collect();
    let mut gone: Vec<(i32, i32, i32)> = Vec::new();
    for d in w.decorations.iter() {
        if d.kind == "tree_top" && (d.pos.0 - x).pow(2) + (d.pos.2 - z).pow(2) <= r * r {
            gone.push(d.pos);
        }
    }
    for &(tx, ty, tz) in &gone {
        let mut y = ty - 1;
        while y > 0 && trunks.contains(&w.get(tx, y, tz)) {
            let i = w.idx(tx, y, tz);
            w.blocks[i] = 0;
            y -= 1;
        }
    }
    w.decorations.retain(|d| !(d.kind == "tree_top" && gone.contains(&d.pos)));
}

/// How lumpy living trees' leaf clusters are: smooth noise moves their edge
/// in and out by this much of their radius, at this frequency (per block);
/// and a finer per-block jitter of this much rags it.
const LEAF_LUMPS: f32 = 0.45;
const LEAF_LUMP_FREQ: f32 = 0.2;
const LEAF_JITTER: f32 = 0.12;

/// One living tree, Terraria's GrowLivingTree in 3D, standing on (x, g, z):
///   trunk   4 wide (1 in 5: 5), round; going up, every 5-15 rows a branch
///           starts (the first after 13-23), on alternate sides (1 in 5
///           the same side again); Terraria's left and right are two
///           opposite ways round the tree. Half the time a branch takes a
///           row off the trunk on its side; once the branches from both
///           sides meet across the trunk it stops.
///   branch  from the trunk's edge, a little below where it started, out
///           3-3.9 trunk widths: now and then a row up or down, thickened
///           above or below every few blocks, a leaf point there and at its
///           end.
///   crown   above the trunk, a spire 3-5 base widths tall, putting out
///           branches as it goes that end in big leaf balls.
///   leaves  at each point a cluster of leaf blocks into the open: on the
///           branches radius 5-8 (wider trunks a bit more) and twice as wide
///           as tall (Terraria's leaf diamonds, round in 3D); on the crown
///           balls of radius 6-12 plus the trunk width.
///   roots   under the trunk it carries on 1-5 blocks into the ground; from
///           there 2 to width + 1 roots per trunk row, 3.5-6 widths long,
///           out and down, straight down where there's nothing under them.
pub fn grow_living_tree(w: &mut World, rng: &mut Rng, base: (i32, i32, i32), wood: u16, leaves: u16) {
    let (bx, g, bz) = base;
    let set = |w: &mut World, x: i32, y: i32, z: i32, b: u16| {
        if w.in_bounds(x, y, z) {
            let i = w.idx(x, y, z);
            w.blocks[i] = b;
        }
    };
    let w0: i32 = if rng.range(0, 5) == 0 { 5 } else { 4 };
    let mut width = w0;
    let (mut cx, mut cz) = (bx as f32 + 0.5, bz as f32 + 0.5);
    let yaw = rng.range(0, 628) as f32 / 100.0;
    let mut side = rng.range(0, 2);
    let mut counter = rng.range(-8, -4);
    let mut threshold = rng.range(5, 15);
    let (mut left, mut right) = (0, w0);
    let mut branches: Vec<(i32, f32, i32, f32, f32)> = Vec::new(); // y, angle, width, centre
    let disc = |w: &mut World, cx: f32, cz: f32, y: i32, width: i32| {
        let r = width.max(1) as f32 * 0.5;
        let reach = r.ceil() as i32 + 1;
        for dz in -reach..=reach {
            for dx in -reach..=reach {
                let (x, z) = (cx.floor() as i32 + dx, cz.floor() as i32 + dz);
                let (ox, oz) = (x as f32 + 0.5 - cx, z as f32 + 0.5 - cz);
                if ox * ox + oz * oz <= r * r + 0.3 && w.in_bounds(x, y, z) {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = wood;
                }
            }
        }
    };
    let mut y = g;
    loop {
        counter += 1;
        if counter > threshold {
            threshold = rng.range(5, 15);
            counter = 0;
            let yb = y - rng.range(0, 5);
            if rng.range(0, 5) == 0 {
                side ^= 1;
            }
            let angle = yaw + if side == 0 { std::f32::consts::PI } else { 0.0 } + (rng.range(-60, 61) as f32 / 100.0);
            branches.push((yb, angle, width, cx, cz));
            if rng.range(0, 2) == 0 && width > 1 {
                // A row off the trunk on that side: narrower, its middle moving over.
                width -= 1;
                cx -= angle.cos() * 0.5;
                cz -= angle.sin() * 0.5;
            }
            if side == 0 {
                left += 1;
                side = 1;
            } else {
                right -= 1;
                side = 0;
            }
            if left >= right {
                break;
            }
        }
        disc(w, cx, cz, y, width);
        y += 1;
        if y >= w.sy - 40 {
            break;
        }
    }
    let top = y;
    // Leaf points: (x, y, z, big).
    let mut points: Vec<(f32, f32, f32, bool)> = Vec::new();
    for &(yb, angle, bw, ccx, ccz) in &branches {
        let (dx, dz) = (angle.cos(), angle.sin());
        let len = (bw as f32 * (1.0 + rng.range(20, 30) as f32 * 0.1)) as i32;
        let mut p = (ccx + dx * (bw as f32 * 0.5), yb, ccz + dz * (bw as f32 * 0.5));
        let mut thick = rng.range(3, 5);
        for k in (1..=len).rev() {
            if rng.range(0, 10) == 0 {
                p.1 += if rng.range(0, 2) == 0 { -1 } else { 1 };
            } else {
                p.0 += dx;
                p.2 += dz;
            }
            let (x, z) = (p.0.floor() as i32, p.2.floor() as i32);
            set(w, x, p.1, z, wood);
            if thick > 0 {
                thick -= 1;
            } else if rng.range(0, 2) == 0 {
                thick = rng.range(2, 5);
                let up = if rng.range(0, 2) == 0 { 1 } else { -1 };
                set(w, x, p.1 + up, z, wood);
                points.push((p.0, p.1 as f32, p.2, false));
            }
            if k == 1 {
                points.push((p.0, p.1 as f32, p.2, false));
            }
        }
    }
    // The crown: a spire from the trunk's top, with branches up and out to big leaf balls.
    let crown = rng.range(w0 * 3, w0 * 5);
    let (sx, sz) = (cx, cz);
    let mut cool = [0i32; 2];
    for k in 0..crown {
        let yy = top + k;
        if yy >= w.sy - 20 {
            break;
        }
        set(w, sx.floor() as i32, yy, sz.floor() as i32, wood);
        for c in cool.iter_mut() {
            if *c > 0 {
                *c -= 1;
            }
        }
        for s in 0..2 {
            if cool[s] == 0 && rng.range(0, 2) == 0 {
                cool[s] = rng.range(3, 5);
                let a = yaw + if s == 0 { std::f32::consts::PI } else { 0.0 } + (rng.range(-90, 91) as f32 / 100.0);
                let blen = rng.range(w0, w0 * 3);
                let mut p = (sx, yy, sz);
                for _ in 0..blen {
                    p.0 += a.cos();
                    p.2 += a.sin();
                    if rng.range(0, 2) == 0 {
                        p.1 += 1;
                    }
                    set(w, p.0.floor() as i32, p.1, p.2.floor() as i32, wood);
                }
                points.push((p.0, p.1 as f32, p.2, true));
            }
        }
        if k == crown - 1 {
            points.push((sx, yy as f32, sz, true));
        }
    }
    let mut placed: Vec<usize> = Vec::new();
    // Leaves into the open (air or plants), never over the wood. Terraria's
    // branch clusters are diamonds twice as wide as tall, its crown's round:
    // here flattened balls and balls, their edge lumpy like Terraria's tiles.
    for &(px, py, pz, big) in &points {
        let r = if big { (rng.range(6, 12) + w0) as f32 } else { rng.range(5, 8) as f32 * (1.0 + w0 as f32 * 0.05) };
        let k = 2.0 - rng.range(0, 5) as f32 * 0.1;
        let (rh, rv) = if big { (r * 0.9, r * 0.9) } else { (r, r / k * 1.3) };
        // Lumpy: smooth noise bulges and dents the cluster by up to LEAF_LUMPS of
        // its radius (lumps a few blocks across), finer jitter rags its edge.
        let lumps = noise(rng.range(0, 1 << 20), LEAF_LUMP_FREQ, 2);
        let jitter = rng.next();
        let reach = (rh.max(rv) * (1.0 + LEAF_LUMPS)).ceil() as i32 + 1;
        for dy in -reach..=reach {
            for dz in -reach..=reach {
                for dx in -reach..=reach {
                    let (fx, fy, fz) = (dx as f32, dy as f32, dz as f32);
                    let d = ((fx * fx + fz * fz) / (rh * rh) + fy * fy / (rv * rv)).sqrt();
                    if d > 1.0 + LEAF_LUMPS + LEAF_JITTER {
                        continue;
                    }
                    let (ax, ay, az) = (px + fx, py + fy, pz + fz);
                    let n = lumps.get_noise_3d(ax, ay * 1.3, az);
                    let h = jitter ^ ((dx as u64 & 0xff) << 16 | (dy as u64 & 0xff) << 8 | (dz as u64 & 0xff));
                    let j = (Rng::new(h).next() % 1000) as f32 / 1000.0 - 0.5;
                    if d > 1.0 + n * LEAF_LUMPS + j * 2.0 * LEAF_JITTER {
                        continue;
                    }
                    let (x, yy, z) = (px.floor() as i32 + dx, py as i32 + dy, pz.floor() as i32 + dz);
                    if w.in_bounds(x, yy, z) && !w.is_solid(x, yy, z) && w.liquid_at(x, yy, z).1 == 0 {
                        let i = w.idx(x, yy, z);
                        w.blocks[i] = leaves;
                        placed.push(i);
                    }
                }
            }
        }
    }
    prune_leaves(w, &placed, wood, leaves);
    // Roots: the trunk carries on into the ground, then roots spread out and down.
    let r0 = w0 as f32 * 0.5;
    let mut deepest = g;
    for dz in -(w0 / 2 + 1)..=(w0 / 2 + 1) {
        for dx in -(w0 / 2 + 1)..=(w0 / 2 + 1) {
            let (ox, oz) = (dx as f32, dz as f32);
            if ox * ox + oz * oz > r0 * r0 + 0.3 {
                continue;
            }
            let (x, z) = (bx + dx, bz + dz);
            let mut solid = rng.range(1, 6);
            let mut yy = g - 1;
            while solid > 0 && yy > 2 {
                if w.is_solid(x, yy, z) {
                    solid -= 1;
                }
                set(w, x, yy, z, wood);
                yy -= 1;
            }
            deepest = deepest.min(yy);
        }
    }
    let roots: i32 = (0..w0).map(|_| rng.range(2, w0 + 1)).sum();
    for i in 0..roots {
        let a = rng.range(0, 628) as f32 / 100.0;
        let mut dir = if i % w0 == w0 / 2 { (0.0, 0.0) } else { (a.cos(), a.sin()) };
        let out = dir;
        let mut p = (bx as f32 + 0.5 + a.cos() * r0, deepest, bz as f32 + 0.5 + a.sin() * r0);
        let mut down = 1;
        let len = rng.range((w0 as f32 * 3.5) as i32, w0 * 6);
        for _ in 0..len {
            p.0 += dir.0;
            p.2 += dir.1;
            let (x, z) = (p.0.floor() as i32, p.2.floor() as i32);
            if p.1 < 3 {
                break;
            }
            set(w, x, p.1, z, wood);
            p.1 -= down;
            set(w, x, p.1, z, wood);
            if !w.is_solid(x, p.1 - 1, z) {
                dir = (0.0, 0.0);
                down = 1;
            }
            if rng.range(0, 3) == 0 {
                dir = if dir == (0.0, 0.0) { out } else { (0.0, 0.0) };
            }
            if rng.range(0, 3) == 0 {
                down = 1 - down;
            }
        }
    }
}

/// Tidies a living tree's leaves (cell indices `placed`): none left floating
/// (only leaves joined face to face, through other leaves, to the tree's wood
/// stay), and none hanging on by a single face (twice over, so a stalk of
/// two goes too).
fn prune_leaves(w: &mut World, placed: &[usize], wood: u16, leaves: u16) {
    let (sx, sy) = (w.sx as usize, w.sy as usize);
    let coords = |i: usize| ((i / sy % sx) as i32, (i % sy) as i32, (i / sy / sx) as i32);
    let faces = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)];
    let mut kept: std::collections::HashSet<usize> = std::collections::HashSet::new();
    let mut queue: std::collections::VecDeque<usize> = std::collections::VecDeque::new();
    for &i in placed {
        let (x, y, z) = coords(i);
        if w.blocks[i] == leaves && faces.iter().any(|&(dx, dy, dz)| w.get(x + dx, y + dy, z + dz) == wood) && kept.insert(i) {
            queue.push_back(i);
        }
    }
    while let Some(i) = queue.pop_front() {
        let (x, y, z) = coords(i);
        for &(dx, dy, dz) in &faces {
            let (nx, ny, nz) = (x + dx, y + dy, z + dz);
            if w.in_bounds(nx, ny, nz) {
                let j = w.idx(nx, ny, nz);
                if w.blocks[j] == leaves && kept.insert(j) {
                    queue.push_back(j);
                }
            }
        }
    }
    for &i in placed {
        if w.blocks[i] == leaves && !kept.contains(&i) {
            w.blocks[i] = 0;
        }
    }
    for _ in 0..2 {
        let mut thin = Vec::new();
        for &i in placed {
            if w.blocks[i] != leaves {
                continue;
            }
            let (x, y, z) = coords(i);
            let held = faces.iter().filter(|&&(dx, dy, dz)| {
                let b = w.get(x + dx, y + dy, z + dz);
                b == leaves || b == wood
            }).count();
            if held <= 1 {
                thin.push(i);
            }
        }
        for i in thin {
            w.blocks[i] = 0;
        }
    }
}

/// A living tree's passage, like Terraria's (GrowLivingTree_MakePassage): a
/// doorway into the trunk at the ground, a winding stair (one down per block
/// along, so you can walk it both ways) through the roots, and a room under
/// them lined with living wood, a chest in it.
pub fn living_tree_passage(w: &mut World, rng: &mut Rng, base: (i32, i32, i32), wood: u16, chest: u16) {
    let (bx, g, bz) = base;
    let carve = |w: &mut World, x: i32, y: i32, z: i32| {
        if w.in_bounds(x, y, z) && y > 2 {
            let i = w.idx(x, y, z);
            w.blocks[i] = 0;
            w.liquid[i] = 0;
        }
    };
    let dirs = [(1, 0), (0, 1), (-1, 0), (0, -1)];
    let mut d = rng.range(0, 4) as usize;
    // The doorway: 2 wide, 3 tall, from outside into the middle.
    let (fx, fz) = dirs[d];
    let (px, pz) = (-fz, fx);
    for k in -4..=0 {
        for side in 0..2 {
            for h in 1..=3 {
                carve(w, bx + fx * k + px * side, g + h, bz + fz * k + pz * side);
            }
        }
    }
    // The stair: on from the middle away from the door, turning now and then.
    d = (d + 2) % 4;
    let (mut x, mut y, mut z) = (bx, g, bz);
    let depth = rng.range(18, 28);
    let mut since_turn = 0;
    while y > g - depth && y > 8 {
        let (dx, dz) = dirs[d];
        let (sx, sz) = (-dz, dx);
        x += dx;
        z += dz;
        y -= 1;
        for side in 0..2 {
            for h in 1..=3 {
                carve(w, x + sx * side, y + h, z + sz * side);
            }
            // A floor under each step.
            let (fx2, fz2) = (x + sx * side, z + sz * side);
            if w.in_bounds(fx2, y, fz2) && !w.is_solid(fx2, y, fz2) {
                let i = w.idx(fx2, y, fz2);
                w.blocks[i] = wood;
            }
        }
        since_turn += 1;
        if since_turn > 4 && rng.range(0, 4) == 0 {
            d = (d + if rng.range(0, 2) == 0 { 1 } else { 3 }) % 4;
            since_turn = 0;
        }
    }
    // The room: 9 x 5 x 9 inside, its shell living wood, the chest on its floor.
    let (rx, ry, rz) = (x, y, z);
    for dz in -5..=5 {
        for dx in -5..=5 {
            for dy in 0..=6 {
                let (xx, yy, zz) = (rx + dx, ry + dy, rz + dz);
                if !w.in_bounds(xx, yy, zz) || yy < 3 {
                    continue;
                }
                let edge = dx.abs() == 5 || dz.abs() == 5 || dy == 0 || dy == 6;
                let i = w.idx(xx, yy, zz);
                if edge {
                    // The floor always; walls and roof where there was ground.
                    if dy == 0 || w.blocks[i] != 0 {
                        w.blocks[i] = wood;
                        w.liquid[i] = 0;
                    }
                } else {
                    w.blocks[i] = 0;
                    w.liquid[i] = 0;
                }
            }
        }
    }
    // The stair's last step opens into the room.
    for h in 1..=3 {
        carve(w, x, y + h, z);
    }
    if chest != 0 && w.in_bounds(rx + 2, ry + 1, rz) {
        let i = w.idx(rx + 2, ry + 1, rz);
        w.blocks[i] = chest;
        w.decorations.push(Decoration { kind: "chest".into(), pos: (rx + 2, ry + 1, rz), style: 0 });
    }
}

/// Whether a canopy style is a forest one (biomes repaint those).
pub fn is_forest_canopy(style: i32) -> bool {
    FOREST_SHEETS.contains(&(style / 10))
}

/// Terraria's forest flora and debris (block ids; 0 where a block isn't defined).
pub struct Flora {
    pub tall_grass: u16,
    taller_grass: u16,
    flowers: u16,
    tall_flowers: u16,
    mushroom: u16,
    daybloom: u16,
    pub sunflower: u16,
    small_rocks: u16,
    twigs: u16,
    large_rocks: u16,
    fallen_log: u16,
    vines: u16,
    vine_flowers: u16,
    lily_pad: u16,
    cattail: u16,
    cattail_stem: u16,
    cattail_top: u16,
}

impl Flora {
    pub fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        Self {
            tall_grass: id("tall_grass"),
            taller_grass: id("taller_grass"),
            flowers: id("flowers"),
            tall_flowers: id("tall_flowers"),
            mushroom: id("mushroom"),
            daybloom: id("daybloom"),
            sunflower: id("sunflower"),
            small_rocks: id("small_rocks"),
            twigs: id("twigs"),
            large_rocks: id("large_rocks"),
            fallen_log: id("fallen_log"),
            vines: id("vines"),
            vine_flowers: id("vine_flowers"),
            lily_pad: id("lily_pad"),
            cattail: id("cattail"),
            cattail_stem: id("cattail_stem"),
            cattail_top: id("cattail_top"),
        }
    }

    /// What grows on a grass block in the forest (0: bare grass): mostly short
    /// and tall grass and flowers, now and then a mushroom, a Daybloom, stones,
    /// twigs, a rock pile or a fallen log. A missing block falls back to tall grass.
    pub fn ground(&self, rng: &mut Rng) -> u16 {
        let table = [
            (self.tall_grass, 1700),
            (self.taller_grass, 700),
            (self.flowers, 500),
            (self.tall_flowers, 250),
            (self.mushroom, 40),
            (self.daybloom, 30),
            (self.small_rocks, 80),
            (self.twigs, 50),
            (self.large_rocks, 15),
            (self.fallen_log, 10),
        ];
        let r = rng.range(0, 10000);
        let mut acc = 0;
        for (id, weight) in table {
            acc += weight;
            if r < acc {
                return if id != 0 { id } else { self.tall_grass };
            }
        }
        0
    }

    /// Ground plants, which other biomes swap for their own (or clear).
    pub fn is_plant(&self, b: u16) -> bool {
        b != 0 && [self.tall_grass, self.taller_grass, self.flowers, self.tall_flowers, self.mushroom, self.daybloom, self.sunflower].contains(&b)
    }

    /// Forest-only pieces that other biomes clear: vines, pond plants, twigs and logs.
    pub fn is_forest_only(&self, b: u16) -> bool {
        b != 0 && [self.vines, self.vine_flowers, self.lily_pad, self.cattail, self.cattail_stem, self.cattail_top, self.twigs, self.fallen_log].contains(&b)
    }

    /// A pond column (water from `floor + 1` up to `surface`): sometimes a lily
    /// pad floating on top, or (in shallow water) a cattail from the bottom up
    /// through the water, its head above it.
    pub fn pond(&self, w: &mut World, rng: &mut Rng, x: i32, floor: i32, surface: i32, z: i32) {
        if !w.in_bounds(x, surface + 2, z) || w.get(x, surface + 1, z) != 0 || w.liquid_at(x, surface, z).1 < LIQ_MAX {
            return;
        }
        let depth = surface - floor;
        if self.cattail != 0 && depth <= 3 && rng.chance(0.12) {
            let top = if self.cattail_top != 0 { self.cattail_top } else { self.cattail };
            let stem = if self.cattail_stem != 0 { self.cattail_stem } else { self.cattail };
            let head = surface + 1 + rng.range(0, 2);
            for y in floor + 1..=head {
                if w.get(x, y, z) != 0 {
                    return;
                }
            }
            for y in floor + 1..=head {
                let b = if y == floor + 1 { self.cattail } else if y == head { top } else { stem };
                let i = w.idx(x, y, z);
                w.blocks[i] = b;
            }
        } else if self.lily_pad != 0 && rng.chance(0.08) {
            let i = w.idx(x, surface + 1, z);
            w.blocks[i] = self.lily_pad;
        }
    }

    /// The fallen log: it stays when the jungle or an evil biome takes over
    /// (rocks stay everywhere; the rest of the forest-only pieces go).
    pub fn log(&self) -> u16 {
        self.fallen_log
    }

    /// Vines hanging 1-5 blocks from the block above `y` (some in flower).
    pub fn hang_vines(&self, w: &mut World, rng: &mut Rng, x: i32, y: i32, z: i32) {
        if self.vines == 0 {
            return;
        }
        let len = rng.range(1, 6);
        for k in 0..len {
            let yy = y - k;
            if !w.in_bounds(x, yy - 1, z) || w.get(x, yy, z) != 0 || w.get(x, yy - 1, z) != 0 || w.liquid_at(x, yy, z).1 > 0 {
                return;
            }
            let i = w.idx(x, yy, z);
            w.blocks[i] = if self.vine_flowers != 0 && rng.chance(0.2) { self.vine_flowers } else { self.vines };
        }
    }
}

/// Cobwebs in the caves, like Terraria's: patches in the corners where a cave
/// ceiling meets its walls (open cells with solid blocks on two or more sides).
pub fn cobwebs(w: &mut World, rng: &mut Rng, web: u16, patches: usize, y_lo: i32, y_hi: i32) {
    if web == 0 || y_hi <= y_lo {
        return;
    }
    let solid_sides = |w: &World, x: i32, y: i32, z: i32| {
        [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 0, -1)].iter().filter(|&&(dx, dy, dz)| w.is_solid(x + dx, y + dy, z + dz)).count()
    };
    for _ in 0..patches {
        let (x, z) = (rng.range(2, w.sx - 2), rng.range(2, w.sz - 2));
        let mut y = rng.range(y_lo, y_hi);
        if w.get(x, y, z) != 0 || w.liquid_at(x, y, z).1 > 0 {
            continue;
        }
        // Up to the ceiling.
        let mut k = 0;
        while k < 24 && y + 1 < y_hi && w.get(x, y + 1, z) == 0 {
            y += 1;
            k += 1;
        }
        if !w.is_solid(x, y + 1, z) {
            continue;
        }
        let r = rng.range(1, 3);
        for dz in -r..=r {
            for dy in -r..=0 {
                for dx in -r..=r {
                    let (cx, cy, cz) = (x + dx, y + dy, z + dz);
                    if w.in_bounds(cx, cy, cz) && w.get(cx, cy, cz) == 0 && w.liquid_at(cx, cy, cz).1 == 0
                        && solid_sides(w, cx, cy, cz) >= 2 && rng.chance(0.7) {
                        let i = w.idx(cx, cy, cz);
                        w.blocks[i] = web;
                    }
                }
            }
        }
    }
}

/// True if the air at (x, y, z) opens to the sky within a few blocks to the
/// side: under an overhang or in a cave mouth, not deep in a cave.
fn open_beside(w: &World, x: i32, y: i32, z: i32) -> bool {
    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        for k in 1..=6 {
            let (nx, nz) = (x + dx * k, z + dz * k);
            if !w.in_bounds(nx, y, nz) || w.is_solid(nx, y, nz) {
                break;
            }
            if w.surface_y(nx, nz) < y {
                return true;
            }
        }
    }
    false
}

/// Silt noise above this: a patch (tuned to Terraria's share of the cavern
/// layer, 1.5%, counted in worlds its own generator made).
const SILT_THRESHOLD: f32 = 0.66;

struct Ids {
    dirt: u16,
    stone: u16,
    grass: u16,
    clay: u16,
    sand: u16,
    mud: u16,
    ash: u16,
    hellstone: u16,
    silt: u16,
    ores: [(u16, i32, i32, f32); 4],
    trunk: u16,
    pot: u16,
    life_crystal: u16,
    chest: u16,
}

/// Directions a waterfall pours (from its wall into the open): +x, -x, +z, -z.
const WATERFALL_DIRS: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

/// A decorative waterfall pouring from `mouth` (style = liquid type * 10 +
/// direction, 4 from the ceiling), with a small pool where it lands; none if
/// it would fall less than 5 blocks.
fn add_waterfall(w: &mut World, rng: &mut Rng, t: u8, mouth: (i32, i32, i32), dir: i32) -> bool {
    let (x, y, z) = mouth;
    let mut floor = y - 1;
    while floor > 0 && !w.is_solid(x, floor, z) && w.liquid[w.idx(x, floor, z)] == 0 {
        floor -= 1;
    }
    if y - floor < 5 {
        return false;
    }
    w.decorations.push(Decoration { kind: "waterfall".into(), pos: mouth, style: t as i32 * 10 + dir });
    if w.liquid[w.idx(x, floor, z)] == 0 {
        w.fill_basin((x, floor + 1, z), floor + 1 + rng.range(0, 2), t, 300);
    }
    true
}

/// Springs on the surface's cliff faces (`attempts` random columns). Only the
/// ground counts (cube blocks): a tree trunk is solid, but a tree isn't a
/// cliff to pour from.
fn cliff_waterfalls(w: &mut World, rng: &mut Rng, attempts: usize) {
    let (sx, sz) = (w.sx, w.sz);
    let terrain = |w: &World, x: i32, y: i32, z: i32| w.is_solid(x, y, z) && w.def(w.get(x, y, z)).render == RENDER_CUBE;
    let ground_y = |w: &World, x: i32, z: i32| (0..w.sy).rev().find(|&y| terrain(w, x, y, z)).unwrap_or(-1);
    for _ in 0..attempts {
        let (x, z) = (rng.range(3, sx - 3), rng.range(3, sz - 3));
        let top = ground_y(w, x, z);
        for (d, (dx, dz)) in WATERFALL_DIRS.iter().enumerate() {
            let low = ground_y(w, x + dx, z + dz);
            if top - low >= 6 {
                let my = top - rng.range(1, 4);
                let mouth = (x + dx, my, z + dz);
                if w.get(mouth.0, mouth.1, mouth.2) == 0 && terrain(w, x, my, z) && add_waterfall(w, rng, LIQ_WATER, mouth, d as i32) {
                    break;
                }
            }
        }
    }
}

pub fn generate(w: &mut World, seed: i32, progress: &AtomicU32) {
    let set_progress = |p: f32| progress.store(p.to_bits(), Ordering::Relaxed);
    let mut rng = Rng::new(seed as u64);
    let (sx, sy, sz) = (w.sx, w.sy, w.sz);
    let l = layers(sy);
    w.seed = seed;

    // Like Terraria, each world gets one ore of every tier pair.
    let pick = |rng: &mut Rng, a: &str, b: &str| {
        let id = w.id_of(if rng.chance(0.5) { a } else { b });
        if id == 0 { w.id_of(a) } else { id }
    };
    let surf_ore_top = l.surface_base - 4;
    let ids = Ids {
        dirt: w.id_of("dirt"),
        stone: w.id_of("stone"),
        grass: w.id_of("grass"),
        clay: w.id_of("clay"),
        sand: w.id_of("sand"),
        mud: w.id_of("mud"),
        ash: w.id_of("ash"),
        hellstone: w.id_of("hellstone"),
        silt: w.id_of("silt"),
        ores: [
            (pick(&mut rng, "copper_ore", "tin_ore"), l.cavern_top - 10, surf_ore_top, 0.62),
            (pick(&mut rng, "iron_ore", "lead_ore"), l.cavern_top - 30, l.surface_base - 25, 0.66),
            (pick(&mut rng, "silver_ore", "tungsten_ore"), l.underworld_top + 20, l.cavern_top + 10, 0.68),
            (pick(&mut rng, "gold_ore", "platinum_ore"), l.underworld_top + 5, l.cavern_top - 10, 0.70),
        ],
        trunk: w.id_of("tree_trunk"),
        pot: w.id_of("pot"),
        life_crystal: w.id_of("life_crystal"),
        chest: w.id_of("chest"),
    };

    let n_height = noise(seed, 0.006, 4);
    let n_mount = {
        let mut n = noise(seed + 1, 0.0035, 3);
        n.set_fractal_type(Some(FractalType::Ridged));
        n
    };
    let n_dirt_depth = noise(seed + 2, 0.03, 1);
    let n_cave_a = noise(seed + 3, 0.018, 2);
    let n_cave_b = noise(seed + 4, 0.018, 2);
    let n_cavern = noise(seed + 5, 0.022, 3);
    let n_entrance = noise(seed + 6, 0.01, 1);
    let n_blob = noise(seed + 7, 0.06, 2);
    let n_ore: Vec<FastNoiseLite> = (0..4).map(|i| noise(seed + 10 + i, 0.11, 1)).collect();
    let n_hell = noise(seed + 20, 0.03, 2);
    let n_biome = noise(seed + 21, 0.004, 2);
    let n_silt = noise(seed + 22, 0.07, 2);
    let coast = Coast::new(seed, sx, sy, sz);
    let sea = coast.ocean;

    // Pass 1: columns, in parallel.
    let done = AtomicU32::new(0);
    let columns = (sx * sz) as u32;
    w.blocks
        .par_chunks_mut(sy as usize)
        .enumerate()
        .for_each(|(ci, col)| {
            let x = (ci as i32) % sx;
            let z = (ci as i32) / sx;
            let (fx, fz) = (x as f32, z as f32);
            // Ridged noise gives mountain chains; smoothstep rounds off the peaks.
            let m = ((n_mount.get_noise_2d(fx, fz) - 0.1) / 0.9).clamp(0.0, 1.0);
            let mountains = m * m * (3.0 - 2.0 * m);
            let mut h = l.surface_base as f32 + n_height.get_noise_2d(fx, fz) * HILLS + mountains * MOUNTAINS;
            // The coast: a beach sloping down to just above the sea, then a sea
            // floor deepening toward the edge. No tunnels break into it.
            let inland = coast.inland(x, z);
            let shore = sea.sea_level as f32 + 1.0;
            if inland < sea.width {
                let f = (inland / sea.width).clamp(0.0, 1.0);
                h = sea.sea_level as f32 - 1.0 - sea.depth * (1.0 - f).powf(0.8);
            } else if inland < sea.width + sea.beach {
                let k = (inland - sea.width) / sea.beach;
                h = shore + (h.max(shore) - shore) * k * k * (3.0 - 2.0 * k);
            }
            let sandy = inland < sea.width + sea.beach * 0.75;
            let coastal = inland < sea.width + sea.beach + 12.0;
            let h = h.min(sy as f32 - 12.0) as i32;
            let dirt_depth = 5 + (n_dirt_depth.get_noise_2d(fx, fz) * 3.0) as i32;
            let entrance = n_entrance.get_noise_2d(fx, fz) > 0.72;
            // Sandy and muddy surface patches.
            let biome = n_biome.get_noise_2d(fx, fz);

            for y in 0..sy {
                let fy = y as f32;
                let mut b = 0u16;
                if y <= h {
                    b = if sandy && y > h - dirt_depth - 3 {
                        ids.sand
                    } else if y > h - dirt_depth {
                        if biome > 0.55 { ids.sand } else if biome < -0.6 { ids.mud } else { ids.dirt }
                    } else {
                        ids.stone
                    };
                    let blob = n_blob.get_noise_3d(fx, fy * 1.3, fz);
                    if b == ids.stone && y > l.cavern_top && blob > 0.45 {
                        b = ids.dirt;
                    } else if b == ids.stone && y <= l.cavern_top && y > l.underworld_top && blob < -0.62 {
                        b = ids.mud;
                    } else if b == ids.dirt && blob < -0.55 {
                        b = ids.clay;
                    }
                    // Silt: Terraria's Silt pass, patches through the cavern
                    // layer (its TileRunners from rockLayerHigh down), the ores
                    // coming after it.
                    if ids.silt != 0 && y <= l.cavern_top && y > l.underworld_top && b != 0
                        && n_silt.get_noise_3d(fx, fy * 1.4, fz) > SILT_THRESHOLD
                    {
                        b = ids.silt;
                    }
                    if b == ids.stone || (b == ids.silt && ids.silt != 0) {
                        for (k, &(ore, lo, hi, thr)) in ids.ores.iter().enumerate() {
                            if y >= lo && y <= hi && n_ore[k].get_noise_3d(fx, fy, fz) > thr {
                                b = ore;
                            }
                        }
                    }

                    // Caves: spaghetti tunnels everywhere underground, cheese caverns deeper.
                    let depth = h - y;
                    if (depth > 5 || entrance) && !coastal {
                        let a = n_cave_a.get_noise_3d(fx, fy * 1.6, fz);
                        let c = n_cave_b.get_noise_3d(fx, fy * 1.6, fz);
                        let width = if y < l.cavern_top { 0.022 } else { 0.012 };
                        if a * a + c * c < width {
                            b = 0;
                        }
                    }
                    if y < l.cavern_top + 15 && y > l.underworld_top + 3 {
                        let fade = ((l.cavern_top + 15 - y) as f32 / 25.0).min(1.0);
                        if n_cavern.get_noise_3d(fx, fy * 1.5, fz) * fade > 0.38 {
                            b = 0;
                        }
                    }
                }

                // The Underworld: ash floor and ceiling around a huge open cavity.
                if y < l.underworld_top {
                    let hn = n_hell.get_noise_2d(fx, fz);
                    let floor = 6 + (hn * 4.0) as i32;
                    let ceil = l.underworld_top - 6 + (n_hell.get_noise_2d(fz, fx) * 4.0) as i32;
                    b = if y <= floor || y >= ceil { ids.ash } else { 0 };
                    if b == ids.ash && n_ore[3].get_noise_3d(fx * 1.3, fy, fz * 1.3) > 0.6 {
                        b = ids.hellstone;
                    }
                }
                col[y as usize] = b;
            }
            let d = done.fetch_add(1, Ordering::Relaxed);
            if d % 4096 == 0 {
                set_progress(0.6 * d as f32 / columns as f32);
            }
        });

    // The sea: water from the sea floor up to sea level, still (no cell is
    // active until something disturbs it; the world's edge holds it in).
    for z in 0..sz {
        for x in 0..sx {
            if coast.inland(x, z) >= sea.width + sea.beach {
                continue;
            }
            let mut y = sea.sea_level;
            while y > 0 && w.get(x, y, z) == 0 {
                let i = w.idx(x, y, z);
                w.liquid[i] = crate::world::liq_pack(LIQ_WATER, crate::world::LIQ_MAX);
                y -= 1;
            }
        }
    }

    // Surface ponds in hollows (before plants, which would let them leak).
    let area = (sx * sz) as f32;
    for _ in 0..(area / 600.0) as usize {
        let (x, z) = (rng.range(4, sx - 4), rng.range(4, sz - 4));
        if coast.inland(x, z) < sea.width + sea.beach + 8.0 {
            continue;
        }
        let top = w.surface_y(x, z);
        if top > 0 && top + 1 < sy {
            w.fill_basin((x, top + 1, z), top + 1, LIQ_WATER, 500);
        }
    }

    // Pass 2: grass and the forest's plants and debris on exposed dirt, lily
    // pads and cattails in the ponds, and grass with vines under overhangs and
    // in cave mouths (open to the sky beside them).
    let flora = Flora::new(w);
    for z in 0..sz {
        for x in 0..sx {
            let y = w.surface_y(x, z);
            if y < 0 || y + 2 >= sy {
                continue;
            }
            let i = w.idx(x, y, z);
            if w.blocks[i] == ids.dirt && ids.grass != 0 {
                w.blocks[i] = ids.grass;
                if w.liquid[w.idx(x, y + 1, z)] == 0 {
                    let plant = flora.ground(&mut rng);
                    if plant != 0 {
                        let j = w.idx(x, y + 1, z);
                        w.blocks[j] = plant;
                    }
                } else {
                    let mut surface = y + 1;
                    while surface + 1 < sy && w.liquid_at(x, surface + 1, z).0 == LIQ_WATER {
                        surface += 1;
                    }
                    if w.liquid_at(x, y + 1, z).0 == LIQ_WATER && coast.inland(x, z) > sea.width + sea.beach {
                        flora.pond(w, &mut rng, x, y, surface, z);
                    }
                }
            }
            if ids.grass != 0 {
                for yy in (y - 10).max(2)..y {
                    if w.get(x, yy, z) == ids.dirt && w.get(x, yy - 1, z) == 0 && w.liquid_at(x, yy - 1, z).1 == 0 && open_beside(w, x, yy - 1, z) {
                        let k = w.idx(x, yy, z);
                        w.blocks[k] = ids.grass;
                        if rng.chance(0.75) {
                            flora.hang_vines(w, &mut rng, x, yy - 1, z);
                        }
                    }
                }
            }
        }
    }
    // Sunflowers grow in patches, like Terraria's.
    if flora.sunflower != 0 {
        for _ in 0..(area / 2500.0) as usize {
            let (cx, cz) = (rng.range(4, sx - 4), rng.range(4, sz - 4));
            for _ in 0..rng.range(3, 8) {
                let (x, z) = (cx + rng.range(-3, 4), cz + rng.range(-3, 4));
                let y = w.surface_y(x, z);
                if y < 0 || y + 3 >= sy || w.get(x, y, z) != ids.grass || w.liquid_at(x, y + 1, z).1 > 0 {
                    continue;
                }
                let above = w.get(x, y + 1, z);
                if (above == 0 || flora.is_plant(above)) && w.get(x, y + 2, z) == 0 {
                    let j = w.idx(x, y + 1, z);
                    w.blocks[j] = flora.sunflower;
                }
            }
        }
    }
    set_progress(0.65);

    // Pass 3: trees on a jittered grid, each forest zone with its leaves.
    let tops = TreeTops::new(seed, sx);
    if ids.trunk != 0 {
        let cell = 7;
        for gz in 0..sz / cell {
            for gx in 0..sx / cell {
                if !rng.chance(0.55) {
                    continue;
                }
                let x = gx * cell + rng.range(1, cell - 1);
                let z = gz * cell + rng.range(1, cell - 1);
                let y = w.surface_y(x, z);
                if y < 0 || w.get(x, y, z) != ids.grass {
                    continue;
                }
                let height = rng.range(6, 15);
                if y + height + 4 >= sy {
                    continue;
                }
                for k in 1..=height {
                    let i = w.idx(x, y + k, z);
                    w.blocks[i] = ids.trunk;
                }
                w.decorations.push(Decoration {
                    kind: "tree_top".into(),
                    pos: (x, y + height + 1, z),
                    style: tops.forest(x, z, rng.range(0, 3)),
                });
            }
        }
    }
    palms(w, seed, &coast, ids.sand);
    set_progress(0.7);

    // Pass 3-: Terraria's big biomes: Snow, Desert and Jungle regions.
    let regions = biome_regions(sx, sz, seed);
    for (k, &(biome, x, z, r)) in regions.iter().enumerate() {
        biome_patch(w, &mut rng, (x, z), r, biome, seed + 200 + k as i32 * 7, Some(&coast));
    }
    // The Dungeon's entrance, on the Snow's side near the coast; its brick
    // colour is the world's, like Terraria's (blue, green or pink).
    let dungeon = dungeon_site(w, seed, &coast);
    let dungeon_brick = ["blue_brick", "green_brick", "pink_brick"][rng.range(0, 3) as usize];
    if let Some((x, y, z, door)) = dungeon {
        dungeon_entrance(w, (x, y, z), door, dungeon_brick);
    }
    set_progress(0.705);

    // Pass 3a: the world evil, like Terraria's: every world has either the
    // Corruption or the Crimson, in 2-3 patches away from spawn.
    let evil = match w.gen_evil {
        EVIL_CORRUPTION | EVIL_CRIMSON => w.gen_evil,
        _ => if rng.chance(0.5) { EVIL_CORRUPTION } else { EVIL_CRIMSON },
    };
    {
        // 2-3 in a small world, more in bigger ones (with the width, as in Terraria).
        let count = ((2 + rng.range(0, 2)) as f32 * (sx.min(sz) as f32 / 768.0).max(1.0)).round() as usize;
        let mut placed: Vec<(i32, i32, i32)> = Vec::new();
        let (cx, cz) = (sx / 2, sz / 2);
        for attempt in 0..count * 40 {
            if placed.len() >= count {
                break;
            }
            let r = rng.range(36, 50).min(sx.min(sz) / 5);
            let (x, z) = (rng.range(r + 4, sx - r - 4), rng.range(r + 4, sz - r - 4));
            let clear = r + sx.min(sz) / 8;
            let d2 = |a: i32, b: i32| (a - x) * (a - x) + (b - z) * (b - z);
            if d2(cx, cz) < clear * clear || placed.iter().any(|&(px, pz, pr)| d2(px, pz) < (pr + r + 10) * (pr + r + 10)) {
                continue;
            }
            // Inland, clear of the beach and of the other biomes.
            if coast.inland(x, z) < sea.width + sea.beach + r as f32 * 0.5
                || regions.iter().any(|&(_, bx, bz, br)| d2(bx, bz) < (br + r * 3 / 4) * (br + r * 3 / 4))
                || dungeon.map_or(false, |(dx, _, dz, _)| d2(dx, dz) < (r + 30) * (r + 30)) {
                continue;
            }
            evil_patch(w, &mut rng, (x, z), r, evil, seed + 100 + attempt as i32);
            placed.push((x, z, r));
        }
    }
    set_progress(0.71);

    // Pass 3b: floating islands high in the sky, like Terraria's: in the Space
    // layer, well above the mountains and away from spawn, each a house island, a lake island or a
    // plain one (at least one house, so every world has a Skyware chest).
    {
        // With the width, as in Terraria: about 5 in a small world, 10 in a large.
        let count = ((sx.min(sz) as f32 / 150.0) as usize).max(2);
        let mut placed: Vec<(i32, i32, i32)> = Vec::new();
        let (cx, cz) = (sx / 2, sz / 2);
        for attempt in 0..count * 30 {
            if placed.len() >= count {
                break;
            }
            let r = rng.range(14, 20);
            let (x, z) = (rng.range(r + 6, sx - r - 6), rng.range(r + 6, sz - r - 6));
            // Well inside the Space layer (the underside too), roof below the
            // build limit.
            let top = rng.range(l.space_top + 16, (sy - 12).max(l.space_top + 17));
            let near = |a: i32, b: i32, d: i32| (a - x) * (a - x) + (b - z) * (b - z) < d * d;
            if near(cx, cz, 70) || placed.iter().any(|&(px, pz, pr)| near(px, pz, 2 * (pr + r) + 20)) {
                continue;
            }
            // Clear of the ground: the highest terrain under it stays far below.
            let mut highest = 0;
            for dz in (-r..=r).step_by(3) {
                for dx in (-r..=r).step_by(3) {
                    highest = highest.max(w.surface_y(x + dx, z + dz));
                }
            }
            if highest > top - 30 {
                continue;
            }
            let kind = if placed.is_empty() {
                ISLAND_HOUSE
            } else {
                match rng.range(0, 20) {
                    0..=11 => ISLAND_HOUSE,
                    12..=16 => ISLAND_LAKE,
                    _ => ISLAND_PLAIN,
                }
            };
            floating_island(w, &mut rng, (x, top, z), r, kind, seed + attempt as i32);
            placed.push((x, z, r));
        }
    }
    set_progress(0.72);

    // Pass 4: cave floor treasures.
    let place_on_floor = |w: &mut World, rng: &mut Rng, id: u16, count: usize, y_lo: i32, y_hi: i32, deco: Option<&str>| {
        if id == 0 {
            return;
        }
        let mut placed = 0;
        for _ in 0..count * 40 {
            if placed >= count {
                break;
            }
            let (x, z) = (rng.range(1, sx - 1), rng.range(1, sz - 1));
            let mut y = rng.range(y_lo, y_hi);
            if w.get(x, y, z) != 0 {
                continue;
            }
            while y > 0 && w.get(x, y - 1, z) == 0 {
                y -= 1;
            }
            if y <= y_lo || !w.is_solid(x, y - 1, z) || w.def(w.get(x, y - 1, z)).render != 1 {
                continue;
            }
            let i = w.idx(x, y, z);
            w.blocks[i] = id;
            if let Some(kind) = deco {
                w.decorations.push(Decoration {
                    kind: kind.into(),
                    pos: (x, y, z),
                    style: 0,
                });
            }
            placed += 1;
        }
    };
    let surface_low = l.surface_base - 8;
    place_on_floor(w, &mut rng, ids.pot, (area / 180.0) as usize, l.underworld_top + 2, surface_low, None);
    place_on_floor(w, &mut rng, ids.life_crystal, (area / 4000.0) as usize, l.underworld_top + 2, surface_low - 15, None);
    place_on_floor(w, &mut rng, ids.chest, (area / 2500.0) as usize, l.underworld_top + 2, surface_low - 10, Some("chest"));
    // Altars of the world's evil scattered through the caverns, as in Terraria.
    let altar = w.id_of(if evil == EVIL_CRIMSON { "crimson_altar" } else { "demon_altar" });
    place_on_floor(w, &mut rng, altar, (area / 35000.0) as usize, l.underworld_top + 10, surface_low - 20, None);
    cobwebs(w, &mut rng, w.id_of("cobweb"), (area / 150.0) as usize, l.underworld_top + 10, surface_low);
    set_progress(0.75);

    // Pass 5: liquids. Water pools on cave floors, lava pockets deep in the
    // caverns and lava lakes across the Underworld floor; each fills an
    // enclosed basin so it starts out settled.
    let pools = |w: &mut World, rng: &mut Rng, t: u8, count: usize, y_lo: i32, y_hi: i32, max_depth: i32, max_cells: usize| {
        for _ in 0..count {
            let (x, z) = (rng.range(2, sx - 2), rng.range(2, sz - 2));
            let mut y = rng.range(y_lo, y_hi.max(y_lo + 1));
            if w.get(x, y, z) != 0 || w.liquid[w.idx(x, y, z)] != 0 {
                continue;
            }
            while y > 1 && w.get(x, y - 1, z) == 0 {
                y -= 1;
            }
            if !w.is_solid(x, y - 1, z) {
                continue;
            }
            w.fill_basin((x, y, z), y + rng.range(0, max_depth), t, max_cells);
        }
    };
    pools(w, &mut rng, LIQ_WATER, (area / 120.0) as usize, l.underworld_top + 4, surface_low, 4, 2500);
    pools(w, &mut rng, LIQ_LAVA, (area / 2500.0) as usize, l.underworld_top + 4, l.cavern_top - 20, 3, 600);
    pools(w, &mut rng, LIQ_LAVA, (area / 200.0) as usize, 3, l.underworld_top - 6, 4, 8000);
    set_progress(0.78);

    // Pass 6: decorative waterfalls, as in Terraria: streams pour from cliff
    // faces and cave walls, and lava falls from the Underworld ceiling. They are
    // drawn by the game (no liquid drains); a small pool forms where they land.
    // style = liquid type * 10 + direction (0 +x, 1 -x, 2 +z, 3 -z, 4 from the ceiling).
    let dirs = WATERFALL_DIRS;
    let add_fall = add_waterfall;
    cliff_waterfalls(w, &mut rng, (area / 2500.0) as usize);
    // Cave walls.
    // Scan down a random column for an open cell just under a cave ceiling,
    // beside a wall: the spring pours out of the top of the wall.
    for _ in 0..(area / 700.0) as usize {
        let (x, z) = (rng.range(3, sx - 3), rng.range(3, sz - 3));
        let mut y = rng.range(l.underworld_top + 12, surface_low);
        let stop = (y - 60).max(l.underworld_top + 6);
        'search: while y > stop {
            if w.get(x, y, z) == 0 && w.liquid[w.idx(x, y, z)] == 0 && w.is_solid(x, y + 1, z) {
                for (d, (dx, dz)) in dirs.iter().enumerate() {
                    if w.is_solid(x - dx, y, z - dz) {
                        add_fall(w, &mut rng, LIQ_WATER, (x, y, z), d as i32);
                        break 'search;
                    }
                }
            }
            y -= 1;
        }
    }
    // Lava falls from the Underworld ceiling.
    for _ in 0..(area / 900.0) as usize {
        let (x, z) = (rng.range(3, sx - 3), rng.range(3, sz - 3));
        let mut y = l.underworld_top - 2;
        while y > 4 && w.is_solid(x, y, z) {
            y -= 1;
        }
        if w.get(x, y, z) == 0 && w.is_solid(x, y + 1, z) {
            add_fall(w, &mut rng, LIQ_LAVA, (x, y, z), 4);
        }
    }
    gem_trees(w, seed, &l);
    vanity_trees(w, seed, ids.grass);
    ash_forest(w, seed, &l);
    living_trees(w, seed, ids.grass, ids.chest);
    mahogany_trees(w, seed, &l, ids.chest);
    jungle_cave_trees(w, seed, &l);
    // Pass 6b: the Dungeon under its entrance (Terraria's Dungeon pass, before
    // its Buried Chests), protected from the structures after it.
    if let Some((x, y, z, door)) = dungeon {
        crate::dungeon::dungeon(w, seed as u64, &l, (x, y, z), door, dungeon_brick, 1.0);
    }
    // Pass 7: underground cabins, after the liquids and the trees as in
    // Terraria (its Buried Chests pass). Terraria's CaveHouseCount is 35-40 in
    // a small world, scaled with its area; its worlds are a 2D slice, so here
    // that many go in each 640 x 640 blocks of the map (about 95 in 1024 x 1024).
    let cabin_count = (rng.range(35, 41) as f32 * area / (640.0 * 640.0)).round() as usize;
    let cabins = crate::cabins::underground_cabins(w, &mut rng, &l, cabin_count);
    // Pass 8: Enchanted Sword Shrines (Terraria's Micro Biomes pass, after its
    // Buried Chests), kept out of the cabins and chests.
    crate::shrines::sword_shrines(w, &mut rng, &l);
    // Springs that were in the rock a cabin now stands in.
    w.decorations.retain(|d| {
        d.kind != "waterfall" || !cabins.iter().flatten().any(|r| {
            let (x, y, z) = d.pos;
            x >= r.x0 - 1 && x <= r.x1() + 1 && z >= r.z0 - 1 && z <= r.z1() + 1 && y >= r.y0 - 1 && y <= r.ceiling() + 1
        })
    });
    set_progress(0.79);

    // Spawn at the world centre, on the surface.
    let (cx, cz) = (sx / 2, sz / 2);
    let mut spawn_y = w.surface_y(cx, cz) + 1;
    while spawn_y < sy - 2 && (w.is_solid(cx, spawn_y, cz) || w.is_solid(cx, spawn_y + 1, cz)) {
        spawn_y += 1;
    }
    w.spawn = (cx, spawn_y, cz);
}

pub const EVIL_CORRUPTION: i32 = 1;
pub const EVIL_CRIMSON: i32 = 2;

/// A Corruption or Crimson patch around column (cx, cz), like Terraria's: the
/// surface and the ground below turn evil (grass, stone, sand, plants, trees,
/// with veins of evil stone and its ore), then:
///   Corruption: deep chasms with side passages ending in Shadow Orbs;
///   Crimson: winding tunnels down to a flesh cavern whose tendrils end in
///   Crimson Hearts.
/// Both line their tunnels with their stone and put an altar at the bottom.
pub const BIOME_SNOW: i32 = 1;
pub const BIOME_DESERT: i32 = 2;
pub const BIOME_JUNGLE: i32 = 3;

/// Where worldgen puts Terraria's big biomes, as (biome, x, z, radius): the
/// Snow and the Jungle on opposite sides of spawn (a random direction), the
/// Desert between them. Radii follow the world's width.
pub fn biome_regions(sx: i32, sz: i32, seed: i32) -> Vec<(i32, i32, i32, i32)> {
    let mut rng = Rng::new(seed as u64 ^ 0x5eed_b10e);
    let d = sx.min(sz) as f32;
    let (cx, cz) = (sx as f32 / 2.0, sz as f32 / 2.0);
    let a = rng.range(0, 628) as f32 / 100.0;
    let side = if rng.chance(0.5) { 1.0 } else { -1.0 };
    let at = |ang: f32, dist: f32| ((cx + ang.cos() * dist) as i32, (cz + ang.sin() * dist) as i32);
    let (snow, jungle, desert) = (at(a, d * 0.26), at(a + std::f32::consts::PI, d * 0.26), at(a + side * std::f32::consts::FRAC_PI_2, d * 0.24));
    vec![
        (BIOME_SNOW, snow.0, snow.1, (d * 0.14) as i32),
        (BIOME_JUNGLE, jungle.0, jungle.1, (d * 0.16) as i32),
        (BIOME_DESERT, desert.0, desert.1, (d * 0.11) as i32),
    ]
}

/// Turns the ground around `center` into one of Terraria's big biomes, like
/// evil_patch does for the Corruption: the noisy-edged region's surface and
/// what lies under it (columns within reach of the sea are left alone).
///   Snow    snow over the ground, the stone below turned to ice, narrowing
///           with depth down into the caverns; boreal trees under snowy pines.
///   Desert  deep sand, over an underground desert of hardened sand and
///           sandstone; trees give way to cacti.
///   Jungle  mud everywhere down to the Underworld (some stone left), jungle
///           grass on the surface and in the caves, jungle plants and spores,
///           and dense mahogany trees.
/// Returns how many columns changed.
/// Whether a block of `id` is within `r` of `p` (a cube round it).
fn near_block(w: &World, p: (i32, i32, i32), r: i32, id: u16) -> bool {
    if id == 0 {
        return false;
    }
    for dy in -r..=r {
        for dz in -r..=r {
            for dx in -r..=r {
                if w.in_bounds(p.0 + dx, p.1 + dy, p.2 + dz) && w.get(p.0 + dx, p.1 + dy, p.2 + dz) == id {
                    return true;
                }
            }
        }
    }
    false
}

pub fn biome_patch(w: &mut World, rng: &mut Rng, center: (i32, i32), radius: i32, biome: i32, seed: i32, coast: Option<&Coast>) -> usize {
    let id = |w: &World, n: &str| w.id_of(n);
    let (stone, dirt, grass, sand, clay, mud) = (id(w, "stone"), id(w, "dirt"), id(w, "grass"), id(w, "sand"), id(w, "clay"), id(w, "mud"));
    let (snow, ice) = (id(w, "snow_block"), id(w, "ice_block"));
    let (silt, slush) = (id(w, "silt"), id(w, "slush"));
    let (hsand, sandstone, cactus) = (id(w, "hardened_sand"), id(w, "sandstone"), id(w, "cactus"));
    let (jgrass, jplants, spores) = (id(w, "jungle_grass"), id(w, "jungle_plants"), id(w, "jungle_spores"));
    let (boreal, mahogany) = (id(w, "boreal_trunk"), id(w, "mahogany_trunk"));
    let flora = Flora::new(w);
    let key = match biome {
        BIOME_SNOW => snow,
        BIOME_DESERT => hsand,
        BIOME_JUNGLE => jgrass,
        _ => 0,
    };
    if key == 0 {
        return 0;
    }
    let trunks: Vec<u16> = ["tree_trunk", "ebonwood_trunk", "shadewood_trunk", "boreal_trunk", "mahogany_trunk"].iter().map(|n| id(w, n)).filter(|&t| t != 0).collect();
    let is_trunk = |b: u16| trunks.contains(&b);
    let natural = |b: u16| b != 0 && (b == stone || b == dirt || b == grass || b == sand || b == clay || b == mud || b == snow || b == ice || b == silt || b == slush);
    let l = layers(w.sy);
    let (cx, cz) = center;
    let r = radius as f32;
    let n_edge = noise(seed, 1.2 / r.max(8.0), 2);
    let n_mix = noise(seed + 1, 0.07, 2);
    let reach = (r * 1.3) as i32 + 2;
    let mut changed = 0;
    for dz in -reach..=reach {
        for dx in -reach..=reach {
            let (x, z) = (cx + dx, cz + dz);
            if !w.in_bounds(x, 0, z) {
                continue;
            }
            let rr = r * (1.0 + 0.25 * n_edge.get_noise_2d(x as f32, z as f32));
            let d = ((dx * dx + dz * dz) as f32).sqrt() / rr;
            if d >= 1.0 {
                continue;
            }
            if let Some(c) = coast {
                if c.inland(x, z) < c.ocean.width + c.ocean.beach + 4.0 {
                    continue;
                }
            }
            // The ground: the highest natural block (not a trunk or a plant).
            let mut ground = w.surface_y(x, z);
            while ground > 0 && !natural(w.get(x, ground, z)) {
                ground -= 1;
            }
            if ground <= 0 {
                continue;
            }
            changed += 1;
            // How deep it goes (deepest in the middle): the snow a cone into the
            // caverns, the jungle down to the Underworld, the underground desert
            // to the cavern layer; at least well below the ground in any world.
            let lowest = match biome {
                BIOME_SNOW => (l.cavern_top - 30).min(ground - 60),
                BIOME_JUNGLE => l.underworld_top + 4,
                _ => l.cavern_top.min(ground - 45),
            };
            let shape = if biome == BIOME_JUNGLE { d.powi(3) } else { d * d };
            let bottom = lowest + ((ground - lowest) as f32 * shape) as i32;
            let sand_depth = 8 + (6.0 * (1.0 - d)) as i32;
            for y in bottom.max(1)..(ground + 26).min(w.sy) {
                let i = w.idx(x, y, z);
                let b = w.blocks[i];
                if b == 0 {
                    continue;
                }
                let m = n_mix.get_noise_3d(x as f32, y as f32 * 1.3, z as f32);
                let below_ground = ground - y;
                let nb = match biome {
                    BIOME_SNOW => {
                        // Terraria's ice biome pass: stone to ice, the soil
                        // (dirt, grass, clay, sand) to snow; then its slush
                        // pass: silt, and mud away from jungle grass, to slush.
                        if b == stone {
                            ice
                        } else if slush != 0 && (b == silt || (b == mud && !near_block(w, (x, y, z), 3, jgrass))) {
                            slush
                        } else if natural(b) {
                            snow
                        } else if flora.is_plant(b) || flora.is_forest_only(b) {
                            0
                        } else if is_trunk(b) && boreal != 0 {
                            boreal
                        } else {
                            b
                        }
                    }
                    BIOME_DESERT => {
                        if natural(b) {
                            if below_ground < sand_depth { sand } else if m > -0.1 { hsand } else if sandstone != 0 { sandstone } else { hsand }
                        } else if flora.is_plant(b) || flora.is_forest_only(b) || is_trunk(b) {
                            0
                        } else {
                            b
                        }
                    }
                    _ => {
                        if b == grass {
                            jgrass
                        } else if b == stone && m > 0.45 {
                            stone
                        } else if natural(b) && b != snow && b != ice && b != silt {
                            mud
                        } else if flora.is_plant(b) && jplants != 0 {
                            if spores != 0 && rng.chance(0.04) { spores } else { jplants }
                        } else if flora.is_forest_only(b) && b != flora.log() {
                            0
                        } else if is_trunk(b) && mahogany != 0 {
                            mahogany
                        } else {
                            b
                        }
                    }
                };
                w.blocks[i] = nb;
            }
            // Jungle caves: grass (and plants) on any mud open to the air.
            if biome == BIOME_JUNGLE {
                for y in bottom.max(1)..ground {
                    if w.get(x, y, z) == mud && w.get(x, y + 1, z) == 0 && w.liquid[w.idx(x, y + 1, z)] == 0 {
                        let i = w.idx(x, y, z);
                        w.blocks[i] = jgrass;
                        if jplants != 0 && rng.chance(0.3) && w.get(x, y + 2, z) == 0 {
                            let j = w.idx(x, y + 1, z);
                            w.blocks[j] = if spores != 0 && rng.chance(0.06) { spores } else { jplants };
                        }
                    }
                }
            }
        }
    }
    // Canopies: the world's snow and jungle tree tops; the desert's go.
    // (A canopy belongs to the region when the trunk under it was converted.)
    let tops = TreeTops::of(w);
    let new_trunk = if biome == BIOME_SNOW { boreal } else { mahogany };
    let decs = std::mem::take(&mut w.decorations);
    let mut keep = Vec::with_capacity(decs.len());
    for mut d in decs {
        if d.kind == "tree_top" && is_forest_canopy(d.style) && ((d.pos.0 - cx).pow(2) + (d.pos.2 - cz).pow(2)) as f32 <= (r * 1.3).powi(2) {
            let below = w.get(d.pos.0, d.pos.1 - 1, d.pos.2);
            if below == 0 {
                continue;  // its trunk went with the desert
            }
            if below == new_trunk && new_trunk != 0 {
                d.style = if biome == BIOME_SNOW { tops.snow(d.pos.0, d.style % 10) } else { tops.jungle(d.style % 10) };
            }
        }
        keep.push(d);
    }
    w.decorations = keep;
    // Extra growth: dense mahogany in the jungle, a few boreal trees in the
    // snow, cacti in the desert.
    let cell = if biome == BIOME_JUNGLE { 5 } else { 9 };
    for gz in (cz - reach..cz + reach).step_by(cell) {
        for gx in (cx - reach..cx + reach).step_by(cell) {
            let (x, z) = (gx + rng.range(0, cell as i32), gz + rng.range(0, cell as i32));
            if !w.in_bounds(x, 0, z) || ((x - cx).pow(2) + (z - cz).pow(2)) as f32 > (r * 0.9).powi(2) {
                continue;
            }
            let top = w.surface_y(x, z);
            if top <= 0 || top + 20 >= w.sy || w.get(x, top + 1, z) != 0 {
                continue;
            }
            let ground = w.get(x, top, z);
            if biome == BIOME_JUNGLE && ground == jgrass && mahogany != 0 && rng.chance(0.55) {
                let h = rng.range(9, 17);
                for k in 1..=h {
                    let i = w.idx(x, top + k, z);
                    w.blocks[i] = mahogany;
                }
                w.decorations.push(Decoration { kind: "tree_top".into(), pos: (x, top + h + 1, z), style: tops.jungle(rng.range(0, 3)) });
            } else if biome == BIOME_SNOW && ground == snow && boreal != 0 && rng.chance(0.3) {
                let h = rng.range(7, 13);
                for k in 1..=h {
                    let i = w.idx(x, top + k, z);
                    w.blocks[i] = boreal;
                }
                w.decorations.push(Decoration { kind: "tree_top".into(), pos: (x, top + h + 1, z), style: tops.snow(x, rng.range(0, 3)) });
            } else if biome == BIOME_DESERT && ground == sand && cactus != 0 && rng.chance(0.45) {
                // A column of cactus cells; the game draws it with arms (CactusArt).
                for k in 1..=rng.range(3, 8) {
                    let i = w.idx(x, top + k, z);
                    w.blocks[i] = cactus;
                }
            }
        }
    }
    changed
}

pub fn evil_patch(w: &mut World, rng: &mut Rng, center: (i32, i32), radius: i32, evil: i32, seed: i32) {
    let crimson = evil == EVIL_CRIMSON;
    let pick = |w: &World, corrupt: &str, crim: &str| w.id_of(if crimson { crim } else { corrupt });
    let (stone, grass, sand, dirt) = (w.id_of("stone"), w.id_of("grass"), w.id_of("sand"), w.id_of("dirt"));
    let e_stone = pick(w, "ebonstone", "crimstone");
    if e_stone == 0 {
        return;
    }
    let or = |a: u16, b: u16| if a != 0 { a } else { b };
    let e_grass = or(pick(w, "corrupt_grass", "crimson_grass"), grass);
    let e_sand = or(pick(w, "ebonsand", "crimsand"), sand);
    let e_plants = pick(w, "corrupt_plants", "crimson_plants");
    let e_mushroom = pick(w, "vile_mushroom", "vicious_mushroom");
    let e_ore = pick(w, "demonite_ore", "crimtane_ore");
    let e_trunk = pick(w, "ebonwood_trunk", "shadewood_trunk");
    let (orb, altar) = (pick(w, "shadow_orb", "crimson_heart"), pick(w, "demon_altar", "crimson_altar"));
    let trunk = w.id_of("tree_trunk");
    let flora = Flora::new(w);
    let (cx, cz) = center;
    let n_edge = noise(seed, 0.04, 2);
    let n_vein = noise(seed + 1, 0.09, 2);
    let n_ore = noise(seed + 2, 0.13, 1);
    let r = radius as f32;
    let bottom_limit = layers(w.sy).underworld_top + 8;

    // The ground turns evil, deepest in the middle.
    for dz in -(radius + 8)..=radius + 8 {
        for dx in -(radius + 8)..=radius + 8 {
            let (x, z) = (cx + dx, cz + dz);
            if !w.in_bounds(x, 0, z) {
                continue;
            }
            let rr = r * (1.0 + 0.2 * n_edge.get_noise_2d(x as f32, z as f32));
            let d = ((dx * dx + dz * dz) as f32).sqrt() / rr;
            if d >= 1.0 {
                continue;
            }
            let top = w.surface_y(x, z);
            if top < 0 {
                continue;
            }
            let depth = 28 + (24.0 * (1.0 - d)) as i32;
            for y in (top - depth).max(bottom_limit)..=(top + 1).min(w.sy - 1) {
                let i = w.idx(x, y, z);
                let b = w.blocks[i];
                let (fx, fy, fz) = (x as f32, y as f32, z as f32);
                let nb = if b == grass {
                    e_grass
                } else if b == sand {
                    e_sand
                } else if b == stone || (b == dirt && n_vein.get_noise_3d(fx, fy * 1.4, fz) > 0.42) {
                    if y < top - 10 && n_ore.get_noise_3d(fx, fy, fz) > 0.68 && e_ore != 0 { e_ore } else { e_stone }
                } else if flora.is_plant(b) {
                    if e_mushroom != 0 && rng.chance(0.08) { e_mushroom } else if e_plants != 0 { e_plants } else { 0 }
                } else if flora.is_forest_only(b) && b != flora.log() {
                    0
                } else if b == trunk && trunk != 0 && e_trunk != 0 {
                    e_trunk
                } else {
                    b
                };
                w.blocks[i] = nb;
            }
        }
    }
    // Canopies over evil trunks take the biome's style (10+ Corruption, 20+ Crimson).
    let offset = if crimson { 20 } else { 10 };
    for d in w.decorations.iter_mut() {
        if d.kind == "tree_top" && is_forest_canopy(d.style) {
            let (dx, dz) = (d.pos.0 - cx, d.pos.2 - cz);
            if ((dx * dx + dz * dz) as f32) < r * r {
                d.style = offset + d.style % 10;
            }
        }
    }

    // Tunnels: a list of spheres (x, y, z, radius) to line and hollow out, and
    // the pockets where orbs/hearts float.
    let mut spheres: Vec<(f32, f32, f32, f32)> = Vec::new();
    let mut pockets: Vec<(i32, i32, i32)> = Vec::new();
    let mut floors: Vec<(i32, i32, i32)> = Vec::new();
    let start_in_patch = |rng: &mut Rng| {
        let a = rng.range(0, 628) as f32 / 100.0;
        let dist = r * rng.range(0, 55) as f32 / 100.0;
        (cx + (a.cos() * dist) as i32, cz + (a.sin() * dist) as i32)
    };
    let branch = |rng: &mut Rng, spheres: &mut Vec<(f32, f32, f32, f32)>, pockets: &mut Vec<(i32, i32, i32)>, from: (f32, f32, f32), len: i32, down: f32| {
        let a = rng.range(0, 628) as f32 / 100.0;
        let (mut x, mut y, mut z) = from;
        for _ in 0..len {
            x += a.cos();
            z += a.sin();
            y -= down;
            spheres.push((x, y, z, 1.4));
        }
        spheres.push((x, y, z, 2.4));
        pockets.push((x as i32, y as i32, z as i32));
    };
    if !crimson {
        for _ in 0..rng.range(3, 6) {
            let (x0, z0) = start_in_patch(rng);
            let top = w.surface_y(x0, z0);
            let depth = rng.range(45, 70);
            let (mut x, mut z) = (x0 as f32 + 0.5, z0 as f32 + 0.5);
            let rad = rng.range(16, 25) as f32 / 10.0;
            let mut y = top as f32 + 2.0;
            let mut since_branch = 0;
            while y > (top - depth).max(bottom_limit + 4) as f32 {
                x += rng.range(-30, 31) as f32 / 100.0;
                z += rng.range(-30, 31) as f32 / 100.0;
                y -= 1.0;
                spheres.push((x, y, z, rad));
                since_branch += 1;
                if since_branch > 12 && y < top as f32 - 12.0 && rng.chance(0.08) {
                    let len = rng.range(7, 14);
                    branch(rng, &mut spheres, &mut pockets, (x, y, z), len, 0.25);
                    since_branch = 0;
                }
            }
            spheres.push((x, y - 1.0, z, rad + 1.2));
            pockets.push((x as i32, y as i32, z as i32));
            floors.push((x as i32, (y - 1.0 - rad - 1.2) as i32 + 1, z as i32));
        }
    } else {
        for _ in 0..rng.range(1, 3) {
            let (x0, z0) = start_in_patch(rng);
            let top = w.surface_y(x0, z0);
            let (mut x, mut z) = (x0 as f32 + 0.5, z0 as f32 + 0.5);
            let mut y = top as f32 + 2.0;
            let mut a = rng.range(0, 628) as f32 / 100.0;
            let target = (top - rng.range(40, 55)).max(bottom_limit + 16) as f32;
            while y > target {
                a += rng.range(-25, 26) as f32 / 100.0;
                x += a.cos() * 0.8;
                z += a.sin() * 0.8;
                y -= 0.7;
                spheres.push((x, y, z, 2.0));
            }
            // The flesh cavern, a little flattened.
            let cr = rng.range(9, 12) as f32;
            let cy = y - cr * 0.6;
            for k in 0..9 {
                let t = k as f32 / 8.0 * std::f32::consts::TAU;
                spheres.push((x + t.cos() * cr * 0.45, cy, z + t.sin() * cr * 0.45, cr * 0.65));
            }
            spheres.push((x, cy, z, cr * 0.7));
            floors.push((x as i32, (cy - cr * 0.7) as i32 + 1, z as i32));
            for _ in 0..rng.range(4, 7) {
                let b = rng.range(0, 628) as f32 / 100.0;
                let from = (x + b.cos() * cr * 0.8, cy - cr * 0.1, z + b.sin() * cr * 0.8);
                let len = rng.range(6, 10);
                branch(rng, &mut spheres, &mut pockets, from, len, 0.35);
            }
        }
    }

    // Line every tunnel with the biome's stone, then hollow them out.
    for pass in 0..2 {
        for &(sx_, sy_, sz_, sr) in &spheres {
            let shell = if pass == 0 { sr + 2.5 } else { sr };
            let reach = shell.ceil() as i32;
            for dz in -reach..=reach {
                for dy in -reach..=reach {
                    for dx in -reach..=reach {
                        let (x, y, z) = (sx_ as i32 + dx, sy_ as i32 + dy, sz_ as i32 + dz);
                        if !w.in_bounds(x, y, z) || y <= bottom_limit {
                            continue;
                        }
                        let (fx, fy, fz) = (x as f32 + 0.5 - sx_, y as f32 + 0.5 - sy_, z as f32 + 0.5 - sz_);
                        if fx * fx + fy * fy + fz * fz > shell * shell {
                            continue;
                        }
                        let i = w.idx(x, y, z);
                        if pass == 0 {
                            if w.blocks[i] != 0 && w.is_solid(x, y, z) {
                                w.blocks[i] = e_stone;
                            }
                        } else {
                            w.blocks[i] = 0;
                            w.liquid[i] = 0;
                        }
                    }
                }
            }
        }
    }
    // Shadow Orbs / Crimson Hearts float in their pockets; altars stand on the
    // tunnel floors.
    if orb != 0 {
        for &(x, y, z) in &pockets {
            if w.in_bounds(x, y, z) && w.get(x, y, z) == 0 {
                let i = w.idx(x, y, z);
                w.blocks[i] = orb;
            }
        }
    }
    if altar != 0 {
        for &(x, y, z) in floors.iter().take(2) {
            let mut y = y;
            while y > bottom_limit && w.in_bounds(x, y - 1, z) && w.get(x, y - 1, z) == 0 {
                y -= 1;
            }
            if w.in_bounds(x, y, z) && w.get(x, y, z) == 0 {
                let i = w.idx(x, y, z);
                w.blocks[i] = altar;
            }
        }
    }
}

pub const ISLAND_PLAIN: i32 = 0;
pub const ISLAND_HOUSE: i32 = 1;
pub const ISLAND_LAKE: i32 = 2;

/// A Terraria-style floating island centred on `c` = (x, top, z): a lens of
/// dirt with grass on top and a cloud underside tapering to a point, wrapped in
/// cloud puffs (sometimes rain clouds), with a few trees. ISLAND_HOUSE adds a
/// Sunplate house with a Skyware chest (a "chest" decoration, style 1 = sky
/// loot); ISLAND_LAKE a sky lake of water in a bowl on top.
pub fn floating_island(w: &mut World, rng: &mut Rng, c: (i32, i32, i32), radius: i32, kind: i32, seed: i32) {
    let (cx, top, cz) = c;
    let id = |w: &World, name: &str| w.id_of(name);
    let (dirt, grass, cloud, rain) = (id(w, "dirt"), id(w, "grass"), id(w, "cloud"), id(w, "rain_cloud"));
    let cloud = if cloud == 0 { dirt } else { cloud };
    let trunk = id(w, "tree_trunk");
    let flora = Flora::new(w);
    let n_edge = noise(seed, 0.09, 2);
    let n_thick = noise(seed + 1, 0.15, 1);
    let r = radius as f32;
    let depth = r * 0.8;
    let set = |w: &mut World, x: i32, y: i32, z: i32, b: u16| {
        if w.in_bounds(x, y, z) {
            let i = w.idx(x, y, z);
            w.blocks[i] = b;
        }
    };

    // The lens: flat top that rounds off at the rim, underside tapering down.
    let reach = (r * 1.25) as i32;
    for dz in -reach..=reach {
        for dx in -reach..=reach {
            let (x, z) = (cx + dx, cz + dz);
            let rr = r * (1.0 + 0.2 * n_edge.get_noise_2d(x as f32, z as f32));
            let d = ((dx * dx + dz * dz) as f32).sqrt() / rr;
            if d >= 1.0 {
                continue;
            }
            let rim = if d > 0.7 { ((d - 0.7) / 0.3).powi(2) * 2.5 } else { 0.0 };
            let ytop = top - rim.round() as i32;
            let thick = depth * (1.0 - d * d).sqrt() * (0.75 + 0.25 * n_thick.get_noise_2d(x as f32, z as f32)) + 1.0;
            let ybot = top - thick as i32;
            let dirt_depth = (4.0 * (1.0 - d)) as i32 + 1;
            for y in ybot..=ytop {
                let b = if y > ytop - dirt_depth && d < 0.85 { dirt } else { cloud };
                set(w, x, y, z, b);
            }
            if d < 0.85 && grass != 0 {
                set(w, x, ytop, z, grass);
            }
        }
    }

    // Cloud puffs around the rim and underneath; some islands get rain clouds.
    let puff_block = if rain != 0 && rng.chance(0.35) { rain } else { cloud };
    for k in 0..rng.range(5, 9) {
        let a = rng.range(0, 628) as f32 / 100.0;
        let under = k % 3 == 2;
        let dist = if under { r * 0.4 } else { r * (0.85 + rng.range(0, 30) as f32 / 100.0) };
        let (px, pz) = (cx + (a.cos() * dist) as i32, cz + (a.sin() * dist) as i32);
        let py = if under { top - (depth * 0.6) as i32 } else { top - rng.range(1, 4) };
        let (pr, ph) = (rng.range(3, 6), rng.range(2, 4));
        let b = if k % 2 == 0 { puff_block } else { cloud };
        for dz in -pr..=pr {
            for dy in -ph..=ph {
                for dx in -pr..=pr {
                    let e = (dx * dx + dz * dz) as f32 / (pr * pr) as f32 + (dy * dy) as f32 / (ph * ph) as f32;
                    if e <= 1.0 && w.in_bounds(px + dx, py + dy, pz + dz) && w.get(px + dx, py + dy, pz + dz) == 0 {
                        set(w, px + dx, py + dy, pz + dz, b);
                    }
                }
            }
        }
    }

    // House or lake, off the centre.
    let a = rng.range(0, 628) as f32 / 100.0;
    let (hx, hz) = (cx + (a.cos() * r * 0.12) as i32, cz + (a.sin() * r * 0.12) as i32);
    let mut keep_clear: Option<(i32, i32, i32)> = None;
    if kind == ISLAND_HOUSE {
        let side = rng.range(0, 4);
        skyware_house(w, (hx, top, hz), side);
        keep_clear = Some((hx, hz, 7));
    } else if kind == ISLAND_LAKE {
        let lr = r * 0.45;
        let reach = lr as i32 + 1;
        for dz in -reach..=reach {
            for dx in -reach..=reach {
                let d = ((dx * dx + dz * dz) as f32).sqrt() / lr;
                if d >= 1.0 {
                    continue;
                }
                let bowl = (3.5 * (1.0 - d * d) + 0.5) as i32;
                for y in top - bowl + 1..=top {
                    set(w, hx + dx, y, hz + dz, 0);
                }
                // A dirt bed under the water.
                set(w, hx + dx, top - bowl, hz + dz, dirt);
                set(w, hx + dx, top - bowl - 1, hz + dz, dirt);
            }
        }
        w.fill_basin((hx, top, hz), top, LIQ_WATER, 4000);
        keep_clear = Some((hx, hz, reach + 1));
    }

    // Tall grass and a few trees on the grass.
    let clear = |x: i32, z: i32| keep_clear.map_or(true, |(kx, kz, kr)| (x - kx).abs() > kr || (z - kz).abs() > kr);
    let reach = r as i32;
    for dz in -reach..=reach {
        for dx in -reach..=reach {
            let (x, z) = (cx + dx, cz + dz);
            let y = top;
            if w.in_bounds(x, y + 1, z) && w.get(x, y, z) == grass && w.get(x, y + 1, z) == 0 && clear(x, z) && rng.chance(0.6) {
                let plant = flora.ground(rng);
                if plant != 0 {
                    set(w, x, y + 1, z, plant);
                }
            }
        }
    }
    if trunk != 0 {
        for _ in 0..rng.range(1, 4) {
            let (x, z) = (cx + rng.range(-reach / 2, reach / 2 + 1), cz + rng.range(-reach / 2, reach / 2 + 1));
            let height = rng.range(5, 10);
            if !clear(x, z) || w.get(x, top, z) != grass || !w.in_bounds(x, top + height + 5, z) {
                continue;
            }
            for k in 1..=height {
                set(w, x, top + k, z, trunk);
            }
            let frame = rng.range(0, 3);
            w.decorations.push(Decoration { kind: "tree_top".into(), pos: (x, top + height + 1, z), style: TreeTops::of(w).forest(x, z, frame) });
        }
    }
}

/// Model directions after 0-3 quarter turns, as the game's Player.WALL_NORMALS:
/// a block with rotation r faces (or, hung on a wall, leans out) along [r].
pub const FACING: [(i32, i32); 4] = [(0, 1), (1, 0), (0, -1), (-1, 0)];

/// A Skyware house like Terraria's, its floor at `base` = (x, top, z) and its
/// door facing FACING[door]: 11 x 9 blocks, a blue Sunplate shell with gold
/// trim on its edges, lined with Disc Wall inside (Terraria's background), glass
/// windows on the long sides, two hanging Skyware lanterns, a World Banner on
/// the back wall and the Skyware chest (a "chest" decoration, style 1).
/// Rotations for the chest and banner are left as "rotation" decorations.
pub fn skyware_house(w: &mut World, base: (i32, i32, i32), door: i32) {
    let (hx, top, hz) = base;
    let or = |a: u16, b: u16| if a != 0 { a } else { b };
    let dirt = w.id_of("dirt");
    let plate = or(w.id_of("sunplate"), dirt);
    let trim = or(w.id_of("sunplate_trim"), plate);
    let disc = or(w.id_of("disc_wall"), plate);
    let glass = w.id_of("glass");
    let (lantern, banner, chest) = (w.id_of("skyware_lantern"), w.id_of("world_banner"), w.id_of("skyware_chest"));
    // Local axes: a along the door direction (the long side), b across.
    let f = FACING[door as usize];
    let sdir = (f.1, f.0);
    let (la, lb): (i32, i32) = (5, 4); // half length, half width
    let at = |a: i32, b: i32| (hx + f.0 * a + sdir.0 * b, hz + f.1 * a + sdir.1 * b);
    let face_index = |d: (i32, i32)| FACING.iter().position(|&x| x == d).unwrap_or(0) as i32;
    let set = |w: &mut World, a: i32, y: i32, b: i32, id: u16| {
        let (x, z) = at(a, b);
        if w.in_bounds(x, y, z) {
            let i = w.idx(x, y, z);
            w.blocks[i] = id;
            w.liquid[i] = 0;
        }
    };
    for a in -la..=la {
        for b in -lb..=lb {
            let (ea, eb) = (a.abs() == la, b.abs() == lb);
            let outer = ea || eb;
            let inner = !outer && (a.abs() == la - 1 || b.abs() == lb - 1);
            let corner = ea && eb;
            // Foundation and floor; clear the space above.
            set(w, a, top - 1, b, dirt);
            set(w, a, top, b, if outer { trim } else { plate });
            for y in top + 1..=top + 9 {
                set(w, a, y, b, 0);
            }
            // Walls: the Sunplate shell (gold trim at the corners), Disc Wall inside.
            for y in top + 1..=top + 5 {
                if outer {
                    set(w, a, y, b, if corner { trim } else { plate });
                } else if inner {
                    set(w, a, y, b, disc);
                }
            }
            // Disc Wall ceiling, Sunplate roof with gold trim round its edge and
            // chamfered corners.
            if !outer {
                set(w, a, top + 5, b, disc);
            }
            if !corner {
                set(w, a, top + 6, b, if outer { trim } else { plate });
            }
            if a.abs() <= la - 2 && b.abs() <= lb - 2 {
                set(w, a, top + 7, b, if a.abs() == la - 2 || b.abs() == lb - 2 { trim } else { plate });
            }
        }
    }
    // Doorway in the front wall (both layers).
    for y in top + 1..=top + 3 {
        set(w, la, y, 0, 0);
        set(w, la - 1, y, 0, 0);
    }
    // Windows: glass in the shell, an open sill in the lining.
    if glass != 0 {
        for side in [-1, 1] {
            for a in [-3, -2, 2, 3] {
                for y in top + 2..=top + 3 {
                    set(w, a, y, lb * side, glass);
                    set(w, a, y, (lb - 1) * side, 0);
                }
            }
        }
    }
    // Furnishings: lanterns hang under the ceiling, the banner on the back wall,
    // the chest against a long wall facing into the room.
    if lantern != 0 {
        for a in [-2, 2] {
            set(w, a, top + 4, 1, lantern);
        }
    }
    if banner != 0 {
        let (x, z) = at(-(la - 2), 0);
        set(w, -(la - 2), top + 3, 0, banner);
        w.decorations.push(Decoration { kind: "rotation".into(), pos: (x, top + 3, z), style: face_index(f) });
    }
    if chest != 0 {
        let (x, z) = at(0, -(lb - 2));
        set(w, 0, top + 1, -(lb - 2), chest);
        w.decorations.push(Decoration { kind: "chest".into(), pos: (x, top + 1, z), style: 1 });
        w.decorations.push(Decoration { kind: "rotation".into(), pos: (x, top + 1, z), style: face_index(sdir) });
    }
}

/// Terraria's Dungeon entrance, as its cross-section looks in game: a tall
/// keep of dungeon brick with towers at its corners and battlements between
/// them, one tall hall inside, and a long covered porch running out from its
/// door - a thick roof with its own battlements and a raised block at its far
/// end, on pillars, over a raised brick floor that steps down at the end. The
/// door faces FACING[door] (toward the world's centre). In the hall: pillars,
/// dungeon banners, chain lanterns and wall torches; the Dungeon itself
/// (dungeon.rs) opens the back of its floor into the entrance hallway. The
/// Old Man waits under the porch.
/// `ground` = (x, y, z): the hall floor is y.
/// Leaves decorations: "dungeon" (the entrance), "old_man" and "rotation" for
/// the banners and torches.
pub fn dungeon_entrance(w: &mut World, ground: (i32, i32, i32), door: i32, brick_name: &str) {
    let brick = w.id_of(brick_name);
    if brick == 0 {
        return;
    }
    let (x0, gy, z0) = ground;
    let f = FACING[door as usize];
    let s = (-f.1, f.0); // to the right of the front
    let at = |a: i32, b: i32| (x0 + f.0 * a + s.0 * b, z0 + f.1 * a + s.1 * b);
    let dir_of = |d: (i32, i32)| FACING.iter().position(|&x| x == d).unwrap_or(0) as u8;
    let set = |w: &mut World, a: i32, y: i32, b: i32, id: u16| {
        let (x, z) = at(a, b);
        if w.in_bounds(x, y, z) {
            let i = w.idx(x, y, z);
            w.blocks[i] = id;
            w.liquid[i] = 0;
            w.shapes.remove(&i);
        }
    };
    let shape = |w: &mut World, a: i32, y: i32, b: i32, sh: u8| {
        let (x, z) = at(a, b);
        if w.in_bounds(x, y, z) {
            let i = w.idx(x, y, z);
            w.shapes.insert(i, sh);
        }
    };
    // A battlement along a line of blocks: every other one, a block up.
    let merlon = |a: i32, b: i32| (a + b).rem_euclid(2) == 0;
    let lantern = w.id_of("chain_lantern");
    let banners: Vec<u16> = ["marching_bones_banner", "necromantic_sign", "ragged_brotherhood_sigil"].iter().map(|n| w.id_of(n)).filter(|&b| b != 0).collect();
    const H: i32 = 7; // half size of the keep (15 x 15)
    const WALL: i32 = 18; // the keep's roof, above the floor
    const TOWER: i32 = 22; // its corner towers' tops
    const PORCH: i32 = 17; // how far the porch runs out from the keep
    const PW: i32 = 5; // the porch's half width
    const UNDER: i32 = 8; // the porch roof's underside, above the floor
    // The site: clear it (and the trees on it) and lay a brick plinth down to
    // the ground, with a plaza at the end of the porch.
    let (amin, amax, bmin, bmax) = (-H - 2, H + PORCH + 6, -H - 2, H + 2);
    let mut area = Vec::new();
    for a in amin..=amax {
        for b in bmin..=bmax {
            area.push(at(a, b));
            for y in gy..gy + TOWER + 4 {
                set(w, a, y, b, 0);
            }
            for y in (gy - 14..gy).rev() {
                let (x, z) = at(a, b);
                if !w.in_bounds(x, y, z) {
                    break;
                }
                let solid_below = w.is_solid(x, y - 1, z) && y < gy - 1;
                set(w, a, y, b, brick);
                if solid_below {
                    break;
                }
            }
        }
    }
    w.decorations.retain(|d| !(d.kind == "tree_top" && area.contains(&(d.pos.0, d.pos.2))));
    // The keep: walls two thick round one tall hall, a flat roof with a
    // battlement round its edge, and corner towers (3 x 3) rising above it.
    for a in -H..=H {
        for b in -H..=H {
            let edge = a.abs().max(b.abs());
            let corner = a.abs() >= H - 2 && b.abs() >= H - 2;
            if edge >= H - 1 || corner {
                let top = if corner { TOWER } else { WALL };
                for y in gy..=gy + top {
                    set(w, a, y, b, brick);
                }
                if corner && (a.abs() == H || b.abs() == H) && merlon(a, b) {
                    set(w, a, gy + top + 1, b, brick);
                }
                if !corner && edge == H && merlon(a, b) {
                    set(w, a, gy + WALL + 1, b, brick);
                }
            } else {
                set(w, a, gy, b, brick); // floor
                set(w, a, gy + WALL, b, brick); // roof
            }
        }
    }
    // The porch: a raised brick floor out from the door, stepping down to the
    // plaza at its end; a roof two thick on pillars, a battlement along its
    // edges, and a raised block at its far end with its own battlement.
    for a in H + 1..=H + PORCH {
        for b in -PW..=PW {
            set(w, a, gy, b, brick);
            for y in gy + UNDER..=gy + UNDER + 1 {
                set(w, a, y, b, brick);
            }
            let end = a >= H + PORCH - 1;
            if end {
                for y in gy + UNDER + 2..=gy + UNDER + 4 {
                    set(w, a, y, b, brick);
                }
                if (b.abs() == PW || a == H + PORCH) && merlon(a, b) {
                    set(w, a, gy + UNDER + 5, b, brick);
                }
            } else if (b.abs() == PW) && merlon(a, b) {
                set(w, a, gy + UNDER + 2, b, brick);
            }
        }
    }
    // Pillars down its sides: by the keep, in the middle and at the end.
    for pa in [H + 1, H + PORCH / 2, H + PORCH - 2] {
        for a in pa..=pa + 1 {
            for b in [-PW, PW] {
                for y in gy + 1..gy + UNDER {
                    set(w, a, y, b, brick);
                }
            }
        }
    }
    for b in -PW..=PW {
        set(w, H + PORCH + 1, gy, b, brick);
        shape(w, H + PORCH + 1, gy, b, SHAPE_HALF);
    }
    // The door: at floor level in the keep's front wall, 5 wide, an arch of
    // upside-down ramps over it.
    let left_dir = dir_of((-s.0, -s.1));
    let right_dir = dir_of(s);
    for a in [H - 1, H] {
        for b in -2..=2 {
            for y in gy + 1..=gy + 6 {
                set(w, a, y, b, 0);
            }
        }
        set(w, a, gy + 6, -2, brick);
        set(w, a, gy + 6, 2, brick);
        shape(w, a, gy + 6, -2, SHAPE_CEILING + left_dir);
        shape(w, a, gy + 6, 2, SHAPE_CEILING + right_dir);
        set(w, a, gy + 7, -1, brick);
        set(w, a, gy + 7, 1, brick);
        shape(w, a, gy + 7, -1, SHAPE_CEILING + left_dir);
        shape(w, a, gy + 7, 1, SHAPE_CEILING + right_dir);
        set(w, a, gy + 7, 0, 0);
    }
    // Hall pillars, banners on the side walls (two rows), lanterns hanging
    // from the roof and under the porch roof.
    for (pa, pb) in [(2, -3), (2, 3), (-2, -3), (-2, 3)] {
        for y in gy + 1..gy + WALL {
            set(w, pa, y, pb, brick);
        }
    }
    for (k, a) in [3, 0, -3].iter().enumerate() {
        if banners.is_empty() {
            break;
        }
        for side in [-1, 1] {
            for (row, y) in [gy + 5, gy + 11].iter().enumerate() {
                let b = (H - 2) * side;
                let (x, z) = at(*a, b);
                set(w, *a, *y, b, banners[(k + row + (side > 0) as usize) % banners.len()]);
                // Hangs on the wall, facing into the hall.
                w.decorations.push(Decoration { kind: "rotation".into(), pos: (x, *y, z), style: dir_of((-s.0 * side, -s.1 * side)) as i32 });
            }
        }
    }
    if lantern != 0 {
        for (la, lb) in [(3, 0), (-1, 0), (0, -3), (0, 3)] {
            set(w, la, gy + WALL - 1, lb, lantern);
        }
        for la in [H + 4, H + 11] {
            for lb in [-2, 2] {
                set(w, la, gy + UNDER - 1, lb, lantern);
            }
        }
    }
    // Wall torches round the hall, between the banners; each faces out of its
    // wall (a wall torch's rotation is the way it leans out).
    let wall_torch = w.id_of("wall_torch");
    let torch = |w: &mut World, a: i32, y: i32, b: i32, out: (i32, i32)| {
        if wall_torch == 0 {
            return;
        }
        let (x, z) = at(a, b);
        if w.in_bounds(x, y, z) && w.get(x, y, z) == 0 {
            let i = w.idx(x, y, z);
            w.blocks[i] = wall_torch;
            w.decorations.push(Decoration { kind: "rotation".into(), pos: (x, y, z), style: FACING.iter().position(|&d| d == out).unwrap_or(0) as i32 });
        }
    };
    let (fw, bk, rt, lf) = ((-f.0, -f.1), f, (-s.0, -s.1), s); // out of the front, back, right, left walls
    for b in [-4, 4] {
        torch(w, H - 2, gy + 4, b, fw);
        torch(w, -H + 2, gy + 4, b, bk);
    }
    for a in [-2, 2] {
        torch(w, a, gy + 4, H - 2, rt);
        torch(w, a, gy + 4, -H + 2, lf);
        torch(w, a, gy + 10, H - 2, rt);
        torch(w, a, gy + 10, -H + 2, lf);
    }
    // The Old Man, under the porch by the door; the entrance itself.
    let (ox, oz) = at(H + 4, 3);
    w.decorations.push(Decoration { kind: "old_man".into(), pos: (ox, gy + 1, oz), style: 0 });
    w.decorations.push(Decoration { kind: "dungeon".into(), pos: (x0, gy, z0), style: door });
}

/// Where the Dungeon goes, like Terraria's: on the Snow's side of the world
/// (away from the Jungle), off to one side of it, near the coast. Returns
/// (x, ground y, z, door facing the world's centre).
pub fn dungeon_site(w: &World, seed: i32, coast: &Coast) -> Option<(i32, i32, i32, i32)> {
    let regions = biome_regions(w.sx, w.sz, seed);
    let &(_, snx, snz, snr) = regions.iter().find(|r| r.0 == BIOME_SNOW)?;
    let (cx, cz) = (w.sx as f32 / 2.0, w.sz as f32 / 2.0);
    let base = (snz as f32 - cz).atan2(snx as f32 - cx);
    for offset in [0.55f32, -0.55, 0.8, -0.8, 0.35, -0.35] {
        let ang = base + offset;
        // Out from the centre to just inside the beach.
        let mut dist = 20.0;
        let mut best = None;
        while dist < w.sx.max(w.sz) as f32 {
            let (x, z) = ((cx + ang.cos() * dist) as i32, (cz + ang.sin() * dist) as i32);
            if !w.in_bounds(x, 0, z) || coast.inland(x, z) < coast.ocean.width + coast.ocean.beach + 26.0 {
                break;
            }
            best = Some((x, z));
            dist += 4.0;
        }
        let Some((x, z)) = best else { continue };
        // Clear of the snow itself.
        if ((x - snx).pow(2) + (z - snz).pow(2)) < (snr + 16).pow(2) {
            continue;
        }
        let y = w.surface_y(x, z);
        if y <= 40 || y + 32 >= w.sy {
            continue;
        }
        // The door faces the world's centre (the nearest of the four ways).
        let (dx, dz) = (cx - x as f32, cz - z as f32);
        let door = if dx.abs() > dz.abs() { if dx > 0.0 { 1 } else { 3 } } else if dz > 0.0 { 0 } else { 2 };
        return Some((x, y, z, door));
    }
    None
}

/// A flat world for testing: stone, a few blocks of dirt, grass on top at
/// `ground` (the top grass block's y). Spawn is the centre of the surface.
pub fn generate_flat(w: &mut World, seed: i32, ground: i32) {
    let (sx, sy, sz) = (w.sx, w.sy, w.sz);
    let (stone, dirt, grass) = (w.id_of("stone"), w.id_of("dirt"), w.id_of("grass"));
    w.seed = seed;
    w.blocks.par_chunks_mut(sy as usize).for_each(|col| {
        for y in 0..=ground.min(sy - 1) {
            col[y as usize] = if y == ground { grass } else if y > ground - 4 { dirt } else { stone };
        }
    });
    w.spawn = (sx / 2, ground + 1, sz / 2);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::BlockDef;

    #[test]
    fn tree_top_variants() {
        // Zones like Terraria's: 2 / 3 / 4 by world size.
        for (sx, zones) in [(768, 2), (1152, 3), (1536, 4)] {
            let mut seen_snow = std::collections::HashSet::new();
            let mut seen_forest = std::collections::HashSet::new();
            for seed in 0..200 {
                let t = TreeTops::new(seed, sx);
                assert_eq!(t.forest.len(), zones);
                // Different styles, except that Terraria turns a plain one into
                // style 4 afterwards (so two zones can share 4).
                let mut f: Vec<i32> = t.forest.iter().copied().filter(|&v| v != 4).collect();
                let n = f.len();
                f.sort();
                f.dedup();
                assert!(f.len() == n && t.forest.iter().all(|&v| (0..6).contains(&v)), "zone styles {:?}", t.forest);
                // Zone 0 at the west edge, the last at the east, whatever z.
                for z in [0, 300, 700] {
                    assert_eq!(t.zone(5, z), 0);
                    assert_eq!(t.zone(sx - 5, z), zones - 1);
                }
                assert!(TreeTops::new(seed, sx).forest == t.forest, "same seed, same trees");
                seen_forest.extend(t.forest.iter().copied());
                seen_snow.insert(t.snow(sx / 4, 0) / 10);
                for x in [3, 50, sx / 2 + 7, sx - 9] {
                    let st = t.forest(x, 100, 2);
                    assert!(is_forest_canopy(st) && st % 10 == 2);
                    assert!([3, 10, 11, 12, 13].contains(&(t.snow(x, 1) / 10)));
                    assert!(!is_forest_canopy(t.snow(x, 1)) && !is_forest_canopy(t.jungle(0)));
                }
            }
            assert_eq!(seen_forest.len(), 6, "all six forest styles turn up");
            assert!(seen_snow.len() >= 4, "snow styles: {:?}", seen_snow);
        }
        // A whole world: its forest canopies follow its zones.
        let w = gen_world(31);
        let t = TreeTops::of(&w);
        let forest: Vec<&Decoration> = w.decorations.iter().filter(|d| d.kind == "tree_top" && is_forest_canopy(d.style)).collect();
        assert!(forest.len() > 50);
        assert!(forest.iter().all(|d| d.style / 10 == FOREST_SHEETS[t.forest_style(d.pos.0, d.pos.2) as usize]), "canopies match their zone");
    }

    #[test]
    fn gem_trees_in_the_caves() {
        let w = gen_world(5);
        let l = layers(w.sy);
        let trunks: Vec<u16> = GEMS.iter().map(|g| w.id_of(&format!("{}_tree_trunk", g))).collect();
        let (stone, ebon, crim) = (w.id_of("stone"), w.id_of("ebonstone"), w.id_of("crimstone"));
        let tops: Vec<&Decoration> = w.decorations.iter().filter(|d| d.kind == "tree_top" && (GEM_CANOPY..GEM_CANOPY + 7).contains(&(d.style / 10))).collect();
        assert!(tops.len() > 20, "gem trees grow in the caves ({})", tops.len());
        let mut kinds = std::collections::HashSet::new();
        for d in tops {
            let gem = (d.style / 10 - GEM_CANOPY) as usize;
            kinds.insert(gem);
            let (x, z) = (d.pos.0, d.pos.2);
            let mut y = d.pos.1 - 1;
            let mut h = 0;
            while w.get(x, y, z) == trunks[gem] {
                h += 1;
                y -= 1;
            }
            assert!((7..=12).contains(&h), "a {} tree {} tall at {:?}", GEMS[gem], h, d.pos);
            assert!([stone, ebon, crim].contains(&w.get(x, y, z)) && y < l.surface_base - 8 && y > l.underworld_top, "on stone, underground");
            assert!((1..=GEM_TOP_ROOM).all(|k| w.get(x, d.pos.1 + k - 1, z) == 0), "room for its top");
            assert!(!w.decorations.iter().any(|f| f.kind == "waterfall" && f.pos.1 > y && (f.pos.0 - x).abs() <= 3 && (f.pos.2 - z).abs() <= 3), "no waterfall pouring through it");
        }
        assert!(kinds.len() >= 5, "several gems ({:?})", kinds);
    }

    #[test]
    fn vanity_and_ash_trees() {
        let w = gen_world(5);
        let l = layers(w.sy);
        let (grass, sakura, willow) = (w.id_of("grass"), w.id_of("sakura_trunk"), w.id_of("willow_trunk"));
        let (ash, ash_grass, ash_trunk) = (w.id_of("ash"), w.id_of("ash_grass"), w.id_of("ash_trunk"));
        let trunk_of = |d: &Decoration| -> (u16, i32, u16) {
            let (x, z) = (d.pos.0, d.pos.2);
            let t = w.get(x, d.pos.1 - 1, z);
            let mut y = d.pos.1 - 1;
            let mut h = 0;
            while w.get(x, y, z) == t {
                h += 1;
                y -= 1;
            }
            (t, h, w.get(x, y, z))
        };
        // Vanity trees: about 1 in 20 of the forest's trees on grass, 7-12 tall.
        let vanity: Vec<&Decoration> = w.decorations.iter().filter(|d| d.kind == "tree_top" && (d.style / 10 == SAKURA_CANOPY || d.style / 10 == WILLOW_CANOPY)).collect();
        let forest = w.decorations.iter().filter(|d| d.kind == "tree_top" && is_forest_canopy(d.style)).count();
        assert!(!vanity.is_empty() && (vanity.len() as f32) < forest as f32 * 0.12, "vanity trees: {} of {}", vanity.len(), forest + vanity.len());
        for d in &vanity {
            let (t, h, ground) = trunk_of(d);
            let want = if d.style / 10 == SAKURA_CANOPY { sakura } else { willow };
            assert!(t == want && (7..=12).contains(&h) && ground == grass, "a vanity tree at {:?}: {} {} on {}", d.pos, t, h, ground);
        }
        assert!(vanity.iter().any(|d| d.style / 10 == SAKURA_CANOPY) && vanity.iter().any(|d| d.style / 10 == WILLOW_CANOPY) || vanity.len() < 4);
        // Ash grass on the Underworld's open ash, in the outer ring only; ash trees on it.
        let mut ring_grass = 0;
        for z in (0..w.sz).step_by(3) {
            for x in (0..w.sx).step_by(3) {
                for y in 1..l.underworld_top {
                    if w.get(x, y, z) == ash_grass {
                        assert!(in_ash_ring(&w, x, z) && w.get(x, y + 1, z) != ash && w.get(x, y + 1, z) != ash_grass, "ash grass where it may be");
                        ring_grass += 1;
                    }
                    if w.get(x, y, z) == ash && in_ash_ring(&w, x, z) {
                        assert!(w.get(x, y + 1, z) != 0 || w.liquid_at(x, y + 1, z).1 > 0, "open ash in the ring turned to grass");
                    }
                }
            }
        }
        assert!(ring_grass > 500, "ash grass ({})", ring_grass);
        let ash_tops: Vec<&Decoration> = w.decorations.iter().filter(|d| d.kind == "tree_top" && d.style / 10 == ASH_CANOPY).collect();
        assert!(ash_tops.len() > 10, "ash trees ({})", ash_tops.len());
        for d in ash_tops {
            let (t, h, ground) = trunk_of(d);
            assert!(t == ash_trunk && (7..=12).contains(&h) && ground == ash_grass && d.pos.1 - h - 1 < l.underworld_top, "an ash tree at {:?}", d.pos);
        }
    }

    #[test]
    fn living_trees() {
        let mut w = gen_world_sized(5, 0, (256, 384, 256));
        let (wood, leaves, grass, chest) = (w.id_of("living_wood"), w.id_of("leaf_block"), w.id_of("grass"), w.id_of("chest"));
        // Make the leaves let the sun through, as the game does.
        let mut def = w.def(leaves).clone();
        def.sun_through = true;
        w.set_def(leaves, def);
        // A grass spot with room (the 256 world may well have no grove of its own).
        let mut site = None;
        'find: for z in (40..216).step_by(4) {
            for x in (40..216).step_by(4) {
                if living_tree_site(&w, x, z, grass) && w.decorations.iter().all(|d| (d.pos.0 - x).abs() > 30 || (d.pos.2 - z).abs() > 30 || d.kind != "chest") {
                    site = Some((x, z));
                    break 'find;
                }
            }
        }
        let (x, z) = site.expect("a site for a living tree");
        let g = w.surface_y(x, z);
        let mut rng = Rng::new(9);
        clear_trees_near(&mut w, x, z, 22);
        grow_living_tree(&mut w, &mut rng, (x, g, z), wood, leaves);
        living_tree_passage(&mut w, &mut rng, (x, g, z), wood, chest);
        // A trunk of living wood rising well above the ground (Terraria's are 4-5 wide).
        // (Rows with living wood near the axis: it shifts over as it narrows.)
        let near_axis = |w: &World, yy: i32| (-3..=3).any(|dz: i32| (-3..=3).any(|dx: i32| w.get(x + dx, yy, z + dz) == wood));
        let mut h = 0;
        while near_axis(&w, g + 6 + h) {
            h += 1;
        }
        assert!(h > 20, "trunk height {}", h);
        let base_cells = (-3..=3).flat_map(|dz| (-3..=3).map(move |dx| (dx, dz))).filter(|&(dx, dz)| w.get(x + dx, g + 6, z + dz) == wood).count();
        assert!((9..=25).contains(&base_cells), "a round trunk 4-5 across ({} cells)", base_cells);
        // Leaves high up, roots in the ground.
        let mut leaf_cells = 0;
        let mut root_cells = 0;
        for dz in -30..=30 {
            for dx in -30..=30 {
                for yy in g - 40..g + 100 {
                    match w.get(x + dx, yy, z + dz) {
                        b if b == leaves => leaf_cells += 1,
                        b if b == wood && yy < g - 2 => root_cells += 1,
                        _ => {}
                    }
                }
            }
        }
        assert!(leaf_cells > 3000 && root_cells > 40, "leaves {} roots {}", leaf_cells, root_cells);
        // No leaf left floating: each touches another leaf or the wood by a face.
        let faces = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)];
        for dz in -30..=30 {
            for dx in -30..=30 {
                for yy in g..g + 100 {
                    let (cx, cz) = (x + dx, z + dz);
                    if w.get(cx, yy, cz) == leaves {
                        assert!(faces.iter().any(|&(fx, fy, fz)| [leaves, wood].contains(&w.get(cx + fx, yy + fy, cz + fz))), "a floating leaf at {:?}", (cx, yy, cz));
                    }
                }
            }
        }
        // The passage: a chest in a room below, the doorway open at the ground.
        assert!(w.decorations.iter().any(|d| d.kind == "chest" && (d.pos.0 - x).abs() < 40 && (d.pos.2 - z).abs() < 40 && d.pos.1 < g - 10
            && w.get(d.pos.0, d.pos.1, d.pos.2) == chest && w.get(d.pos.0, d.pos.1 - 1, d.pos.2) == wood), "a root room with a chest on its living wood floor");
        assert!((1..=3).all(|h| (-4..=4).any(|dz: i32| (-4..=4).any(|dx: i32| w.get(x + dx, g + h, z + dz) == 0 && (dx.abs() <= 1 && dz.abs() <= 1)))), "the doorway is open at the ground");
        // The sun comes through the leaves: the air under them is sunlit.
        w.snapshot_sky_floor();
        w.compute_all_light();
        let under = (1..=8).map(|k| (x + k, z)).find_map(|(ax, az)| {
            let mut yy = g + 60;
            while yy > g && w.get(ax, yy, az) != leaves {
                yy -= 1;
            }
            (yy > g && w.get(ax, yy - 1, az) == 0).then_some((ax, yy - 1, az))
        });
        if let Some((ax, ay, az)) = under {
            assert_eq!(crate::world::unpack_light(w.light_at(ax, ay, az))[0], 15, "sunlit under the leaves");
        }
    }

    #[test]
    fn jungle_cave_trees_grow() {
        let w = gen_world(5);
        let l = layers(w.sy);
        let (jgrass, trunk) = (w.id_of("jungle_grass"), w.id_of("jungle_cave_trunk"));
        let tops: Vec<&Decoration> = w.decorations.iter().filter(|d| d.kind == "tree_top" && d.style / 10 == JUNGLE_CAVE_CANOPY).collect();
        assert!(!tops.is_empty(), "mahogany trees in the underground jungle ({})", tops.len());
        for d in tops {
            let (x, z) = (d.pos.0, d.pos.2);
            let mut y = d.pos.1 - 1;
            let mut h = 0;
            while w.get(x, y, z) == trunk {
                h += 1;
                y -= 1;
            }
            assert!((5..=14).contains(&h) && w.get(x, y, z) == jgrass && y < l.surface_base - 8, "a tree {} tall on {} at {:?}", h, w.get(x, y, z), d.pos);
            assert!((0..7).all(|k| !w.is_solid(x, d.pos.1 + k, z)), "room for its top");
        }
    }

    #[test]
    fn living_mahogany_trees() {
        let w = gen_world_sized(5, 0, (384, 384, 384));
        let (wood, leaves, chest) = (w.id_of("living_mahogany"), w.id_of("mahogany_leaves"), w.id_of("chest"));
        let regions = biome_regions(w.sx, w.sz, 5);
        let &(_, jx, jz, jr) = regions.iter().find(|r| r.0 == BIOME_JUNGLE).unwrap();
        let (mut woods, mut leafs) = (0, 0);
        for z in (jz - jr).max(0)..(jz + jr).min(w.sz) {
            for x in (jx - jr).max(0)..(jx + jr).min(w.sx) {
                for y in 0..w.sy {
                    match w.get(x, y, z) {
                        b if b == wood => woods += 1,
                        b if b == leaves => leafs += 1,
                        _ => {}
                    }
                }
            }
        }
        assert!(woods > 2000 && leafs > 500, "living mahogany trees in the underground jungle (wood {}, leaves {})", woods, leafs);
        // Each has its Ivy Chest in its hollow foot, on living mahogany.
        let ivy = w.id_of("ivy_chest");
        let chests = w.decorations.iter().filter(|d| d.kind == "chest" && d.style == 2 && w.get(d.pos.0, d.pos.1, d.pos.2) == ivy && w.get(d.pos.0, d.pos.1 - 1, d.pos.2) == wood).count();
        assert!(chests >= 3 && chest != 0, "an Ivy Chest (jungle loot) in each tree's foot ({})", chests);
    }

    #[test]
    fn palm_trees_on_the_beach() {
        let w = gen_world(5);
        let coast = Coast::new(w.seed, w.sx, w.sy, w.sz);
        let (palm, sand) = (w.id_of("palm_trunk"), w.id_of("sand"));
        let tops: Vec<&Decoration> = w.decorations.iter().filter(|d| d.kind == "tree_top" && d.style / 10 == PALM_CANOPY).collect();
        assert!(tops.len() > 10, "palms grow on the beach ({})", tops.len());
        for d in tops {
            let (x, z) = (d.pos.0, d.pos.2);
            // A trunk of 10-20 palm cells on sand, the canopy right above it.
            let mut y = d.pos.1 - 1;
            let mut h = 0;
            while w.get(x, y, z) == palm {
                h += 1;
                y -= 1;
            }
            assert!((10..=20).contains(&h) && w.get(x, y, z) == sand, "palm at {:?}: {} tall on {}", d.pos, h, w.get(x, y, z));
            let inland = coast.inland(x, z);
            assert!(inland >= coast.ocean.width && inland <= coast.ocean.width + coast.ocean.beach, "on the beach");
            assert!(d.style % 10 < 3);
        }
        // No palms inland, no forest trees on the sand.
        assert!(w.decorations.iter().filter(|d| d.kind == "tree_top" && (is_forest_canopy(d.style) || d.style / 10 == SAKURA_CANOPY || d.style / 10 == WILLOW_CANOPY))
            .all(|d| coast.inland(d.pos.0, d.pos.2) > coast.ocean.width + coast.ocean.beach * 0.5));
    }

    fn gen_world(seed: i32) -> World {
        gen_world_evil(seed, 0)
    }

    fn gen_world_evil(seed: i32, evil: i32) -> World {
        gen_world_sized(seed, evil, (256, 256, 256))
    }

    /// Enchanted Sword Shrines (EnchantedSwordBiome): a grass-lined cave with
    /// a dirt mound, the sword in stone on it, water round it, vines from its
    /// ceiling, and a shaft open to the sky, deep under the outer map.
    #[test]
    fn sword_shrines_are_built_like_terrarias() {
        let mut w = gen_world_sized(7, 0, (384, 384, 384));
        let l = layers(w.sy);
        let mut rng = Rng::new(99);
        let mut tries = 0;
        while !w.decorations.iter().any(|d| d.kind == "sword_shrine") && tries < 40 {
            crate::shrines::sword_shrines(&mut w, &mut rng, &l);
            tries += 1;
        }
        let shrines: Vec<(i32, i32, i32)> = w.decorations.iter().filter(|d| d.kind == "sword_shrine").map(|d| d.pos).collect();
        assert!(!shrines.is_empty(), "no shrine placed in {tries} passes");
        let id = |n: &str| w.id_of(n);
        for &(x, y, z) in &shrines {
            assert_eq!(w.get(x, y, z), id("sword_in_stone"), "the sword in stone at {:?}", (x, y, z));
            assert_eq!(w.get(x, y - 1, z), id("grass"), "it stands on the grass over the mound");
            assert_eq!(w.get(x, y - 2, z), id("dirt"), "the mound is dirt");
            // 50 to 99 below the surface line (its room's top), in the outer map.
            let top = y + 15;
            assert!(top <= l.surface_base - 50 && top >= l.surface_base - 99, "depth: room top {top}, surface line {}", l.surface_base);
            let (cx, cz) = (w.sx as f32 / 2.0, w.sz as f32 / 2.0);
            assert!(((x as f32 - cx).abs() / cx).max((z as f32 - cz).abs() / cz) >= 0.4, "in the outer map");
            // The room round the mound: open, grass-lined, with water low down and vines.
            let (mut water, mut vines, mut grass) = (0, 0, 0);
            for dx in -24..=24 {
                for dz in -24..=24 {
                    for dy in -16..=15 {
                        let (px, py, pz) = (x + dx, y + dy, z + dz);
                        let b = w.get(px, py, pz);
                        if w.liquid_at(px, py, pz).1 > 0 {
                            water += 1;
                        }
                        if b == id("vine_flowers") {
                            vines += 1;
                        }
                        if b == id("grass") {
                            grass += 1;
                        }
                    }
                }
            }
            assert!(water > 500 && vines > 20 && grass > 1000, "pools ({water}), vines ({vines}), a grass lining ({grass})");
            // The shaft: open from the room's top up through the surface (to
            // Space, above the highest mountain; a floating island may hang
            // over it).
            let blocked: Vec<i32> = (top..l.space_top).filter(|&q| w.is_solid(x, q, z)).collect();
            assert!(blocked.is_empty(), "the shaft above {:?} is open to the sky (solid at {:?})", (x, y, z), blocked);
            // Its mouth: wide, with wall torches on its sides leaning in over it.
            let torches: Vec<&Decoration> = w
                .decorations
                .iter()
                .filter(|d| d.kind == "rotation" && w.get(d.pos.0, d.pos.1, d.pos.2) == id("wall_torch"))
                .filter(|d| (d.pos.0 - x).abs() <= 2 && (d.pos.2 - z).abs() <= 2 && d.pos.1 > top)
                .collect();
            assert!(torches.len() >= 3, "wall torches round the mouth ({})", torches.len());
            for t in &torches {
                let (fx, fz) = FACING[t.style as usize];
                assert_eq!((t.pos.0 + fx * 2, t.pos.2 + fz * 2), (x, z), "a torch leans in over the shaft");
                assert!(w.is_solid(t.pos.0 - fx, t.pos.1, t.pos.2 - fz), "on the wall");
                for (dx, dz) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)] {
                    assert!(!w.is_solid(x + dx, t.pos.1, z + dz), "the mouth is 5 across at the torches");
                }
            }
        }
    }

    fn gen_world_sized(seed: i32, evil: i32, size: (i32, i32, i32)) -> World {
        let mut w = World::new();
        for (i, name) in ["dirt", "stone", "grass", "copper_ore", "iron_ore", "tree_trunk", "cloud", "sunplate", "skyware_chest", "sunplate_trim", "disc_wall", "ebonstone", "corrupt_grass", "crimstone", "crimson_grass", "sand", "mud", "clay", "tall_grass", "snow_block", "ice_block", "hardened_sand", "sandstone", "cactus", "jungle_grass", "jungle_plants", "jungle_spores", "boreal_trunk", "mahogany_trunk", "taller_grass", "flowers", "tall_flowers", "mushroom", "daybloom", "sunflower", "small_rocks", "twigs", "large_rocks", "fallen_log", "vines", "vine_flowers", "lily_pad", "cattail", "cattail_stem", "cattail_top", "cobweb", "blue_brick", "green_brick", "pink_brick", "chain_lantern", "sign", "wall_torch",
            "marching_bones_banner", "necromantic_sign", "ragged_brotherhood_sigil", "palm_trunk",
            "topaz_tree_trunk", "amethyst_tree_trunk", "sapphire_tree_trunk", "emerald_tree_trunk", "ruby_tree_trunk", "diamond_tree_trunk", "amber_tree_trunk",
            "ash", "ash_grass", "sakura_trunk", "willow_trunk", "ash_trunk", "living_wood", "leaf_block", "chest", "jungle_cave_trunk", "living_mahogany", "mahogany_leaves", "ivy_chest", "sword_in_stone"].iter().enumerate() {
            // The forest's plants and debris (and the dungeon's furnishings)
            // are sprites you walk through.
            let plant = (i >= 29 || ["jungle_plants", "jungle_spores"].contains(name)) && !name.ends_with("_brick") && !name.ends_with("_trunk");
            w.set_def(
                i as u16 + 1,
                BlockDef {
                    name: name.to_string(),
                    // Tree trunks are cutout sprites in the game, like plants
                    // solid but not ground.
                    render: if plant {
                        crate::world::RENDER_CROSS
                    } else if name.ends_with("_trunk") {
                        crate::world::RENDER_CUTOUT
                    } else {
                        RENDER_CUBE
                    },
                    solid: !plant,
                    opaque: !plant,
                    variants: 1,
                    ..Default::default()
                },
            );
        }
        crate::cabins::tests::add_cabin_defs(&mut w);
        crate::dungeon::tests::add_dungeon_defs(&mut w);
        for name in ["silt", "slush"] {
            let id = w.defs.len() as u16;
            w.set_def(id, BlockDef { name: name.into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        }
        w.resize(size.0, size.1, size.2);
        w.gen_evil = evil;
        generate(&mut w, seed, &AtomicU32::new(0));
        w
    }

    #[test]
    fn worlds_get_underground_cabins() {
        let w = gen_world(7);
        let l = layers(w.sy);
        let kinds: Vec<u16> = ["gold_chest", "frozen_chest", "sandstone_chest", "rich_mahogany_chest"].iter().map(|n| w.id_of(n)).collect();
        let cabins: Vec<_> = w.decorations.iter().filter(|d| d.kind == "chest" && (3..=6).contains(&d.style)).collect();
        // 35-40 per 640 x 640: 6 in this 256 x 256 world, if the caves have room.
        assert!(cabins.len() >= 3, "{} cabins", cabins.len());
        for d in &cabins {
            let (x, y, z) = d.pos;
            assert!(kinds.contains(&w.get(x, y, z)), "each holds its kind's chest");
            assert!(y < l.surface_base - 9 && y > l.underworld_top, "underground, above the Underworld (y {y})");
            assert!(w.surface_y(x, z) > y + 5, "under the ground");
        }
    }

    #[test]
    fn forest_gets_its_plants_and_debris() {
        let w = gen_world(42);
        let count = |name: &str| {
            let id = w.id_of(name);
            w.blocks.iter().filter(|&&b| b == id).count()
        };
        for (name, least) in [("tall_grass", 2000), ("taller_grass", 800), ("flowers", 500), ("tall_flowers", 250), ("mushroom", 10),
                ("daybloom", 5), ("sunflower", 10), ("small_rocks", 20), ("twigs", 10), ("vines", 3)] {
            assert!(count(name) >= least, "{name}: {} (want {least})", count(name));
        }
        // Plants stand on grass, vines hang; pond plants sit in or on water.
        let (grass, vines, lily, cattail) = (w.id_of("grass"), w.id_of("vines"), w.id_of("lily_pad"), w.id_of("cattail"));
        for name in ["flowers", "sunflower", "daybloom"] {
            let id = w.id_of(name);
            for z in 0..w.sz {
                for x in 0..w.sx {
                    for y in 1..w.sy {
                        if w.get(x, y, z) == id {
                            assert_eq!(w.get(x, y - 1, z), grass, "{name} at {x},{y},{z} stands on grass");
                        }
                    }
                }
            }
        }
        let mut hanging = 0;
        let mut on_water = 0;
        for z in 0..w.sz {
            for x in 0..w.sx {
                for y in 1..w.sy - 1 {
                    let b = w.get(x, y, z);
                    let above = w.get(x, y + 1, z);
                    if b == vines && (w.is_solid(x, y + 1, z) || above == vines || above == w.id_of("vine_flowers")) {
                        hanging += 1;
                    }
                    if (b == lily && w.liquid_at(x, y - 1, z).1 > 0) || (b == cattail && w.liquid_at(x, y, z).1 > 0) {
                        on_water += 1;
                    }
                }
            }
        }
        assert!(hanging == count("vines"), "vines hang from a block or another vine ({hanging} of {})", count("vines"));
        assert!(on_water > 0 && on_water == count("lily_pad") + count("cattail"), "pond plants in ponds ({on_water})");
    }

    /// The Dungeon (dungeon.rs): reached from its entrance down a hallway,
    /// rooms and halls of brick deep below, doors, platforms, shelves,
    /// chests in Terraria's order, lights with their switches, banners and
    /// spikes, and the entrance above its floor left as it was built.
    #[test]
    fn the_dungeon_is_built_under_its_entrance() {
        let w = gen_world_sized(42, 0, (384, 384, 384));
        let l = layers(w.sy);
        let id = |n: &str| w.id_of(n);
        let (keep, door) = w.decorations.iter().find(|d| d.kind == "dungeon").map(|d| (d.pos, d.style)).expect("a Dungeon");
        let (x0, gy, z0) = keep;
        let brick = ["blue_brick", "green_brick", "pink_brick"].iter().map(|n| id(n)).find(|&b| w.get(x0, gy, z0 + 3) == b || w.get(x0 + 3, gy, z0) == b).expect("brick floor");
        let count = |b: u16| w.blocks.iter().filter(|&&c| c == b).count();
        assert!(count(brick) > 150_000, "a mass of dungeon brick ({})", count(brick));
        let (lo, hi) = *w.structures.last().expect("the Dungeon is a protected structure");
        assert!(lo.1 >= l.underworld_top - 6 && hi.1 < gy + 30, "between the underworld and the surface: {lo:?} {hi:?}");
        // Walk from the hall floor through open cells, doors and platforms.
        // (Spikes too: you can walk over them, if it hurts.)
        let pass = |b: u16| b == 0 || !w.def(b).solid || [id("dungeon_door"), id("door_top"), id("blue_dungeon_door"), id("green_dungeon_door"), id("pink_dungeon_door"), id("spike")].contains(&b);
        let f = FACING[door as usize];
        let s = (-f.1, f.0);
        let start = (x0 + f.0 * 0 + s.0 * 2, gy + 1, z0 + f.1 * 0 + s.1 * 2);
        let mut seen = std::collections::HashSet::new();
        let mut queue = std::collections::VecDeque::from([start]);
        seen.insert(start);
        let mut deepest = gy;
        while let Some(p) = queue.pop_front() {
            deepest = deepest.min(p.1);
            for d in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                let n = (p.0 + d.0, p.1 + d.1, p.2 + d.2);
                if n.0 < lo.0 || n.0 > hi.0 || n.2 < lo.2 || n.2 > hi.2 || n.1 < lo.1 || n.1 > gy + 18 || seen.contains(&n) {
                    continue;
                }
                if pass(w.get(n.0, n.1, n.2)) {
                    seen.insert(n);
                    queue.push_back(n);
                }
            }
        }
        assert!(deepest < depth_y_t(&l, 230.0), "the Dungeon goes deep, reached from the entrance (to y {deepest})");
        let chests: Vec<_> = w.decorations.iter().filter(|d| d.kind == "chest" && d.style >= crate::dungeon::DUNGEON_LOOT).collect();
        assert!(chests.len() >= 5, "a chest in each room ({})", chests.len());
        let reached = chests.iter().filter(|d| seen.contains(&(d.pos.0, d.pos.1 + 1, d.pos.2))).count();
        assert!(reached * 2 >= chests.len(), "most chests reached from the entrance ({reached} of {})", chests.len());
        for c in &chests {
            let b = w.get(c.pos.0, c.pos.1, c.pos.2);
            let key = c.style == crate::dungeon::DUNGEON_LOOT + 6;
            assert_eq!(b, if key { id("chest") } else { id("locked_gold_chest") }, "a locked Gold Chest (a wooden one with the key) at {:?}", c.pos);
            assert!(w.is_solid(c.pos.0, c.pos.1 - 1, c.pos.2), "on the floor");
        }
        // In Terraria's order, a shallow chest being a key chest.
        let deep: Vec<i32> = chests.iter().map(|c| c.style).collect();
        assert_eq!(deep[0], crate::dungeon::DUNGEON_LOOT, "the first chest holds the Muramasa (or a key near the top): {deep:?}");
        let doors: Vec<_> = (0..w.blocks.len()).filter(|&i| w.blocks[i] == id("dungeon_door") || [id("blue_dungeon_door"), id("green_dungeon_door"), id("pink_dungeon_door")].contains(&w.blocks[i])).collect();
        assert!(doors.len() >= 5, "doors in the halls ({})", doors.len());
        for &i in &doors {
            let (x, y, z) = unflat(&w, i);
            assert_eq!(w.get(x, y + 1, z), id("door_top"), "a door's top half over it");
            assert!(w.is_solid(x, y - 1, z), "a door stands on the floor");
        }
        let platform = id(&format!("{}_platform", w.def(brick).name));
        assert!(count(platform) > 20, "platforms across the shafts ({})", count(platform));
        let shelves: usize = ["metal_shelf", "brass_shelf", "wood_shelf", "dungeon_shelf"].iter().map(|n| count(id(n))).sum();
        assert!(shelves > 30 && count(id("book")) > 20, "shelves ({shelves}) with books ({})", count(id("book")));
        assert!(count(id("spike")) > 200, "spikes ({})", count(id("spike")));
        let banners: usize = ["marching_bones_banner", "necromantic_sign", "rusted_company_standard", "ragged_brotherhood_sigil", "molten_legion_flag", "diabolic_sigil"].iter().map(|n| count(id(n))).sum();
        assert!(banners > 20, "banners ({banners})");
        // Each switch is wired to a light.
        let switches: Vec<_> = w.decorations.iter().filter(|d| d.kind == "switch").collect();
        assert!(switches.len() >= 10, "lights with switches ({})", switches.len());
        for sw in &switches {
            assert_eq!(w.get(sw.pos.0, sw.pos.1, sw.pos.2), id("switch"));
            let o = (sw.style & 31, (sw.style >> 5) & 31, sw.style >> 10);
            let light = (sw.pos.0 + o.0 - 16, sw.pos.1 + o.2, sw.pos.2 + o.1 - 16);
            let name = w.def(w.get(light.0, light.1, light.2)).name.clone();
            assert!(name.contains("lantern") || name.contains("lamp") || name.contains("sconse") || name.contains("chandelier"), "switch at {:?} wired to a light, not {name}", sw.pos);
        }
        // The entrance above its floor is as it was built: its towers and
        // hall pillars stand, its door is open.
        let at = |a: i32, b: i32| (x0 + f.0 * a + s.0 * b, z0 + f.1 * a + s.1 * b);
        let (tx, tz) = at(7, 7);
        assert!(w.get(tx, gy + 22, tz) == brick && w.get(at(2, 3).0, gy + 3, at(2, 3).1) == brick, "the keep stands");
        assert_eq!(w.get(at(7, 0).0, gy + 2, at(7, 0).1), 0, "the doorway is open");
    }

    fn depth_y_t(l: &Layers, d: f64) -> i32 {
        crate::dungeon::depth_y(l, d)
    }

    /// A cell's position from its index (World::idx).
    fn unflat(w: &World, i: usize) -> (i32, i32, i32) {
        let i = i as i32;
        ((i / w.sy) % w.sx, i % w.sy, i / (w.sy * w.sx))
    }

    #[test]
    fn the_dungeon_entrance_stands_on_the_snow_side() {
        let w = gen_world(42);
        let deco = |kind: &str| w.decorations.iter().find(|d| d.kind == kind).map(|d| (d.pos, d.style));
        let ((x, gy, z), door) = deco("dungeon").expect("the world has a Dungeon entrance");
        assert!(deco("old_man").is_some(), "the Old Man waits there");
        let bricks: usize = ["blue_brick", "green_brick", "pink_brick"].iter().map(|n| {
            let id = w.id_of(n);
            w.blocks.iter().filter(|&&b| b == id).count()
        }).sum();
        assert!(bricks > 3000, "a keep of dungeon brick ({bricks})");
        // On the Snow's side of the world, inland of the beach.
        let regions = biome_regions(w.sx, w.sz, w.seed);
        let snow = regions.iter().find(|r| r.0 == BIOME_SNOW).unwrap();
        let (cx, cz) = (w.sx / 2, w.sz / 2);
        assert!((x - cx) * (snow.1 - cx) + (z - cz) * (snow.2 - cz) > 0, "the dungeon is on the snow's side");
        let coast = Coast::new(w.seed, w.sx, w.sy, w.sz);
        assert!(coast.inland(x, z) > coast.ocean.width + coast.ocean.beach, "inland of the beach");
        // The door (5 wide, 6 high) faces the centre and is open; the hall
        // behind it is open; a shaft goes down from the hall.
        let f = FACING[door as usize];
        let s = (-f.1, f.0);
        let at = |a: i32, b: i32| (x + f.0 * a + s.0 * b, z + f.1 * a + s.1 * b);
        assert!((cx - x) * f.0 + (cz - z) * f.1 > 0, "the door faces the world's centre");
        for b in -2..=2 {
            for y in gy + 1..=gy + 5 {
                let (px, pz) = at(7, b);
                assert_eq!(w.get(px, y, pz), 0, "the doorway is open at {b},{y}");
            }
        }
        let (hx, hz) = at(-2, 0);
        assert!(!w.is_solid(hx, gy, hz), "the back of the hall floor opens into the Dungeon's hallway");
        // The overhang: the upper front juts out over the door, open below.
        let (ox, oz) = at(17, 0);
        assert!(w.is_solid(ox, gy + 8, oz) && !w.is_solid(ox, gy + 3, oz) && w.is_solid(ox, gy, oz), "a long covered porch out from the door");
        let (tx, tz) = at(7, 7);
        assert!(w.is_solid(tx, gy + 22, tz), "corner towers rise above the keep");
        // The arch's corners are upside-down ramps.
        let (ax, az) = at(7, -2);
        assert!(w.shape_at(ax, gy + 6, az) >= crate::world::SHAPE_CEILING, "an arched doorway");
    }

    #[test]
    fn caves_get_cobwebs_in_their_corners() {
        let w = gen_world(42);
        let web = w.id_of("cobweb");
        let surface = layers(w.sy).surface_base;
        // Cabins' cobwebs hang anywhere in their rooms (Terraria's AgeRoom):
        // a room's walls are the first thing each way, lined with Planked Wall.
        let cabin = [w.id_of("planked_wall"), w.id_of("wood"), w.id_of("boreal_wood_wall"), w.id_of("boreal_wood"), w.id_of("rich_mahogany_wall"), w.id_of("rich_mahogany"), w.id_of("sandstone_wall")];
        let in_cabin = |x: i32, y: i32, z: i32| {
            [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|&(dx, dz)| {
                (1..24).map(|k| w.get(x + dx * k, y, z + dz * k)).find(|&b| b != 0 && b != web).map_or(false, |b| cabin.contains(&b))
            })
        };
        let mut webs = 0;
        let mut cornered = 0;
        for z in 0..w.sz {
            for x in 0..w.sx {
                for y in 1..w.sy - 1 {
                    if w.get(x, y, z) == web && !in_cabin(x, y, z) {
                        webs += 1;
                        assert!(y < surface, "cobweb at {x},{y},{z} is underground");
                        let sides = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 0, -1)].iter()
                            .filter(|&&(dx, dy, dz)| w.is_solid(x + dx, y + dy, z + dz) || w.get(x + dx, y + dy, z + dz) == web).count();
                        if sides >= 2 {
                            cornered += 1;
                        }
                    }
                }
            }
        }
        assert!(webs > 100, "cobwebs: {webs}");
        assert!(cornered * 10 >= webs * 9, "cobwebs sit in corners ({cornered} of {webs})");
    }

    #[test]
    fn generation_is_deterministic_and_layered() {
        let a = gen_world(42);
        let b = gen_world(42);
        assert!(a.blocks == b.blocks);
        let stone = a.id_of("stone");
        let count = |id: u16| a.blocks.iter().filter(|&&b| b == id).count();
        assert!(count(stone) > count(a.id_of("dirt")));
        assert!(count(a.id_of("grass")) > 1000);
        assert!(count(0) > a.blocks.len() / 4);
        // One world evil, in patches away from spawn.
        let (eb, cr) = (count(a.id_of("ebonstone")), count(a.id_of("crimstone")));
        assert!((eb > 2000) != (cr > 2000), "one evil biome (ebonstone {eb}, crimstone {cr})");
        let c = gen_world_evil(42, EVIL_CRIMSON);
        assert!(c.blocks.iter().filter(|&&b| b == c.id_of("crimstone")).count() > 2000 && c.blocks.iter().all(|&b| b != c.id_of("ebonstone")));
        assert!(c.blocks.iter().filter(|&&b| b == c.id_of("crimson_grass")).count() > 300);
        // Floating islands: clouds and Sunplate in the sky, a sky chest (style 1).
        let l = layers(256);
        let sky_cloud = a.blocks.iter().enumerate().filter(|&(i, &b)| b == a.id_of("cloud") && (i as i32 % 256) > l.surface_base + 36).count();
        assert!(sky_cloud > 100, "islands have cloud undersides ({sky_cloud})");
        // The Space layer starts above every mountain top and below every
        // island: no ground (grass) anywhere near its boundary.
        let grass_ys: Vec<i32> = a.blocks.iter().enumerate().filter(|&(_, &b)| b == a.id_of("grass")).map(|(i, _)| i as i32 % 256).collect();
        let (ground_top, island_low) = (
            grass_ys.iter().filter(|&&y| y < l.space_top).max().copied().unwrap_or(0),
            grass_ys.iter().filter(|&&y| y >= l.space_top).min().copied().unwrap_or(256),
        );
        assert!(ground_top < l.space_top - 4 && island_low > l.space_top + 8,
            "Space layer at {}: ground reaches {ground_top}, islands start at {island_low}", l.space_top);
        assert!(count(a.id_of("sunplate")) > 50 && count(a.id_of("sunplate_trim")) > 30 && count(a.id_of("disc_wall")) > 50, "an island house");
        assert!(a.decorations.iter().any(|d| d.kind == "chest" && d.style == 1 && a.get(d.pos.0, d.pos.1, d.pos.2) == a.id_of("skyware_chest")));
        // The ocean all round: sea at every edge, a sand beach, the centre dry
        // land; the sea floor is solid (no tunnels into it) and the sea still.
        let coast = Coast::new(42, a.sx, a.sy, a.sz);
        let o = coast.ocean;
        let water_at = |x: i32, y: i32, z: i32| crate::world::liq_unpack(a.liquid[a.idx(x, y, z)]).0 == LIQ_WATER;
        let mid = a.sx / 2;
        for &(x, z) in &[(1, mid), (a.sx - 2, mid), (mid, 1), (mid, a.sz - 2), (2, 2), (a.sx - 3, a.sz - 3)] {
            assert!(water_at(x, o.sea_level, z), "sea at the edge ({x}, {z})");
            assert!(!water_at(x, o.sea_level + 1, z) && a.get(x, o.sea_level + 1, z) == 0, "sea level is flat at ({x}, {z})");
        }
        assert!(!water_at(mid, o.sea_level, mid) && a.surface_y(mid, mid) > o.sea_level, "the middle is dry land");
        let (mut beach_sand, mut beach) = (0, 0);
        let mut floor_holes = 0;
        for z in 0..a.sz {
            for x in 0..a.sx {
                let e = coast.inland(x, z);
                if e > o.width + 1.0 && e < o.width + o.beach * 0.6 {
                    beach += 1;
                    if a.get(x, a.surface_y(x, z), z) == a.id_of("sand") {
                        beach_sand += 1;
                    }
                }
                if e < o.width - 1.0 {
                    let mut y = o.sea_level;
                    while y > 0 && a.get(x, y, z) == 0 {
                        y -= 1;
                    }
                    floor_holes += (y - 12..y).filter(|&yy| a.get(x, yy, z) == 0).count();
                }
            }
        }
        assert!(beach > 1000 && beach_sand * 10 > beach * 9, "a sand beach ({beach_sand} of {beach})");
        assert_eq!(floor_holes, 0, "the sea floor has no caves under it");
        assert!(a.liquid_active.iter().all(|&(x, _, z)| coast.inland(x, z) > o.width + o.beach), "the sea is still");
        // The big biomes: Snow, Desert and Jungle regions with their blocks,
        // trees (boreal, mahogany with their canopies) and cacti; spawn stays forest.
        let regions = biome_regions(a.sx, a.sz, 42);
        let near = |(b, x, z, r): (i32, i32, i32, i32), name: &str| {
            let id = a.id_of(name);
            let mut n = 0;
            for zz in (z - r).max(0)..(z + r).min(a.sz) {
                for xx in (x - r).max(0)..(x + r).min(a.sx) {
                    n += (0..a.sy).filter(|&y| a.get(xx, y, zz) == id).count();
                }
            }
            let _ = b;
            n
        };
        let region = |b: i32| *regions.iter().find(|r| r.0 == b).unwrap();
        let snow = region(BIOME_SNOW);
        let desert = region(BIOME_DESERT);
        let jungle = region(BIOME_JUNGLE);
        assert!(near(snow, "snow_block") > 3000 && near(snow, "ice_block") > 1000, "snow: snow and ice ({}, {})", near(snow, "snow_block"), near(snow, "ice_block"));
        // Silt through the cavern layer (as much as Terraria's worlds have
        // there: 1.4-1.6% of its blocks), none above it; in the snow it's slush.
        let silt = a.id_of("silt");
        let (mut cavern_solid, mut cavern_silt, mut high_silt) = (0, 0, 0);
        for (i, &b) in a.blocks.iter().enumerate() {
            let y = i as i32 % a.sy;
            if b == silt && y > l.cavern_top {
                high_silt += 1;
            }
            if y <= l.cavern_top && y > l.underworld_top && b != 0 {
                cavern_solid += 1;
                cavern_silt += (b == silt) as usize;
            }
        }
        let share = cavern_silt as f32 / cavern_solid as f32;
        assert!(share > 0.011 && share < 0.02 && high_silt == 0, "silt: {:.1}% of the cavern layer, {high_silt} above it", share * 100.0);
        assert!(near(snow, "slush") > 100, "snow: slush ({})", near(snow, "slush"));
        assert!(near(desert, "sand") > 3000 && near(desert, "hardened_sand") > 1000 && near(desert, "cactus") > 5, "desert: sand, hardened sand, cacti");
        assert!(near(jungle, "mud") > 10000 && near(jungle, "jungle_grass") > 1000 && near(jungle, "mahogany_trunk") > 50, "jungle: mud, jungle grass, mahogany");
        let styles: Vec<i32> = a.decorations.iter().filter(|d| d.kind == "tree_top").map(|d| d.style).collect();
        let tops = TreeTops::of(&a);
        assert!(styles.contains(&tops.jungle(0)) || styles.contains(&tops.jungle(1)) || styles.contains(&tops.jungle(2)), "the world's jungle canopies");
        // The underground jungle: jungle grass in its caves, far below the surface.
        let jg = a.id_of("jungle_grass");
        let deep_grass = (jungle.2 - 10..jungle.2 + 10).flat_map(|z| (jungle.1 - 10..jungle.1 + 10).map(move |x| (x, z)))
            .map(|(x, z)| (0..l.surface_base - 40).filter(|&y| a.get(x, y, z) == jg).count()).sum::<usize>();
        assert!(deep_grass > 5, "jungle grass in the underground jungle's caves ({deep_grass})");
        let (sx_, sz_) = (a.sx / 2, a.sz / 2);
        assert!(regions.iter().all(|&(_, x, z, r)| (x - sx_).pow(2) + (z - sz_).pow(2) > r * r), "spawn is outside the biomes");
        // Spawn has headroom.
        let (x, y, z) = a.spawn;
        assert!(!a.is_solid(x, y, z) && !a.is_solid(x, y + 1, z) && a.is_solid(x, y - 1, z));
    }

    #[test]
    fn no_waterfalls_from_trees_on_flat_ground() {
        // Flat grass with a forest of 12-block trunks and no cliffs: no springs.
        let mut w = World::new();
        for (i, (name, render)) in [("grass", RENDER_CUBE), ("tree_trunk", crate::world::RENDER_CUTOUT)].iter().enumerate() {
            w.set_def(i as u16 + 1, BlockDef { name: name.to_string(), render: *render, solid: true, opaque: true, variants: 1, ..Default::default() });
        }
        w.resize(64, 64, 64);
        for z in 0..64 {
            for x in 0..64 {
                let i = w.idx(x, 20, z);
                w.blocks[i] = 1;
                if x % 3 == 0 && z % 3 == 0 {
                    for y in 21..33 {
                        let i = w.idx(x, y, z);
                        w.blocks[i] = 2;
                    }
                }
            }
        }
        cliff_waterfalls(&mut w, &mut Rng::new(5), 400);
        let n = w.decorations.iter().filter(|d| d.kind == "waterfall").count();
        assert_eq!(n, 0, "{n} springs poured out of trees");
    }

    #[test]
    fn waterfalls_pour_from_the_ground_not_from_trees() {
        for seed in [1, 7, 42] {
            let w = gen_world(seed);
            let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];
            let mut bad = vec![];
            for d in w.decorations.iter().filter(|d| d.kind == "waterfall" && d.style % 10 < 4) {
                let (dx, dz) = dirs[(d.style % 10) as usize];
                let wall = w.get(d.pos.0 - dx, d.pos.1, d.pos.2 - dz);
                if w.def(wall).render != RENDER_CUBE {
                    bad.push((d.pos, w.def(wall).name.clone()));
                }
            }
            assert!(bad.is_empty(), "seed {seed}: springs pouring from {:?}", bad);
        }
    }
}

#[cfg(test)]
mod bench {
    use super::*;
    use crate::world::{BlockDef, RENDER_CUBE};

    /// cargo test --release -- --ignored --nocapture full_size
    #[test]
    #[ignore]
    fn full_size_generation_timing() {
        let mut w = World::new();
        let names = ["dirt", "stone", "grass", "clay", "sand", "mud", "ash", "hellstone", "copper_ore", "iron_ore", "silver_ore", "gold_ore", "tree_trunk", "obsidian",
            "topaz_tree_trunk", "amethyst_tree_trunk", "sapphire_tree_trunk", "emerald_tree_trunk", "ruby_tree_trunk", "diamond_tree_trunk", "amber_tree_trunk"];
        for (i, name) in names.iter().enumerate() {
            w.set_def(i as u16 + 1, BlockDef { name: name.to_string(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        }
        crate::cabins::tests::add_cabin_defs(&mut w);
        // WORLD_SIZE="x,y,z" times another size (default: Small).
        let size: Vec<i32> = std::env::var("WORLD_SIZE").unwrap_or("768,384,768".into()).split(',').map(|v| v.trim().parse().unwrap()).collect();
        let t = std::time::Instant::now();
        w.resize(size[0], size[1], size[2]);
        generate(&mut w, 1234, &AtomicU32::new(0));
        let gen_time = t.elapsed();
        let t = std::time::Instant::now();
        w.compute_all_light();
        let light_time = t.elapsed();
        let t = std::time::Instant::now();
        let mut faces = 0;
        for cz in 0..16 { for cy in 0..8 { for cx in 0..16 {
            faces += crate::mesher::mesh_chunk(&w, cx, cy, cz).opaque.indices.len() / 6;
        }}}
        println!("gen {gen_time:?}, light {light_time:?}, mesh all 2048 chunks {:?} ({faces} faces)", t.elapsed());
        let falls: Vec<i32> = w.decorations.iter().filter(|d| d.kind == "waterfall").map(|d| d.style / 10).collect();
        for chest in ["gold_chest", "frozen_chest", "sandstone_chest", "rich_mahogany_chest"] {
            let id = w.id_of(chest);
            println!("cabins with a {chest}: {}", w.decorations.iter().filter(|d| d.kind == "chest" && (3..=6).contains(&d.style) && w.get(d.pos.0, d.pos.1, d.pos.2) == id).count());
        }
        println!("gem trees: {}", w.decorations.iter().filter(|d| d.kind == "tree_top" && d.style / 10 >= GEM_CANOPY && d.style / 10 < GEM_CANOPY + 7).count());
        {
            let t = std::time::Instant::now();
            let mut w2 = World::new();
            for (i, name) in names.iter().enumerate() {
                w2.set_def(i as u16 + 1, BlockDef { name: name.to_string(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
            }
            w2.resize(w.sx, w.sy, w.sz);
            w2.blocks = w.blocks.clone();
            w2.seed = w.seed;
            let l = layers(w2.sy);
            let n = gem_trees(&mut w2, 99, &l);
            println!("gem_trees pass alone: {:?} ({} more)", t.elapsed(), n);
        }
        println!("waterfalls: {} water, {} lava", falls.iter().filter(|&&t| t == 1).count(), falls.iter().filter(|&&t| t == 2).count());
        println!("water {} cells-worth, lava {} cells-worth", w.liquid_volume(crate::world::LIQ_WATER) / 63, w.liquid_volume(crate::world::LIQ_LAVA) / 63);
        w.activate_unsettled_liquid();
        let t = std::time::Instant::now();
        let mut active = 0;
        for _ in 0..100 {
            active = w.step_liquids(20_000);
        }
        println!("100 liquid ticks from load state: {:?}, {active} still active", t.elapsed());
        let t = std::time::Instant::now();
        let mut out = Vec::new();
        crate::save::save(&w, "{}", &mut out).unwrap();
        println!("save {:?}, {} MB", t.elapsed(), out.len() / 1_000_000);
    }
}
