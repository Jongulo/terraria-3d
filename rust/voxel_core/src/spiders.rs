//! Terraria's spider caves (its Spider Caves pass: WorldGen.countTiles and
//! Spread.Spider; then its Webs In Spider Caves pass), in 3D.
//!
//! - **How many:** maxTilesX x 0.005 tries (21 in a small world); its worlds
//!   are a 2D slice, so here that many in each 640 x 640 blocks of the map,
//!   as the cabins do.
//! - **Where:** a try picks a spot 200 tiles in from the world's sides,
//!   between halfway down to the cavern layer and 230 tiles above the
//!   world's bottom, and measures the open cave there (countTiles): it must
//!   hold 500 to 3500 open tiles, with no background wall in it (another
//!   structure's) and no more than one glowing mushroom. Else it tries again
//!   (from 30 under the cavern layer down), up to maxTilesX / 2 times. In 3D
//!   nearly every cave joins the next, so instead a cave is measured out
//!   from the spot to a size picked between those (2000 to 12000 cells here,
//!   Terraria's tiles a slab of cave about 6 blocks high), and turned down if
//!   it runs out first, reaches the world's edge, a structure or glowing
//!   mushrooms.
//! - **The nest:** every cell of it gets Terraria's spider wall (here a
//!   "spider_cave" decoration at its middle, its style the nest's radius,
//!   which the game spawns its spiders in) and its liquid drained. On its
//!   floors, now and then a pot of the spider caves' styles (19 and 20), 1
//!   in 15 of them a Web Covered Chest instead, holding a Web Slinger, none
//!   within 15 tiles of another chest (AddBuriedChest, chest style 15). From
//!   its ceilings, now and then a webbed stalactite (PlaceTight with
//!   spiders). Terraria tries these in a third of its floor and ceiling
//!   tiles; 3D caves have far more floor and ceiling for their size, so here
//!   1 in 40 floor cells and 1 in 12 ceiling cells.
//! - **Piles:** on the rest of its floor, Terraria's webbed piles (big pile
//!   styles 9-13) wherever one fits, and 1 in 3 of the spots one doesn't
//!   (here, as one always fits, 1 in 3 of the floor it doesn't take) a small
//!   one, webbed rocks 2 x 1 (styles 34-37) or, where that doesn't fit
//!   either, 1 x 1 (48-53): here half each. Thinned as the pots: 1 in 40 of
//!   the floor cells a big pile, 1 in 120 a small one.
//! - **Webs:** 9 in 10 of the nest's open cells with a block within 2 to 4
//!   tiles get a cobweb (WebsInSpiderCaves), so the nest is thick with them
//!   along its walls.
//!
//! Terraria's tiles are 2/3 of a block here.

use crate::world::{Decoration, World};
use crate::worldgen::{Layers, Rng};
use std::collections::{HashSet, VecDeque};

type P = (i32, i32, i32);

/// A Terraria tile, in blocks.
const TILE: f64 = 2.0 / 3.0;
/// The Web Covered Chest's loot (Chests.LOOT in the game: "web_chest").
pub const WEB_CHEST_LOOT: i32 = 28;
/// How big a nest is measured out to, in open cells.
const CELLS: (i32, i32) = (2000, 12000);

pub struct Ids {
    web: u16,
    pot: u16,
    chest: u16,
    stalactite: u16,
    mushroom: u16,
    pile: u16,
    rock_pile: u16,
    small_rocks: u16,
}

impl Ids {
    pub fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        Ids {
            web: id("cobweb"),
            pot: id("spider_pot"),
            chest: id("web_covered_chest"),
            stalactite: id("spider_stalactite"),
            mushroom: id("mushroom_grass"),
            pile: id("webbed_pile"),
            rock_pile: id("webbed_rock_pile"),
            small_rocks: id("small_webbed_rocks"),
        }
    }
}

/// The world's spider caves; returns each nest's middle.
pub fn spider_caves(w: &mut World, rng: &mut Rng, l: &Layers) -> Vec<P> {
    let ids = Ids::new(w);
    let mut nests = Vec::new();
    if ids.web == 0 {
        return nests;
    }
    let tries = (21.0 * w.sx as f64 * w.sz as f64 / (640.0 * 640.0)).round() as usize;
    let margin = ((200.0 * TILE) as i32).min(w.sx.min(w.sz) / 6);
    // Halfway between the surface line and the cavern layer; 30 under the
    // cavern layer on later tries; to 230 tiles above the bottom.
    let (first_top, then_top, bottom) = (crate::dungeon::depth_y(l, 65.0), crate::dungeon::depth_y(l, 160.0), crate::dungeon::depth_y(l, 680.0));
    for _ in 0..tries {
        let mut top = first_top;
        // Terraria's maxTilesX / 2 retries; fewer suffice here (each fills).
        for _ in 0..200 {
            let p = (rng.range(margin, w.sx - margin), rng.range(bottom, top.max(bottom + 1)), rng.range(margin, w.sz - margin));
            top = then_top;
            let want = rng.range(CELLS.0, CELLS.1) as usize;
            if let Some(cells) = measure(w, &ids, p, want) {
                nests.push(nest(w, rng, &ids, &cells));
                break;
            }
        }
    }
    nests
}

/// countTiles from `p`: the first `want` open cells of the cave there, out
/// from it; None if there aren't that many, or it reaches the world's edge,
/// a structure (Terraria's walls) or glowing mushroom grass.
pub fn measure(w: &World, ids: &Ids, p: P, want: usize) -> Option<Vec<P>> {
    if !w.in_bounds(p.0, p.1, p.2) || w.is_solid(p.0, p.1, p.2) || in_structure(w, p) {
        return None;
    }
    let mut seen: HashSet<P> = HashSet::from([p]);
    let mut queue = VecDeque::from([p]);
    let mut cells = Vec::with_capacity(want);
    let mut shrooms = 0;
    while let Some(c) = queue.pop_front() {
        cells.push(c);
        if cells.len() >= want {
            return Some(cells);
        }
        for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
            let n = (c.0 + dx, c.1 + dy, c.2 + dz);
            if n.0 <= 1 || n.1 <= 1 || n.2 <= 1 || n.0 >= w.sx - 2 || n.1 >= w.sy - 2 || n.2 >= w.sz - 2 {
                return None;
            }
            if !seen.insert(n) {
                continue;
            }
            if w.get(n.0, n.1, n.2) == ids.mushroom && ids.mushroom != 0 {
                shrooms += 1;
                if shrooms > 1 {
                    return None;
                }
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
    None
}

fn in_structure(w: &World, p: P) -> bool {
    w.structures.iter().any(|&(a, b)| p.0 >= a.0 && p.0 <= b.0 && p.1 >= a.1 && p.1 <= b.1 && p.2 >= a.2 && p.2 <= b.2)
}

/// Spread.Spider and the webs through `cells`: returns the nest's middle
/// (its "spider_cave" decoration).
pub fn nest(w: &mut World, rng: &mut Rng, ids: &Ids, cells: &[P]) -> P {
    let mut chests: Vec<P> = w.decorations.iter().filter(|d| d.kind == "chest").map(|d| d.pos).collect();
    let chest_room = (15.0 * TILE) as i32;
    // Trees' tops (gem trees, the Jungle's) keep their room: nothing goes in
    // it (in Terraria they're tiles the nest goes round).
    let (lo, hi) = cells.iter().fold(((i32::MAX, i32::MAX, i32::MAX), (i32::MIN, i32::MIN, i32::MIN)), |(a, b), c| {
        ((a.0.min(c.0), a.1.min(c.1), a.2.min(c.2)), (b.0.max(c.0), b.1.max(c.1), b.2.max(c.2)))
    });
    let tops: Vec<P> = w.decorations.iter().filter(|d| d.kind == "tree_top").map(|d| d.pos)
        .filter(|p| p.0 >= lo.0 - 3 && p.0 <= hi.0 + 3 && p.1 >= lo.1 - 9 && p.1 <= hi.1 && p.2 >= lo.2 - 3 && p.2 <= hi.2 + 3)
        .collect();
    let canopy = |(x, y, z): P| tops.iter().any(|t| (t.0 - x).abs() <= 3 && (t.2 - z).abs() <= 3 && y >= t.1 && y <= t.1 + 8);
    let cells: Vec<P> = cells.iter().copied().filter(|&c| !canopy(c)).collect();
    let cells = &cells[..];
    for &(x, y, z) in cells {
        let i = w.idx(x, y, z);
        w.liquid[i] = 0;
        if w.blocks[i] != 0 {
            continue;
        }
        if w.is_solid(x, y - 1, z) && rng.range(0, 40) == 0 {
            if rng.range(0, 15) == 0 {
                if ids.chest != 0 && !chests.iter().any(|c| (c.0 - x).abs() < chest_room && (c.1 - y).abs() < chest_room && (c.2 - z).abs() < chest_room) {
                    w.blocks[i] = ids.chest;
                    w.decorations.push(Decoration { kind: "chest".into(), pos: (x, y, z), style: WEB_CHEST_LOOT });
                    chests.push((x, y, z));
                }
            } else if ids.pot != 0 && w.get(x, y + 1, z) == 0 {
                w.blocks[i] = ids.pot;
            }
        } else if w.is_solid(x, y + 1, z) && ids.stalactite != 0 && w.get(x, y - 1, z) == 0 && rng.range(0, 12) == 0 {
            w.blocks[i] = ids.stalactite;
        } else if w.is_solid(x, y - 1, z) {
            // The piles: a big one, else now and then a small one.
            if rng.range(0, 40) == 0 {
                w.blocks[i] = ids.pile;
            } else if rng.range(0, 120) == 0 {
                w.blocks[i] = if rng.range(0, 2) == 0 { ids.rock_pile } else { ids.small_rocks };
            }
        }
    }
    // The webs.
    for &(x, y, z) in cells {
        if w.get(x, y, z) != 0 || rng.range(0, 10) == 0 {
            continue;
        }
        let r = (rng.range(2, 5) as f64 * TILE).round() as i32;
        let near = (-r..=r).any(|dx| (-r..=r).any(|dy| (-r..=r).any(|dz| w.is_solid(x + dx, y + dy, z + dz))));
        if near {
            let i = w.idx(x, y, z);
            w.blocks[i] = ids.web;
        }
    }
    let n = cells.len() as f64;
    let mid = cells.iter().fold((0.0, 0.0, 0.0), |a, c| (a.0 + c.0 as f64, a.1 + c.1 as f64, a.2 + c.2 as f64));
    let mid = ((mid.0 / n).round() as i32, (mid.1 / n).round() as i32, (mid.2 / n).round() as i32);
    // Its reach: the distance most of its cells are within.
    let mut d: Vec<f64> = cells.iter().map(|c| (((c.0 - mid.0).pow(2) + (c.1 - mid.1).pow(2) + (c.2 - mid.2).pow(2)) as f64).sqrt()).collect();
    d.sort_by(|a, b| a.total_cmp(b));
    let radius = d[(d.len() * 9 / 10).min(d.len() - 1)].ceil() as i32;
    w.decorations.push(Decoration { kind: "spider_cave".into(), pos: mid, style: radius.max(4) });
    mid
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE, RENDER_CUTOUT};

    pub fn add_spider_defs(w: &mut World) {
        for (name, render) in [("spider_pot", RENDER_CROSS), ("web_covered_chest", RENDER_CUTOUT), ("spider_stalactite", RENDER_CROSS),
            ("webbed_pile", RENDER_CUTOUT), ("webbed_rock_pile", RENDER_CUTOUT), ("small_webbed_rocks", RENDER_CUTOUT)] {
            let id = w.defs.len() as u16;
            w.set_def(id, BlockDef { name: name.into(), render, solid: false, opaque: false, variants: 1, ..Default::default() });
        }
    }

    /// A cave of 40 x 8 x 40 in stone, and one 3 x 3 x 3 pocket.
    fn cave_world() -> World {
        let mut w = World::new();
        w.set_def(1, BlockDef { name: "stone".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        w.set_def(2, BlockDef { name: "cobweb".into(), render: RENDER_CROSS, solid: false, opaque: false, variants: 1, ..Default::default() });
        add_spider_defs(&mut w);
        w.resize(96, 64, 96);
        for b in w.blocks.iter_mut() {
            *b = 1;
        }
        for x in 20..60 {
            for y in 20..28 {
                for z in 20..60 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 0;
                }
            }
        }
        for x in 80..83 {
            for y in 40..43 {
                for z in 80..83 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 0;
                }
            }
        }
        w
    }

    #[test]
    fn a_nest_is_measured_out_of_its_cave() {
        let mut w = cave_world();
        let ids = Ids::new(&w);
        // Too small a pocket, or in a block: none.
        assert!(measure(&w, &ids, (81, 41, 81), 2000).is_none());
        assert!(measure(&w, &ids, (5, 5, 5), 2000).is_none());
        let cells = measure(&w, &ids, (40, 22, 40), 6000).expect("a nest");
        assert_eq!(cells.len(), 6000);
        // Out from the spot: the nearest cells first.
        assert_eq!(cells[0], (40, 22, 40));
        // A structure in the cave turns it down.
        w.structures.push(((30, 20, 30), (31, 21, 31)));
        assert!(measure(&w, &ids, (40, 22, 40), 6000).is_none());
    }

    /// The nest: webs thick along its walls, pots, stalactites and piles, a
    /// chest now and then, no liquid, and its decoration.
    #[test]
    fn spiders_nest_in_it() {
        let mut w = cave_world();
        let ids = Ids::new(&w);
        let cells = measure(&w, &ids, (40, 22, 40), 12_000).unwrap();
        let i = w.idx(40, 20, 40);
        w.liquid[i] = crate::world::liq_pack(crate::world::LIQ_WATER, 8);
        let mid = nest(&mut w, &mut Rng::new(4), &ids, &cells);
        assert_eq!(w.liquid[i], 0, "drained");
        let count = |b: u16| cells.iter().filter(|c| w.get(c.0, c.1, c.2) == b).count();
        let (webs, pots, tites) = (count(ids.web), count(ids.pot), count(ids.stalactite));
        // Within 1 to 3 of the walls (9 in 10): about half an 8-high cave.
        assert!(webs > cells.len() * 2 / 5, "webs ({webs} of {})", cells.len());
        assert!(pots > 10 && tites > 30, "pots ({pots}), stalactites ({tites})");
        // The piles: big ones 1 in 40 of the floor, small ones a third as many.
        let floor = cells.iter().filter(|c| c.1 == 20).count();
        let (big, small) = (count(ids.pile), count(ids.rock_pile) + count(ids.small_rocks));
        assert!(big * 40 > floor * 7 / 10 && big * 40 < floor * 13 / 10, "big piles ({big} on {floor})");
        assert!(small > 0 && small < big, "small piles ({small})");
        for c in &cells {
            let b = w.get(c.0, c.1, c.2);
            if [ids.pile, ids.rock_pile, ids.small_rocks].contains(&b) {
                assert!(w.is_solid(c.0, c.1 - 1, c.2), "a pile on the floor");
            }
            if b == ids.pot {
                assert!(w.is_solid(c.0, c.1 - 1, c.2), "a pot on the floor");
            }
            if b == ids.stalactite {
                assert!(w.is_solid(c.0, c.1 + 1, c.2), "a stalactite under the ceiling");
            }
        }
        let d = w.decorations.iter().find(|d| d.kind == "spider_cave").expect("its decoration");
        assert_eq!(d.pos, mid);
        assert!(d.style >= 10, "its radius ({})", d.style);
        for d in w.decorations.iter().filter(|d| d.kind == "chest") {
            assert_eq!(d.style, WEB_CHEST_LOOT);
            assert_eq!(w.get(d.pos.0, d.pos.1, d.pos.2), ids.chest);
        }
    }
}
