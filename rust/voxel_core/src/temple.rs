//! Terraria's Jungle Temple (WorldGen.makeTemple, templePart2, mayanTrap), in
//! 3D. Terraria's tiles are half a block here: its caverns are far deeper than
//! this world's (dungeon::depth_y), and the temple keeps its share of them.
//!
//! - **Where** (the "Jungle Temple" pass): on jungle grass in the Jungle's
//!   caves, from the cavern layer's top down to Terraria's 600 tiles above the
//!   world's bottom (depth_y: 300 under the surface); else in the Jungle's
//!   middle, 100 under the cavern layer's top.
//! - **Rooms**: 10-15 per 4200 tiles of width (here by the map's area, as the
//!   cabins count), each 25-49 across and 20-34 tall (no taller than wide;
//!   here as deep as it is across, 25-49), chained along x from the start:
//!   1-2 to a row, then a room down a row (one more to each row than the
//!   last), turning back the other way. Each joins the last overlapping 10
//!   and moves on until it overlaps none before it. The last - or the first
//!   within 80 of the Underworld - is the big one: 55-64 x 1.6 across, 45-49
//!   x 1.35 tall, 5-9 lower.
//! - **Brick** (makeTemple_GenerateBricks): each row's rooms in a box of
//!   Lihzahrd Brick 10 out round them, and between every two rows their
//!   corners joined by lines at 45 degrees and then straight, the brick
//!   filled in to them - here each side's edge sloping a block a row from
//!   the upper row's toward the lower's: a stepped, sloping ziggurat.
//! - **Insides**: each room hollowed 3-7 in from its edges, the edges
//!   wandering a block 1 time in 20; passages (templePather: 5-19 steps at
//!   a time toward a spot, 2-4 to each side of the way) from the start to a
//!   spot inside each room in turn, between them by the middle between the
//!   two (1 in 3) or down into the next one's top 0.2 or 0.8 along it or 80%
//!   down its side; the big room's spot within 10 of its middle. Then brick
//!   at least 6 thick round what's open (outerTempled), and stray brick and
//!   holes smoothed away (templeCleaner).
//! - **Entrance**: from the start out the other way from the first room,
//!   2-4 to each side, a block higher every 9-13, out through the brick; at
//!   the start the locked Lihzahrd Door (here in a brick wall across the
//!   passage: a 1 x 2 doorway).
//! - **The Lihzahrd Altar** in the big room, within 15 of its middle, on
//!   its floor.
//! - **Wooden Spikes** (1.1 x the rooms, give or take 25%): from a spot in a
//!   room straight to a floor, ceiling or wall, the brick facing the room
//!   within 3-9 of it turned to spikes, every other one sticking out a block
//!   (or in, on a ceiling or wall).
//! - templePart2: **traps** (1.9 x the rooms, give or take 15%: mayanTrap)
//!   on Lihzahrd Pressure Plates, wired (red, blue or green); **Lihzahrd
//!   Chests** (0.35 x, Chests' "lihzahrd_chest" loot: a Lihzahrd Power Cell);
//!   **statues** (1.25 x: the Lihzahrd, Watcher and Guardian Statues);
//!   **furniture** (1.35 x: a Lihzahrd Work Bench, Table or Chair); and the
//!   **Lizard King** painting (1, 2 in a world wider than 4200 tiles, and
//!   maybe 3 past 6400) in a big open space, here on the wall nearest it.
//!   - mayanTrap: from a spot down to the floor, with room round it (3 x 3
//!     clear) and no spikes or door under it, a plate and, 1 time in 3, a
//!     wall trap: a wall 5-50 away across (here along x or z), 0-2 over the
//!     floor, its brick turned to a Super Dart Trap (or within 10, 2 times
//!     in 3, a Flame Trap) facing the plate, 0-4 more stacked above it; else
//!     a ceiling trap: the ceiling at least 3 over it, its brick a Spiky Ball
//!     Trap (under 16 up, 2 times in 3, a Spear Trap) facing down, 1-4 more
//!     along it each way.
//!
//! The passes after it that don't keep out of structures (pots, chests,
//! pools, waterfalls, cobwebs, trees) are undone in it by `restore`.

use std::collections::{HashMap, HashSet};

use crate::world::{Decoration, World};
use crate::worldgen::{biome_regions, Layers, Rng, BIOME_JUNGLE, FACING};

type P = (i32, i32, i32);

/// Terraria's tiles to blocks here.
const TILE: f64 = 0.5;

fn t(tiles: i32) -> i32 {
    ((tiles as f64) * TILE).round() as i32
}

/// Chests' loot table for a Lihzahrd Chest (Chests.LOOT).
pub const LIHZAHRD_LOOT: i32 = 30;

pub struct Ids {
    brick: u16,
    jungle_grass: u16,
    spike: u16,
    door: u16,
    door_top: u16,
    altar: u16,
    chest: u16,
    plate: u16,
    super_dart: u16,
    flame: u16,
    spiky_ball: u16,
    spear: u16,
    statues: [u16; 3],
    furniture: [u16; 3],
    painting: u16,
}

impl Ids {
    pub fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        Ids {
            brick: id("lihzahrd_brick"),
            jungle_grass: id("jungle_grass"),
            spike: id("wooden_spike"),
            door: id("lihzahrd_door_locked"),
            door_top: id("door_top"),
            altar: id("lihzahrd_altar"),
            chest: id("lihzahrd_chest"),
            plate: id("lihzahrd_pressure_plate"),
            super_dart: id("super_dart_trap"),
            flame: id("flame_trap"),
            spiky_ball: id("spiky_ball_trap"),
            spear: id("spear_trap"),
            statues: ["lihzahrd_statue", "lihzahrd_watcher_statue", "lihzahrd_guardian_statue"].map(id),
            furniture: ["lihzahrd_work_bench", "lihzahrd_table", "lihzahrd_chair"].map(id),
            painting: id("lizard_king"),
        }
    }

    fn special(&self, b: u16) -> bool {
        b != 0 && [self.spike, self.door, self.door_top, self.altar, self.plate, self.super_dart, self.flame, self.spiky_ball, self.spear, self.chest].contains(&b)
    }
}

/// A room: [lo, hi) on each axis.
#[derive(Clone, Copy, Debug)]
struct Room {
    lo: P,
    hi: P,
}

impl Room {
    fn centred(c: P, size: P) -> Room {
        let lo = (c.0 - size.0 / 2, c.1 - size.1 / 2, c.2 - size.2 / 2);
        Room { lo, hi: (lo.0 + size.0, lo.1 + size.1, lo.2 + size.2) }
    }

    fn overlaps(&self, o: &Room) -> bool {
        self.lo.0 < o.hi.0 && o.lo.0 < self.hi.0 && self.lo.1 < o.hi.1 && o.lo.1 < self.hi.1 && self.lo.2 < o.hi.2 && o.lo.2 < self.hi.2
    }

    fn size(&self) -> P {
        (self.hi.0 - self.lo.0, self.hi.1 - self.lo.1, self.hi.2 - self.lo.2)
    }

    fn centre(&self) -> P {
        ((self.lo.0 + self.hi.0) / 2, (self.lo.1 + self.hi.1) / 2, (self.lo.2 + self.hi.2) / 2)
    }

    fn shrunk(&self, by: i32) -> Room {
        Room { lo: (self.lo.0 + by, self.lo.1 + by, self.lo.2 + by), hi: (self.hi.0 - by, self.hi.1 - by, self.hi.2 - by) }
    }
}

/// A box of flags over the temple and round it.
struct Grid {
    lo: P,
    size: P,
    cells: Vec<bool>,
}

impl Grid {
    fn new(lo: P, hi: P) -> Grid {
        let size = (hi.0 - lo.0 + 1, hi.1 - lo.1 + 1, hi.2 - lo.2 + 1);
        Grid { lo, size, cells: vec![false; (size.0 * size.1 * size.2).max(0) as usize] }
    }

    fn index(&self, (x, y, z): P) -> Option<usize> {
        let (a, b, c) = (x - self.lo.0, y - self.lo.1, z - self.lo.2);
        (a >= 0 && b >= 0 && c >= 0 && a < self.size.0 && b < self.size.1 && c < self.size.2)
            .then(|| (a + self.size.0 * (b + self.size.1 * c)) as usize)
    }

    fn get(&self, p: P) -> bool {
        self.index(p).is_some_and(|i| self.cells[i])
    }

    fn set(&mut self, p: P, v: bool) {
        if let Some(i) = self.index(p) {
            self.cells[i] = v;
        }
    }

    /// Flags within `r` (a cube) of a flag, by three passes along the axes.
    fn dilated(&self, r: i32) -> Grid {
        let mut out = Grid { lo: self.lo, size: self.size, cells: self.cells.clone() };
        for axis in 0..3 {
            let src = out.cells.clone();
            let (sx, sy, sz) = self.size;
            for c in 0..sz {
                for b in 0..sy {
                    for a in 0..sx {
                        let i = (a + sx * (b + sy * c)) as usize;
                        if !src[i] {
                            continue;
                        }
                        for d in -r..=r {
                            let (mut a2, mut b2, mut c2) = (a, b, c);
                            match axis {
                                0 => a2 += d,
                                1 => b2 += d,
                                _ => c2 += d,
                            }
                            if a2 >= 0 && b2 >= 0 && c2 >= 0 && a2 < sx && b2 < sy && c2 < sz {
                                out.cells[(a2 + sx * (b2 + sy * c2)) as usize] = true;
                            }
                        }
                    }
                }
            }
        }
        out
    }
}

/// The temple built: its box, what it dug out and put there (for `restore`).
pub struct Built {
    pub x: i32,
    pub z: i32,
    /// Its widest reach across from (x, z).
    pub reach: i32,
    pub door: P,
    pub altar: Option<P>,
    brick: Grid,
    open: Grid,
    own: Vec<(P, u16)>,
    decs: Vec<Decoration>,
}

/// The "Jungle Temple" and "Temple" passes. None without the Jungle (or its blocks).
pub fn temple(w: &mut World, rng: &mut Rng, l: &Layers) -> Option<Built> {
    let ids = Ids::new(w);
    if ids.brick == 0 || ids.jungle_grass == 0 {
        return None;
    }
    let &(_, jx, jz, jr) = biome_regions(w.sx, w.sz, w.seed).iter().find(|r| r.0 == BIOME_JUNGLE)?;
    let (y_lo, y_hi) = (crate::dungeon::depth_y(l, 300.0), l.cavern_top);
    let mut start = None;
    'find: for _ in 0..20_000 {
        let a = rng.unit() * std::f64::consts::TAU;
        let d = rng.unit().sqrt() * jr as f64 * 0.8;
        let (x, z) = (jx + (a.cos() * d) as i32, jz + (a.sin() * d) as i32);
        if !w.in_bounds(x, 0, z) {
            continue;
        }
        let y0 = rng.range(y_lo, y_hi.max(y_lo + 1));
        for y in (y_lo..=y0).rev() {
            if w.get(x, y, z) == ids.jungle_grass && w.get(x, y + 1, z) == 0 {
                start = Some((x, y, z));
                break 'find;
            }
        }
    }
    let start = start.unwrap_or((jx, crate::dungeon::depth_y(l, 230.0), jz));
    Some(make_temple(w, rng, &ids, l, start))
}

/// WorldGen.makeTemple and templePart2 from `start` (x, y, z).
pub fn make_temple(w: &mut World, rng: &mut Rng, ids: &Ids, l: &Layers, start: P) -> Built {
    let s = ((w.sx as f64 * w.sz as f64).sqrt() / 640.0).max(1.0);
    let mut count = rng.range((s * 10.0) as i32, (s * 16.0) as i32).max(2);
    let first_dir = if rng.range(0, 2) == 0 { 1 } else { -1 };
    let mut dir = first_dir;
    let (mut cx, mut cy) = (start.0, start.1);
    let mut row_len = rng.range(1, 3);
    let mut in_row = 0;
    let mut row = 0;
    let mut overlap = -t(10);
    let mut rooms: Vec<Room> = Vec::new();
    let mut rows: Vec<i32> = Vec::new();
    let mut i = 0;
    while i < count {
        in_row += 1;
        let mut room_dir = dir;
        let mut chosen = None;
        let mut down = false;
        for _ in 0..2000 {
            let (mut nx, mut ny) = (cx, cy);
            let mut wd = t(rng.range(25, 50));
            let mut ht = t(rng.range(20, 35)).min(wd);
            let mut dp = t(rng.range(25, 50));
            let near_hell = ny - t(70) <= l.underworld_top + t(10);
            let last = i == count - 1 || near_hell;
            if last {
                let (a, b) = (rng.range(55, 65), rng.range(45, 50).min(rng.range(55, 65)));
                wd = t((a as f64 * 1.6) as i32);
                ht = t((b as f64 * 1.35) as i32);
                dp = wd;
                ny -= t(rng.range(5, 10));
            }
            down = in_row > row_len;
            if down {
                ny -= rng.range(ht + 1, ht + 3) + overlap;
                nx += t(rng.range(-5, 6));
                room_dir = -dir;
            } else {
                nx += (rng.range(wd + 1, wd + 3) + overlap) * room_dir;
                ny += t(rng.range(-5, 6));
            }
            let nz = start.2 + t(rng.range(-5, 6));
            let r = Room::centred((nx, ny, nz), (wd, ht, dp));
            if last {
                count = i + 1;
                chosen = Some((r, nx, ny));
                break;
            }
            if rooms.iter().any(|o| o.overlaps(&r)) {
                if rng.range(0, 100) == 0 {
                    overlap += 1;
                }
                continue;
            }
            chosen = Some((r, nx, ny));
            break;
        }
        let Some((r, nx, ny)) = chosen else { break };
        let _ = &count;
        if down {
            row_len += 1;
            in_row = 1;
            row += 1;
        }
        rooms.push(r);
        rows.push(row);
        dir = room_dir;
        cx = nx;
        cy = ny;
        i += 1;
    }

    if rooms.is_empty() {
        rooms.push(Room::centred((start.0, start.1 - t(30), start.2), (t(60), t(40), t(60))));
        rows.push(0);
    }
    // Its bounds: the rooms and 10 round them (and room for the hull).
    let pad = t(10) + 2;
    let mut lo = (i32::MAX, i32::MAX, i32::MAX);
    let mut hi = (i32::MIN, i32::MIN, i32::MIN);
    for r in &rooms {
        lo = (lo.0.min(r.lo.0), lo.1.min(r.lo.1), lo.2.min(r.lo.2));
        hi = (hi.0.max(r.hi.0), hi.1.max(r.hi.1), hi.2.max(r.hi.2));
    }
    lo = ((lo.0 - pad).max(1), (lo.1 - pad).max(1), (lo.2 - pad).max(1));
    hi = ((hi.0 + pad).min(w.sx - 2), (hi.1 + pad).min(w.sy - 2), (hi.2 + pad).min(w.sz - 2));
    let mut brick = Grid::new((lo.0 - 20, lo.1 - 20, lo.2 - 20), (hi.0 + 20, hi.1 + 20, hi.2 + 20));
    let mut open = Grid::new(brick.lo, (brick.lo.0 + brick.size.0 - 1, brick.lo.1 + brick.size.1 - 1, brick.lo.2 + brick.size.2 - 1));
    let mut own: Vec<(P, u16)> = Vec::new();
    let mut decs: Vec<Decoration> = Vec::new();

    // Brick: each row's box, 10 out, and the slopes between rows.
    let rows_n = rows.iter().copied().max().unwrap_or(0) + 1;
    let mut boxes: Vec<Room> = Vec::new();
    for rw in 0..rows_n {
        let members: Vec<&Room> = rooms.iter().zip(&rows).filter(|(_, q)| **q == rw).map(|(r, _)| r).collect();
        if members.is_empty() {
            continue;
        }
        let mut b = *members[0];
        for m in &members[1..] {
            b.lo = (b.lo.0.min(m.lo.0), b.lo.1.min(m.lo.1), b.lo.2.min(m.lo.2));
            b.hi = (b.hi.0.max(m.hi.0), b.hi.1.max(m.hi.1), b.hi.2.max(m.hi.2));
        }
        let inflate = t(10);
        b.lo = (b.lo.0 - inflate, b.lo.1 - inflate, b.lo.2 - inflate);
        b.hi = (b.hi.0 + inflate, b.hi.1 + inflate, b.hi.2 + inflate);
        boxes.push(b);
    }
    let lay = |w: &mut World, brick: &mut Grid, p: P| {
        if w.in_bounds(p.0, p.1, p.2) {
            put(w, p, ids.brick);
            brick.set(p, true);
        }
    };
    for b in &boxes {
        for z in b.lo.2..b.hi.2 {
            for y in b.lo.1..b.hi.1 {
                for x in b.lo.0..b.hi.0 {
                    lay(w, &mut brick, (x, y, z));
                }
            }
        }
    }
    for a in 0..boxes.len() {
        for b in a + 1..boxes.len() {
            let (up, low) = if boxes[a].lo.1 > boxes[b].lo.1 { (boxes[a], boxes[b]) } else { (boxes[b], boxes[a]) };
            // From the upper box's bottom down to the lower's top, each edge a
            // block a row toward the lower's.
            let toward = |from: i32, to: i32, k: i32| if to < from { (from - k).max(to) } else { (from + k).min(to) };
            for y in low.hi.1..up.lo.1 {
                let k = up.lo.1 - y;
                let (x0, x1) = (toward(up.lo.0, low.lo.0, k), toward(up.hi.0, low.hi.0, k));
                let (z0, z1) = (toward(up.lo.2, low.lo.2, k), toward(up.hi.2, low.hi.2, k));
                for z in z0..z1 {
                    for x in x0..x1 {
                        lay(w, &mut brick, (x, y, z));
                    }
                }
            }
        }
    }

    // Hollow each room 3-7 in, its edges wandering.
    let dig = |w: &mut World, brick: &mut Grid, open: &mut Grid, p: P| {
        if w.in_bounds(p.0, p.1, p.2) {
            put(w, p, 0);
            brick.set(p, false);
            open.set(p, true);
        }
    };
    for r in &rooms {
        let lo = (r.lo.0 + t(rng.range(3, 8)).max(1), r.lo.1 + t(rng.range(3, 8)).max(1), r.lo.2 + t(rng.range(3, 8)).max(1));
        let hi = (r.hi.0 - t(rng.range(3, 8)).max(1), r.hi.1 - t(rng.range(3, 8)).max(1), r.hi.2 - t(rng.range(3, 8)).max(1));
        let mid = ((lo.0 + hi.0) / 2, (lo.1 + hi.1) / 2, (lo.2 + hi.2) / 2);
        let (mut a, mut b) = ([lo.0, lo.1, lo.2], [hi.0, hi.1, hi.2]);
        let m = [mid.0, mid.1, mid.2];
        let (l3, h3) = ([lo.0, lo.1, lo.2], [hi.0, hi.1, hi.2]);
        for x in lo.0..hi.0 {
            for k in 0..3 {
                if rng.range(0, 20) == 0 {
                    a[k] += rng.range(-1, 2);
                }
                if rng.range(0, 20) == 0 {
                    b[k] += rng.range(-1, 2);
                }
                a[k] = a[k].clamp(l3[k], m[k]);
                b[k] = b[k].clamp(m[k], h3[k]);
            }
            if x < a[0] || x >= b[0] {
                continue;
            }
            for y in a[1]..b[1] {
                for z in a[2]..b[2] {
                    dig(w, &mut brick, &mut open, (x, y, z));
                }
            }
        }
    }

    // The passages: from the start through each room in turn.
    let mut pos = (start.0, start.1 + 1, start.2);
    let n = rooms.len();
    let path_to = |w: &mut World, brick: &mut Grid, open: &mut Grid, rng: &mut Rng, pos: &mut P, to: P| {
        for _ in 0..200 {
            let steps = rng.range(5, 20);
            let half = t(rng.range(2, 5)).max(1);
            for _ in 0..steps {
                if *pos == to {
                    break;
                }
                pos.0 += (to.0 - pos.0).signum();
                pos.1 += (to.1 - pos.1).signum();
                pos.2 += (to.2 - pos.2).signum();
                for z in pos.2 - half..pos.2 + half {
                    for y in pos.1 - half..pos.1 + half {
                        for x in pos.0 - half..pos.0 + half {
                            dig(w, brick, open, (x, y, z));
                        }
                    }
                }
            }
            if *pos == to {
                break;
            }
        }
    };
    for k in 0..n {
        let inner = rooms[k].shrunk(t(8));
        let spot = if k == n - 1 {
            let c = rooms[k].centre();
            (c.0 + t(rng.range(-10, 10)), c.1 + t(rng.range(-10, 10)), c.2 + t(rng.range(-10, 10)))
        } else {
            let pick = |rng: &mut Rng, a: i32, b: i32| if b > a { rng.range(a, b) } else { a };
            (pick(rng, inner.lo.0, inner.hi.0), pick(rng, inner.lo.1, inner.hi.1), pick(rng, inner.lo.2, inner.hi.2))
        };
        path_to(w, &mut brick, &mut open, rng, &mut pos, spot);
        if k + 1 >= n {
            break;
        }
        let (cur, next) = (rooms[k], rooms[k + 1]);
        let (a, b) = (cur.centre(), next.centre());
        let via = if rng.range(0, 3) == 0 {
            ((a.0 + b.0) / 2, (a.1 + b.1) / 2, (a.2 + b.2) / 2)
        } else if next.hi.1 <= cur.lo.1 {
            // Down into the next one's top, toward its far side.
            let share = if (k == 0 && first_dir > 0) || (k > 0 && next.lo.0 >= cur.lo.0) { 0.8 } else { 0.2 };
            (next.lo.0 + (next.size().0 as f64 * share) as i32, next.hi.1, (a.2 + b.2) / 2)
        } else {
            ((a.0 + b.0) / 2, next.hi.1 - (next.size().1 as f64 * 0.8) as i32, (a.2 + b.2) / 2)
        };
        let to = (via.0 + t(rng.range(-6, 7)), via.1 + t(rng.range(-6, 7)), via.2 + t(rng.range(-6, 7)));
        path_to(w, &mut brick, &mut open, rng, &mut pos, to);
    }

    // Brick at least 6 round what's open (outerTempled).
    let near = open.dilated(t(6));
    for z in lo.2..=hi.2 {
        for y in lo.1..=hi.1 {
            for x in lo.0..=hi.0 {
                let p = (x, y, z);
                if near.get(p) && !open.get(p) && !brick.get(p) && w.in_bounds(x, y, z) {
                    put(w, p, ids.brick);
                    brick.set(p, true);
                }
            }
        }
    }

    // The entrance: out the other way from the first room, rising now and
    // then, through the brick. The door goes where it first runs through
    // solid brick (Terraria's at the start, in 2D a wall across everything).
    let away = -first_dir;
    let half = t(rng.range(2, 5)).max(1);
    let every = rng.range(9, 14);
    let (mut ex, mut ey) = (start.0, start.1 + half);
    let mut since = 0;
    let mut door_at: Option<(i32, i32)> = None;
    for _ in 0..400 {
        since += 1;
        if since >= every {
            since = 0;
            ey += 1;
        }
        ex += away;
        let mut any = false;
        let mut solid = true;
        for z in start.2 - half - 1..=start.2 + half {
            for y in ey - half - 1..=ey + half {
                let p = (ex, y, z);
                let inside = z >= start.2 - half && z < start.2 + half && y >= ey - half && y < ey + half;
                if !brick.get(p) {
                    solid = false;
                }
                if inside && (brick.get(p) || open.get(p)) {
                    any = true;
                }
            }
        }
        if solid && door_at.is_none() {
            door_at = Some((ex, ey));
        }
        if !any {
            break;
        }
        for z in start.2 - half..start.2 + half {
            for y in ey - half..ey + half {
                if brick.get((ex, y, z)) {
                    dig(w, &mut brick, &mut open, (ex, y, z));
                }
            }
        }
    }

    // The locked door, in a wall of brick across the passage.
    let (dx, dy) = door_at.unwrap_or((start.0, start.1 + half));
    let floor = dy - half;
    let door = (dx, floor, start.2);
    for z in start.2 - half..start.2 + half {
        for y in floor..dy + half {
            let p = (dx, y, z);
            if p == door || p == (door.0, door.1 + 1, door.2) {
                dig(w, &mut brick, &mut open, p);
                continue;
            }
            put(w, p, ids.brick);
            brick.set(p, true);
            open.set(p, false);
        }
    }
    if !w.is_solid(door.0, door.1 - 1, door.2) {
        put(w, (door.0, door.1 - 1, door.2), ids.brick);
        brick.set((door.0, door.1 - 1, door.2), true);
    }
    if ids.door != 0 {
        put(w, door, ids.door);
        put(w, (door.0, door.1 + 1, door.2), ids.door_top);
        own.push((door, ids.door));
        own.push(((door.0, door.1 + 1, door.2), ids.door_top));
        // Facing out of the temple (Doors: bits 0-1).
        let out = FACING.iter().position(|&f| f == (away, 0)).unwrap_or(0) as i32;
        decs.push(Decoration { kind: "rotation".into(), pos: door, style: out });
    }

    // Stray brick and holes smoothed away (templeCleaner), both ways round.
    for pass in 0..2 {
        let order: Vec<i32> = if pass == 0 { (lo.0..=hi.0).collect() } else { (lo.0..=hi.0).rev().collect() };
        for &x in &order {
            for y in lo.1..=hi.1 {
                for z in lo.2..=hi.2 {
                    let p = (x, y, z);
                    if p == door || p == (door.0, door.1 + 1, door.2) {
                        continue;
                    }
                    let around = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
                        .iter()
                        .filter(|d| w.get(x + d.0, y + d.1, z + d.2) == ids.brick)
                        .count();
                    let b = w.get(x, y, z);
                    if b == ids.brick && brick.get(p) && around <= 1 {
                        dig(w, &mut brick, &mut open, p);
                    } else if b == 0 && open.get(p) && around >= 5 {
                        put(w, p, ids.brick);
                        brick.set(p, true);
                        open.set(p, false);
                    }
                }
            }
        }
    }

    // The Lihzahrd Altar in the big room, on its floor.
    let big = rooms[n - 1];
    let mut altar = None;
    for _ in 0..1000 {
        let c = big.centre();
        let (x, z) = (c.0 + t(rng.range(-15, 16)), c.2 + t(rng.range(-15, 16)));
        let mut y = c.1 + t(rng.range(-15, 16));
        if !open.get((x, y, z)) {
            continue;
        }
        while y > big.lo.1 && w.get(x, y - 1, z) == 0 {
            y -= 1;
        }
        if w.get(x, y - 1, z) == ids.brick && w.get(x, y, z) == 0 && w.get(x, y + 1, z) == 0 && ids.altar != 0 {
            put(w, (x, y, z), ids.altar);
            own.push(((x, y, z), ids.altar));
            altar = Some((x, y, z));
            break;
        }
    }

    let is_open = |w: &World, open: &Grid, p: P| open.get(p) && w.get(p.0, p.1, p.2) == 0;
    let random_open = |rng: &mut Rng| {
        let r = rooms[rng.range(0, n as i32) as usize];
        let pick = |rng: &mut Rng, a: i32, b: i32| if b > a { rng.range(a, b) } else { a };
        (pick(rng, r.lo.0, r.hi.0), pick(rng, r.lo.1, r.hi.1), pick(rng, r.lo.2, r.hi.2))
    };

    // Wooden Spikes.
    let mut spikes_left = (n as f64 * 1.1 * (1.0 + rng.range(-25, 26) as f64 * 0.01)).round() as i32;
    let mut misses = 0;
    while spikes_left > 0 && ids.spike != 0 {
        misses += 1;
        if misses > 1000 {
            misses = 0;
            spikes_left -= 1;
        }
        let p = random_open(rng);
        if !is_open(w, &open, p) {
            continue;
        }
        // Straight to a floor or ceiling (half the time), else a wall.
        let d: P = if rng.range(0, 2) == 0 {
            (0, if rng.range(0, 2) == 0 { 1 } else { -1 }, 0)
        } else if rng.range(0, 2) == 0 {
            (if rng.range(0, 2) == 0 { 1 } else { -1 }, 0, 0)
        } else {
            (0, 0, if rng.range(0, 2) == 0 { 1 } else { -1 })
        };
        let mut q = p;
        let mut steps = 0;
        while is_open(w, &open, (q.0 + d.0, q.1 + d.1, q.2 + d.2)) && steps < 100 {
            q = (q.0 + d.0, q.1 + d.1, q.2 + d.2);
            steps += 1;
        }
        let hit = (q.0 + d.0, q.1 + d.1, q.2 + d.2);
        let r = t(rng.range(3, 10)).max(1);
        // Not near the door or the altar.
        let mut clear = true;
        for z in hit.2 - r..=hit.2 + r {
            for y in hit.1 - r..=hit.1 + r {
                for x in hit.0 - r..=hit.0 + r {
                    let b = w.get(x, y, z);
                    if b == ids.door || b == ids.door_top || b == ids.altar {
                        clear = false;
                    }
                }
            }
        }
        if !clear {
            continue;
        }
        let mut made = false;
        let mut alt = rng.range(0, 2);
        for z in hit.2 - r..=hit.2 + r {
            for y in hit.1 - r..=hit.1 + r {
                for x in hit.0 - r..=hit.0 + r {
                    let c = (x, y, z);
                    let front = (x - d.0, y - d.1, z - d.2);
                    if w.get(x, y, z) != ids.brick || !brick.get(c) || w.is_solid(front.0, front.1, front.2) {
                        continue;
                    }
                    put(w, c, ids.spike);
                    own.push((c, ids.spike));
                    made = true;
                    if alt == 0 {
                        // Every other one sticks out a block (into the wall on a ceiling or wall).
                        let more = if d.1 == -1 { front } else { (x + d.0, y + d.1, z + d.2) };
                        if (w.get(more.0, more.1, more.2) == 0 && open.get(more)) || w.get(more.0, more.1, more.2) == ids.brick {
                            put(w, more, ids.spike);
                            own.push((more, ids.spike));
                        }
                    }
                    alt = 1 - alt;
                }
            }
        }
        if made {
            misses = 0;
            spikes_left -= 1;
        }
    }

    // templePart2: traps.
    let mut traps_left = (n as f64 * 1.9 * (1.0 + rng.range(-15, 16) as f64 * 0.01)).round() as i32;
    let mut misses = 0;
    while traps_left > 0 && ids.plate != 0 {
        let p = random_open(rng);
        if is_open(w, &open, p) && mayan_trap(w, rng, ids, &open, &brick, p, &mut own, &mut decs) {
            traps_left -= 1;
            misses = 0;
        } else {
            misses += 1;
        }
        if misses > 100 {
            misses = 0;
            traps_left -= 1;
        }
    }

    // Lihzahrd Chests.
    let mut chests_left = (n as f64 * 0.35 * (1.0 + rng.range(-15, 16) as f64 * 0.01)).round() as i32;
    let mut chests: Vec<P> = Vec::new();
    for _ in 0..10_000 {
        if chests_left <= 0 || ids.chest == 0 {
            break;
        }
        let p = random_open(rng);
        let Some(f) = on_floor(w, &open, p, ids) else { continue };
        if chests.iter().any(|c| (c.0 - f.0).abs() < 8 && (c.1 - f.1).abs() < 8 && (c.2 - f.2).abs() < 8) {
            continue;
        }
        put(w, f, ids.chest);
        own.push((f, ids.chest));
        decs.push(Decoration { kind: "chest".into(), pos: f, style: LIHZAHRD_LOOT });
        decs.push(Decoration { kind: "rotation".into(), pos: f, style: rng.range(0, 4) });
        chests.push(f);
        chests_left -= 1;
    }
    // Statues, then furniture.
    for (share, lo_pc, hi_pc, set) in [(1.25, -25, 36, ids.statues), (1.35, -15, 26, ids.furniture)] {
        let mut left = (n as f64 * share * (1.0 + rng.range(lo_pc, hi_pc) as f64 * 0.01)).round() as i32;
        for _ in 0..10_000 {
            if left <= 0 {
                break;
            }
            let p = random_open(rng);
            let Some(f) = on_floor(w, &open, p, ids) else { continue };
            let b = set[rng.range(0, 3) as usize];
            if b == 0 {
                continue;
            }
            put(w, f, b);
            own.push((f, b));
            decs.push(Decoration { kind: "rotation".into(), pos: f, style: rng.range(0, 4) });
            left -= 1;
        }
    }
    // The Lizard King, in a big open space, on the wall nearest it.
    let mut paintings = 1 + if s > 1.0 { 1 } else { 0 } + if s > 6400.0 / 4200.0 { rng.range(0, 2) } else { 0 };
    let mut hung: Vec<P> = Vec::new();
    for _ in 0..10_000 {
        if paintings <= 0 || ids.painting == 0 {
            break;
        }
        let p = random_open(rng);
        if !is_open(w, &open, p) || hung.iter().any(|h| (h.0 - p.0).abs() < t(70) && (h.2 - p.2).abs() < t(70)) {
            continue;
        }
        let r = t(4);
        let roomy = (-r..=r).all(|dz| (-r..=r).all(|dy| (-r..=r).all(|dx| w.get(p.0 + dx, p.1 + dy, p.2 + dz) != ids.brick)));
        if !roomy {
            continue;
        }
        let d = FACING[rng.range(0, 4) as usize];
        let mut q = p;
        while is_open(w, &open, (q.0 + d.0, q.1, q.2 + d.1)) {
            q = (q.0 + d.0, q.1, q.2 + d.1);
        }
        if w.get(q.0 + d.0, q.1, q.2 + d.1) != ids.brick {
            continue;
        }
        put(w, q, ids.painting);
        own.push((q, ids.painting));
        let out = FACING.iter().position(|&f| f == (-d.0, -d.1)).unwrap_or(0) as i32;
        decs.push(Decoration { kind: "rotation".into(), pos: q, style: out });
        hung.push(p);
        paintings -= 1;
    }

    // What was there before goes (from the earlier passes), then its own.
    w.decorations.retain(|d| !(brick.get(d.pos) || open.get(d.pos)));
    w.decorations.extend(decs.iter().cloned());
    w.decorations.push(Decoration { kind: "temple".into(), pos: door, style: 0 });
    let reach = (hi.0 - start.0).abs().max((lo.0 - start.0).abs()).max((hi.2 - start.2).abs()).max((lo.2 - start.2).abs());
    w.structures.push((lo, hi));
    Built { x: start.0, z: start.2, reach, door, altar, brick, open, own, decs }
}

/// A floor cell under `p`, in the temple, empty with room over it.
fn on_floor(w: &World, open: &Grid, p: P, ids: &Ids) -> Option<P> {
    if !open.get(p) || w.get(p.0, p.1, p.2) != 0 {
        return None;
    }
    let mut y = p.1;
    while w.get(p.0, y - 1, p.2) == 0 && open.get((p.0, y - 1, p.2)) {
        y -= 1;
    }
    (w.get(p.0, y - 1, p.2) == ids.brick && w.get(p.0, y + 1, p.2) == 0).then_some((p.0, y, p.2))
}

/// WorldGen.mayanTrap from a spot in the temple: a plate on the floor under
/// it, wired to a wall trap across (1 in 3) or a ceiling trap over it.
#[allow(clippy::too_many_arguments)]
fn mayan_trap(w: &mut World, rng: &mut Rng, ids: &Ids, open: &Grid, brick: &Grid, p: P, own: &mut Vec<(P, u16)>, decs: &mut Vec<Decoration>) -> bool {
    let ceiling = rng.range(0, 3) != 0;
    let mut y = p.1;
    while w.get(p.0, y - 1, p.2) == 0 {
        y -= 1;
        if y < 2 {
            return false;
        }
    }
    let under = w.get(p.0, y - 1, p.2);
    if under != ids.brick || w.liquid_at(p.0, y, p.2).0 == crate::world::LIQ_LAVA {
        return false;
    }
    let plate = (p.0, y, p.2);
    // Room round it: 3 x 3 and 3 tall clear.
    for dz in -1..=1 {
        for dy in 0..=2 {
            for dx in -1..=1 {
                if w.get(plate.0 + dx, plate.1 + dy, plate.2 + dz) != 0 {
                    return false;
                }
            }
        }
    }
    let colour = [crate::wires::RED, 2, 4][rng.range(0, 3) as usize];
    let temple_brick = |w: &World, c: P| w.get(c.0, c.1, c.2) == ids.brick && brick.get(c) && !ids.special(w.get(c.0, c.1, c.2));
    if !ceiling {
        let h = plate.1 + rng.range(0, 3);
        let axis = if rng.range(0, 2) == 0 { (1, 0) } else { (0, 1) };
        let find = |w: &World, s: i32| -> Option<(P, i32)> {
            for d in 1..=200 {
                let c = (plate.0 + axis.0 * d * s, h, plate.2 + axis.1 * d * s);
                if !w.in_bounds(c.0, c.1, c.2) {
                    return None;
                }
                if w.is_solid(c.0, c.1, c.2) {
                    return Some((c, d));
                }
            }
            None
        };
        let ok = |w: &World, hit: Option<(P, i32)>| -> Option<(P, i32)> {
            let (c, d) = hit?;
            (d > t(5) && d < t(50) && w.is_solid(c.0, c.1 - 1, c.2) && temple_brick(w, c) && !ids.special(w.get(c.0, c.1 - 1, c.2))).then_some((c, d))
        };
        let (a, b) = (ok(w, find(w, -1)), ok(w, find(w, 1)));
        let ((wall, d), s) = match (a, b) {
            (Some(a), Some(b)) => {
                if rng.range(0, 2) == 0 { (a, -1) } else { (b, 1) }
            }
            (Some(a), None) => (a, -1),
            (None, Some(b)) => (b, 1),
            _ => return false,
        };
        let kind = if d < t(10) && rng.range(0, 3) != 0 { ids.flame } else { ids.super_dart };
        if kind == 0 {
            return false;
        }
        put(w, plate, ids.plate);
        own.push((plate, ids.plate));
        let back = (-axis.0 * s, -axis.1 * s);
        let facing = FACING.iter().position(|&f| f == back).unwrap_or(0) as i32;
        set_trap(w, own, decs, wall, kind, facing);
        // 0-4 more stacked above it, while there's wall behind and room in front.
        let mut c = wall;
        for _ in 0..rng.range(0, 5) {
            c = (c.0, c.1 + 1, c.2);
            let behind = (c.0 + axis.0 * s, c.1, c.2 + axis.1 * s);
            let front = (c.0 - axis.0 * s, c.1, c.2 - axis.1 * s);
            if !temple_brick(w, c) || !w.is_solid(behind.0, behind.1, behind.2) || w.is_solid(front.0, front.1, front.2) {
                break;
            }
            set_trap(w, own, decs, c, kind, facing);
            decs.push(Decoration { kind: "wire".into(), pos: c, style: colour });
        }
        lay_wire(decs, plate, wall, colour);
        return true;
    }
    // Up to the ceiling, at least 3 over.
    let mut top = plate.1;
    while !w.is_solid(plate.0, top, plate.2) {
        top += 1;
        if top >= w.sy - 1 || !open.get((plate.0, top, plate.2)) && !w.is_solid(plate.0, top, plate.2) {
            return false;
        }
    }
    let up = top - plate.1;
    if up < t(3).max(2) {
        return false;
    }
    let kind = if up < t(16) && rng.range(0, 3) != 0 { ids.spear } else { ids.spiky_ball };
    let c = (plate.0, top, plate.2);
    if kind == 0 || !temple_brick(w, c) {
        return false;
    }
    put(w, plate, ids.plate);
    own.push((plate, ids.plate));
    // Facing down (Wiring.trap_dir: 4).
    set_trap(w, own, decs, c, kind, 4);
    let axis = if rng.range(0, 2) == 0 { (1, 0) } else { (0, 1) };
    for s in [-1, 1] {
        let mut q = c;
        for _ in 0..rng.range(1, 5) {
            q = (q.0 + axis.0 * s, q.1, q.2 + axis.1 * s);
            if !w.is_solid(q.0, q.1 + 1, q.2) || w.is_solid(q.0, q.1 - 1, q.2) || !temple_brick(w, q) {
                break;
            }
            set_trap(w, own, decs, q, kind, 4);
            decs.push(Decoration { kind: "wire".into(), pos: q, style: colour });
        }
    }
    lay_wire(decs, plate, c, colour);
    true
}

/// A trap block at `c`, facing `facing` (Wiring.trap_dir).
fn set_trap(w: &mut World, own: &mut Vec<(P, u16)>, decs: &mut Vec<Decoration>, c: P, kind: u16, facing: i32) {
    put(w, c, kind);
    own.push((c, kind));
    decs.push(Decoration { kind: "rotation".into(), pos: c, style: facing });
}

/// Wire of `colour` from `from` to `to` (as wires::lay), into `decs`.
fn lay_wire(decs: &mut Vec<Decoration>, from: P, to: P, colour: i32) {
    let mut p = from;
    decs.push(Decoration { kind: "wire".into(), pos: p, style: colour });
    for axis in [0, 2, 1] {
        loop {
            let (cur, target) = match axis {
                0 => (p.0, to.0),
                1 => (p.1, to.1),
                _ => (p.2, to.2),
            };
            if cur == target {
                break;
            }
            let step = (target - cur).signum();
            match axis {
                0 => p.0 += step,
                1 => p.1 += step,
                _ => p.2 += step,
            }
            decs.push(Decoration { kind: "wire".into(), pos: p, style: colour });
        }
    }
}

/// The passes between the temple and the end don't all keep out of it
/// (pots, chests, pools, waterfalls, webs, trees): its brick, passages and
/// own things are put back, and what they left in it goes.
pub fn restore(w: &mut World, b: &Built) {
    let mine: HashMap<P, u16> = b.own.iter().copied().collect();
    let brick = Ids::new(w).brick;
    let (sx, sy, sz) = b.brick.size;
    for c in 0..sz {
        for bb in 0..sy {
            for a in 0..sx {
                let p = (b.brick.lo.0 + a, b.brick.lo.1 + bb, b.brick.lo.2 + c);
                if !w.in_bounds(p.0, p.1, p.2) {
                    continue;
                }
                if let Some(&id) = mine.get(&p) {
                    put(w, p, id);
                } else if b.brick.get(p) {
                    put(w, p, brick);
                } else if b.open.get(p) {
                    put(w, p, 0);
                }
            }
        }
    }
    let ours: HashSet<(String, P)> = b.decs.iter().map(|d| (d.kind.clone(), d.pos)).collect();
    w.decorations.retain(|d| !((b.brick.get(d.pos) || b.open.get(d.pos)) && d.kind != "temple") || ours.contains(&(d.kind.clone(), d.pos)));
}

fn put(w: &mut World, (x, y, z): P, id: u16) {
    if w.in_bounds(x, y, z) {
        let i = w.idx(x, y, z);
        w.blocks[i] = id;
        w.liquid[i] = 0;
    }
}
