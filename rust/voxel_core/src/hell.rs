//! The Underworld's ruined houses, like Terraria's (WorldGen.AddHellHouses
//! and HellFort, at the end of its Underworld pass, and its Hellforges pass),
//! in 3D.
//!
//! Terraria's tiles are 2/3 of a block here, as the cabins scale theirs (its
//! 3-tile player is 2 blocks tall): a room 6-11 tiles tall is 4-7 blocks.
//!
//! - **Where**: Terraria walks across the middle half of its width, building
//!   a fort on the ground (the first open cell up from the bottom with no
//!   lava in it) every 30-129 tiles, and 1 time in 10 up to 200 more. Here
//!   the middle half each way, the walk along x on lines across z spaced the
//!   same way, each fort up to 15 blocks off its line. The outer sixth each
//!   way is the ash forest.
//! - **A fort** (HellFort) is a grid of rooms 5 columns across and 10 rows
//!   tall, the rows 6-11 tiles high, the 4th from the top standing on the
//!   ground and the lower 6 dug into it. The middle column is 4-9 tiles each
//!   side of the spot, the others 8-19 across; neighbours share their walls,
//!   floors and ceilings. Its plan, twice over: 1 time in 3 a wing on the left
//!   (the column beside the middle, or both on that side), on the ground's row
//!   - and 9 times in 10 a shaft from it up or down the column at its end to
//!   the top or the bottom - and likewise on the right. A fort with no wing is
//!   a tower: the middle column at least 6 rows tall. Here each wing goes out
//!   along x or z (the fort is a cross of two of Terraria's lines through the
//!   middle column), each column a box: a column standing where another fort
//!   is already is left out, and so is a room above the Underworld, too near
//!   its bottom (Terraria's last 20 tiles; here 2 blocks), or in another
//!   structure (the Dungeon).
//! - Each room is a shell of Obsidian Brick (1 time in 10 Hellstone Brick)
//!   round its own brick wall (Terraria's wall behind the room: here the
//!   walls between the frame's floor, ceiling and corner posts, as the cabins
//!   have theirs), emptied and drained. Doors (Obsidian Doors): one between
//!   each pair of neighbouring columns, and 1 time in 3 another between each
//!   pair of neighbouring rooms; one out of each end of the fort (Terraria's
//!   left and right; here the ends of both lines) where it's open outside. A
//!   hatch of Obsidian Platforms 3-6 tiles across in the floor of each room
//!   with one below it, and one in the roof of a room on the top row where
//!   it's open above. Then each room's outer walls that face open air (and
//!   have no door) crumble half the time: Terraria knocks out the wall from
//!   under the ceiling 2 tiles down and more; here each column of the wall
//!   its own way about that far, the corner posts standing.
//! - **Inside** (AddHellHouses, about 23 forts in a small world, the counts
//!   here per fort): Demon Torches on the walls (200), nowhere within 8 tiles
//!   of another, on a wall's side with open air under them; furniture (1000
//!   tries), each at the middle of an open run of floor long enough for it
//!   and clear to its height (Terraria's floor is a line through the room;
//!   here the room's two middle lines, one each way): a table with chairs each side and 1 time in 2
//!   a candle on it, a work bench with a chair and 1 time in 2 a candle, a
//!   vase, a bookcase, a chair, a bed, a piano, a dresser, a sofa, a clock, a
//!   bathtub, a lamp or a candelabra, all Obsidian (here each across the run
//!   it's in, the chairs facing their table); paintings (not in the game
//!   here); and from the ceilings (100 tries) one of the world's three Hell
//!   banners (of six; here on a wall, their tops at the ceiling, as the
//!   Dungeon's are), an Obsidian Chandelier or an Obsidian Lantern, none
//!   beside a door or another of them.
//! - **Hellforges**: one per 200 tiles of width (about 9 forts in 10), each
//!   on the floor of a room.

use crate::world::{Decoration, World};
use crate::worldgen::{Layers, Rng, FACING};

/// Terraria's tiles to blocks here (2/3), rounded.
fn blocks(tiles: i32) -> i32 {
    (tiles as f64 * 2.0 / 3.0).round() as i32
}

/// Terraria's forts in a small world (its middle half, 2100 tiles, a fort
/// every 90.5 or so): the counts of what goes in them are per that many.
const FORTS_SMALL: f64 = 23.2;

/// A room: its shell's box, the floor at `y0` and the ceiling at `y1`, the
/// walls at x0, x1, z0 and z1.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Room {
    pub x0: i32,
    pub x1: i32,
    pub y0: i32,
    pub y1: i32,
    pub z0: i32,
    pub z1: i32,
}

impl Room {
    /// Strictly inside the shell.
    pub fn inside(&self, x: i32, y: i32, z: i32) -> bool {
        x > self.x0 && x < self.x1 && y > self.y0 && y < self.y1 && z > self.z0 && z < self.z1
    }
    fn overlaps(&self, lo: (i32, i32, i32), hi: (i32, i32, i32)) -> bool {
        self.x0 <= hi.0 && lo.0 <= self.x1 && self.y0 <= hi.1 && lo.1 <= self.y1 && self.z0 <= hi.2 && lo.2 <= self.z1
    }
    fn floor_area(&self) -> i32 {
        (self.x1 - self.x0 - 1).max(0) * (self.z1 - self.z0 - 1).max(0)
    }
    /// The wall on side `d` (the way to it from inside): a cell of it at `t`
    /// along it and height y.
    fn wall_cell(&self, d: (i32, i32), t: i32, y: i32) -> (i32, i32, i32) {
        match d {
            (1, 0) => (self.x1, y, t),
            (-1, 0) => (self.x0, y, t),
            (0, 1) => (t, y, self.z1),
            _ => (t, y, self.z0),
        }
    }
    /// The range of t inside the wall on side `d` (its corner posts not).
    fn wall_span(&self, d: (i32, i32)) -> (i32, i32) {
        if d.0 != 0 {
            (self.z0 + 1, self.z1 - 1)
        } else {
            (self.x0 + 1, self.x1 - 1)
        }
    }
}

/// A fort: its rooms and what it's built of (0 Obsidian Brick, 1 Hellstone Brick).
pub struct Fort {
    pub rooms: Vec<Room>,
    pub kind: usize,
}

struct Ids {
    brick: [u16; 2],
    wall: [u16; 2],
    door: u16,
    door_top: u16,
    platform: u16,
    torch: u16,
    table: u16,
    chair: u16,
    workbench: u16,
    candle: u16,
    chandelier: u16,
    lantern: u16,
    banners: [u16; 6],
    hellforge: u16,
    /// The furniture by Terraria's kind (Next(13)): the table, work bench and
    /// lone chair are placed with their sets; the rest by themselves.
    pieces: [u16; 13],
}

impl Ids {
    fn of(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        let o = |n: &str| id(&format!("obsidian_{n}"));
        Ids {
            brick: [id("obsidian_brick"), id("hellstone_brick")],
            wall: [id("obsidian_brick_wall"), id("hellstone_brick_wall")],
            door: o("door"),
            door_top: id("door_top"),
            platform: o("platform"),
            torch: id("demon_wall_torch"),
            table: o("table"),
            chair: o("chair"),
            workbench: o("workbench"),
            candle: o("candle"),
            chandelier: o("chandelier"),
            lantern: o("lantern"),
            banners: ["hellbound_banner", "hell_hammer_banner", "helltower_banner", "lost_hopes_banner", "obsidian_watcher_banner", "lava_erupts_banner"].map(id),
            hellforge: id("hellforge"),
            pieces: [o("table"), o("workbench"), o("vase"), o("bookcase"), o("chair"), o("bed"), o("piano"), o("dresser"), o("sofa"), o("clock"), o("bathtub"), o("lamp"), o("candelabra")],
        }
    }
    fn is_fort(&self, b: u16) -> bool {
        b != 0 && (self.brick.contains(&b) || self.wall.contains(&b))
    }
    /// What a hanging thing keeps away from (Terraria's doors, chandeliers,
    /// lanterns and banners).
    fn keeps_off(&self, b: u16) -> bool {
        b != 0 && (b == self.door || b == self.door_top || b == self.chandelier || b == self.lantern || self.banners.contains(&b))
    }
}

/// Each kind of furniture's room (Terraria's in tiles): half its width along
/// its run of floor, and the height clear over the floor.
const SIZES: [(i32, i32); 13] = [(5, 4), (4, 3), (3, 5), (4, 6), (3, 3), (5, 3), (5, 4), (5, 4), (5, 4), (3, 5), (5, 3), (2, 4), (3, 3)];

fn put(w: &mut World, (x, y, z): (i32, i32, i32), id: u16) {
    if w.in_bounds(x, y, z) {
        let i = w.idx(x, y, z);
        w.blocks[i] = id;
        w.liquid[i] = 0;
        w.shapes.remove(&i);
    }
}

fn turn(w: &mut World, p: (i32, i32, i32), facing: (i32, i32)) {
    let style = FACING.iter().position(|&f| f == facing).unwrap_or(0) as i32;
    w.decorations.push(Decoration { kind: "rotation".into(), pos: p, style });
}

fn open_dry(w: &World, (x, y, z): (i32, i32, i32)) -> bool {
    !w.is_solid(x, y, z) && w.liquid_at(x, y, z).1 == 0
}

/// The Underworld's forts, furnished, and its Hellforges. Returns the forts.
pub fn hell_houses(w: &mut World, rng: &mut Rng, l: &Layers) -> Vec<Fort> {
    let ids = Ids::of(w);
    if ids.brick[0] == 0 || ids.wall[0] == 0 {
        return Vec::new();
    }
    let mut forts: Vec<Fort> = Vec::new();
    let (cx, cz) = (w.sx / 2, w.sz / 2);
    let half = w.sx.min(w.sz) / 4;
    let step = |rng: &mut Rng| {
        let mut t = rng.range(30, 130);
        if rng.range(0, 10) == 0 {
            t += rng.range(0, 200);
        }
        blocks(t + 1)
    };
    let mut z_line = cz - half;
    while z_line < cz + half {
        let mut x = cx - half;
        while x < cx + half {
            let z = (z_line + rng.range(-15, 16)).clamp(cz - half, cz + half);
            let Some(y) = ground(w, l, x, z) else {
                x += 1;
                continue;
            };
            // Obsidian Brick and its wall, 1 time in 10 Hellstone Brick and its.
            let pick = rng.range(0, 2) as usize;
            let kind = if rng.range(0, 5) > 0 { 0 } else { pick };
            if let Some(fort) = hell_fort(w, rng, &ids, l, (x, y, z), kind, &forts) {
                forts.push(fort);
            }
            x += step(rng);
        }
        z_line += step(rng);
    }
    for f in &forts {
        let lo = f.rooms.iter().fold((i32::MAX, i32::MAX, i32::MAX), |a, r| (a.0.min(r.x0), a.1.min(r.y0), a.2.min(r.z0)));
        let hi = f.rooms.iter().fold((i32::MIN, i32::MIN, i32::MIN), |a, r| (a.0.max(r.x1), a.1.max(r.y1), a.2.max(r.z1)));
        w.structures.push((lo, hi));
    }
    // No lava falls pouring through them.
    let rooms: Vec<Room> = forts.iter().flat_map(|f| f.rooms.iter().copied()).collect();
    w.decorations.retain(|d| d.kind != "waterfall" || !rooms.iter().any(|r| d.pos.0 >= r.x0 && d.pos.0 <= r.x1 && d.pos.2 >= r.z0 && d.pos.2 <= r.z1 && d.pos.1 >= r.y0));
    furnish(w, rng, &ids, &forts);
    forts
}

/// Terraria's spot for a fort: up from the bottom past anything there and
/// any liquid, to the first open cell; on solid ground.
fn ground(w: &World, l: &Layers, x: i32, z: i32) -> Option<i32> {
    let mut y = 1;
    while y < l.underworld_top && (w.get(x, y, z) != 0 || w.liquid_at(x, y, z).1 > 0) {
        y += 1;
    }
    (y < l.underworld_top && w.is_solid(x, y - 1, z)).then_some(y)
}

/// HellFort: a fort standing on `(x, y, z)`, if any of it fits.
fn hell_fort(w: &mut World, rng: &mut Rng, ids: &Ids, l: &Layers, (ax, ay, az): (i32, i32, i32), kind: usize, forts: &[Fort]) -> Option<Fort> {
    // The columns each way: the middle one round the spot, two each side.
    let columns = |rng: &mut Rng, a: i32| {
        let mut c = [(0, 0); 5];
        c[2] = (a - blocks(rng.range(4, 10)), a + blocks(rng.range(4, 10)));
        c[1] = (c[2].0 - blocks(rng.range(8, 20)), c[2].0);
        c[0] = (c[1].0 - blocks(rng.range(8, 20)), c[1].0);
        c[3] = (c[2].1, c[2].1 + blocks(rng.range(8, 20)));
        c[4] = (c[3].1, c[3].1 + blocks(rng.range(8, 20)));
        c
    };
    let xs = columns(rng, ax);
    let zs = columns(rng, az);
    // The rows (floor, ceiling): the 4th from the top on the ground.
    let mut rows = [(0, 0); 10];
    let h = |rng: &mut Rng| blocks(rng.range(6, 12));
    rows[3] = (ay, ay + h(rng));
    for r in 4..10 {
        let top = rows[r - 1].0;
        rows[r] = (top - h(rng), top);
    }
    for r in (0..3).rev() {
        let bottom = rows[r + 1].1;
        rows[r] = (bottom, bottom + h(rng));
    }
    // The plan: mask[x column][z column][row].
    let mut mask = [[[false; 10]; 5]; 5];
    let mut wings = false;
    for _ in 0..2 {
        for (near, far) in [(1usize, 0usize), (3, 4)] {
            if rng.range(0, 3) != 0 {
                continue;
            }
            wings = true;
            let along_x = rng.range(0, 2) == 0;
            let at = |c: usize| if along_x { (c, 2) } else { (2, c) };
            let mut shaft = near;
            if rng.range(0, 2) == 0 {
                mask[at(far).0][at(far).1][3] = true;
                shaft = far;
            }
            mask[at(near).0][at(near).1][3] = true;
            let dir = if rng.range(0, 2) == 0 { -1 } else { 1 };
            if rng.range(0, 10) > 0 {
                let mut r = 3i32;
                while (0..10).contains(&r) {
                    mask[at(shaft).0][at(shaft).1][r as usize] = true;
                    r += dir;
                }
            }
        }
    }
    let room = |cx: usize, cz: usize, r: usize| Room { x0: xs[cx].0, x1: xs[cx].1, y0: rows[r].0, y1: rows[r].1, z0: zs[cz].0, z1: zs[cz].1 };
    // A column where another fort stands already, or near the world's edge,
    // is left out.
    for (cx, cz) in cells() {
        if !mask[cx][cz].iter().any(|&b| b) {
            continue;
        }
        let r = room(cx, cz, 3);
        let edge = r.x0 < 8 || r.z0 < 8 || r.x1 >= w.sx - 8 || r.z1 >= w.sz - 8;
        let taken = forts.iter().flat_map(|f| &f.rooms).any(|o| o.x0 <= r.x1 && r.x0 <= o.x1 && o.z0 <= r.z1 && r.z0 <= o.z1);
        if edge || taken {
            mask[cx][cz] = [false; 10];
        }
    }
    // With no wing, a tower.
    let (mut lo, mut hi) = (3, 3);
    if !wings {
        while hi - lo < 5 {
            let r = rng.range(0, 10);
            lo = lo.min(r);
            let r = rng.range(0, 10);
            hi = hi.max(r);
        }
    }
    for r in lo..=hi {
        mask[2][2][r as usize] = true;
    }
    // Not above the Underworld, too near its bottom, nor in another structure.
    let mut list: Vec<((usize, usize, usize), Room)> = Vec::new();
    for (cx, cz) in cells() {
        for r in 0..10 {
            if !mask[cx][cz][r] {
                continue;
            }
            let rm = room(cx, cz, r);
            let in_structure = w.structures.iter().any(|&(lo, hi)| rm.overlaps(lo, hi));
            if rm.y1 > l.underworld_top || rm.y0 < 2 || in_structure || rm.x0 < 1 || rm.z0 < 1 || rm.x1 >= w.sx - 1 || rm.z1 >= w.sz - 1 {
                mask[cx][cz][r] = false;
            } else {
                list.push(((cx, cz, r), rm));
            }
        }
    }
    if list.is_empty() {
        return None;
    }
    let (brick, wall) = (ids.brick[kind], ids.wall[kind]);
    for (_, r) in &list {
        for x in r.x0..=r.x1 {
            for z in r.z0..=r.z1 {
                for y in r.y0..=r.y1 {
                    let (ex, ez, ey) = (x == r.x0 || x == r.x1, z == r.z0 || z == r.z1, y == r.y0 || y == r.y1);
                    let id = if !(ex || ez || ey) {
                        0
                    } else if ey || (ex && ez) {
                        brick
                    } else {
                        wall
                    };
                    put(w, (x, y, z), id);
                }
            }
        }
    }
    let has = |c: (usize, usize, usize)| mask[c.0][c.1][c.2];
    let index = |c: (usize, usize, usize)| list.iter().position(|(k, _)| *k == c);
    // Faces with a door in them (room index, side): they don't crumble.
    let mut doors: Vec<(usize, (i32, i32))> = Vec::new();
    // Between neighbouring columns, a door in a row where both have a room.
    for (cx, cz) in cells() {
        for (d, (nx, nz)) in [((1, 0), (cx + 1, cz)), ((0, 1), (cx, cz + 1))] {
            if nx > 4 || nz > 4 || (d.0 == 1 && cz != 2) || (d.1 == 1 && cx != 2) {
                continue;
            }
            let shared: Vec<usize> = (0..10).filter(|&r| has((cx, cz, r)) && has((nx, nz, r))).collect();
            if shared.is_empty() {
                continue;
            }
            for _ in 0..20 {
                let r = shared[rng.range(0, shared.len() as i32) as usize];
                if inner_door(w, rng, ids, &room(cx, cz, r), d) {
                    break;
                }
            }
        }
    }
    // Platforms up into each room from the one below, and another door to a
    // neighbour 1 time in 3.
    for &((cx, cz, r), rm) in &list {
        if r > 0 && has((cx, cz, r - 1)) {
            hatch(w, rng, ids, &rm, rm.y1, false);
        }
        for (d, (nx, nz)) in [((1, 0), (cx + 1, cz)), ((0, 1), (cx, cz + 1))] {
            if nx <= 4 && nz <= 4 && has((nx, nz, r)) && rng.range(0, 3) == 0 {
                inner_door(w, rng, ids, &rm, d);
            }
        }
    }
    // A door out of each end where it's open outside.
    for (along_x, d) in [(true, -1), (true, 1), (false, -1), (false, 1)] {
        let at = |c: usize| if along_x { (c, 2) } else { (2, c) };
        let ends: Vec<usize> = if d < 0 { (0..5).collect() } else { (0..5).rev().collect() };
        let Some(&end) = ends.iter().find(|&&c| (0..10).any(|r| has((at(c).0, at(c).1, r)))) else { continue };
        let (ex, ez) = at(end);
        let side = if along_x { (d, 0) } else { (0, d) };
        let mut spots: Vec<(usize, (i32, i32, i32))> = Vec::new();
        for r in (0..10).filter(|&r| has((ex, ez, r))) {
            let rm = room(ex, ez, r);
            let (t0, t1) = rm.wall_span(side);
            for t in t0..=t1 {
                let p = rm.wall_cell(side, t, rm.y0 + 1);
                let outside = (p.0 + side.0, p.1, p.2 + side.1);
                if (0..2).all(|k| open_dry(w, (outside.0, outside.1 + k, outside.2))) {
                    spots.push((index((ex, ez, r)).unwrap(), p));
                }
            }
        }
        if !spots.is_empty() {
            let (i, p) = spots[rng.range(0, spots.len() as i32) as usize];
            place_door(w, ids, p, side);
            doors.push((i, side));
        }
    }
    // A hatch in the roof of a room on the top row, if it's open above.
    if let Some(top) = (0..10).find(|&r| list.iter().any(|((_, _, rr), _)| *rr == r)) {
        let on_top: Vec<Room> = list.iter().filter(|((_, _, r), _)| *r == top).map(|(_, rm)| *rm).collect();
        let rm = on_top[rng.range(0, on_top.len() as i32) as usize];
        hatch(w, rng, ids, &rm, rm.y1, true);
    }
    // Outer walls facing open air crumble half the time.
    let all: Vec<Room> = forts.iter().flat_map(|f| f.rooms.iter().copied()).chain(list.iter().map(|(_, r)| *r)).collect();
    for (i, (_, rm)) in list.iter().enumerate() {
        for side in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            if doors.contains(&(i, side)) || rng.range(0, 2) != 0 {
                continue;
            }
            let (t0, t1) = rm.wall_span(side);
            let open = (t0..=t1).all(|t| {
                (rm.y0 + 1..rm.y1).all(|y| {
                    let c = rm.wall_cell(side, t, y);
                    let o = (c.0 + side.0, y, c.2 + side.1);
                    open_dry(w, o) && !all.iter().any(|a| a.inside(o.0, o.1, o.2))
                })
            });
            if !open {
                continue;
            }
            let h = rm.y1 - rm.y0;
            let k = ((h - 3) as f64 * rng.unit()) as i32 + rng.range(0, 2);
            for t in t0..=t1 {
                let kt = (k + rng.range(-1, 2)).clamp(1, h - 2);
                for y in rm.y1 - 1 - kt..rm.y1 {
                    let c = rm.wall_cell(side, t, y);
                    if ids.is_fort(w.get(c.0, c.1, c.2)) {
                        put(w, c, 0);
                    }
                }
            }
        }
    }
    Some(Fort { rooms: list.into_iter().map(|(_, r)| r).collect(), kind })
}

/// The grid's columns a fort uses: the two lines through the middle.
fn cells() -> impl Iterator<Item = (usize, usize)> {
    (0..5).map(|c| (c, 2)).chain((0..5).filter(|&c| c != 2).map(|c| (2, c)))
}

fn place_door(w: &mut World, ids: &Ids, p: (i32, i32, i32), out: (i32, i32)) {
    put(w, p, ids.door);
    put(w, (p.0, p.1 + 1, p.2), ids.door_top);
    turn(w, p, out);
}

/// HellFort_AttemptToPlaceDoor: a door in the room's wall on side `d` (to
/// the neighbour), at the floor, somewhere along it, with the wall over it.
fn inner_door(w: &mut World, rng: &mut Rng, ids: &Ids, r: &Room, d: (i32, i32)) -> bool {
    if ids.door == 0 || ids.door_top == 0 {
        return false;
    }
    let (t0, t1) = r.wall_span(d);
    if t1 < t0 {
        return false;
    }
    let p = r.wall_cell(d, rng.range(t0, t1 + 1), r.y0 + 1);
    if !w.is_solid(p.0, r.y0, p.2) || !ids.is_fort(w.get(p.0, r.y0 + 3, p.2)) || r.y0 + 3 >= r.y1 {
        return false;
    }
    place_door(w, ids, p, d);
    true
}

/// A hatch of platforms 3-6 tiles across each way in the room's floor or
/// roof at `y`, inside its walls; in a roof only where it's open above.
fn hatch(w: &mut World, rng: &mut Rng, ids: &Ids, r: &Room, y: i32, roof: bool) {
    if ids.platform == 0 {
        return;
    }
    let span = |rng: &mut Rng, a: i32, b: i32| {
        // Clear of the walls by a block where the room's wide enough.
        let (lo, hi) = if b - a >= 6 { (a + 2, b - 2) } else { (a + 1, b - 1) };
        let len = blocks(rng.range(3, 7)).min(hi - lo + 1).max(1);
        let s = rng.range(lo, hi - len + 2);
        (s, s + len - 1)
    };
    let (x0, x1) = span(rng, r.x0, r.x1);
    let (z0, z1) = span(rng, r.z0, r.z1);
    if roof && !(x0..=x1).all(|x| (z0..=z1).all(|z| open_dry(w, (x, y + 1, z)))) {
        return;
    }
    for x in x0..=x1 {
        for z in z0..=z1 {
            put(w, (x, y, z), ids.platform);
        }
    }
}

/// Inside: Demon Torches, furniture, banners and lights, then Hellforges.
fn furnish(w: &mut World, rng: &mut Rng, ids: &Ids, forts: &[Fort]) {
    let rooms: Vec<Room> = forts.iter().flat_map(|f| f.rooms.iter().copied()).filter(|r| r.floor_area() > 0).collect();
    if rooms.is_empty() {
        return;
    }
    let per_fort = |n: f64| (n * forts.len() as f64 / FORTS_SMALL).round() as usize;
    // A room picked as Terraria picks a spot: by its floor's size.
    let total: i64 = rooms.iter().map(|r| r.floor_area() as i64).sum();
    let pick = |rng: &mut Rng| {
        let mut n = (rng.unit() * total as f64) as i64;
        for r in &rooms {
            n -= r.floor_area() as i64;
            if n < 0 {
                return *r;
            }
        }
        rooms[rooms.len() - 1]
    };
    let sides = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    let near_door = |w: &World, (x, y, z): (i32, i32, i32)| sides.iter().any(|d| [ids.door, ids.door_top].contains(&w.get(x + d.0, y, z + d.1)));
    // Demon Torches on the walls, none within 8 tiles (5 blocks) of another.
    let mut torches: Vec<(i32, i32, i32)> = Vec::new();
    if ids.torch != 0 {
        for _ in 0..per_fort(200.0) {
            for _ in 0..1000 {
                let r = pick(rng);
                let d = sides[rng.range(0, 4) as usize];
                let (t0, t1) = r.wall_span(d);
                if t1 < t0 || r.y1 - 1 < r.y0 + 2 {
                    continue;
                }
                let c = r.wall_cell(d, rng.range(t0, t1 + 1), rng.range(r.y0 + 2, r.y1));
                let p = (c.0 - d.0, c.1, c.2 - d.1);
                if !ids.is_fort(w.get(c.0, c.1, c.2)) || w.get(p.0, p.1, p.2) != 0 || w.get(p.0, p.1 - 1, p.2) != 0 || w.liquid_at(p.0, p.1, p.2).1 > 0 {
                    continue;
                }
                if torches.iter().any(|t| (t.0 - p.0).abs().max((t.1 - p.1).abs()).max((t.2 - p.2).abs()) <= 5) {
                    continue;
                }
                put(w, p, ids.torch);
                turn(w, p, (-d.0, -d.1));
                torches.push(p);
                break;
            }
        }
    }
    // Furniture, each at the middle of a run of open floor (Terraria's floor
    // is a line through its room; here the room's two middle lines).
    let floor_ok = |w: &World, (x, y, z): (i32, i32, i32)| w.get(x, y, z) == 0 && w.liquid_at(x, y, z).1 == 0 && w.is_solid(x, y - 1, z);
    for _ in 0..per_fort(1000.0) {
        let r = pick(rng);
        let y = r.y0 + 1;
        let along = if rng.range(0, 2) == 0 { (1, 0) } else { (0, 1) };
        let spot = if along.0 != 0 { (rng.range(r.x0 + 1, r.x1), y, (r.z0 + r.z1) / 2) } else { ((r.x0 + r.x1) / 2, y, rng.range(r.z0 + 1, r.z1)) };
        if !floor_ok(w, spot) {
            continue;
        }
        let at = |k: i32| (spot.0 + along.0 * k, y, spot.2 + along.1 * k);
        let (mut lo, mut hi) = (0, 0);
        while floor_ok(w, at(lo - 1)) {
            lo -= 1;
        }
        while floor_ok(w, at(hi + 1)) {
            hi += 1;
        }
        let mid_k = (lo + hi).div_euclid(2);
        let mid = at(mid_k);
        let kind = rng.range(0, 13) as usize;
        let (hw, ht) = (blocks(SIZES[kind].0), blocks(SIZES[kind].1 + 1));
        if ((hi - lo) as f64) < hw as f64 * 1.75 {
            continue;
        }
        let clear = (-hw..=hw).all(|k| (0..ht).all(|dy| {
            let c = at(mid_k + k);
            w.get(c.0, y + dy, c.2) == 0
        }));
        if !clear || near_door(w, mid) {
            continue;
        }
        let across = if rng.range(0, 2) == 0 { (-along.1, along.0) } else { (along.1, -along.0) };
        let piece = ids.pieces[kind];
        if piece == 0 {
            continue;
        }
        let chair = |w: &mut World, k: i32| {
            let c = at(mid_k + k);
            if ids.chair != 0 && w.get(c.0, c.1, c.2) == 0 && !near_door(w, c) {
                put(w, c, ids.chair);
                turn(w, c, (-along.0 * k.signum(), -along.1 * k.signum()));
            }
        };
        match kind {
            0 => {
                put(w, mid, ids.table);
                turn(w, mid, across);
                if rng.range(0, 6) < 3 && ids.candle != 0 {
                    put(w, (mid.0, y + 1, mid.2), ids.candle);
                }
                chair(w, -1);
                chair(w, 1);
            }
            1 => {
                put(w, mid, ids.workbench);
                turn(w, mid, across);
                if rng.range(0, 4) < 2 && ids.candle != 0 {
                    put(w, (mid.0, y + 1, mid.2), ids.candle);
                }
                chair(w, if rng.range(0, 2) == 0 { -1 } else { 1 });
            }
            4 => {
                put(w, mid, piece);
                let s = if rng.range(0, 2) == 0 { 1 } else { -1 };
                turn(w, mid, (along.0 * s, along.1 * s));
            }
            _ => {
                put(w, mid, piece);
                turn(w, mid, across);
            }
        }
    }
    // From the ceilings: the world's three Hell banners (of six), Obsidian
    // Chandeliers and Lanterns, none beside a door or another of them.
    let mut styles: Vec<usize> = Vec::new();
    while styles.len() < 3 {
        let s = rng.range(0, 6) as usize;
        if !styles.contains(&s) {
            styles.push(s);
        }
    }
    for _ in 0..per_fort(100.0) {
        let r = pick(rng);
        if r.y1 - 3 <= r.y0 {
            continue;
        }
        match rng.range(0, 3) {
            0 => {
                let banner = ids.banners[styles[rng.range(0, 3) as usize]];
                let d = sides[rng.range(0, 4) as usize];
                let (t0, t1) = r.wall_span(d);
                if banner == 0 || t1 < t0 {
                    continue;
                }
                let t = rng.range(t0, t1 + 1);
                // The cell under the one by the ceiling, so its top meets it.
                let c = r.wall_cell(d, t, r.y1 - 2);
                let p = (c.0 - d.0, c.1, c.2 - d.1);
                let free = (-1..=1).all(|dy| w.get(p.0, p.1 + dy, p.2) == 0);
                let walled = (0..=1).all(|dy| ids.is_fort(w.get(c.0, c.1 + dy, c.2)));
                let beside = (-1..=1).any(|k| (-1..=1).any(|dy| {
                    let q = r.wall_cell(d, t + k, p.1 + dy);
                    ids.keeps_off(w.get(q.0 - d.0, q.1, q.2 - d.1)) || ids.keeps_off(w.get(q.0, q.1, q.2))
                }));
                if free && walled && !beside {
                    put(w, p, banner);
                    turn(w, p, (-d.0, -d.1));
                }
            }
            kind => {
                let (id, tall) = if kind == 1 { (ids.chandelier, 3) } else { (ids.lantern, 2) };
                let p = (rng.range(r.x0 + 1, r.x1), r.y1 - 1, rng.range(r.z0 + 1, r.z1));
                if id == 0 || !w.is_solid(p.0, r.y1, p.2) || !(0..tall).all(|k| w.get(p.0, p.1 - k, p.2) == 0) {
                    continue;
                }
                let beside = (-1..=1).any(|a| (-1..=1).any(|b| (0..tall).any(|k| ids.keeps_off(w.get(p.0 + a, p.1 - k, p.2 + b)))));
                if !beside {
                    put(w, p, id);
                }
            }
        }
    }
    // Hellforges, each on a room's floor.
    if ids.hellforge != 0 {
        for _ in 0..per_fort(21.0) {
            for _ in 0..10000 {
                let r = pick(rng);
                let p = (rng.range(r.x0 + 1, r.x1), r.y0 + 1, rng.range(r.z0 + 1, r.z1));
                if floor_ok(w, p) && w.get(p.0, p.1 + 1, p.2) == 0 && !near_door(w, p) {
                    put(w, p, ids.hellforge);
                    turn(w, p, sides[rng.range(0, 4) as usize]);
                    break;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{BlockDef, LIQ_LAVA, RENDER_CROSS, RENDER_CUBE};

    const SOLID: [&str; 9] = ["ash", "hellstone", "obsidian_brick", "hellstone_brick", "obsidian_brick_wall", "hellstone_brick_wall", "obsidian_door", "door_top", "obsidian_workbench"];
    const SPRITES: [&str; 25] = [
        "obsidian_platform", "demon_wall_torch", "obsidian_table", "obsidian_chair", "obsidian_candle", "obsidian_vase", "obsidian_bookcase", "obsidian_bed",
        "obsidian_piano", "obsidian_dresser", "obsidian_sofa", "obsidian_clock", "obsidian_bathtub", "obsidian_lamp", "obsidian_candelabra", "obsidian_chandelier",
        "obsidian_lantern", "hellbound_banner", "hell_hammer_banner", "helltower_banner", "lost_hopes_banner", "obsidian_watcher_banner", "lava_erupts_banner",
        "hellforge", "obsidian_door_open",
    ];

    /// An Underworld 256 across and 128 tall: ash up to 6 (rising to 9 in a
    /// ridge), a cavity up to the ash ceiling at 40, a lava lake in a hollow.
    fn underworld() -> (World, Layers) {
        let mut w = World::new();
        for (i, name) in SOLID.iter().chain(SPRITES.iter()).enumerate() {
            let solid = SOLID.contains(name);
            w.set_def(i as u16 + 1, BlockDef {
                name: name.to_string(),
                render: if solid { RENDER_CUBE } else { RENDER_CROSS },
                solid,
                opaque: solid,
                platform: *name == "obsidian_platform",
                variants: 1,
                ..Default::default()
            });
        }
        w.resize(256, 128, 256);
        let ash = w.id_of("ash");
        for z in 0..256i32 {
            for x in 0..256i32 {
                let floor = if (x / 20) % 3 == 0 { 9 } else { 6 };
                let hollow = (x - 160).pow(2) + (z - 100).pow(2) < 15 * 15;
                for y in 1..128 {
                    let solid = y <= if hollow { 3 } else { floor } || (40..48).contains(&y);
                    let i = w.idx(x, y, z);
                    if solid {
                        w.blocks[i] = ash;
                    } else if hollow && y <= 5 {
                        w.liquid[i] = crate::world::liq_pack(LIQ_LAVA, crate::world::LIQ_MAX);
                    }
                }
            }
        }
        (w, Layers { underworld_top: 46, cavern_top: 90, surface_base: 110, space_top: 120 })
    }

    /// A block index's cell.
    fn pos_of(w: &World, i: usize) -> (i32, i32, i32) {
        let i = i as i32;
        (i / w.sy % w.sx, i % w.sy, i / w.sy / w.sx)
    }

    fn count(w: &World, name: &str) -> usize {
        let id = w.id_of(name);
        w.blocks.iter().filter(|&&b| b == id).count()
    }

    #[test]
    fn forts_in_the_middle_standing_on_the_ground() {
        let (mut w, l) = underworld();
        let forts = hell_houses(&mut w, &mut Rng::new(3), &l);
        assert!(forts.len() >= 4, "{} forts", forts.len());
        let (lo, hi) = (256 / 4 - 40, 256 * 3 / 4 + 40);
        for f in &forts {
            for r in &f.rooms {
                assert!(r.x0 >= lo && r.x1 <= hi && r.z0 >= lo && r.z1 <= hi, "in the middle: {r:?}");
                assert!(r.y0 >= 2 && r.y1 <= l.underworld_top, "inside the Underworld: {r:?}");
                assert!((4..=7).contains(&(r.y1 - r.y0)), "4-7 tall: {r:?}");
                // Drained: no lava inside.
                for x in r.x0 + 1..r.x1 {
                    for z in r.z0 + 1..r.z1 {
                        for y in r.y0 + 1..r.y1 {
                            assert_eq!(w.liquid_at(x, y, z).1, 0, "no lava in {r:?}");
                        }
                    }
                }
            }
        }
        assert!(count(&w, "obsidian_brick") > count(&w, "hellstone_brick"), "mostly Obsidian Brick");
    }

    #[test]
    fn rooms_are_shells_of_brick_round_their_walls() {
        let (mut w, l) = underworld();
        let forts = hell_houses(&mut w, &mut Rng::new(5), &l);
        let rooms: Vec<Room> = forts.iter().flat_map(|f| f.rooms.iter().copied()).collect();
        let ids = Ids::of(&w);
        for f in &forts {
            let (brick, wall) = (ids.brick[f.kind], ids.wall[f.kind]);
            for r in &f.rooms {
                // The corner posts stand (brick, or another fort's), floor to ceiling.
                for (x, z) in [(r.x0, r.z0), (r.x1, r.z0), (r.x0, r.z1), (r.x1, r.z1)] {
                    for y in r.y0..=r.y1 {
                        assert!(ids.is_fort(w.get(x, y, z)), "a post at {:?} in {r:?}", (x, y, z));
                    }
                }
                // Its walls: brick walls or doors, or crumbled from the top
                // (never a hole under wall); not where another room overlaps.
                for d in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let (t0, t1) = r.wall_span(d);
                    for t in t0..=t1 {
                        let mut gone = true;
                        for y in (r.y0 + 1..r.y1).rev() {
                            let c = r.wall_cell(d, t, y);
                            if rooms.iter().any(|o| o.inside(c.0, c.1, c.2)) {
                                break;
                            }
                            let b = w.get(c.0, c.1, c.2);
                            if b == 0 {
                                assert!(gone, "a hole below the wall at {c:?}");
                            } else {
                                gone = false;
                                assert!(ids.is_fort(b) || b == ids.door || b == ids.door_top, "the wall at {c:?}: {}", w.def(b).name);
                            }
                        }
                    }
                }
            }
            assert!(w.blocks.iter().any(|&b| b == brick) && w.blocks.iter().any(|&b| b == wall));
        }
    }

    #[test]
    fn doors_between_rooms_and_out_and_platforms_between_floors() {
        let (mut w, l) = underworld();
        let forts = hell_houses(&mut w, &mut Rng::new(7), &l);
        let doors = count(&w, "obsidian_door");
        assert_eq!(doors, count(&w, "door_top"), "each door has its top");
        assert!(doors >= forts.len(), "{doors} doors for {} forts", forts.len());
        let door = w.id_of("obsidian_door");
        for i in 0..w.blocks.len() {
            if w.blocks[i] == door {
                let (x, y, z) = pos_of(&w, i);
                assert!(w.is_solid(x, y - 1, z), "a door at {:?} stands on the floor", (x, y, z));
                assert_eq!(w.get(x, y + 1, z), w.id_of("door_top"));
            }
        }
        // Stacked rooms: a hatch of platforms in the floor between them.
        let stacked = forts.iter().flat_map(|f| f.rooms.iter().map(move |r| (f, r))).filter(|(f, r)| f.rooms.iter().any(|o| o.y0 == r.y1 && o.x0 == r.x0 && o.z0 == r.z0)).count();
        assert!(stacked > 0, "some rooms are stacked");
        let platform = w.id_of("obsidian_platform");
        for f in &forts {
            for r in &f.rooms {
                if f.rooms.iter().any(|o| o.y0 == r.y1 && o.x0 == r.x0 && o.z0 == r.z0) {
                    let n = (r.x0..=r.x1).flat_map(|x| (r.z0..=r.z1).map(move |z| (x, z))).filter(|&(x, z)| w.get(x, r.y1, z) == platform).count();
                    assert!(n >= 1, "a hatch up out of {r:?}");
                }
            }
        }
    }

    #[test]
    fn torches_furniture_lights_and_hellforges() {
        let (mut w, l) = underworld();
        let forts = hell_houses(&mut w, &mut Rng::new(11), &l);
        let rooms: Vec<Room> = forts.iter().flat_map(|f| f.rooms.iter().copied()).collect();
        let inside = |p: (i32, i32, i32)| rooms.iter().any(|r| r.inside(p.0, p.1, p.2));
        let ids = Ids::of(&w);
        let torch = w.id_of("demon_wall_torch");
        let mut torches = Vec::new();
        for d in w.decorations.iter().filter(|d| d.kind == "rotation") {
            let (x, y, z) = d.pos;
            if w.get(x, y, z) == torch {
                let (fx, fz) = FACING[d.style as usize];
                assert!(ids.is_fort(w.get(x - fx, y, z - fz)), "a torch at {:?} on a fort's wall", d.pos);
                assert!(inside(d.pos) && w.get(x, y - 1, z) == 0, "inside, open under it");
                torches.push(d.pos);
            }
        }
        assert!(torches.len() >= forts.len() * 2, "{} torches for {} forts", torches.len(), forts.len());
        for (i, a) in torches.iter().enumerate() {
            for b in &torches[i + 1..] {
                assert!((a.0 - b.0).abs().max((a.1 - b.1).abs()).max((a.2 - b.2).abs()) > 5, "torches {a:?} and {b:?} 8 tiles apart");
            }
        }
        // Furniture on the floors.
        let furniture: usize = ids.pieces.iter().map(|&p| w.blocks.iter().filter(|&&b| b == p).count()).sum();
        assert!(furniture >= forts.len(), "{furniture} pieces for {} forts", forts.len());
        for i in 0..w.blocks.len() {
            let b = w.blocks[i];
            if ids.pieces.contains(&b) && b != ids.workbench {
                let p = pos_of(&w, i);
                assert!(inside(p), "furniture at {p:?} inside a room");
                let under = w.get(p.0, p.1 - 1, p.2);
                assert!(w.is_solid(p.0, p.1 - 1, p.2) || under == ids.table || under == ids.workbench, "on the floor (or a candle on a table): {p:?}");
            }
            if b == ids.chandelier || b == ids.lantern {
                let p = pos_of(&w, i);
                assert!(inside(p) && w.is_solid(p.0, p.1 + 1, p.2), "a light hangs from the ceiling at {p:?}");
            }
        }
        let banners: usize = ids.banners.iter().filter(|&&b| w.blocks.contains(&b)).count();
        assert!(banners <= 3, "three of the six banners at most");
        let forges = count(&w, "hellforge");
        assert_eq!(forges, ((21.0 * forts.len() as f64) / FORTS_SMALL).round() as usize, "Hellforges");
    }

    #[test]
    fn no_lava_falls_through_the_forts() {
        let (mut w, l) = underworld();
        for x in (40..220).step_by(7) {
            for z in (40..220).step_by(7) {
                w.decorations.push(Decoration { kind: "waterfall".into(), pos: (x, 39, z), style: 24 });
            }
        }
        let forts = hell_houses(&mut w, &mut Rng::new(13), &l);
        for d in w.decorations.iter().filter(|d| d.kind == "waterfall") {
            for r in forts.iter().flat_map(|f| &f.rooms) {
                assert!(!(d.pos.0 >= r.x0 && d.pos.0 <= r.x1 && d.pos.2 >= r.z0 && d.pos.2 <= r.z1), "a lava fall at {:?} over {r:?}", d.pos);
            }
        }
    }
}
