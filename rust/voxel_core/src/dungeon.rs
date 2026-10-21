//! Terraria's Dungeon below its entrance (1.4.5's
//! Terraria.GameContent.Generation.Dungeon: DungeonCrawler.MakeDungeon with
//! the LegacyDungeonLayoutProvider, the layout every normal world gets), its
//! 2D layout grown into 3D. Sizes are Terraria's, a block a tile (the player
//! jumps about as many blocks as Terraria's does tiles); depths are
//! Terraria's mapped onto this world's layers (`depth_y`).
//!
//! - **Entrance hallway** (LegacyEntranceDungeonHall): Terraria digs it from
//!   the dungeon's highest room up to the surface and builds the entrance
//!   where it comes out; here the entrance stands first, so the hallway is dug
//!   down from the back of its hall instead, segment by segment (5-8 strong,
//!   10-29 steps, rising one block a step and 1-3 across, or 0.5-0.75, now
//!   and then 2 up a step), each segment heading back toward the entrance's
//!   column (Terraria's toward the top room's) and never more than half a
//!   block a step toward the world's edge (a quarter of dungeons: turned back
//!   instead, useSkewedDungeonEntranceHalls), until it's as deep as
//!   Terraria's dungeon starts: halfway from the surface to the cavern layer,
//!   give or take 200 tiles, at least 60 under the ground.
//! - **Layout** (LegacyDungeonLayout): from there a walker takes maxTilesX / 60
//!   steps (and up to a third more; maxTilesX here: Terraria's width for a
//!   world this size), each a hall, or (no sooner than 5 steps after the last,
//!   then 1 time in 3) a room - half the time a side branch instead: a hall or
//!   two and a room, then back. A room (LegacyDungeonRoom) is a box of brick
//!   0.8 x its strength (15-29) + 5 to each side round an open box half its
//!   strength to each side, moved 10-19 times along a drifting velocity; a hall
//!   (LegacyDungeonHall) the same with strength 4-5 (brick 4-9 more round it),
//!   35-79 steps straight up, down or across (Terraria's left or right: here
//!   any of the four ways), a horizontal one slanting a fifth of a block a step
//!   1 time in 3 and 10-49% stronger 2 times in 3, a vertical one leaning 0.2-0.4
//!   across or half as long; 1 time in 5 twice as strong and half as long. It
//!   won't head back the way the last came, nor along a line that leaves the
//!   dungeon and runs into it again. It's sent down while above 100 tiles below
//!   the cavern layer's top, up within 100 of the underworld, inward near the
//!   world's edge and outward once more than a quarter of the world from it
//!   (here also back toward where it started once that far from it: the 3D
//!   dungeon has two ways across to wander). Brick doesn't go where the dungeon
//!   is already (Terraria: where a dungeon wall is; here a mask of the cells
//!   the dungeon has walled), so later boxes don't fill earlier ones.
//! - **Doors and platforms** (CalculatePlatformsAndDoors): a horizontal hall
//!   gets a door at each end, a vertical one a platform; a room a platform
//!   where a hall opens into its top or bottom and a door where one opens into
//!   a side. A door (DungeonGlobalDoors) goes within 10 blocks along the hall
//!   (3 by a room) where the passage is lowest (under 20, at least 3 high), no
//!   other door within 20, nothing in the way: brick fills the passage round
//!   it (Terraria's column above it to the ceiling), 2 in 3 the plain Dungeon
//!   Door, else the brick colour's. A platform (DungeonGlobalPlatforms) spans
//!   the shaft within 5 blocks (3) of its spot where it's at most 10 across
//!   (20 near the surface), with 3 open below and 5 above.
//! - **Features**, in Terraria's order: spikes, doors, wall variants,
//!   platforms, shelves, chests, lights, banners (DungeonGlobal*). The wall
//!   variants (brick, slab and tiled: 5 rounds of a blob of each, radius 16-96)
//!   aren't drawn - the dungeon has no back wall here - but pick what Terraria
//!   picks by them: spikes only in brick-wall parts, each part's shelf,
//!   lantern and banner styles.
//!   - Spikes: 42 strips on floors and ceilings, 42 on walls (per 4200 tiles of
//!     width), 5-12 each way from a spot, the surface block turning to spikes
//!     and every other one sticking 2 out; on floors and ceilings each strip
//!     runs across the passage too (Terraria's floor is a line).
//!   - Shelves: maxTilesX / 20, 1-3 long on a wall with 6 open in front and
//!     no floor under it, half with books (1 in 50 the Water Bolt, deep down),
//!     else a 1 in 4 a Water Candle or a Lesser Healing or Mana Potion on it.
//!     Terraria's shelf sticks out of its wall; here it runs along the wall.
//!   - Chests: one in each room (the room's last box, its middle 0.4 x its
//!     strength): Locked Gold Chests holding, in turn, the Muramasa, Cobalt
//!     Shield, Aqua Scepter, Blue Moon, Magic Missile, Valor, a Golden Key (a
//!     wooden chest) and Handgun; near the surface, a wooden chest with a key.
//!   - Lights: 28 per 4200 tiles, hanging from ceilings 15 apart, 1 in 7 the
//!     brick colour's Dungeon Chandelier (where 15 is open below), else a
//!     lantern of the part's style (three of the seven lanterns); each with a
//!     switch on a wall within sight below, and 2 in 3 switched off.
//!   - Banners: 200 tries per 4200 tiles, under ceilings with 3 open below, the
//!     part's two banners: Marching Bones Banner or Necromantic Sign (brick),
//!     Rusted Company Standard or Ragged Brotherhood Sigil (slab), Molten Legion
//!     Flag or Diabolic Sigil (tiled). Terraria hangs them on the back wall
//!     from the ceiling; here they hang on a wall, their tops at the ceiling.
//!
//! Not here yet: Terraria's cracked-brick pit traps, dart and boulder traps,
//! locked biome chests, furniture and paintings.

use crate::world::{Decoration, World};
use crate::worldgen::{Layers, Rng, FACING};

type P = (i32, i32, i32);
type V = (f64, f64, f64);

/// Terraria's tiles below its surface -> this world's y. A small Terraria
/// world has about 130 tiles from its surface to the cavern layer and 580
/// from there to the underworld; this world's layers stand in for those.
pub fn depth_y(l: &Layers, d: f64) -> i32 {
    let (s, c, u) = (l.surface_base as f64, l.cavern_top as f64, l.underworld_top as f64);
    let y = if d <= 130.0 { s - d * (s - c) / 130.0 } else { c - (d - 130.0) * (c - u) / 580.0 };
    y.round() as i32
}

const UP: P = (0, 1, 0);
const DOWN: P = (0, -1, 0);
const ACROSS: [P; 4] = [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)];

/// The cells the dungeon has walled (Terraria's dungeon walls: its open
/// insides and the inner layers of its brick), in a box round its start.
struct Mask {
    x0: i32,
    z0: i32,
    y0: i32,
    w: i32,
    d: i32,
    h: i32,
    bits: Vec<u64>,
}

impl Mask {
    fn new(x0: i32, z0: i32, y0: i32, w: i32, d: i32, h: i32) -> Self {
        let n = (w.max(0) as usize) * (d.max(0) as usize) * (h.max(0) as usize);
        Mask { x0, z0, y0, w, d, h, bits: vec![0; n / 64 + 1] }
    }
    fn idx(&self, p: P) -> Option<usize> {
        let (x, y, z) = (p.0 - self.x0, p.1 - self.y0, p.2 - self.z0);
        if x < 0 || y < 0 || z < 0 || x >= self.w || y >= self.h || z >= self.d {
            return None;
        }
        Some(((x * self.d + z) * self.h + y) as usize)
    }
    fn get(&self, p: P) -> bool {
        self.idx(p).map_or(false, |i| self.bits[i / 64] >> (i % 64) & 1 == 1)
    }
    fn set(&mut self, p: P) {
        if let Some(i) = self.idx(p) {
            self.bits[i / 64] |= 1 << (i % 64);
        }
    }
}

struct Ids {
    brick: u16,
    /// Every dungeon brick colour (Terraria's tileDungeon).
    bricks: Vec<u16>,
    platform: u16,
    door: u16,
    colour_door: u16,
    door_top: u16,
    chest: u16,
    locked_chest: u16,
    book: u16,
    water_bolt: u16,
    water_candle: u16,
    potions: [u16; 2],
    shelves: [u16; 4],
    lanterns: [u16; 7],
    lanterns_off: [u16; 7],
    chandelier: u16,
    chandelier_off: u16,
    banners: [u16; 6],
    spike: u16,
    switch: u16,
}

impl Ids {
    fn new(w: &World, brick_name: &str) -> Self {
        let id = |n: &str| w.id_of(n);
        let colour = brick_name.trim_end_matches("_brick");
        // The colour's platform (DungeonData.platformItemType: Blue, Green and
        // Pink Brick Platforms), door (Blue, Green, Pink Dungeon Door) and
        // chandelier.
        let lanterns = ["chain_lantern", "brass_lantern", "caged_lantern", "carriage_lantern", "alchemy_lantern", "diablost_lamp", "oil_rag_sconse"];
        Ids {
            brick: id(brick_name),
            bricks: ["blue_brick", "green_brick", "pink_brick"].iter().map(|n| id(n)).filter(|&b| b != 0).collect(),
            platform: id(&format!("{colour}_brick_platform")),
            door: id("dungeon_door"),
            colour_door: id(&format!("{colour}_dungeon_door")),
            door_top: id("door_top"),
            chest: id("chest"),
            locked_chest: id("locked_gold_chest"),
            book: id("book"),
            water_bolt: id("water_bolt_book"),
            water_candle: id("water_candle"),
            potions: [id("lesser_healing_potion_bottle"), id("lesser_mana_potion_bottle")],
            shelves: [id("metal_shelf"), id("brass_shelf"), id("wood_shelf"), id("dungeon_shelf")],
            lanterns: lanterns.map(|n| id(n)),
            lanterns_off: lanterns.map(|n| id(&format!("{n}_off"))),
            chandelier: id(&format!("{colour}_dungeon_chandelier")),
            chandelier_off: id(&format!("{colour}_dungeon_chandelier_off")),
            banners: ["marching_bones_banner", "necromantic_sign", "rusted_company_standard", "ragged_brotherhood_sigil", "molten_legion_flag", "diabolic_sigil"].map(|n| id(n)),
            spike: id("spike"),
            switch: id("switch"),
        }
    }
}

/// Chest decoration styles (scripts/world/chests.gd's loot tables): the
/// dungeon's chests in Terraria's order (WorldGen.GetDungeonLootAndChestStyle),
/// DUNGEON_LOOT + 0..7.
pub const DUNGEON_LOOT: i32 = 7;
const LOOT_ORDER: usize = 8;
/// The one that holds a Golden Key (in a wooden chest).
const KEY_LOOT: i32 = 6;

#[derive(Clone, Copy)]
struct Room {
    lo: P,
    hi: P,
    end: V,
    strength: f64,
}

struct Hall {
    start: V,
    end: V,
    /// Its axis: horizontal halls get doors at their ends, vertical ones
    /// platforms.
    dir: P,
}

struct DoorSpot {
    pos: P,
    /// The way through: the hall's axis, or out of the room's side.
    axis: (i32, i32),
    fluff: i32,
    /// By a room: the column nearest the room wins, not the lowest.
    room: bool,
}

struct PlatformSpot {
    pos: P,
    fluff: i32,
}

struct Gen<'a> {
    w: &'a mut World,
    rng: Rng,
    ids: Ids,
    l: Layers,
    mask: Mask,
    /// The ground's height over each column of the mask's box when the
    /// dungeon began: the layout stays 6 under it (only the entrance hallway
    /// comes up, into the entrance).
    ground: Vec<i32>,
    hallway: bool,
    /// The entrance's protected box (x0, z0, x1, z1, floor y): nothing above
    /// its floor changes; its floor only in `opening`.
    keep: (i32, i32, i32, i32, i32),
    opening: (i32, i32, i32, i32),
    pos: P,
    start: P,
    last_hall: P,
    rooms: Vec<Room>,
    halls: Vec<Hall>,
    doors: Vec<DoorSpot>,
    platforms: Vec<PlatformSpot>,
    lo: P,
    hi: P,
    /// Terraria's maxTilesX for a world this size.
    width_t: f64,
    /// The world's edge margin (Terraria's 200 tiles: here past the ocean)
    /// and how far a hall may run toward it (100: past half the ocean, its
    /// brick clear of the edge).
    edge: i32,
    edge_stop: i32,
    /// A quarter of the world: how far in from the edge, and from its start,
    /// the dungeon goes.
    quarter: i32,
    /// Depths: sent down above this, up below `bottom`; a hall going up stops
    /// above `stop_up`; nothing below `floor`.
    send_down: i32,
    bottom: i32,
    stop_up: i32,
    floor: i32,
    loot: usize,
    variants: Vec<(V, f64, u8)>,
    placed_doors: Vec<P>,
    placed_platforms: Vec<P>,
    lights: Vec<P>,
}

/// Builds the Dungeon under its entrance: `keep` is the entrance hall's floor
/// centre (worldgen::dungeon_entrance's `ground`), `door` its door's facing,
/// `steps` how many layout steps per Terraria's (1 normally; the test world
/// takes a few). Returns false if it can't (no brick).
pub fn dungeon(w: &mut World, seed: u64, l: &Layers, keep: P, door: i32, brick: &str, steps: f64) -> bool {
    let ids = Ids::new(w, brick);
    if ids.brick == 0 {
        return false;
    }
    let width_t = 4200.0 * (w.sx.min(w.sz) as f64 / 768.0);
    let quarter = w.sx.min(w.sz) / 4;
    // Terraria's 200 tiles from the world's edge sit inside its ocean; here
    // the ocean (worldgen::ocean) and 30 more, so brick never shows at the edge.
    let ocean = crate::worldgen::ocean(w.sx, w.sy, w.sz).width as i32;
    let reach = quarter + 140;
    let (x0, z0) = ((keep.0 - reach).max(0), (keep.2 - reach).max(0));
    let (x1, z1) = ((keep.0 + reach).min(w.sx), (keep.2 + reach).min(w.sz));
    let y0 = (l.underworld_top - 16).max(0);
    let y1 = (keep.1 + 8).min(w.sy);
    let mask = Mask::new(x0, z0, y0, x1 - x0, z1 - z0, y1 - y0);
    let mut ground = Vec::with_capacity(((x1 - x0) * (z1 - z0)).max(0) as usize);
    for x in x0..x1 {
        for z in z0..z1 {
            ground.push(w.surface_y(x, z));
        }
    }
    // The entrance's footprint (worldgen::dungeon_entrance: the keep, its
    // porch and the plaza round them), and the hole in its hall floor at the
    // back of the hall where the hallway comes up.
    let f = FACING[door.rem_euclid(4) as usize];
    let s = (-f.1, f.0);
    let at = |a: i32, b: i32| (keep.0 + f.0 * a + s.0 * b, keep.2 + f.1 * a + s.1 * b);
    let corners = [at(-9, -9), at(-9, 9), at(30, -9), at(30, 9)];
    let kx0 = corners.iter().map(|c| c.0).min().unwrap();
    let kx1 = corners.iter().map(|c| c.0).max().unwrap();
    let kz0 = corners.iter().map(|c| c.1).min().unwrap();
    let kz1 = corners.iter().map(|c| c.1).max().unwrap();
    let hole = [at(-4, -2), at(1, 2)];
    let opening = (hole[0].0.min(hole[1].0), hole[0].1.min(hole[1].1), hole[0].0.max(hole[1].0), hole[0].1.max(hole[1].1));
    let start = at(-2, 0);
    let mut g = Gen {
        w,
        rng: Rng::new(seed ^ 0xd4_96e0),
        ids,
        l: *l,
        mask,
        ground,
        hallway: true,
        keep: (kx0, kz0, kx1, kz1, keep.1),
        opening,
        pos: (start.0, keep.1, start.1),
        start: (start.0, keep.1, start.1),
        last_hall: (0, 0, 0),
        rooms: Vec::new(),
        halls: Vec::new(),
        doors: Vec::new(),
        platforms: Vec::new(),
        lo: (i32::MAX, i32::MAX, i32::MAX),
        hi: (i32::MIN, i32::MIN, i32::MIN),
        width_t,
        edge: ocean + 30,
        edge_stop: ocean / 2 + 24,
        quarter,
        send_down: depth_y(l, 230.0),
        bottom: depth_y(l, 610.0),
        stop_up: depth_y(l, 180.0),
        floor: l.underworld_top - 6,
        loot: 0,
        variants: Vec::new(),
        placed_doors: Vec::new(),
        placed_platforms: Vec::new(),
        lights: Vec::new(),
    };
    let outward = (-f.0, -f.1);
    g.entrance_hallway(outward);
    g.hallway = false;
    g.layout(steps);
    g.w.structures.push(((g.lo.0, g.lo.1, g.lo.2), (g.hi.0, g.hi.1, g.hi.2)));
    g.clear_old_decorations();
    // CalculatePlatformsAndDoors: the rooms', then the halls'.
    for i in 0..g.rooms.len() {
        let r = g.rooms[i];
        g.room_openings(&r);
    }
    for i in 0..g.halls.len() {
        let (start, end, dir) = (g.halls[i].start, g.halls[i].end, g.halls[i].dir);
        for p in [start, end] {
            let p = (p.0 as i32, p.1 as i32, p.2 as i32);
            if dir.1 == 0 {
                g.doors.push(DoorSpot { pos: p, axis: (dir.0, dir.2), fluff: 10, room: false });
            } else {
                g.platforms.push(PlatformSpot { pos: p, fluff: 5 });
            }
        }
    }
    g.spikes();
    g.place_doors();
    g.wall_variants();
    g.place_platforms();
    g.shelves();
    g.chests();
    g.tidy_cut_flora();
    // DungeonBounds.Inflate(25) before the lights.
    g.lo = (g.lo.0 - 25, g.lo.1 - 25, g.lo.2 - 25);
    g.hi = (g.hi.0 + 25, g.hi.1 + 25, g.hi.2 + 25);
    g.lights();
    g.banners();
    true
}

impl<'a> Gen<'a> {
    fn r(&mut self, n: i32) -> i32 {
        self.rng.range(0, n.max(1))
    }

    fn in_keep(&self, p: P) -> bool {
        let (x0, z0, x1, z1, _) = self.keep;
        p.0 >= x0 && p.0 <= x1 && p.2 >= z0 && p.2 <= z1
    }

    /// Whether worldgen may change this cell: in the world, above the
    /// underworld's floor, not the entrance above its floor.
    fn can_change(&self, p: P) -> bool {
        let w = &self.w;
        if p.0 < 1 || p.2 < 1 || p.0 >= w.sx - 1 || p.2 >= w.sz - 1 || p.1 < self.floor || p.1 >= w.sy - 1 {
            return false;
        }
        if self.in_keep(p) && p.1 >= self.keep.4 {
            let (ox0, oz0, ox1, oz1) = self.opening;
            return p.1 == self.keep.4 && p.0 >= ox0 && p.0 <= ox1 && p.2 >= oz0 && p.2 <= oz1;
        }
        if !self.hallway {
            let m = &self.mask;
            let (x, z) = (p.0 - m.x0, p.2 - m.z0);
            if x >= 0 && z >= 0 && x < m.w && z < m.d && p.1 >= self.ground[(x * m.d + z) as usize] - 6 {
                return false;
            }
        }
        true
    }

    fn set(&mut self, p: P, id: u16) {
        let i = self.w.idx(p.0, p.1, p.2);
        self.w.blocks[i] = id;
        self.w.liquid[i] = 0;
        self.w.shapes.remove(&i);
    }

    fn get(&self, p: P) -> u16 {
        self.w.get(p.0, p.1, p.2)
    }

    fn is_brick(&self, p: P) -> bool {
        let b = self.get(p);
        b != 0 && self.ids.bricks.contains(&b)
    }

    fn open(&self, p: P) -> bool {
        self.w.in_bounds(p.0, p.1, p.2) && self.get(p) == 0
    }

    fn grow_bounds(&mut self, lo: P, hi: P) {
        self.lo = (self.lo.0.min(lo.0), self.lo.1.min(lo.1), self.lo.2.min(lo.2));
        self.hi = (self.hi.0.max(hi.0), self.hi.1.max(hi.1), self.hi.2.max(hi.2));
    }

    /// One box of a room or hall: brick in [lo, hi) where the dungeon isn't
    /// yet, walled inside its outer layer, open in [ilo, ihi).
    fn carve(&mut self, lo: P, hi: P, ilo: P, ihi: P, brick_below: i32) {
        self.grow_bounds(lo, hi);
        for x in lo.0..hi.0 {
            for z in lo.2..hi.2 {
                for y in lo.1..hi.1 {
                    let p = (x, y, z);
                    if !self.can_change(p) {
                        continue;
                    }
                    if !self.mask.get(p) && y < brick_below {
                        self.set(p, self.ids.brick);
                    }
                    if x > lo.0 && x < hi.0 - 1 && y > lo.1 && y < hi.1 - 1 && z > lo.2 && z < hi.2 - 1 {
                        self.mask.set(p);
                    }
                }
            }
        }
        for x in ilo.0..ihi.0 {
            for z in ilo.2..ihi.2 {
                for y in ilo.1..ihi.1 {
                    let p = (x, y, z);
                    if self.can_change(p) {
                        self.set(p, 0);
                        self.mask.set(p);
                    }
                }
            }
        }
    }

    fn edge_dist(&self, p: P) -> i32 {
        p.0.min(p.2).min(self.w.sx - 1 - p.0).min(self.w.sz - 1 - p.2)
    }

    /// The way in from the nearest edge.
    fn inward(&self, p: P) -> P {
        let (sx, sz) = (self.w.sx, self.w.sz);
        let d = [p.0, sx - 1 - p.0, p.2, sz - 1 - p.2];
        let k = (0..4).min_by_key(|&k| d[k]).unwrap();
        [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)][k]
    }

    /// The way back toward where the dungeon started (the longer way across).
    fn homeward(&self, p: P) -> P {
        let (dx, dz) = (self.start.0 - p.0, self.start.2 - p.2);
        if dx.abs() > dz.abs() { (dx.signum(), 0, 0) } else { (0, 0, dz.signum()) }
    }

    fn sign(&mut self) -> f64 {
        if self.r(2) == 0 { -1.0 } else { 1.0 }
    }

    // ------------------------------------------------------------ hallway

    /// LegacyEntranceDungeonHall, dug downward from the entrance's floor.
    fn entrance_hallway(&mut self, outward: (i32, i32)) {
        let skewed = self.r(4) == 0;
        // Where Terraria's dungeon starts: (surface + rock layer) / 2 +- 200
        // tiles, at least 60 tiles under the ground.
        let d = (65 + self.rng.range(-200, 200)).max(60) as f64;
        let target = depth_y(&self.l, d).min(self.keep.4 - 20);
        let column = (self.start.0 as f64, self.start.2 as f64);
        let mut p: V = (self.start.0 as f64 + 0.5, self.keep.4 as f64, self.start.2 as f64 + 0.5);
        let mut first = true;
        for _ in 0..100 {
            if p.1 <= target as f64 {
                break;
            }
            let strength = if first { 5.0 } else { self.rng.range(5, 9) as f64 };
            let steps = self.rng.range(10, 30);
            // Across: back toward the entrance's column (a random way at the
            // start), 1-3 x a step, 0.5-0.75, or the drop doubled.
            let (hx, hz) = {
                let (dx, dz) = (column.0 - p.0, column.1 - p.2);
                let len = (dx * dx + dz * dz).sqrt();
                if len > 4.0 {
                    (dx / len, dz / len)
                } else {
                    let a = ACROSS[self.r(4) as usize];
                    (a.0 as f64, a.2 as f64)
                }
            };
            let (mut k, mut dy) = (1.0, -1.0);
            if self.r(3) != 0 {
                k *= 1.0 + self.r(200) as f64 * 0.01;
            } else if self.r(3) != 0 {
                k *= self.rng.range(50, 76) as f64 * 0.01;
            } else if self.r(6) == 0 {
                dy *= 2.0;
            }
            let (mut vx, mut vz) = (hx * k, hz * k);
            let out = vx * outward.0 as f64 + vz * outward.1 as f64;
            if out > 0.5 {
                // Toward the edge: at most half a block a step (non-skewed),
                // or turned back (skewed).
                let fix = if skewed { -0.5 - out } else { 0.5 - out };
                vx += fix * outward.0 as f64;
                vz += fix * outward.1 as f64;
            }
            let v = (vx, dy, vz);
            for _ in 0..steps {
                if p.1 <= target as f64 {
                    break;
                }
                let s = strength as i32;
                let j = if self.r(s) == 0 { self.rng.range(1, 3) } else { 0 };
                let (cx, cy, cz) = (p.0 as i32, p.1 as i32, p.2 as i32);
                // It opens the hall floor (can_change keeps the rest of the
                // entrance); its brick stays under the ground.
                let lo = (cx - s - 4 - self.r(6), cy - s - 4, cz - s - 4 - self.r(6));
                let hi = (cx + s + 4 + self.r(6), cy + s + 4 + self.r(6), cz + s + 4 + self.r(6));
                let hs = strength * 0.5 + j as f64;
                let ilo = ((p.0 - hs) as i32, (p.1 - hs) as i32, (p.2 - hs) as i32);
                let ihi = ((p.0 + hs) as i32, (p.1 + hs) as i32, (p.2 + hs) as i32);
                self.carve(lo, hi, ilo, ihi, self.keep.4);
                p = (p.0 + v.0, p.1 + v.1, p.2 + v.2);
            }
            first = false;
        }
        self.pos = (p.0 as i32, p.1 as i32, p.2 as i32);
        self.start = self.pos;
    }

    // ------------------------------------------------------------- layout

    fn layout(&mut self, scale: f64) {
        let mut steps = (self.width_t / 60.0) as i32;
        steps += self.r(steps / 3);
        let steps = ((steps as f64) * scale).round().max(1.0) as i32;
        let mut forced = 5;
        self.room(true);
        for _ in 0..steps {
            if forced > 0 {
                forced -= 1;
            }
            if forced == 0 && self.r(3) == 0 {
                forced = 5;
                if self.r(2) == 0 {
                    let back = self.pos;
                    self.hall(false);
                    if self.r(2) == 0 {
                        self.hall(false);
                    }
                    self.room(false);
                    self.pos = back;
                } else {
                    self.room(false);
                }
            } else {
                self.hall(false);
            }
        }
        self.room(false);
    }

    /// LegacyDungeonRoom at the walker (who stays put).
    fn room(&mut self, _starting: bool) {
        let s = (15 + self.r(15)) as f64;
        let mut v: V = (self.rng.range(-10, 11) as f64 * 0.1, self.rng.range(-10, 11) as f64 * 0.1, self.rng.range(-10, 11) as f64 * 0.1);
        if v == (0.0, 0.0, 0.0) {
            let sign = self.sign();
            if self.r(2) == 0 {
                v.1 = sign;
            } else if self.r(2) == 0 {
                v.0 = sign;
            } else {
                v.2 = sign;
            }
        }
        let mut p: V = (self.pos.0 as f64, self.pos.1 as f64 + s / 2.0, self.pos.2 as f64);
        let mut steps = 10 + self.r(10);
        let (mut ilo_all, mut ihi_all) = ((i32::MAX, i32::MAX, i32::MAX), (i32::MIN, i32::MIN, i32::MIN));
        while steps > 0 {
            steps -= 1;
            let o = s * 0.8 + 5.0;
            let lo = ((p.0 - o) as i32, (p.1 - o) as i32, (p.2 - o) as i32);
            let hi = ((p.0 + o) as i32, (p.1 + o) as i32, (p.2 + o) as i32);
            let i = s * 0.5;
            let ilo = ((p.0 - i) as i32, (p.1 - i) as i32, (p.2 - i) as i32);
            let ihi = ((p.0 + i) as i32, (p.1 + i) as i32, (p.2 + i) as i32);
            self.carve(lo, hi, ilo, ihi, i32::MAX);
            ilo_all = (ilo_all.0.min(ilo.0), ilo_all.1.min(ilo.1), ilo_all.2.min(ilo.2));
            ihi_all = (ihi_all.0.max(ihi.0 - 1), ihi_all.1.max(ihi.1 - 1), ihi_all.2.max(ihi.2 - 1));
            p = (p.0 + v.0, p.1 + v.1, p.2 + v.2);
            let drift = |c: f64, rng: &mut Rng| (c + rng.range(-10, 11) as f64 * 0.05).clamp(-1.0, 1.0);
            v = (drift(v.0, &mut self.rng), drift(v.1, &mut self.rng), drift(v.2, &mut self.rng));
        }
        self.rooms.push(Room { lo: ilo_all, hi: ihi_all, end: p, strength: s });
    }

    /// Whether a hall could run `len` along `d` from `p` without leaving the
    /// world or leaving the dungeon and running into it again; and whether a
    /// downward one hits the bottom.
    fn way_open(&self, p: P, d: P, len: i32) -> (bool, bool) {
        let mut left = false;
        let m = self.edge_stop;
        for k in 0..len {
            let q = (p.0 + d.0 * k, p.1 + d.1 * k, p.2 + d.2 * k);
            if q.0 < m || q.2 < m || q.0 >= self.w.sx - m || q.2 >= self.w.sz - m || q.1 < self.floor || q.1 >= self.w.sy - m {
                return (false, false);
            }
            if d.1 < 0 && q.1 <= self.bottom {
                return (false, true);
            }
            if self.mask.get(q) {
                if left {
                    return (false, false);
                }
            } else {
                left = true;
            }
        }
        (true, false)
    }

    /// LegacyDungeonHall from the walker; the walker ends at its end.
    fn hall(&mut self, force_across: bool) {
        let mut strength = (4 + self.r(2)) as f64;
        let mut steps = 35 + self.r(45);
        if force_across {
            steps += 20;
            self.last_hall = (0, 0, 0);
        } else if self.r(5) == 0 {
            strength *= 2.0;
            steps /= 2;
        }
        let strength0 = strength;
        let p0 = self.pos;
        let mut dir: P;
        let mut v: V;
        // (Not straight back the way the last hall came, unless that's all
        // there is: after this many tries it goes anyway.)
        let mut tries_left = 50;
        loop {
            tries_left -= 1;
            let up = self.way_open(p0, UP, steps).0;
            let (down, at_bottom) = self.way_open(p0, DOWN, steps);
            let across: Vec<P> = ACROSS.iter().copied().filter(|&d| self.way_open(p0, d, steps).0).collect();
            let horizontal;
            let mut vsign = 1;
            let mut hdir = ACROSS[self.r(4) as usize];
            if !up && !down && across.is_empty() {
                vsign = if self.r(2) == 0 { -1 } else { 1 };
                horizontal = self.r(2) == 0;
            } else {
                let mut pick;
                let mut tries = 100;
                loop {
                    tries -= 1;
                    if tries <= 0 {
                        pick = 0;
                        break;
                    }
                    pick = self.r(4);
                    if pick == 1 && at_bottom {
                        pick = 2 + self.r(2);
                    }
                    if (pick == 0 && up) || (pick == 1 && down) || (pick >= 2 && !across.is_empty()) {
                        break;
                    }
                }
                match pick {
                    0 => { horizontal = false; vsign = 1; }
                    1 => { horizontal = false; vsign = -1; }
                    _ => {
                        horizontal = true;
                        hdir = across[self.r(across.len() as i32) as usize];
                    }
                }
            }
            if force_across || horizontal {
                dir = hdir;
                v = (hdir.0 as f64, 0.0, hdir.2 as f64);
                if self.r(3) == 0 {
                    v.1 = 0.2 * self.sign();
                }
            } else {
                strength += 1.0;
                dir = (0, vsign, 0);
                v = (0.0, vsign as f64, 0.0);
                if self.r(2) == 0 {
                    let a = ACROSS[self.r(4) as usize];
                    let lean = self.rng.range(20, 40) as f64 * 0.01;
                    v.0 = a.0 as f64 * lean;
                    v.2 = a.2 as f64 * lean;
                } else {
                    steps /= 2;
                }
            }
            if self.last_hall != (-dir.0, -dir.1, -dir.2) || tries_left <= 0 {
                break;
            }
            strength = strength0;
        }
        // Where Terraria sends it regardless.
        if !force_across {
            let across_to = |g: &mut Gen, d: P| -> (P, V) {
                let mut v = (d.0 as f64, 0.0, d.2 as f64);
                if g.r(3) == 0 {
                    v.1 = 0.2 * g.sign();
                }
                (d, v)
            };
            let upright = |g: &mut Gen, s: i32| -> (P, V) {
                let mut v = (0.0, s as f64, 0.0);
                if g.r(2) == 0 {
                    let a = ACROSS[g.r(4) as usize];
                    let lean = g.rng.range(20, 50) as f64 * 0.01;
                    v.0 = a.0 as f64 * lean;
                    v.2 = a.2 as f64 * lean;
                }
                ((0, s, 0), v)
            };
            let p = p0;
            let hdist = (((p.0 - self.start.0).pow(2) + (p.2 - self.start.2).pow(2)) as f64).sqrt();
            if self.edge_dist(p) < self.edge {
                (dir, v) = across_to(self, self.inward(p));
            } else if p.1 <= self.bottom {
                strength = strength0 + 1.0;
                (dir, v) = upright(self, 1);
            } else if p.1 >= self.w.sy - 30 {
                strength = strength0 + 1.0;
                (dir, v) = upright(self, -1);
            } else if p.1 > self.send_down {
                strength = strength0 + 1.0;
                (dir, v) = upright(self, -1);
            } else if self.edge_dist(p) > self.quarter {
                let out = self.inward(p);
                (dir, v) = across_to(self, (-out.0, 0, -out.2));
            } else if hdist > self.quarter as f64 {
                let home = self.homeward(p);
                (dir, v) = across_to(self, home);
            }
        }
        self.last_hall = dir;
        if v.0.abs() + v.2.abs() > v.1.abs() && self.r(3) != 0 {
            strength = strength0 * self.rng.range(110, 150) as f64 * 0.01;
        }
        let mut p: V = (p0.0 as f64, p0.1 as f64, p0.2 as f64);
        let start = p;
        let s = strength as i32;
        while steps > 0 {
            let c = (p.0 as i32, p.1 as i32, p.2 as i32);
            let (sx, sz) = (self.w.sx, self.w.sz);
            if (dir.0 > 0 && c.0 > sx - self.edge_stop) || (dir.0 < 0 && c.0 < self.edge_stop)
                || (dir.2 > 0 && c.2 > sz - self.edge_stop) || (dir.2 < 0 && c.2 < self.edge_stop)
                || (dir.1 < 0 && c.1 <= self.bottom) || (dir.1 > 0 && c.1 >= self.stop_up)
            {
                steps = 0;
            }
            steps -= 1;
            let lo = (c.0 - s - 4 - self.r(6), c.1 - s - 4 - self.r(6), c.2 - s - 4 - self.r(6));
            let hi = (c.0 + s + 4 + self.r(6), c.1 + s + 4 + self.r(6), c.2 + s + 4 + self.r(6));
            let j = if v.1 == 0.0 {
                if self.r(s + 1) == 0 { self.rng.range(1, 3) } else { 0 }
            } else if v.0 == 0.0 && v.2 == 0.0 {
                if self.r(s - 1) == 0 { self.rng.range(1, 3) } else { 0 }
            } else if self.r(s * 3) == 0 {
                self.rng.range(1, 3)
            } else {
                0
            };
            let hs = strength * 0.5 + j as f64;
            let ilo = ((p.0 - hs) as i32, (p.1 - hs) as i32, (p.2 - hs) as i32);
            let ihi = ((p.0 + hs) as i32, (p.1 + hs) as i32, (p.2 + hs) as i32);
            self.carve(lo, hi, ilo, ihi, i32::MAX);
            p = (p.0 + v.0, p.1 + v.1, p.2 + v.2);
        }
        self.pos = (p.0 as i32, p.1 as i32, p.2 as i32);
        self.halls.push(Hall { start, end: p, dir });
    }

    /// Drops what earlier passes left where the dungeon now is.
    fn clear_old_decorations(&mut self) {
        let mask = &self.mask;
        let w = &*self.w;
        let bricks = &self.ids.bricks;
        let keep_y = self.keep.4;
        let keep = self.keep;
        let in_keep = |p: P| p.0 >= keep.0 && p.0 <= keep.2 && p.2 >= keep.1 && p.2 <= keep.3 && p.1 >= keep_y;
        let stale: Vec<bool> = w.decorations.iter().map(|d| {
            let p = d.pos;
            !in_keep(p) && (mask.get(p) || (w.in_bounds(p.0, p.1, p.2) && bricks.contains(&w.get(p.0, p.1, p.2))))
        }).collect();
        let mut i = 0;
        self.w.decorations.retain(|_| {
            i += 1;
            !stale[i - 1]
        });
    }

    /// The trees and plants the Dungeon cut into (Terraria digs its Dungeon
    /// before they grow; here they're older): a canopy whose trunk no longer
    /// stands on the ground goes, with what's left of its trunk, and a plant
    /// left standing on brick or over a gap goes (worldgen::tidy_plants).
    fn tidy_cut_flora(&mut self) {
        let (lo, hi) = (self.lo, self.hi);
        let bricks = self.ids.bricks.clone();
        let w = &mut *self.w;
        let mut cut: Vec<(usize, i32, i32, Vec<i32>)> = Vec::new();
        for (k, d) in w.decorations.iter().enumerate() {
            let (x, y, z) = d.pos;
            if d.kind != "tree_top" || x < lo.0 || x > hi.0 || z < lo.2 || z > hi.2 || y < lo.1 || y > hi.1 + 30 {
                continue;
            }
            let trunk = w.get(x, y - 1, z);
            let mut cells = Vec::new();
            let mut yy = y - 1;
            if trunk != 0 && w.def(trunk).name.contains("trunk") {
                while yy > 0 && w.get(x, yy, z) == trunk {
                    cells.push(yy);
                    yy -= 1;
                }
            }
            if cells.is_empty() || !w.is_solid(x, yy, z) || bricks.contains(&w.get(x, yy, z)) {
                cut.push((k, x, z, cells));
            }
        }
        for (_, x, z, cells) in &cut {
            for &y in cells {
                let i = w.idx(*x, y, *z);
                w.blocks[i] = 0;
            }
        }
        let gone: std::collections::HashSet<usize> = cut.iter().map(|c| c.0).collect();
        let mut k = 0;
        w.decorations.retain(|_| {
            k += 1;
            !gone.contains(&(k - 1))
        });
        crate::worldgen::tidy_plants(w, lo, (hi.0, hi.1 + 30, hi.2), &bricks);
    }

    // ---------------------------------------------- doors and platforms

    /// CalculatePlatformsAndDoorsOnEdgesOfRoom (fluff 3).
    fn room_openings(&mut self, r: &Room) {
        let (lo, hi) = (r.lo, r.hi);
        'top: for x in lo.0..=hi.0 {
            for z in lo.2..=hi.2 {
                if self.open((x, hi.1 + 1, z)) && self.mask.get((x, hi.1 + 1, z)) {
                    self.platforms.push(PlatformSpot { pos: (x, hi.1 + 1, z), fluff: 3 });
                    break 'top;
                }
            }
        }
        'bottom: for x in lo.0..=hi.0 {
            for z in lo.2..=hi.2 {
                if self.open((x, lo.1 - 1, z)) && self.mask.get((x, lo.1 - 1, z)) {
                    self.platforms.push(PlatformSpot { pos: (x, lo.1 - 1, z), fluff: 3 });
                    break 'bottom;
                }
            }
        }
        for (k, out) in [(-1, 0), (1, 0), (0, -1), (0, 1)].iter().enumerate() {
            let found = (0..=(hi.1 - lo.1)).rev().find_map(|dy| {
                let y = lo.1 + dy;
                let span: Vec<i32> = if k < 2 { (lo.2..=hi.2).collect() } else { (lo.0..=hi.0).collect() };
                span.into_iter().find_map(|t| {
                    let p = match k {
                        0 => (lo.0 - 1, y, t),
                        1 => (hi.0 + 1, y, t),
                        2 => (t, y, lo.2 - 1),
                        _ => (t, y, hi.2 + 1),
                    };
                    (self.open(p) && self.mask.get(p)).then_some(p)
                })
            });
            if let Some(p) = found {
                self.doors.push(DoorSpot { pos: p, axis: *out, fluff: 3, room: true });
            }
        }
    }

    /// The open run from `p` down to the floor and up to the ceiling:
    /// (floor y, ceiling y), both dungeon brick, or None.
    fn floor_and_ceiling(&self, p: P) -> Option<(i32, i32)> {
        if !self.open(p) {
            return None;
        }
        let mut c = p.1;
        while c < self.w.sy - 1 && self.open((p.0, c, p.2)) {
            c += 1;
        }
        let mut f = p.1;
        while f > 1 && self.open((p.0, f, p.2)) {
            f -= 1;
        }
        (self.is_brick((p.0, c, p.2)) && self.is_brick((p.0, f, p.2))).then_some((f, c))
    }

    /// DungeonGlobalDoors.
    fn place_doors(&mut self) {
        if self.ids.door == 0 || self.ids.door_top == 0 {
            return;
        }
        let spots = std::mem::take(&mut self.doors);
        for spot in spots {
            let (ax, az) = spot.axis;
            let side = (-az, ax);
            let mut best: Option<(i32, P, i32, i32)> = None; // (score, column, floor, ceiling)
            for t in -spot.fluff..spot.fluff {
                let q = (spot.pos.0 + ax * t, spot.pos.1, spot.pos.2 + az * t);
                let Some((f, c)) = self.floor_and_ceiling(q) else { continue };
                let h = c - f;
                if !(3..20).contains(&h) {
                    continue;
                }
                let d = (q.0, f + 1, q.2);
                if self.placed_doors.iter().any(|o| (o.0 - d.0).abs() < 20 && (o.2 - d.2).abs() < 20 && (o.1 - d.1).abs() < 10) {
                    continue;
                }
                // Nothing in the way within 3 along the passage, 3 up.
                let blocked = (-3..=3).any(|k| (1..=3).any(|dy| !self.open((q.0 + ax * k, f + dy, q.2 + az * k))));
                if blocked {
                    continue;
                }
                // By a room the column nearest it, else the lowest.
                let score = if spot.room { t } else { h };
                if best.map_or(true, |b| score < b.0) {
                    best = Some((score, q, f, c));
                }
            }
            let Some((_, q, f, c)) = best else { continue };
            // The passage's cross-section at the door: open cells reached from
            // the door's column, across and up, at most 12 to a side.
            let across = |t: i32| (q.0 + side.0 * t, f + 1, q.2 + side.1 * t);
            let mut lo_t = 0;
            while lo_t > -12 && self.open(across(lo_t - 1)) {
                lo_t -= 1;
            }
            let mut hi_t = 0;
            while hi_t < 12 && self.open(across(hi_t + 1)) {
                hi_t += 1;
            }
            if lo_t <= -12 || hi_t >= 12 {
                continue;
            }
            let mut cells = Vec::new();
            for t in lo_t..=hi_t {
                let (x, _, z) = across(t);
                let mut y = f + 1;
                while y < c + 6 && self.open((x, y, z)) {
                    cells.push((x, y, z));
                    y += 1;
                }
                let mut y = f;
                while y > f - 6 && self.open((x, y, z)) {
                    cells.push((x, y, z));
                    y -= 1;
                }
            }
            let mid = (lo_t + hi_t) / 2;
            let dx = (q.0 + side.0 * mid, f + 1, q.2 + side.1 * mid);
            for &cell in &cells {
                if (cell.0, cell.2) == (dx.0, dx.2) && (cell.1 == f + 1 || cell.1 == f + 2) {
                    continue;
                }
                if self.can_change(cell) {
                    self.set(cell, self.ids.brick);
                }
            }
            // The door, its front and back kept open.
            let door = if self.r(3) == 0 && self.ids.colour_door != 0 { self.ids.colour_door } else { self.ids.door };
            self.set(dx, door);
            self.set((dx.0, dx.1 + 1, dx.2), self.ids.door_top);
            for k in [-2, -1, 1, 2] {
                for dy in 0..2 {
                    let p = (dx.0 + ax * k, dx.1 + dy, dx.2 + az * k);
                    if self.mask.get(p) && self.can_change(p) {
                        self.set(p, 0);
                    }
                }
            }
            let facing = FACING.iter().position(|&d| d == (ax, az)).unwrap_or(0) as i32;
            self.w.decorations.push(Decoration { kind: "rotation".into(), pos: dx, style: facing });
            self.placed_doors.push(dx);
        }
    }

    /// DungeonGlobalPlatforms.
    fn place_platforms(&mut self) {
        if self.ids.platform == 0 {
            return;
        }
        let spots = std::mem::take(&mut self.platforms);
        let near_surface = depth_y(&self.l, 50.0);
        for spot in spots {
            let max_len = if spot.pos.1 > near_surface { 20 } else { 10 };
            let p = spot.pos;
            let mut chosen = None;
            for y in (p.1 - spot.fluff..=p.1 + spot.fluff).rev() {
                let q = (p.0, y, p.2);
                if !self.open(q) || !self.mask.get(q) {
                    continue;
                }
                let Some(cells) = self.shaft_section(q, max_len) else { continue };
                let reach = max_len / 2 + 2;
                if self.placed_platforms.iter().any(|o| (o.0 - p.0).abs() <= reach && (o.2 - p.2).abs() <= reach && (o.1 - y).abs() <= spot.fluff) {
                    continue;
                }
                if (y - 3..=y + 5).any(|yy| !self.open((p.0, yy, p.2))) {
                    continue;
                }
                chosen = Some((q, cells));
                break;
            }
            let Some((q, cells)) = chosen else { continue };
            for c in cells {
                self.set(c, self.ids.platform);
            }
            self.placed_platforms.push(q);
        }
    }

    /// The level cross-section of a shaft through `p`: its open cells, if it's
    /// closed in by dungeon brick and at most `max_len` across either way.
    fn shaft_section(&self, p: P, max_len: i32) -> Option<Vec<P>> {
        let mut seen = vec![p];
        let mut k = 0;
        while k < seen.len() {
            let c = seen[k];
            k += 1;
            if (c.0 - p.0).abs() > max_len || (c.2 - p.2).abs() > max_len {
                return None;
            }
            for d in ACROSS {
                let n = (c.0 + d.0, c.1, c.2 + d.2);
                if seen.contains(&n) {
                    continue;
                }
                if self.open(n) {
                    seen.push(n);
                } else if !self.is_brick(n) {
                    return None;
                }
            }
            if seen.len() > (max_len * max_len) as usize {
                return None;
            }
        }
        let (x0, x1) = (seen.iter().map(|c| c.0).min()?, seen.iter().map(|c| c.0).max()?);
        let (z0, z1) = (seen.iter().map(|c| c.2).min()?, seen.iter().map(|c| c.2).max()?);
        (x1 - x0 < max_len && z1 - z0 < max_len).then_some(seen)
    }

    // ----------------------------------------------------------- features

    /// A random open, walled cell in the dungeon's bounds.
    fn random_inside(&mut self, y_max: i32) -> Option<P> {
        let p = (
            self.rng.range(self.lo.0, self.hi.0 + 1),
            self.rng.range(self.lo.1, self.hi.1.min(y_max) + 1),
            self.rng.range(self.lo.2, self.hi.2 + 1),
        );
        (self.w.in_bounds(p.0, p.1, p.2) && self.mask.get(p) && self.get(p) == 0 && !(self.in_keep(p) && p.1 >= self.keep.4)).then_some(p)
    }

    /// DungeonGlobalWallVariants: 5 rounds of a blob of each wall.
    fn wall_variants(&mut self) {
        for _ in 0..5 {
            for k in 0..3u8 {
                let r = self.rng.range(40, 240) as f64 * 0.4;
                let c = (
                    self.rng.range(self.lo.0, self.hi.0 + 1) as f64,
                    self.rng.range(self.lo.1, self.hi.1 + 1) as f64,
                    self.rng.range(self.lo.2, self.hi.2 + 1) as f64,
                );
                self.variants.push((c, r, k));
            }
        }
    }

    /// The wall Terraria would have here: 0 brick, 1 slab, 2 tiled.
    fn variant(&self, p: P) -> usize {
        let mut v = 0;
        for &(c, r, k) in &self.variants {
            let d = (p.0 as f64 - c.0).powi(2) + (p.1 as f64 - c.1).powi(2) + (p.2 as f64 - c.2).powi(2);
            if d < r * r {
                v = k as usize;
            }
        }
        v
    }

    /// Whether a spike can grow from this block (Spikes_CanSupportSpike: a
    /// solid cube of the dungeon's).
    fn supports_spike(&self, p: P) -> bool {
        self.is_brick(p)
    }

    /// DungeonGlobalSpikes.
    fn spikes(&mut self) {
        if self.ids.spike == 0 {
            return;
        }
        let count = (42.0 * self.width_t / 4200.0) as i32;
        let y_max = depth_y(&self.l, 25.0);
        // Floors and ceilings.
        let (mut made, mut tries) = (0, 0);
        while made < count {
            tries += 1;
            if tries > 1000 {
                tries = 0;
                made += 1;
            }
            let Some(mut p) = self.random_inside(y_max) else { continue };
            if self.variant(p) != 0 {
                continue;
            }
            let dir = if self.r(2) == 0 { 1 } else { -1 };
            while self.open(p) {
                p.1 += dir;
            }
            let run = ACROSS[self.r(2) as usize * 2];
            let side = (run.2, 0, run.0);
            let flat = |g: &Gen, q: P| g.supports_spike(q) && g.open((q.0, q.1 - dir, q.2));
            if !flat(self, p) || !flat(self, (p.0 + run.0, p.1, p.2 + run.2)) || !flat(self, (p.0 - run.0, p.1, p.2 - run.2)) {
                continue;
            }
            made += 1;
            tries = 0;
            for sgn in [-1, 1] {
                let n = self.rng.range(5, 13);
                for k in 0..n {
                    let t = if sgn < 0 { -k } else { k + 1 };
                    let q = (p.0 + run.0 * t, p.1, p.2 + run.2 * t);
                    if !flat(self, q) {
                        break;
                    }
                    // Across the passage both ways, while the surface goes on.
                    self.spike_at(q, dir, 2);
                    for s2 in [-1, 1] {
                        for u in 1..10 {
                            let c = (q.0 + side.0 * u * s2, q.1, q.2 + side.2 * u * s2);
                            if !flat(self, c) {
                                break;
                            }
                            self.spike_at(c, dir, 2);
                        }
                    }
                }
            }
        }
        // Walls.
        let (mut made, mut tries) = (0, 0);
        while made < count {
            tries += 1;
            if tries > 1000 {
                tries = 0;
                made += 1;
            }
            let Some(mut p) = self.random_inside(y_max) else { continue };
            if self.variant(p) != 0 {
                continue;
            }
            let d = ACROSS[self.r(4) as usize];
            let mut n = 0;
            while self.open(p) && n < 60 {
                p = (p.0 + d.0, p.1, p.2 + d.2);
                n += 1;
            }
            let out = (-d.0, -d.2);
            let face = |g: &Gen, q: P| g.supports_spike(q) && g.open((q.0 + out.0, q.1, q.2 + out.1));
            if !face(self, p) || !face(self, (p.0, p.1 + 1, p.2)) || !face(self, (p.0, p.1 - 1, p.2)) {
                continue;
            }
            made += 1;
            tries = 0;
            let side = (-out.1, out.0);
            for sgn in [-1, 1] {
                let n = self.rng.range(5, 13);
                for k in 0..n {
                    let t = if sgn < 0 { -k } else { k + 1 };
                    let q = (p.0, p.1 + t, p.2);
                    if !face(self, q) {
                        break;
                    }
                    for u in -1..=1 {
                        let c = (q.0 + side.0 * u, q.1, q.2 + side.1 * u);
                        if face(self, c) {
                            self.spike_wall(c, out);
                        }
                    }
                }
            }
        }
    }

    /// A floor or ceiling block turned to spikes, sticking `len` out (away
    /// from `dir`, the way to the surface) where no spike beside it does.
    fn spike_at(&mut self, c: P, dir: i32, len: i32) {
        self.set(c, self.ids.spike);
        let out = |k: i32| (c.0, c.1 - dir * k, c.2);
        let busy = ACROSS.iter().any(|d| self.get((c.0 + d.0, c.1 - dir, c.2 + d.2)) == self.ids.spike);
        if busy {
            return;
        }
        for k in 1..=len {
            let q = out(k);
            if !self.open(q) || !self.can_change(q) {
                break;
            }
            self.set(q, self.ids.spike);
        }
    }

    /// A wall block turned to spikes, sticking 2 out where no spike above,
    /// below or beside it does.
    fn spike_wall(&mut self, c: P, out: (i32, i32)) {
        self.set(c, self.ids.spike);
        let o = (c.0 + out.0, c.1, c.2 + out.1);
        let side = (-out.1, out.0);
        let busy = [(0, 1, 0), (0, -1, 0), (side.0, 0, side.1), (-side.0, 0, -side.1)]
            .iter()
            .any(|d| self.get((o.0 + d.0, o.1 + d.1, o.2 + d.2)) == self.ids.spike);
        if busy {
            return;
        }
        for k in 1..=2 {
            let q = (c.0 + out.0 * k, c.1, c.2 + out.1 * k);
            if !self.open(q) || !self.can_change(q) {
                break;
            }
            self.set(q, self.ids.spike);
        }
    }

    /// DungeonGlobalBookshelves.
    fn shelves(&mut self) {
        let count = (self.width_t / 20.0) as i32;
        let deep = depth_y(&self.l, 65.0);
        let picks = self.shelf_picks();
        let (mut made, mut tries) = (0, 0);
        while made < count {
            tries += 1;
            if tries > 1000 {
                tries = 0;
                made += 1;
            }
            let Some(mut p) = self.random_inside(i32::MAX) else { continue };
            let d = ACROSS[self.r(4) as usize];
            let mut n = 0;
            while self.open(p) && n < 60 {
                p = (p.0 + d.0, p.1, p.2 + d.2);
                n += 1;
            }
            // A flat wall of dungeon brick.
            if !self.is_brick(p) || !self.is_brick((p.0, p.1 + 1, p.2)) || !self.is_brick((p.0, p.1 - 1, p.2)) {
                continue;
            }
            let p = (p.0 - d.0, p.1, p.2 - d.2);
            let near_platform = (-3..=3).any(|a| (-3..=3).any(|b| (-3..=3).any(|c| {
                let id = self.get((p.0 + a, p.1 + b, p.2 + c));
                id != 0 && (id == self.ids.platform || self.ids.shelves.contains(&id))
            })));
            if near_platform || !(1..=3).all(|k| self.open((p.0, p.1 + k, p.2))) {
                continue;
            }
            // Open in front, with no floor under it, for more than 5.
            let mut run = 0;
            let mut q = p;
            while run < 20 && self.open(q) && self.open((q.0, q.1 + 1, q.2)) && self.open((q.0, q.1 - 1, q.2)) {
                q = (q.0 - d.0, q.1, q.2 - d.2);
                run += 1;
            }
            if run <= 5 {
                continue;
            }
            made += 1;
            tries = 0;
            let shelf = self.ids.shelves[picks[self.variant(p)]];
            if shelf == 0 {
                continue;
            }
            let books = self.r(2) == 0;
            let len = self.rng.range(1, 4);
            let side = (-d.2, d.0);
            let mut first = None;
            for k in 0..len {
                let c = (p.0 + side.0 * k, p.1, p.2 + side.1 * k);
                if !self.open(c) || !self.is_brick((c.0 + d.0, c.1, c.2 + d.2)) {
                    break;
                }
                self.set(c, shelf);
                first.get_or_insert(c);
                let top = (c.0, c.1 + 1, c.2);
                if books && self.open(top) && self.ids.book != 0 {
                    let bolt = self.r(50) == 0 && c.1 < deep && self.ids.water_bolt != 0;
                    self.set(top, if bolt { self.ids.water_bolt } else { self.ids.book });
                }
            }
            if !books && self.r(2) == 0 {
                if let Some(c) = first {
                    let top = (c.0, c.1 + 1, c.2);
                    let thing = if self.r(4) == 0 { self.ids.water_candle } else { self.ids.potions[self.r(2) as usize] };
                    if thing != 0 && self.open(top) {
                        self.set(top, thing);
                    }
                }
            }
        }
    }

    /// DungeonData.shelfStyles: three of Terraria's four shelves, all
    /// different, one for each wall.
    fn shelf_picks(&mut self) -> [usize; 3] {
        let a = self.r(4) as usize;
        let mut b = self.r(4) as usize;
        while b == a {
            b = self.r(4) as usize;
        }
        let mut c = self.r(4) as usize;
        while c == a || c == b {
            c = self.r(4) as usize;
        }
        [a, b, c]
    }

    /// DungeonGlobalBasicChests: a chest in each room's last box.
    fn chests(&mut self) {
        let shallow = depth_y(&self.l, 50.0);
        for i in 0..self.rooms.len() {
            let r = self.rooms[i];
            let half = r.strength * 0.4;
            for _ in 0..1000 {
                let x = self.rng.range((r.end.0 - half) as i32, (r.end.0 + half) as i32 + 1);
                let z = self.rng.range((r.end.2 - half) as i32, (r.end.2 + half) as i32 + 1);
                let mut y = self.rng.range((r.end.1 - half) as i32, (r.end.1 + half) as i32 + 1);
                if !self.open((x, y, z)) {
                    continue;
                }
                while y > 1 && self.open((x, y - 1, z)) {
                    y -= 1;
                }
                let p = (x, y, z);
                if !self.is_brick((x, y - 1, z)) || !self.open((x, y + 1, z)) || !self.mask.get(p) {
                    continue;
                }
                let mut style = (self.loot % LOOT_ORDER) as i32;
                if y > shallow {
                    style = KEY_LOOT;
                }
                let block = if style == KEY_LOOT || self.ids.locked_chest == 0 { self.ids.chest } else { self.ids.locked_chest };
                if block == 0 {
                    break;
                }
                self.set(p, block);
                self.w.decorations.push(Decoration { kind: "chest".into(), pos: p, style: DUNGEON_LOOT + style });
                // Facing into the room.
                let face = (r.end.0 as i32 - x, r.end.2 as i32 - z);
                let into = if face.0.abs() > face.1.abs() { (face.0.signum(), 0) } else if face.1 < 0 { (0, -1) } else { (0, 1) };
                let facing = FACING.iter().position(|&d| d == into).unwrap_or(0) as i32;
                self.w.decorations.push(Decoration { kind: "rotation".into(), pos: p, style: facing });
                self.loot += 1;
                break;
            }
        }
    }

    /// DungeonGlobalLights.
    fn lights(&mut self) {
        let count = (28.0 * self.width_t / 4200.0) as i32;
        // DungeonData.lanternStyles: three different lanterns, one per wall.
        let mut styles = [self.r(7) as usize, 0, 0];
        styles[1] = self.r(7) as usize;
        while styles[1] == styles[0] {
            styles[1] = self.r(7) as usize;
        }
        styles[2] = self.r(7) as usize;
        while styles[2] == styles[0] || styles[2] == styles[1] {
            styles[2] = self.r(7) as usize;
        }
        let (mut made, mut tries) = (0, 0);
        while made < count {
            tries += 1;
            if tries > 1000 {
                tries = 0;
                made += 1;
            }
            let Some(mut p) = self.random_inside(i32::MAX) else { continue };
            while self.open((p.0, p.1 + 1, p.2)) {
                p.1 += 1;
            }
            if !self.is_brick((p.0, p.1 + 1, p.2)) || !self.mask.get(p) {
                continue;
            }
            if self.lights.iter().any(|o| (o.0 - p.0).abs() < 15 && (o.1 - p.1).abs() < 15 && (o.2 - p.2).abs() < 15) {
                continue;
            }
            let crowded = ACROSS.iter().any(|d| !self.open((p.0 + d.0, p.1, p.2 + d.2)) || !self.open((p.0 + d.0, p.1 - 1, p.2 + d.2)))
                || !self.open((p.0, p.1 - 2, p.2));
            if crowded {
                continue;
            }
            let chandelier = self.r(7) == 0 && (1..15).all(|k| self.open((p.0, p.1 - k, p.2))) && self.ids.chandelier != 0;
            let (lit, off) = if chandelier {
                (self.ids.chandelier, self.ids.chandelier_off)
            } else {
                let s = styles[self.variant(p)];
                (self.ids.lanterns[s], self.ids.lanterns_off[s])
            };
            if lit == 0 {
                continue;
            }
            made += 1;
            tries = 0;
            self.lights.push(p);
            // Its switch, and 2 in 3 switched off.
            let on = if self.switch_for(p) { self.r(3) == 0 } else { true };
            self.set(p, if on || off == 0 { lit } else { off });
        }
    }

    /// Lights_GenerateSwitch: on a wall within sight, 3-20 below the light and
    /// up to 12 across. Leaves a "switch" decoration whose style is the
    /// light's offset (x + 16, z + 16 << 5, -y << 10).
    fn switch_for(&mut self, light: P) -> bool {
        if self.ids.switch == 0 {
            return false;
        }
        for _ in 0..1000 {
            let p = (light.0 + self.rng.range(-12, 13), light.1 - self.rng.range(3, 21), light.2 + self.rng.range(-12, 13));
            if !self.open(p) || !self.open((p.0, p.1 - 1, p.2)) || !self.mask.get(p) {
                continue;
            }
            let Some(wall) = ACROSS.iter().find(|d| self.is_brick((p.0 + d.0, p.1, p.2 + d.2))) else { continue };
            if !self.sees(p, light) {
                continue;
            }
            self.set(p, self.ids.switch);
            let out = FACING.iter().position(|&f| f == (-wall.0, -wall.2)).unwrap_or(0) as i32;
            self.w.decorations.push(Decoration { kind: "rotation".into(), pos: p, style: out });
            let style = (light.0 - p.0 + 16) | (light.2 - p.2 + 16) << 5 | (light.1 - p.1) << 10;
            self.w.decorations.push(Decoration { kind: "switch".into(), pos: p, style });
            return true;
        }
        false
    }

    /// Whether the line from a to b crosses only open cells (Collision.CanHit).
    fn sees(&self, a: P, b: P) -> bool {
        let n = (b.0 - a.0).abs().max((b.1 - a.1).abs()).max((b.2 - a.2).abs()).max(1);
        (1..n).all(|k| {
            let t = k as f64 / n as f64;
            let q = (
                (a.0 as f64 + 0.5 + (b.0 - a.0) as f64 * t) as i32,
                (a.1 as f64 + 0.5 + (b.1 - a.1) as f64 * t) as i32,
                (a.2 as f64 + 0.5 + (b.2 - a.2) as f64 * t) as i32,
            );
            self.open(q)
        })
    }

    /// DungeonGlobalBanners.
    fn banners(&mut self) {
        let tries = (200.0 * self.width_t / 4200.0) as i32;
        for _ in 0..tries {
            let mut found = None;
            for _ in 0..1000 {
                if let Some(p) = self.random_inside(i32::MAX) {
                    found = Some(p);
                    break;
                }
            }
            let Some(mut p) = found else { continue };
            while self.open((p.0, p.1 + 1, p.2)) {
                p.1 += 1;
            }
            // Along the ceiling to a wall.
            let d = ACROSS[self.r(4) as usize];
            let mut n = 0;
            while n < 20 && self.open((p.0 + d.0, p.1, p.2 + d.2)) && !self.open((p.0 + d.0, p.1 + 1, p.2 + d.2)) {
                p = (p.0 + d.0, p.1, p.2 + d.2);
                n += 1;
            }
            let wall = (p.0 + d.0, p.1, p.2 + d.2);
            if !self.is_brick(wall) || !self.is_brick((p.0, p.1 + 1, p.2)) || self.get((p.0, p.1 + 1, p.2)) == self.ids.spike {
                continue;
            }
            if !(0..3).all(|k| self.open((p.0, p.1 - k, p.2))) || !self.mask.get(p) {
                continue;
            }
            let side = (-d.2, d.0);
            let near = (-1..=1).any(|t| (0..4).any(|k| {
                let id = self.get((p.0 + side.0 * t, p.1 - k, p.2 + side.1 * t));
                id != 0 && (id == self.ids.door || id == self.ids.colour_door || id == self.ids.door_top || self.ids.banners.contains(&id))
            }));
            if near {
                continue;
            }
            let banner = self.ids.banners[self.variant(p) * 2 + self.r(2) as usize];
            // A banner block hangs 1.5 tall from half a block up its cell:
            // the cell under the one by the ceiling, so its top meets it.
            let at = (p.0, p.1 - 1, p.2);
            if banner == 0 || !self.is_brick((at.0 + d.0, at.1, at.2 + d.2)) {
                continue;
            }
            self.set(at, banner);
            let out = FACING.iter().position(|&f| f == (-d.0, -d.2)).unwrap_or(0) as i32;
            self.w.decorations.push(Decoration { kind: "rotation".into(), pos: at, style: out });
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE, RENDER_CUTOUT};

    /// The dungeon's blocks for test worlds (the game has them in blocks.json).
    pub(crate) fn add_dungeon_defs(w: &mut World) {
        let mut id = w.defs.len() as u16;
        let mut add = |w: &mut World, name: &str, render: u8, solid: bool, platform: bool| {
            if w.id_of(name) != 0 {
                return;
            }
            w.set_def(id, BlockDef { name: name.into(), render, solid, opaque: solid && render == RENDER_CUBE, platform, variants: 1, ..Default::default() });
            id += 1;
        };
        for name in ["blue_brick", "green_brick", "pink_brick", "spike"] {
            add(w, name, RENDER_CUBE, true, false);
        }
        for name in ["blue_brick_platform", "green_brick_platform", "pink_brick_platform", "metal_shelf", "brass_shelf", "wood_shelf", "dungeon_shelf"] {
            add(w, name, RENDER_CUTOUT, false, true);
        }
        for name in ["dungeon_door", "blue_dungeon_door", "green_dungeon_door", "pink_dungeon_door", "door_top", "chest", "locked_gold_chest"] {
            add(w, name, RENDER_CUTOUT, true, false);
        }
        let mut sprites = vec!["book", "water_bolt_book", "water_candle", "lesser_healing_potion_bottle", "lesser_mana_potion_bottle", "switch",
            "marching_bones_banner", "necromantic_sign", "rusted_company_standard", "ragged_brotherhood_sigil", "molten_legion_flag", "diabolic_sigil"]
            .into_iter().map(String::from).collect::<Vec<_>>();
        for n in ["chain_lantern", "brass_lantern", "caged_lantern", "carriage_lantern", "alchemy_lantern", "diablost_lamp", "oil_rag_sconse",
                "blue_dungeon_chandelier", "green_dungeon_chandelier", "pink_dungeon_chandelier"] {
            sprites.push(n.into());
            sprites.push(format!("{n}_off"));
        }
        for name in &sprites {
            add(w, name, RENDER_CROSS, false, false);
        }
    }

    #[test]
    fn depths_map_onto_the_layers() {
        let l = crate::worldgen::layers(384);
        assert_eq!(depth_y(&l, 0.0), l.surface_base);
        assert_eq!(depth_y(&l, 130.0), l.cavern_top);
        assert_eq!(depth_y(&l, 710.0), l.underworld_top);
    }

    #[test]
    fn mask_marks_cells() {
        let mut m = Mask::new(10, 20, 5, 30, 40, 50);
        assert!(!m.get((12, 9, 25)));
        m.set((12, 9, 25));
        assert!(m.get((12, 9, 25)) && !m.get((12, 10, 25)));
        m.set((0, 0, 0)); // outside: ignored
        assert!(!m.get((0, 0, 0)));
    }
}
