//! Terraria's moss (its Moss pass: WorldGen.randMoss, neonMossBiome, setMoss,
//! Spread.Moss; and its Moss Grass pass), in 3D.
//!
//! - **Colours:** three of the five plain mosses (green, brown, red, blue,
//!   purple), all different, one for each third of the world across x
//!   (setMoss); and one of the four neon mosses (krypton, xenon, argon,
//!   violet) for the neon patches.
//! - **Neon patches:** maxTilesX / 2100 (2 in a small world), here that many
//!   in each 640 x 640 blocks of the map, as the cabins do. Each starts away
//!   from the world's middle (Terraria keeps out of 38-62% of its width),
//!   between 40 tiles under the cavern layer and 40 over the lava line, and
//!   not within 50 tiles of the Jungle, the Glowing Mushroom biome, snow and
//!   ice, the desert's sandstone, marble, granite or the Dungeon (here within
//!   25: a 3D world's cube round a spot holds far more than Terraria's
//!   square). It drifts 30-40 steps (a random turn each), 60-80 tiles across
//!   and 2% smaller a step (scaled with the world, as Terraria's), kept in
//!   that band, turning the stone open to a cave within 0.8 of it (here 3/4
//!   of that: a ball takes in more than a circle) to its neon moss.
//! - **Moss caves:** maxTilesX x 0.01 tries (42 in a small world), here that
//!   many in each 640 x 640 blocks: a spot halfway down to the cavern layer
//!   to the water line (later tries from 30 under the cavern layer down);
//!   its cave (countTiles: 10 to 2500 open tiles, with no lava, ice or
//!   glowing mushrooms in it and some stone round it) gets its walls turned
//!   to its third's moss (Spread.Moss). In 3D nearly every cave joins the
//!   next, so a cave is measured out from the spot to a size picked in the
//!   matching range (as the spider caves are), or all of it if it's smaller.
//! - **Specks:** maxTilesX stone cells at random from halfway to the cavern
//!   layer to the lava line (most inside the rock, there to be dug into), and
//!   maxTilesX x 0.05 that are open to a cave; each of its third's moss.
//! - **Lava moss:** maxTilesX x 0.065 of it, from the water line down to the
//!   Underworld, on stone open to a cave with lava round it (Terraria's more
//!   than 20 of the 2500 tiles within 25 of it; a 3D world's caverns hold far
//!   less lava for their size, so here any within 17 blocks).
//! - **Spreading:** Terraria then grows every moss tile over the stone round
//!   it that's open to a cave and touches no lava (SpreadGrass), which its
//!   broken-up cave walls stop well short of covering everything; 3D caves
//!   all join, so here moss grows out to SPREAD blocks over that stone, which
//!   covers as much of the caverns' walls as Terraria's worlds do (about a
//!   quarter in the upper caverns, a fifth lower down, measured from a small
//!   world Terraria's own server made).
//! - **Long Moss:** every open cell on a moss floor, and under a moss
//!   ceiling (Moss Grass; Terraria's on its sides too, which have no sprite
//!   here).
//!
//! Terraria's tiles are 2/3 of a block here.

use crate::world::{World, LIQ_LAVA};
use crate::worldgen::{Layers, Rng};
use std::collections::{HashSet, VecDeque};

type P = (i32, i32, i32);

/// A Terraria tile, in blocks.
const TILE: f64 = 2.0 / 3.0;
/// The mosses, in Terraria's order: the five plain (0-4, its mossType), lava
/// (5) and the four neon (6-9).
pub const MOSSES: [&str; 10] = ["green", "brown", "red", "blue", "purple", "lava", "krypton", "xenon", "argon", "violet"];
const LAVA: usize = 5;
const NEON: [usize; 4] = [6, 7, 8, 9];
/// How far moss grows from where it started over the stone open to a cave,
/// in blocks along the wall (see Spreading).
pub const SPREAD: i32 = 16;
/// A neon patch's reach, as a share of Terraria's: a ball drifting through
/// the rock takes in more than its circle does a 2D slice.
const PATCH_REACH: f64 = 0.75;
/// How much lava within 25 tiles makes lava moss: Terraria's 20 tiles of the
/// 2500 round about; a 3D world's caverns hold far less lava for their size,
/// so here any.
const LAVA_NEAR: i32 = 0;
/// A moss cave's size in open cells: Terraria's 10 to 2500 tiles (countTiles),
/// its tiles a slab of cave about 6 blocks deep.
const CAVE_CELLS: (i32, i32) = (40, 9000);

const SIDES: [P; 6] = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)];

pub struct Ids {
    stone: u16,
    moss: [u16; 10],
    long_floor: [u16; 10],
    long_hanging: [u16; 10],
    /// What a moss cave can't hold: ice (and snow), glowing mushroom grass.
    ice: Vec<u16>,
    mushroom: u16,
    /// What a neon patch keeps 50 tiles from.
    keep_from: Vec<u16>,
}

impl Ids {
    pub fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        let all = |names: &[&str]| names.iter().map(|n| id(n)).filter(|&i| i != 0).collect::<Vec<u16>>();
        Ids {
            stone: id("stone"),
            moss: MOSSES.map(|m| id(&format!("{m}_moss"))),
            long_floor: MOSSES.map(|m| id(&format!("long_moss_{m}"))),
            long_hanging: MOSSES.map(|m| id(&format!("long_moss_{m}_hanging"))),
            ice: all(&["ice_block", "snow_block"]),
            mushroom: id("mushroom_grass"),
            keep_from: all(&["jungle_grass", "mushroom_grass", "ice_block", "snow_block", "sandstone", "hardened_sand", "marble",
                "granite", "blue_brick", "green_brick", "pink_brick"]),
        }
    }
}

/// Terraria's depth lines for its moss: tiles under the surface, as
/// dungeon::depth_y takes them. Its water line is halfway from the cavern
/// layer to the world's bottom, less 100 to plus 20 (GenVars.waterLine); its
/// lava line 50-80 under that.
struct Lines {
    half_to_caverns: i32,
    caverns: i32,
    water: i32,
    lava: i32,
    /// 230 tiles over the world's bottom (Terraria's maxTilesY - 230).
    deep: i32,
}

fn lines(l: &Layers, rng: &mut Rng) -> Lines {
    let water = 470.0 + rng.range(-100, 21) as f64;
    let lava = water + rng.range(50, 81) as f64;
    let y = |d: f64| crate::dungeon::depth_y(l, d);
    Lines { half_to_caverns: y(65.0), caverns: y(130.0), water: y(water), lava: y(lava), deep: y(633.0) }
}

/// The world's moss: its patches, caves, specks, lava moss and spreading.
/// Returns the moss colour of each third (0-4) and the neon moss (6-9).
pub fn moss(w: &mut World, rng: &mut Rng, l: &Layers) -> ([usize; 3], usize) {
    let ids = Ids::new(w);
    // randMoss: three different plain mosses, and a neon one.
    let mut thirds = [rng.range(0, 5) as usize; 3];
    while thirds[1] == thirds[0] {
        thirds[1] = rng.range(0, 5) as usize;
    }
    while thirds[2] == thirds[0] || thirds[2] == thirds[1] {
        thirds[2] = rng.range(0, 5) as usize;
    }
    let neon = NEON[rng.range(0, 4) as usize];
    if ids.stone == 0 || ids.moss.contains(&0) {
        return (thirds, neon);
    }
    let lines = lines(l, rng);
    let per_area = w.sx as f64 * w.sz as f64 / (640.0 * 640.0);
    let scale = w.sx.min(w.sz) as f64 / 768.0;
    let sx = w.sx.max(1);
    let third = move |x: i32| -> usize { thirds[((x * 3) / sx).clamp(0, 2) as usize] };

    // Neon patches.
    let patches = (2.0 * per_area).round() as usize;
    let (cx, cz) = (w.sx as f64 / 2.0, w.sz as f64 / 2.0);
    let mut made = 0;
    for _ in 0..patches * 20 {
        if made >= patches {
            break;
        }
        let x = rng.range(70, w.sx - 70);
        let z = rng.range(70, w.sz - 70);
        // Out of the world's middle (Terraria's 38-62% of its width).
        if ((x as f64 - cx).powi(2) + (z as f64 - cz).powi(2)).sqrt() < w.sx.min(w.sz) as f64 * 0.12 {
            continue;
        }
        let (top, bottom) = (lines.caverns - (40.0 * TILE) as i32, lines.lava + (40.0 * TILE) as i32);
        if top <= bottom {
            break;
        }
        let y = rng.range(bottom, top);
        if near_any(w, (x, y, z), (25.0 * TILE) as i32, &ids.keep_from) {
            continue;
        }
        neon_patch(w, rng, &ids, (x, y, z), ids.moss[neon], scale, &lines);
        made += 1;
    }

    // Moss caves.
    let tries = (42.0 * per_area).round() as usize;
    for _ in 0..tries {
        let (mut bottom, mut top) = (lines.water, lines.half_to_caverns);
        for _ in 0..200 {
            let p = (rng.range(40, w.sx - 40), rng.range(bottom, top.max(bottom + 1)), rng.range(40, w.sz - 40));
            (bottom, top) = (lines.deep, lines.caverns - (30.0 * TILE) as i32);
            let want = rng.range(CAVE_CELLS.0, CAVE_CELLS.1) as usize;
            if let Some(cells) = measure(w, &ids, p, want) {
                spread_cave(w, &ids, &cells, ids.moss[third(p.0)]);
                break;
            }
        }
    }

    // Specks: in the rock, then open to a cave.
    for _ in 0..(4200.0 * per_area) as usize {
        let (x, y, z) = (rng.range(1, w.sx - 1), rng.range(lines.lava, lines.half_to_caverns), rng.range(1, w.sz - 1));
        if w.get(x, y, z) == ids.stone {
            let i = w.idx(x, y, z);
            w.blocks[i] = ids.moss[third(x)];
        }
    }
    let mut left = (210.0 * per_area) as i32;
    for _ in 0..left * 400 {
        if left <= 0 {
            break;
        }
        let (x, y, z) = (rng.range(1, w.sx - 1), rng.range(lines.lava, lines.half_to_caverns), rng.range(1, w.sz - 1));
        if w.get(x, y, z) == ids.stone && open(w, (x, y, z)) {
            let i = w.idx(x, y, z);
            w.blocks[i] = ids.moss[third(x)];
            left -= 1;
        }
    }

    // Lava moss: Terraria's count goes down by 1 for each placed, 0.002 for
    // each open stone with too little lava round it, and 0.001 a try. Most
    // cells of a 3D world are buried rock, so here only the tries that find
    // open stone count (else the count runs out before lava is found).
    let mut budget = 273.0 * per_area;
    let reach = (25.0 * TILE) as i32;
    let mut tries = 0;
    while budget > 0.0 && tries < 20_000_000 {
        tries += 1;
        let (x, y, z) = (rng.range(1, w.sx - 1), rng.range(l.underworld_top, lines.water), rng.range(1, w.sz - 1));
        if w.get(x, y, z) != ids.stone || !open(w, (x, y, z)) {
            continue;
        }
        budget -= 0.001;
        if lava_near(w, (x, y, z), reach) > LAVA_NEAR {
            let i = w.idx(x, y, z);
            w.blocks[i] = ids.moss[LAVA];
            budget -= 1.0;
        } else {
            budget -= 0.002;
        }
    }

    spread(w, &ids);
    (thirds, neon)
}

/// Whether a cell is open to a cave: a side of it isn't solid.
fn open(w: &World, p: P) -> bool {
    SIDES.iter().any(|d| !w.is_solid(p.0 + d.0, p.1 + d.1, p.2 + d.2))
}

fn touches_lava(w: &World, p: P) -> bool {
    for dz in -1..=1 {
        for dy in -1..=1 {
            for dx in -1..=1 {
                let (t, a) = w.liquid_at(p.0 + dx, p.1 + dy, p.2 + dz);
                if t == LIQ_LAVA && a > 0 {
                    return true;
                }
            }
        }
    }
    false
}

/// About how many cells within `r` of `p` hold lava (every other cell each
/// way looked at, each standing for eight).
fn lava_near(w: &World, p: P, r: i32) -> i32 {
    let mut lava = 0;
    for z in (p.2 - r..=p.2 + r).step_by(2) {
        for y in (p.1 - r..=p.1 + r).step_by(2) {
            for x in (p.0 - r..=p.0 + r).step_by(2) {
                let (t, a) = w.liquid_at(x, y, z);
                if t == LIQ_LAVA && a > 0 {
                    lava += 8;
                }
            }
        }
    }
    lava
}

/// Whether any of `ids` is within `r` of `p` (every third cell each way).
fn near_any(w: &World, p: P, r: i32, ids: &[u16]) -> bool {
    for z in (p.2 - r..=p.2 + r).step_by(3) {
        for y in (p.1 - r..=p.1 + r).step_by(3) {
            for x in (p.0 - r..=p.0 + r).step_by(3) {
                if w.in_bounds(x, y, z) && ids.contains(&w.get(x, y, z)) {
                    return true;
                }
            }
        }
    }
    false
}

/// neonMossBiome: a patch drifting through the rock, turning the stone open
/// to a cave within 0.8 of its size to `moss`.
fn neon_patch(w: &mut World, rng: &mut Rng, ids: &Ids, start: P, moss: u16, scale: f64, lines: &Lines) {
    let mut pos = (start.0 as f64, start.1 as f64, start.2 as f64);
    let mut vel = (rng.unit() * 4.0 - 2.0, rng.unit() * 4.0 - 2.0, rng.unit() * 4.0 - 2.0);
    if vel.0 == 0.0 {
        vel.0 = 1.0;
    }
    while (vel.0 * vel.0 + vel.1 * vel.1 + vel.2 * vel.2).sqrt() < 4.0 {
        vel = (vel.0 * 1.5, vel.1 * 1.5, vel.2 * 1.5);
    }
    let mut size = rng.range(60, 80) as f64 * scale;
    let mut steps = rng.range(30, 40) as f64 * scale;
    while steps > 0.0 {
        size *= 0.98;
        steps -= 1.0;
        let r = size * TILE;
        // Kept between the cavern layer and the lava line (Terraria's rock
        // layer and the bottom it's given), turned back when it gets there.
        if pos.1 + r > lines.caverns as f64 {
            pos.1 = lines.caverns as f64 - r;
            vel.1 = vel.1.min(-5.0);
        }
        if pos.1 - r < lines.lava as f64 {
            pos.1 = lines.lava as f64 + r;
            vel.1 = vel.1.max(5.0);
        }
        let reach = r * 0.8 * PATCH_REACH * (1.0 + rng.unit() * 0.4 - 0.2);
        let ri = reach.ceil() as i32;
        let c = (pos.0.round() as i32, pos.1.round() as i32, pos.2.round() as i32);
        for z in c.2 - ri..=c.2 + ri {
            for y in c.1 - ri..=c.1 + ri {
                for x in c.0 - ri..=c.0 + ri {
                    let d = ((x - c.0).pow(2) + (y - c.1).pow(2) + (z - c.2).pow(2)) as f64;
                    if d < reach * reach && w.in_bounds(x, y, z) && w.get(x, y, z) == ids.stone && open(w, (x, y, z)) {
                        let i = w.idx(x, y, z);
                        w.blocks[i] = moss;
                    }
                }
            }
        }
        pos = (pos.0 + vel.0 * TILE, pos.1 + vel.1 * TILE, pos.2 + vel.2 * TILE);
        vel = (
            (vel.0 + rng.unit() * 4.0 - 2.0).clamp(-10.0, 10.0),
            (vel.1 + rng.unit() * 4.0 - 2.0).clamp(-10.0, 10.0),
            (vel.2 + rng.unit() * 4.0 - 2.0).clamp(-10.0, 10.0),
        );
    }
}

/// countTiles from `p`: its cave's open cells, out from it, up to `want` (all
/// of it if it's smaller, so long as there are 10 tiles' worth); None if it
/// holds lava, ice or glowing mushrooms, has no stone round it, or reaches
/// the world's edge or a structure.
fn measure(w: &World, ids: &Ids, p: P, want: usize) -> Option<Vec<P>> {
    if !w.in_bounds(p.0, p.1, p.2) || w.is_solid(p.0, p.1, p.2) || in_structure(w, p) {
        return None;
    }
    let mut seen: HashSet<P> = HashSet::from([p]);
    let mut queue = VecDeque::from([p]);
    let mut cells = Vec::with_capacity(want);
    let mut stone = false;
    while let Some(c) = queue.pop_front() {
        let (t, a) = w.liquid_at(c.0, c.1, c.2);
        if t == LIQ_LAVA && a > 0 {
            return None;
        }
        cells.push(c);
        if cells.len() >= want {
            break;
        }
        for d in SIDES {
            let n = (c.0 + d.0, c.1 + d.1, c.2 + d.2);
            if n.0 <= 1 || n.1 <= 1 || n.2 <= 1 || n.0 >= w.sx - 2 || n.1 >= w.sy - 2 || n.2 >= w.sz - 2 {
                return None;
            }
            if !seen.insert(n) {
                continue;
            }
            let b = w.get(n.0, n.1, n.2);
            if ids.ice.contains(&b) || (b == ids.mushroom && ids.mushroom != 0) {
                return None;
            }
            if b == ids.stone {
                stone = true;
            }
            if w.is_solid(n.0, n.1, n.2) {
                continue;
            }
            if in_structure(w, n) {
                return None;
            }
            queue.push_back(n);
        }
    }
    (stone && cells.len() >= CAVE_CELLS.0 as usize).then_some(cells)
}

fn in_structure(w: &World, p: P) -> bool {
    w.structures.iter().any(|&(a, b)| p.0 >= a.0 && p.0 <= b.0 && p.1 >= a.1 && p.1 <= b.1 && p.2 >= a.2 && p.2 <= b.2)
}

/// Spread.Moss: the stone round a cave's open cells turns to `moss`.
fn spread_cave(w: &mut World, ids: &Ids, cells: &[P], moss: u16) {
    for c in cells {
        for d in SIDES {
            let n = (c.0 + d.0, c.1 + d.1, c.2 + d.2);
            if w.get(n.0, n.1, n.2) == ids.stone {
                let i = w.idx(n.0, n.1, n.2);
                w.blocks[i] = moss;
            }
        }
    }
}

/// Every moss block grows over the stone open to a cave round it, touching
/// no lava, out to SPREAD blocks (each cell taking the moss nearest it).
fn spread(w: &mut World, ids: &Ids) {
    let is_moss = |b: u16| ids.moss.contains(&b);
    let mut queue: VecDeque<(P, u16, i32)> = VecDeque::new();
    for z in 1..w.sz - 1 {
        for y in 1..w.sy - 1 {
            for x in 1..w.sx - 1 {
                let b = w.blocks[w.idx(x, y, z)];
                if is_moss(b) && open(w, (x, y, z)) {
                    queue.push_back(((x, y, z), b, 0));
                }
            }
        }
    }
    while let Some((c, moss, d)) = queue.pop_front() {
        if d >= SPREAD {
            continue;
        }
        for dz in -1..=1 {
            for dy in -1..=1 {
                for dx in -1..=1 {
                    let n = (c.0 + dx, c.1 + dy, c.2 + dz);
                    if !w.in_bounds(n.0, n.1, n.2) || w.get(n.0, n.1, n.2) != ids.stone || !open(w, n) || touches_lava(w, n) {
                        continue;
                    }
                    let i = w.idx(n.0, n.1, n.2);
                    w.blocks[i] = moss;
                    queue.push_back((n, moss, d + 1));
                }
            }
        }
    }
}

/// Moss Grass: Long Moss on every open cell of a moss floor, hanging under a
/// moss ceiling (not in liquid, nor in the room a tree's top spreads in).
pub fn long_moss(w: &mut World) {
    let ids = Ids::new(w);
    if ids.long_floor.contains(&0) || ids.long_hanging.contains(&0) {
        return;
    }
    let mut tops: HashSet<P> = HashSet::new();
    for d in w.decorations.iter().filter(|d| d.kind == "tree_top") {
        for dz in -2..=2 {
            for dx in -2..=2 {
                for dy in 0..crate::worldgen::GEM_TOP_ROOM {
                    tops.insert((d.pos.0 + dx, d.pos.1 + dy, d.pos.2 + dz));
                }
            }
        }
    }
    for z in 1..w.sz - 1 {
        for y in 1..w.sy - 1 {
            for x in 1..w.sx - 1 {
                let b = w.blocks[w.idx(x, y, z)];
                let Some(k) = ids.moss.iter().position(|&m| m == b) else { continue };
                for (dy, plant) in [(1, ids.long_floor[k]), (-1, ids.long_hanging[k])] {
                    let n = (x, y + dy, z);
                    if w.get(n.0, n.1, n.2) == 0 && w.liquid_at(n.0, n.1, n.2).1 == 0 && !tops.contains(&n) {
                        let i = w.idx(n.0, n.1, n.2);
                        w.blocks[i] = plant;
                    }
                }
            }
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE};

    pub fn add_moss_defs(w: &mut World) {
        for m in MOSSES {
            let id = w.defs.len() as u16;
            w.set_def(id, BlockDef { name: format!("{m}_moss"), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        }
        for m in MOSSES {
            for end in ["", "_hanging"] {
                let id = w.defs.len() as u16;
                w.set_def(id, BlockDef { name: format!("long_moss_{m}{end}"), render: RENDER_CROSS, solid: false, opaque: false, variants: 1, ..Default::default() });
            }
        }
    }
}
