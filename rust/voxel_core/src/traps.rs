//! Terraria's traps (WorldGen.placeTrap), for its Traps pass under the
//! surface and the Dungeon's (DungeonGlobalTraps), in 3D. Terraria's tiles
//! are 2/3 of a block here, as the cabins scale theirs.
//!
//! From a spot, down to the first solid ground: a pressure plate there (a
//! cell with room round it and over it, no spikes under it, no lava in it, not
//! within 20 tiles of mushroom grass) and, wired to it ("trap_wire"
//! decorations: the plate's cell, the target's offset in the style), one of:
//! - **Dart trap** (half the rest): along a line across through the plate
//!   (here x or z, picked at random), a wall 5-50 tiles off on either side,
//!   with ground under it and no door or spikes; up to 2 tiles over the
//!   floor, that wall's block becomes a Dart Trap facing the plate (a gray or
//!   brown plate).
//! - **Boulder** (the other half; a dart trap near snow or ice): up from the
//!   plate, 8 tiles and more, to where the rock round the spot is solid
//!   (5-40 tiles up, under the surface, no Dungeon brick, no chest or
//!   boulder near): a shaft is cut down from there to the plate, the rock
//!   round it turns to stone, and in its top a Boulder rests on a plug of
//!   actuated stone (an orange plate). Stepping on the plate drops the plug.
//! - **Explosives** (1 in 20): 4-6 tiles down through solid ground beside the
//!   plate, with solid ground all round it (a gray or brown plate).
//! - Deep down (30 tiles under the lava line, 1 in 6) Terraria's is a
//!   Geyser instead, not wired to anything; that isn't here yet (nothing is
//!   placed, as if it were).

use crate::world::{Decoration, World};
use crate::worldgen::{Layers, Rng};

/// Terraria's tiles to blocks here (2/3), rounded.
fn blocks(tiles: i32) -> i32 {
    (tiles as f64 * 2.0 / 3.0).round() as i32
}

type P = (i32, i32, i32);

pub struct TrapIds {
    plates: [u16; 3],
    dart: u16,
    boulder: u16,
    plug: u16,
    explosives: u16,
    stone: u16,
    spike: u16,
    mushroom_grass: u16,
    snow: [u16; 2],
    avoid_near: Vec<u16>,
    no_ground: Vec<u16>,
    dungeon: Vec<u16>,
}

impl TrapIds {
    pub fn of(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        TrapIds {
            plates: [id("gray_pressure_plate"), id("brown_pressure_plate"), id("orange_pressure_plate")],
            dart: id("dart_trap"),
            boulder: id("boulder"),
            plug: id("boulder_plug"),
            explosives: id("explosives"),
            stone: id("stone"),
            spike: id("spike"),
            mushroom_grass: id("mushroom_grass"),
            snow: [id("snow_block"), id("ice_block")],
            // Chests and boulders keep a boulder trap away (IsTileNearby 21,
            // 467; the Boulders set).
            avoid_near: ["chest", "gold_chest", "locked_gold_chest", "frozen_chest", "ivy_chest", "rich_mahogany_chest", "sandstone_chest", "mushroom_chest", "locked_shadow_chest", "boulder"]
                .iter().map(|n| id(n)).filter(|&b| b != 0).collect(),
            // Not on spikes, nor a dart trap's wall a door or spikes.
            no_ground: ["spike", "dungeon_door", "blue_dungeon_door", "green_dungeon_door", "pink_dungeon_door", "door_top", "wooden_door"]
                .iter().map(|n| id(n)).filter(|&b| b != 0).collect(),
            dungeon: ["blue_brick", "green_brick", "pink_brick", "cracked_blue_brick", "cracked_green_brick", "cracked_pink_brick"]
                .iter().map(|n| id(n)).filter(|&b| b != 0).collect(),
        }
    }

    pub fn ready(&self) -> bool {
        self.plates.iter().all(|&p| p != 0) && self.dart != 0 && self.boulder != 0 && self.plug != 0 && self.explosives != 0
    }
}

/// A "trap_wire" decoration from the plate at `from` to `to`.
fn wire(w: &mut World, from: P, to: P) {
    let (dx, dy, dz) = (to.0 - from.0, to.1 - from.1, to.2 - from.2);
    let style = (dx + 64) | (dz + 64) << 7 | (dy + 64) << 14;
    w.decorations.push(Decoration { kind: "trap_wire".into(), pos: from, style });
}

fn set(w: &mut World, (x, y, z): P, id: u16) {
    if w.in_bounds(x, y, z) {
        let i = w.idx(x, y, z);
        w.blocks[i] = id;
        w.liquid[i] = 0;
        w.shapes.remove(&i);
    }
}

/// Any of `ids` within `r` blocks of `p` (a cube; Terraria's IsTileNearby).
fn near(w: &World, p: P, r: i32, ids: &[u16]) -> bool {
    for x in p.0 - r..=p.0 + r {
        for y in p.1 - r..=p.1 + r {
            for z in p.2 - r..=p.2 + r {
                if w.in_bounds(x, y, z) && ids.contains(&w.get(x, y, z)) {
                    return true;
                }
            }
        }
    }
    false
}

/// A whole solid cell (Terraria's SolidTile: not a platform, nor a slope).
fn solid(w: &World, (x, y, z): P) -> bool {
    w.in_bounds(x, y, z) && w.is_solid(x, y, z) && !w.shapes.contains_key(&w.idx(x, y, z))
}

/// WorldGen.placeTrap from `start`: `kind` -1 for Terraria's pick, else 0
/// dart, 1 boulder, 2 explosives. `in_dungeon`: the Dungeon's (its brick
/// counts as solid rock round a dart trap or explosives, but no boulder goes
/// into it). Returns whether a trap went in.
pub fn place_trap(w: &mut World, rng: &mut Rng, l: &Layers, ids: &TrapIds, start: P, kind: i32, lava_line: i32) -> bool {
    let (x, mut y, z) = start;
    while y > 1 && !solid(w, (x, y, z)) {
        y -= 1;
    }
    if y <= 1 {
        return false;
    }
    let p = (x, y + 1, z);
    if !w.in_bounds(p.0, p.1 + 2, p.2) || x < 3 || z < 3 || x > w.sx - 4 || z > w.sz - 4 {
        return false;
    }
    if ids.mushroom_grass != 0 && near(w, p, blocks(20), &[ids.mushroom_grass]) {
        return false;
    }
    let lava = w.liquid_at(p.0, p.1, p.2);
    let mut kind = kind;
    if kind < 0 {
        kind = if rng.range(0, 20) == 0 {
            2
        } else if p.1 < lava_line - blocks(30) && rng.range(0, 6) == 0 {
            3
        } else {
            rng.range(0, 2)
        };
    }
    if lava.1 > 0 && (lava.0 == crate::world::LIQ_LAVA) && kind != 3 {
        return false;
    }
    if kind == 3 {
        // (A Geyser: not here yet.)
        return true;
    }
    // Room round the plate and over it.
    for (dx, dz) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] {
        for dy in 0..2 {
            if w.get(p.0 + dx, p.1 + dy, p.2 + dz) != 0 {
                return false;
            }
        }
    }
    if ids.no_ground.contains(&w.get(x, y, z)) {
        return false;
    }
    if kind == 1 && ids.snow.iter().any(|&s| s != 0 && near(w, p, 2, &[s])) {
        kind = 0;
    }
    match kind {
        0 => dart(w, rng, ids, p),
        1 => boulder(w, rng, l, ids, p),
        _ => explosives(w, rng, ids, p),
    }
}

fn dart(w: &mut World, rng: &mut Rng, ids: &TrapIds, p: P) -> bool {
    let h = p.1 + rng.range(0, 2);
    let axis = if rng.range(0, 2) == 0 { (1, 0) } else { (0, 1) };
    let reach = blocks(50);
    let find = |w: &World, s: i32| -> Option<(P, i32)> {
        for d in 1..=reach {
            let c = (p.0 + axis.0 * d * s, h, p.2 + axis.1 * d * s);
            if !w.in_bounds(c.0, c.1, c.2) {
                return None;
            }
            if solid(w, c) {
                return Some((c, d));
            }
        }
        None
    };
    let ok = |w: &World, hit: Option<(P, i32)>| -> Option<P> {
        let (c, d) = hit?;
        (d > blocks(5) && d < reach && solid(w, (c.0, c.1 - 1, c.2)) && !ids.no_ground.contains(&w.get(c.0, c.1, c.2))
            && !ids.no_ground.contains(&w.get(c.0, c.1 - 1, c.2)))
            .then_some(c)
    };
    let (a, b) = (ok(w, find(w, -1)), ok(w, find(w, 1)));
    let (wall, s) = match (a, b) {
        (Some(a), Some(b)) => {
            if rng.range(0, 2) == 0 { (a, -1) } else { (b, 1) }
        }
        (Some(a), None) => (a, -1),
        (None, Some(b)) => (b, 1),
        _ => return false,
    };
    set(w, p, ids.plates[rng.range(0, 2) as usize]);
    set(w, wall, ids.dart);
    // Facing back along the line to the plate (worldgen FACING order).
    let back = (-axis.0 * s, -axis.1 * s);
    let facing = crate::worldgen::FACING.iter().position(|&f| f == back).unwrap_or(0) as i32;
    w.decorations.push(Decoration { kind: "rotation".into(), pos: wall, style: facing });
    wire(w, p, wall);
    true
}

fn boulder(w: &mut World, rng: &mut Rng, l: &Layers, ids: &TrapIds, p: P) -> bool {
    let (bx, bz) = (p.0 + rng.range(-1, 2), p.2);
    // Up from the plate to where the rock all round is solid (Terraria's 6 x
    // 4 tiles: here 3 x 3 across and 3 tall).
    let mut k = blocks(8);
    let top = loop {
        let y0 = p.1 + k;
        // Under the ground (Terraria's worldSurface): the pocket well below
        // the surface here.
        if y0 + 3 >= (w.surface_y(bx, bz) - 4).min(w.sy - 2) {
            return false;
        }
        let mut all = true;
        for dx in -1..=1 {
            for dz in -1..=1 {
                for dy in 0..3 {
                    let c = (bx + dx, y0 + dy, bz + dz);
                    let b = w.get(c.0, c.1, c.2);
                    if ids.dungeon.contains(&b) || b == ids.boulder || b == ids.plug {
                        return false;
                    }
                    if !solid(w, c) {
                        all = false;
                    }
                }
            }
        }
        if all {
            break y0;
        }
        k += 1;
        if k >= blocks(40) {
            return false;
        }
    };
    if k <= blocks(5) {
        return false;
    }
    if near(w, (bx, top + 1, bz), blocks(4), &ids.avoid_near) || near(w, (bx, top + 1, bz), blocks(10), &[ids.boulder]) {
        return false;
    }
    // The shaft from the pocket down to the plate; stone round the pocket.
    for y in p.1..top + 3 {
        set(w, (bx, y, bz), 0);
    }
    for dx in -1..=1 {
        for dz in -1..=1 {
            for dy in -1..4 {
                let c = (bx + dx, top + dy, bz + dz);
                if (dx, dz) != (0, 0) && solid(w, c) {
                    set(w, c, ids.stone);
                }
            }
        }
    }
    set(w, p, ids.plates[2]);
    set(w, (bx, top + 2, bz), ids.boulder);
    set(w, (bx, top + 1, bz), ids.plug);
    set(w, (bx, top, bz), ids.plug);
    wire(w, p, (bx, top + 2, bz));
    true
}

fn explosives(w: &mut World, rng: &mut Rng, ids: &TrapIds, p: P) -> bool {
    let n = blocks(rng.range(4, 7)).max(2);
    let (ex, ez) = if rng.range(0, 2) == 0 { (p.0 + rng.range(-1, 2), p.2) } else { (p.0, p.2 + rng.range(-1, 2)) };
    let mut e = (ex, p.1, ez);
    for _ in 0..n {
        e.1 -= 1;
        if !solid(w, e) {
            return false;
        }
    }
    for dx in -1..=1 {
        for dy in -1..=1 {
            for dz in -1..=1 {
                if !solid(w, (e.0 + dx, e.1 + dy, e.2 + dz)) {
                    return false;
                }
            }
        }
    }
    set(w, e, ids.explosives);
    set(w, p, ids.plates[rng.range(0, 2) as usize]);
    wire(w, p, e);
    true
}

/// Terraria's Traps pass: maxTilesX x 0.05 traps in a small world (here that
/// many in each 640 x 640 blocks, as the cave cabins are counted), each up to
/// 1150 tries at a random spot from the surface to the Underworld's top, in
/// the open rock (Terraria: no wall behind it; here not in a structure or
/// `keep_out`).
pub fn traps_pass(w: &mut World, rng: &mut Rng, l: &Layers, keep_out: &dyn Fn(P) -> bool) -> usize {
    let ids = TrapIds::of(w);
    if !ids.ready() {
        return 0;
    }
    // The lava line, as the game has it (Game.lava_level).
    let lava_line = l.cavern_top - 20;
    let area = (w.sx as f32) * (w.sz as f32);
    let count = (4200.0 * 0.05 * area / (640.0 * 640.0)).round() as usize;
    let structures = w.structures.clone();
    let inside = |p: P| structures.iter().any(|(lo, hi)| p.0 >= lo.0 - 2 && p.0 <= hi.0 + 2 && p.1 >= lo.1 - 2 && p.1 <= hi.1 + 2 && p.2 >= lo.2 - 2 && p.2 <= hi.2 + 2);
    let edge = blocks(200).min(w.sx / 8);
    let mut placed = 0;
    for _ in 0..count {
        for _ in 0..1150 {
            let s = (rng.range(edge, w.sx - edge), rng.range(l.underworld_top + 4, l.surface_base - 6), rng.range(edge, w.sz - edge));
            // Under the ground (Terraria: below worldSurface).
            if w.get(s.0, s.1, s.2) != 0 || s.1 >= w.surface_y(s.0, s.2) - 6 || inside(s) || keep_out(s) {
                continue;
            }
            if place_trap(w, rng, l, &ids, s, -1, lava_line) {
                placed += 1;
                break;
            }
        }
    }
    placed
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE};

    pub(crate) fn add_trap_defs(w: &mut World) {
        let mut id = w.defs.len() as u16;
        for (name, solid) in [("gray_pressure_plate", false), ("brown_pressure_plate", false), ("orange_pressure_plate", false), ("dart_trap", true),
                ("boulder", true), ("boulder_plug", true), ("explosives", true), ("stone", true)] {
            if w.id_of(name) != 0 {
                continue;
            }
            w.set_def(id, BlockDef { name: name.into(), render: if solid { RENDER_CUBE } else { RENDER_CROSS }, solid, opaque: solid, variants: 1, ..Default::default() });
            id += 1;
        }
    }

    /// A cave: stone all round a long tunnel 4 tall and 3 wide along x, rock
    /// above it to the top.
    fn cave() -> (World, Layers) {
        let mut w = World::new();
        add_trap_defs(&mut w);
        w.resize(96, 96, 96);
        let stone = w.id_of("stone");
        for x in 0..96 {
            for z in 0..96 {
                for y in 0..90 {
                    let open = (10..86).contains(&x) && (47..50).contains(&z) && (20..24).contains(&y);
                    if !open {
                        let i = w.idx(x, y, z);
                        w.blocks[i] = stone;
                    }
                }
            }
        }
        (w, Layers { underworld_top: 6, cavern_top: 50, surface_base: 92, space_top: 95 })
    }

    fn wires(w: &World) -> Vec<(P, P)> {
        w.decorations.iter().filter(|d| d.kind == "trap_wire").map(|d| {
            let s = d.style;
            (d.pos, (d.pos.0 + (s & 127) - 64, d.pos.1 + (s >> 14) - 64, d.pos.2 + ((s >> 7) & 127) - 64))
        }).collect()
    }

    #[test]
    fn a_dart_trap_in_the_wall_facing_its_plate() {
        let (mut w, l) = cave();
        let ids = TrapIds::of(&w);
        // The tunnel ends 10 and 85: from x 20 the near end is 10 off.
        let mut rng = Rng::new(3);
        let mut done = false;
        for _ in 0..40 {
            if place_trap(&mut w, &mut rng, &l, &ids, (20, 22, 48), 0, 0) {
                done = true;
                break;
            }
        }
        assert!(done, "a dart trap goes in");
        let ws = wires(&w);
        assert_eq!(ws.len(), 1);
        let (plate, dart) = ws[0];
        assert!(ids.plates[..2].contains(&w.get(plate.0, plate.1, plate.2)), "a gray or brown plate");
        assert_eq!(plate.1, 20, "on the floor");
        assert_eq!(w.get(dart.0, dart.1, dart.2), ids.dart, "wired to the dart trap");
        assert!(dart.1 >= 20 && dart.1 <= 21 && dart.2 == 48 && (dart.0 == 9 || dart.0 == 86), "in the tunnel's end wall: {dart:?}");
        let rot = w.decorations.iter().find(|d| d.kind == "rotation" && d.pos == dart).expect("facing");
        let f = crate::worldgen::FACING[rot.style as usize];
        assert_eq!(f.0, (plate.0 - dart.0).signum(), "facing the plate");
    }

    #[test]
    fn a_boulder_over_a_shaft_down_to_its_plate() {
        let (mut w, l) = cave();
        let ids = TrapIds::of(&w);
        let mut rng = Rng::new(5);
        assert!(place_trap(&mut w, &mut rng, &l, &ids, (40, 22, 48), 1, 0), "a boulder trap goes in");
        let (plate, b) = wires(&w)[0];
        assert_eq!(w.get(plate.0, plate.1, plate.2), ids.plates[2], "an orange plate");
        assert_eq!(w.get(b.0, b.1, b.2), ids.boulder, "wired to the boulder");
        assert!(b.1 - plate.1 > blocks(5), "well over the plate ({} up)", b.1 - plate.1);
        assert_eq!(w.get(b.0, b.1 - 1, b.2), ids.plug);
        assert_eq!(w.get(b.0, b.1 - 2, b.2), ids.plug, "resting on its plug");
        for y in plate.1..b.1 - 2 {
            assert!(!w.is_solid(b.0, y, b.2), "the shaft is open down to the tunnel at {y}");
        }
    }

    #[test]
    fn explosives_under_the_plate() {
        let (mut w, l) = cave();
        let ids = TrapIds::of(&w);
        let mut rng = Rng::new(7);
        assert!(place_trap(&mut w, &mut rng, &l, &ids, (50, 22, 48), 2, 0));
        let (plate, e) = wires(&w)[0];
        assert_eq!(w.get(e.0, e.1, e.2), ids.explosives);
        assert!(plate.1 - e.1 >= 2 && plate.1 - e.1 <= 4, "a few blocks down ({})", plate.1 - e.1);
    }

    #[test]
    fn the_traps_pass_places_its_share() {
        let (mut w, l) = cave();
        let n = traps_pass(&mut w, &mut Rng::new(11), &l, &|_| false);
        // 210 per 640 x 640: 4.7 here, the tunnel taking what fits.
        assert!(n >= 1 && n <= 5, "{n} traps");
        assert!(!wires(&w).is_empty() || n > 0);
    }
}
