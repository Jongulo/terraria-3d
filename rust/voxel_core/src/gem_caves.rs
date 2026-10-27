//! Terraria's gem caves (its Gem Caves pass: WorldGen.gemCave, Spread.Gem)
//! and loose gems (its Exposed Gems, tile 178: the Gems In Ice Biome and
//! Random Gems passes), in 3D.
//!
//! - **Gem caves:** maxTilesX x 0.003 (13 in a small world), here that many
//!   in each 640 x 640 blocks of the map, as the cabins do. A try picks a
//!   spot from 30 tiles under the cavern layer to 230 tiles over the world's
//!   bottom and measures its cave (countTiles: 50 to 300 open tiles, no lava
//!   or ice in it, some stone round it); up to 1000 tries. In 3D nearly
//!   every cave joins the next, so a cave is measured out from the spot to a
//!   size picked in the matching range (as the spider caves are), or all of
//!   it if it's smaller. A cave has one gem for sure and each other 1 in 6
//!   (gemCave). Its walls (dirt, stone, clay, mud, jungle grass, mushroom
//!   grass, snow, ice) turn to its gems' ores, 1 in 20 to stone. Terraria
//!   tries a loose gem in half its open tiles, which comes to one in about
//!   9 of them (most have nothing to hold one); a 3D cave's cells mostly
//!   have a floor or ceiling, so here that many (a tile is about 3.4
//!   cells), on its floors and under its ceilings. (Terraria's gem walls
//!   behind it have no place in 3D.)
//! - **Loose gems** elsewhere, lying on cave floors and hanging from their
//!   ceilings: in snow and ice caves, clusters a few tiles across (Gems In
//!   Ice Biome); in the underground desert's sandstone, clusters of amber;
//!   and one at a time through the caverns (Random Gems). Terraria tries a
//!   tile at random and places one where it's open and something holds it;
//!   a 3D world is mostly rock, so here they're placed till as many lie
//!   about as in a small world Terraria's server made (for its 4200 tiles
//!   across: 249 by ice, 105 amber, 169 elsewhere), in each 640 x 640 blocks.
//!   Their gems as Terraria picks them: amethyst and topaz 3 in 12 each,
//!   sapphire and emerald 2 in 12, ruby and diamond 1 in 12.
//!
//! Terraria's tiles are 2/3 of a block here.

use crate::world::{World, LIQ_LAVA, RENDER_CROSS, RENDER_CUTOUT};
use crate::worldgen::{Layers, Rng};
use std::collections::{HashSet, VecDeque};

type P = (i32, i32, i32);

/// A Terraria tile, in blocks.
const TILE: f64 = 2.0 / 3.0;
/// Terraria's gems in its order (WorldGen.gem, Exposed Gems' styles), then
/// amber (style 6).
pub const GEMS: [&str; 7] = ["amethyst", "topaz", "sapphire", "emerald", "ruby", "diamond", "amber"];
const AMBER: usize = 6;
/// A gem cave's size in open cells: Terraria's 50 to 300 tiles (countTiles),
/// its tiles a slab of cave about 6 blocks deep.
const CAVE_CELLS: (i32, i32) = (170, 1000);
/// The share of a gem cave's open tiles with a loose gem (281 in 2452 tiles
/// in a small world Terraria's server made).
const CAVE_GEMS: f64 = 281.0 / 2452.0;
/// Loose gems in each 640 x 640 blocks: by ice, amber, elsewhere.
const ICE_GEMS: f64 = 249.0;
const AMBER_GEMS: f64 = 105.0;
const RANDOM_GEMS: f64 = 169.0;

const SIDES: [P; 6] = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)];

pub struct Ids {
    stone: u16,
    ores: [u16; 6],
    floor: [u16; 7],
    hanging: [u16; 7],
    /// Spread.Gemmable: dirt, stone, clay, mud, jungle grass, mushroom grass,
    /// snow, ice.
    gemmable: Vec<u16>,
    ice: Vec<u16>,
    snow_ice: Vec<u16>,
    sandstone: Vec<u16>,
}

impl Ids {
    pub fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        let all = |names: &[&str]| names.iter().map(|n| id(n)).filter(|&i| i != 0).collect::<Vec<u16>>();
        Ids {
            stone: id("stone"),
            ores: [0, 1, 2, 3, 4, 5].map(|k| id(&format!("{}_ore", GEMS[k]))),
            floor: GEMS.map(|g| id(&format!("loose_{g}"))),
            hanging: GEMS.map(|g| id(&format!("loose_{g}_hanging"))),
            gemmable: all(&["dirt", "stone", "clay", "mud", "jungle_grass", "mushroom_grass", "snow_block", "ice_block"]),
            ice: all(&["ice_block"]),
            snow_ice: all(&["snow_block", "ice_block"]),
            sandstone: all(&["sandstone", "hardened_sand"]),
        }
    }

    fn ready(&self) -> bool {
        self.stone != 0 && !self.ores.contains(&0) && !self.floor.contains(&0) && !self.hanging.contains(&0)
    }
}

/// The world's gem caves.
pub fn gem_caves(w: &mut World, rng: &mut Rng, l: &Layers) {
    let ids = Ids::new(w);
    if !ids.ready() {
        return;
    }
    let per_area = w.sx as f64 * w.sz as f64 / (640.0 * 640.0);
    let caves = (12.6 * per_area).round() as usize;
    let (top, bottom) = (crate::dungeon::depth_y(l, 160.0), crate::dungeon::depth_y(l, 633.0));
    let margin = ((200.0 * TILE) as i32).min(w.sx.min(w.sz) / 6);
    for _ in 0..caves {
        for _ in 0..1000 {
            let p = (rng.range(margin, w.sx - margin), rng.range(bottom, top.max(bottom + 1)), rng.range(margin, w.sz - margin));
            let want = rng.range(CAVE_CELLS.0, CAVE_CELLS.1) as usize;
            if let Some(cells) = measure(w, &ids, p, want) {
                gem_cave(w, rng, &ids, &cells);
                break;
            }
        }
    }
}

/// countTiles from `p`: its cave's open cells, out from it, up to `want` (all
/// of it if it's smaller, so long as there are 50 tiles' worth); None if it
/// holds lava or ice, has no stone round it, or reaches the world's edge or
/// a structure.
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
            if ids.ice.contains(&b) {
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

/// gemCave and Spread.Gem: the cave's gems (one for sure, each other 1 in
/// 6); its walls turn to their ores (1 in 20 to stone), and loose gems of
/// them lie about it (CAVE_GEMS).
fn gem_cave(w: &mut World, rng: &mut Rng, ids: &Ids, cells: &[P]) {
    let mut gems = [false; 6];
    gems[rng.range(0, 6) as usize] = true;
    for g in gems.iter_mut() {
        if rng.range(0, 6) == 0 {
            *g = true;
        }
    }
    let pick = |rng: &mut Rng| -> usize {
        loop {
            let k = rng.range(0, 6) as usize;
            if gems[k] {
                return k;
            }
        }
    };
    // Its walls. (Terraria grows its cave plants after: here what already
    // grows on a wall or hangs from it goes, and a trunk keeps its ground.)
    for &c in cells {
        for d in SIDES {
            let n = (c.0 + d.0, c.1 + d.1, c.2 + d.2);
            if !ids.gemmable.contains(&w.get(n.0, n.1, n.2)) {
                continue;
            }
            let above = w.get(n.0, n.1 + 1, n.2);
            if above != 0 && w.def(above).render == RENDER_CUTOUT {
                continue;
            }
            let ore = if rng.range(0, 20) == 0 { ids.stone } else { ids.ores[pick(rng)] };
            let i = w.idx(n.0, n.1, n.2);
            w.blocks[i] = ore;
            for dy in [1, -1] {
                let q = (n.0, n.1 + dy, n.2);
                let b = w.get(q.0, q.1, q.2);
                if b != 0 && w.def(b).render == RENDER_CROSS {
                    let j = w.idx(q.0, q.1, q.2);
                    w.blocks[j] = 0;
                }
            }
        }
    }
    let mut gems_left = (cells.len() as f64 * CAVE_GEMS / 3.4).round() as usize;
    for _ in 0..cells.len() * 4 {
        if gems_left == 0 {
            break;
        }
        let c = cells[rng.range(0, cells.len() as i32) as usize];
        let k = pick(rng);
        if place(w, ids, c, k) {
            gems_left -= 1;
        }
    }
}

/// A loose gem of kind `k` at `p` if it's empty and dry: lying on the block
/// under it, else hanging from the one over it. Whether it was placed.
fn place(w: &mut World, ids: &Ids, p: P, k: usize) -> bool {
    if !w.in_bounds(p.0, p.1, p.2) || w.get(p.0, p.1, p.2) != 0 || w.liquid_at(p.0, p.1, p.2).1 > 0 {
        return false;
    }
    let gem = if w.is_solid(p.0, p.1 - 1, p.2) {
        ids.floor[k]
    } else if w.is_solid(p.0, p.1 + 1, p.2) {
        ids.hanging[k]
    } else {
        return false;
    };
    let i = w.idx(p.0, p.1, p.2);
    w.blocks[i] = gem;
    true
}

/// Terraria's pick for a loose gem: amethyst and topaz 3 in 12, sapphire and
/// emerald 2 in 12, ruby and diamond 1 in 12.
fn weighted(rng: &mut Rng) -> usize {
    match rng.range(0, 12) {
        0..=2 => 0,
        3..=5 => 1,
        6..=7 => 2,
        8..=9 => 3,
        10 => 4,
        _ => 5,
    }
}

/// Loose gems through the caves: clusters by snow and ice, amber clusters in
/// the underground desert's sandstone, and single gems everywhere else.
pub fn loose_gems(w: &mut World, rng: &mut Rng, l: &Layers) {
    let ids = Ids::new(w);
    if !ids.ready() {
        return;
    }
    let per_area = w.sx as f64 * w.sz as f64 / (640.0 * 640.0);
    let y = |d: f64| crate::dungeon::depth_y(l, d);
    // Gems In Ice Biome: from halfway to the cavern layer to the lava line.
    clusters(w, rng, &ids, (ICE_GEMS * per_area) as usize, (y(540.0), y(65.0)), &ids.snow_ice, None);
    // Amber, in the sandstone under the desert (Terraria's desert walls).
    clusters(w, rng, &ids, (AMBER_GEMS * per_area) as usize, (y(563.0), y(0.0)), &ids.sandstone, Some(AMBER));
    // Random Gems: from the cavern layer to 300 tiles over the bottom, not in
    // lava or a structure (Terraria's dungeon walls).
    let (bottom, top) = (y(563.0), y(130.0));
    let want = (RANDOM_GEMS * per_area) as usize;
    let mut placed = 0;
    for _ in 0..want * 2000 {
        if placed >= want {
            break;
        }
        let p = (rng.range(20, w.sx - 20), rng.range(bottom, top.max(bottom + 1)), rng.range(20, w.sz - 20));
        if w.get(p.0, p.1, p.2) != 0 || in_structure(w, p) {
            continue;
        }
        let k = weighted(rng);
        if place(w, &ids, p, k) {
            placed += 1;
        }
    }
}

/// Clusters of loose gems by blocks of `by` open to a cave, till `want` lie
/// about: each fills the open cells 1-3 tiles round its spot (amber if
/// `gem`, else a gem picked for each cluster).
fn clusters(w: &mut World, rng: &mut Rng, ids: &Ids, want: usize, (bottom, top): (i32, i32), by: &[u16], gem: Option<usize>) {
    if by.is_empty() {
        return;
    }
    let mut placed = 0;
    for _ in 0..want * 20000 {
        if placed >= want {
            break;
        }
        let p = (rng.range(20, w.sx - 20), rng.range(bottom, top.max(bottom + 1)), rng.range(20, w.sz - 20));
        if !by.contains(&w.get(p.0, p.1, p.2)) || !SIDES.iter().any(|d| !w.is_solid(p.0 + d.0, p.1 + d.1, p.2 + d.2)) {
            continue;
        }
        let k = gem.unwrap_or_else(|| weighted(rng));
        let reach = |rng: &mut Rng| (rng.range(1, 4) as f64 * TILE).round().max(1.0) as i32;
        let (x0, x1, y0, y1, z0, z1) = (reach(rng), reach(rng), reach(rng), reach(rng), reach(rng), reach(rng));
        for z in p.2 - z0..p.2 + z1 {
            for yy in p.1 - y0..p.1 + y1 {
                for x in p.0 - x0..p.0 + x1 {
                    if placed < want && !in_structure(w, (x, yy, z)) && place(w, ids, (x, yy, z), k) {
                        placed += 1;
                    }
                }
            }
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::world::BlockDef;

    pub fn add_gem_defs(w: &mut World) {
        for g in GEMS {
            for end in ["", "_hanging"] {
                let id = w.defs.len() as u16;
                w.set_def(id, BlockDef { name: format!("loose_{g}{end}"), render: RENDER_CROSS, solid: false, opaque: false, variants: 1, ..Default::default() });
            }
        }
    }
}
