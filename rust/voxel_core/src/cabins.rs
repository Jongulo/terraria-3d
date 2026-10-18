//! Underground cabins, like Terraria's (GameContent.Biomes.CaveHouse:
//! CaveHouseBiome, HouseUtils, HouseBuilder, WoodHouseBuilder), in 3D.
//!
//! Terraria's tiles are 2/3 of a block here (its 3-tile player is 2 blocks
//! tall), so its numbers are scaled by that: a room 15-30 tiles wide is 10-20
//! blocks, 8-12 tiles tall is 6-8 blocks (in practice 8-10 tiles, 6-7 blocks:
//! the search for the ceiling only reaches 10). Terraria's rooms are rectangles in
//! its 2D slice; here they're boxes, found the same way along z as along x.
//!
//! - A cabin starts at a random open spot in the caves, below the surface and
//!   above the Underworld, with no chest within 17 blocks (25 tiles).
//! - Its main room stands on the ground under that spot. Terraria's FindRoom
//!   searches for the walls from the floor block itself, so the main room is
//!   always its smallest: 10 x 10 x 6 (15 x 8 tiles). A room is stacked above it
//!   (sharing its ceiling) if that space is mostly open, and one below
//!   likewise; those are fitted to the cave around them. The cabin is then sunk
//!   2 blocks (3 tiles) into the ground.
//! - Not near lava or other structures; its surroundings decide its kind
//!   (Terraria's GetHouseType): Wood in dirt and stone, Ice in the snow,
//!   Desert in the underground desert, Jungle in the mud (Terraria's Mushroom,
//!   Granite and Marble cabins wait for their biomes: those sites are skipped).
//! - Each kind is built the same way from its own materials (HouseBuilder and
//!   its WoodHouseBuilder, IceHouseBuilder, DesertHouseBuilder and
//!   JungleHouseBuilder): a frame (floor, ceiling, the walls' corner posts) with
//!   the background wall between, the walls clad outside in a second layer of
//!   the frame (Terraria's wall is behind the room; here it lines the walls, so
//!   the outside is the frame like the Skyware house's Sunplate over its Disc
//!   Wall), platform stairs up between stacked rooms through a hatch of
//!   platforms, doors in the walls where there's open cave outside, platform
//!   hatches in the roof and the floor where it's open beyond, and beams down
//!   from the floor to the ground. Inside: unlit chandeliers, furniture against
//!   the walls (table, anvil, work bench, loom, piano, keg, bookcase, in the
//!   kind's style), and the kind's chest.
//!
//!   kind    frame / wall / beam                    chest
//!   Wood    Wood / Planked Wall / Wooden Beam      Gold Chest
//!   Ice     Boreal Wood / its wall / Boreal Beam   Frozen Chest
//!   Desert  Sandstone / its wall / Sandstone Column Sandstone Chest
//!   Jungle  Rich Mahogany / its wall / its beam    Rich Mahogany Chest
//!
//! - Then each room ages (AgeRoom), its own way for each kind:
//!   Wood    cobwebs, the wall gone to dirt in patches, holes in the frame.
//!   Ice     the frame mostly ice in patches (a fifth of that snow), icicles
//!           under the icy ceiling, the wall gone to snow in patches.
//!   Desert  a little of the frame hardened sand, sandstone stalactites under
//!           the ceiling, patches of the wall hardened sand.
//!   Jungle  the frame mostly jungle grass (a fifth of that mud), jungle vines
//!           down from the grassy ceiling, patches of the wall jungle mud.
//! - Extras (PlaceBiomeSpecificTool): a Desert cabin may have a Bast Statue
//!   (3 in the world at most) and an Extractinator, a Jungle cabin a
//!   Sharpening Station (the first 2-4 cabins of the kind).

use crate::world::{Decoration, World, LIQ_LAVA, SHAPE_RAMP};
use crate::worldgen::{Layers, Rng, FACING};

/// A room: a box with a one-block shell. (x0, y0, z0) is its low corner; y0 is
/// the floor and y0 + h - 1 the ceiling.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Room {
    pub x0: i32,
    pub y0: i32,
    pub z0: i32,
    pub w: i32,
    pub h: i32,
    pub d: i32,
}

impl Room {
    pub fn x1(&self) -> i32 {
        self.x0 + self.w - 1
    }
    pub fn z1(&self) -> i32 {
        self.z0 + self.d - 1
    }
    pub fn ceiling(&self) -> i32 {
        self.y0 + self.h - 1
    }
    fn holds_column(&self, x: i32, z: i32) -> bool {
        x >= self.x0 && x <= self.x1() && z >= self.z0 && z <= self.z1()
    }
    /// Within the room's footprint or its walls' outer Wood layer.
    fn covers_column(&self, x: i32, z: i32) -> bool {
        x >= self.x0 - 1 && x <= self.x1() + 1 && z >= self.z0 - 1 && z <= self.z1() + 1
    }
    fn is_shell(&self, x: i32, y: i32, z: i32) -> bool {
        x == self.x0 || x == self.x1() || z == self.z0 || z == self.z1() || y == self.y0 || y == self.ceiling()
    }
}

// Terraria's numbers, in blocks (tiles x 2/3).
const WALL_SEARCH: i32 = 17; // 25 tiles
const CEILING_SEARCH: i32 = 7; // 10 tiles
const FLOOR_SEARCH: i32 = 133; // 200 tiles
const MIN_WIDTH: i32 = 10; // 15 tiles
const MAX_WIDTH: i32 = 20; // 30 tiles
const MIN_HEIGHT: i32 = 6; // 8 tiles (5.3 blocks: 6, for a door and headroom)
const MAX_HEIGHT: i32 = 8; // 12 tiles
const BELOW_ROOM: i32 = 7; // the room below is looked for 10 tiles under the floor
const SINK: i32 = 2; // 3 tiles
const CHEST_CLEARANCE: i32 = 17; // 25 tiles
const SURROUNDINGS: i32 = 7; // GetHouseType looks 10 tiles round each room
const BEAM_REACH: i32 = 33; // 50 tiles

/// The cabin's kinds (Terraria's HouseType).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Kind {
    Wood,
    Ice,
    Desert,
    Jungle,
    Mushroom,
    Granite,
    Marble,
}

/// What a kind of cabin is built from (HouseBuilder's TileType, WallType,
/// BeamType, PlatformStyle, DoorStyle, ChestStyle and furniture styles).
struct Style {
    kind: Kind,
    frame: u16,
    lining: u16,
    beam: u16,
    platform: u16,
    door: u16,
    chest: u16,
    /// The chest decoration's style: which loot it holds (scripts/world/chests.gd).
    chest_style: i32,
    /// FillRooms' furniture: table, anvil, work bench, loom, piano, keg, bookcase.
    furniture: Vec<u16>,
}

// Chest decoration styles (chests.gd's loot tables).
const CHEST_GOLD: i32 = 3;
const CHEST_FROZEN: i32 = 4;
const CHEST_SANDSTONE: i32 = 5;
const CHEST_SANDSTONE_DEEP: i32 = 6;

struct Ids {
    door_top: u16,
    cobweb: u16,
    dirt: u16,
    ice: u16,
    snow: u16,
    sandstone: u16,
    hardened_sand: u16,
    mud: u16,
    jungle_grass: u16,
    /// Hanging stalactites, large and small (Terraria's tile 165): ice, sandstone.
    icicles: [u16; 2],
    sand_stalactites: [u16; 2],
    jungle_vines: u16,
    bast_statue: u16,
    extractinator: u16,
    sharpening_station: u16,
    chandeliers: Vec<u16>,
    styles: Vec<Style>,
    blacklist: Vec<bool>,
}

impl Ids {
    fn new(w: &World) -> Self {
        let id = |n: &str| w.id_of(n);
        // Structures a cabin mustn't be built into (Terraria's protected
        // structures and blacklisted tiles): dungeon brick, living trees, tree
        // trunks, other cabins, chests, sky islands.
        let mut blacklist = vec![false; w.defs.len()];
        for (i, d) in w.defs.iter().enumerate() {
            let n = d.name.as_str();
            blacklist[i] = n.ends_with("_brick") && !n.starts_with("sandstone") && !n.starts_with("ice")
                || n.contains("trunk")
                || n.starts_with("living_")
                || n.contains("leaves")
                || n.contains("chest")
                || n.ends_with("_wall")
                || n.ends_with("_beam")
                || n.ends_with("_column")
                || n.starts_with("sunplate")
                || n == "cloud";
        }
        let style = |kind: Kind, wood: &str, frame: &str, lining: &str, beam: &str, chest: &str, chest_style: i32| {
            let f = |piece: &str, plain: &str| if wood.is_empty() { id(plain) } else { id(&format!("{wood}_{piece}")) };
            Style {
                kind,
                frame: id(frame),
                lining: id(lining),
                beam: id(beam),
                platform: if wood.is_empty() { id("wood_platform") } else { id(&format!("{wood}_platform")) },
                door: if wood.is_empty() { id("wooden_door") } else { id(&format!("{wood}_door")) },
                chest: id(chest),
                chest_style,
                furniture: vec![f("table", "wooden_table"), id("iron_anvil"), f("work_bench", "work_bench"), id("loom"), f("piano", "piano"), id("keg"), f("bookcase", "bookcase")],
            }
        };
        Ids {
            door_top: id("door_top"),
            cobweb: id("cobweb"),
            dirt: id("dirt"),
            ice: id("ice_block"),
            snow: id("snow_block"),
            sandstone: id("sandstone"),
            hardened_sand: id("hardened_sand"),
            mud: id("mud"),
            jungle_grass: id("jungle_grass"),
            icicles: [id("icicle"), id("small_icicle")],
            sand_stalactites: [id("sandstone_stalactite"), id("small_sandstone_stalactite")],
            jungle_vines: id("jungle_vines"),
            bast_statue: id("bast_statue"),
            extractinator: id("extractinator"),
            sharpening_station: id("sharpening_station"),
            // Terraria's chandelier styles 0-5 (copper, silver, gold, tin,
            // tungsten, platinum), unlit as cabins have them.
            chandeliers: ["copper", "silver", "gold", "tin", "tungsten", "platinum"]
                .iter()
                .map(|m| id(&format!("{m}_chandelier_off")))
                .collect(),
            styles: vec![
                style(Kind::Wood, "", "wood", "planked_wall", "wooden_beam", "gold_chest", CHEST_GOLD),
                style(Kind::Ice, "boreal_wood", "boreal_wood", "boreal_wood_wall", "boreal_beam", "frozen_chest", CHEST_FROZEN),
                style(Kind::Desert, "sandstone", "sandstone", "sandstone_wall", "sandstone_column", "sandstone_chest", CHEST_SANDSTONE),
                style(Kind::Jungle, "rich_mahogany", "rich_mahogany", "rich_mahogany_wall", "rich_mahogany_beam", "rich_mahogany_chest", CHEST_GOLD),
            ],
            blacklist,
        }
    }

    /// The kind's materials, if the game has them.
    fn style(&self, kind: Kind) -> Option<&Style> {
        self.styles.iter().find(|s| s.kind == kind && s.frame != 0 && s.lining != 0 && s.platform != 0 && s.chest != 0)
    }
}

/// What the cabins built so far have had (HouseBuilderContext; GenVars'
/// extraBastStatueCount).
#[derive(Default)]
struct Context {
    sharpeners: i32,
    extractinators: i32,
    bast_statues: i32,
    bast_statue_max: i32,
    /// Below this, a Sandstone Chest holds the deeper desert's loot.
    desert_deep_below: i32,
}

/// Builds up to `count` cabins (Terraria's CaveHouseCount), trying random
/// spots until that many are up or 10000 tries have failed. Returns the rooms
/// of each cabin built.
pub fn underground_cabins(w: &mut World, rng: &mut Rng, l: &Layers, count: usize) -> Vec<Vec<Room>> {
    let ids = Ids::new(w);
    let mut built: Vec<Vec<Room>> = Vec::new();
    if ids.style(Kind::Wood).is_none() {
        return built;
    }
    let mut chests: Vec<(i32, i32, i32)> = w.decorations.iter().filter(|d| d.kind == "chest").map(|d| d.pos).collect();
    let mut cx = context(w, l);
    // Terraria: x 80 tiles from the edges, y from 20 tiles under the lowest
    // surface to 230 tiles above the world's bottom.
    let margin = 53;
    let top = l.surface_base - 9 - 13; // below the lowest valleys (the hills' depth), then 20 tiles
    let bottom = l.underworld_top + 20;
    let mut failures = 0;
    while built.len() < count && failures < 10000 {
        let origin = (rng.range(margin, w.sx - margin), rng.range(bottom, top.max(bottom + 1)), rng.range(margin, w.sz - margin));
        match try_cabin(w, rng, &ids, &mut cx, origin, l, &built, &chests) {
            Some(rooms) => {
                for d in w.decorations.iter().rev() {
                    if d.kind == "chest" {
                        chests.push(d.pos);
                        break;
                    }
                }
                built.push(rooms);
            }
            None => failures += 1,
        }
    }
    built
}

/// The world's limits for the extras: Terraria allows 2 extra Bast Statues,
/// 3 in a large world (wider than 6400 tiles; Terraria's small world is about
/// 640 x 640 blocks here); a Sandstone Chest in the lower 3/7 of the
/// underground desert (from the surface down to where the desert ends) has
/// the deeper loot.
fn context(w: &World, l: &Layers) -> Context {
    let wide = 4200.0 * ((w.sx as f32 * w.sz as f32) / (640.0 * 640.0)).sqrt();
    let top = l.surface_base;
    let lowest = l.cavern_top.min(top - 45);
    Context {
        bast_statue_max: 2 + if wide > 8400.0 { 2 } else if wide > 6400.0 { 1 } else { 0 },
        desert_deep_below: top - (top - lowest) * 4 / 7,
        ..Default::default()
    }
}

/// One cabin at `origin` (CaveHouseBiome.Place): its rooms if it was built.
fn try_cabin(w: &mut World, rng: &mut Rng, ids: &Ids, cx: &mut Context, origin: (i32, i32, i32), l: &Layers, built: &[Vec<Room>], chests: &[(i32, i32, i32)]) -> Option<Vec<Room>> {
    let (ox, oy, oz) = origin;
    if chests.iter().any(|&(x, y, z)| (x - ox).abs() <= CHEST_CLEARANCE && (y - oy).abs() <= CHEST_CLEARANCE && (z - oz).abs() <= CHEST_CLEARANCE) {
        return None;
    }
    let rooms = create_rooms(w, rng, origin)?;
    if !rooms_in_place(w, &rooms, l) {
        return None;
    }
    let style = ids.style(house_type(w, &rooms))?;
    if !rooms_clear(w, ids, &rooms, built) {
        return None;
    }
    build(w, rng, ids, style, cx, &rooms);
    Some(rooms)
}

/// Terraria's HouseUtils.CreateRooms: the main room on the ground under
/// `origin`, maybe one stacked above and one below. Top to bottom.
pub fn create_rooms(w: &World, rng: &mut Rng, origin: (i32, i32, i32)) -> Option<Vec<Room>> {
    let (ox, oy, oz) = origin;
    // Down to the ground (the origin itself mustn't be in it).
    let mut floor = None;
    for k in 0..FLOOR_SEARCH {
        if oy - k < 1 {
            break;
        }
        if w.is_solid(ox, oy - k, oz) {
            floor = Some(oy - k);
            break;
        }
    }
    let fy = floor?;
    if fy == oy {
        return None;
    }
    let main = find_room(w, (ox, fy, oz));
    let (cx, cz) = (main.x0 + main.w / 2, main.z0 + main.d / 2);
    // Above: looked for from just under the main room's ceiling; its floor
    // is the main room's ceiling.
    let mut above = find_room(w, (cx, main.ceiling() - 1, cz));
    above.y0 = main.ceiling();
    // Below: looked for under the floor; its ceiling is the main room's floor.
    let mut below = find_room(w, (cx, main.y0 - 1 - BELOW_ROOM, cz));
    below.y0 = main.y0 - (below.h - 1);
    let solid_above = solid_fraction(w, &above);
    let solid_below = solid_fraction(w, &below);
    let sink = |r: Room| Room { y0: r.y0 - SINK, ..r };
    let mut rooms = Vec::new();
    if rng.unit() > solid_above + 0.2 {
        rooms.push(sink(above));
    }
    rooms.push(sink(main));
    if rng.unit() > solid_below + 0.2 {
        rooms.push(sink(below));
    }
    Some(rooms)
}

/// Terraria's HouseUtils.FindRoom from the block `p` (the room's floor is the
/// cell above it): the walls are the nearest solid blocks each way (searching
/// from `p` itself), the room spanning the wider side; its height reaches the
/// ceiling over the wall points.
pub fn find_room(w: &World, p: (i32, i32, i32)) -> Room {
    let (px, py, pz) = p;
    let search = |dx: i32, dz: i32| -> (i32, i32) {
        for k in 0..WALL_SEARCH {
            let (x, z) = (px + dx * k, pz + dz * k);
            if w.is_solid(x, py, z) {
                return (x, z);
            }
        }
        (px + dx * WALL_SEARCH, pz + dz * WALL_SEARCH)
    };
    let (left, _) = search(-1, 0);
    let (right, _) = search(1, 0);
    let (_, back) = search(0, -1);
    let (_, front) = search(0, 1);
    let span = |lo: i32, hi: i32, at: i32| -> (i32, i32) {
        let size = (hi - lo).clamp(MIN_WIDTH, MAX_WIDTH);
        if at - lo > hi - at { (lo, size) } else { (hi - size, size) }
    };
    let (x0, wd) = span(left, right, px);
    let (z0, dp) = span(back, front, pz);
    let up = |x: i32, z: i32| -> i32 {
        for k in 0..CEILING_SEARCH {
            if w.is_solid(x, py + k, z) {
                return k;
            }
        }
        CEILING_SEARCH
    };
    let rise = up(left, pz).max(up(right, pz)).max(up(px, back)).max(up(px, front));
    let h = rise.clamp(MIN_HEIGHT, MAX_HEIGHT);
    Room { x0, y0: py + 1, z0, w: wd, h, d: dp }
}

/// How much of the room's box is solid (HouseUtils.GetRoomSolidPrecentage).
fn solid_fraction(w: &World, r: &Room) -> f64 {
    let mut solid = 0;
    for x in r.x0..=r.x1() {
        for z in r.z0..=r.z1() {
            for y in r.y0..=r.ceiling() {
                if w.is_solid(x, y, z) {
                    solid += 1;
                }
            }
        }
    }
    solid as f64 / (r.w * r.h * r.d) as f64
}

/// Inside the world with a margin, and clear of the Underworld
/// (AreRoomLocationsValid).
fn rooms_in_place(w: &World, rooms: &[Room], l: &Layers) -> bool {
    rooms.iter().all(|r| {
        let m = CEILING_SEARCH;
        r.x0 >= m && r.z0 >= m && r.x1() < w.sx - m && r.z1() < w.sz - m && r.y0 >= l.underworld_top + 13 && r.ceiling() < w.sy - m
    })
}

/// No lava within 2 blocks, no protected structure within 3 and no other
/// cabin within 5 (AreRoomsValid; StructureMap's padding).
fn rooms_clear(w: &World, ids: &Ids, rooms: &[Room], built: &[Vec<Room>]) -> bool {
    for r in rooms {
        for other in built.iter().flatten() {
            let pad = 5;
            if r.x0 - pad <= other.x1() && other.x0 <= r.x1() + pad && r.z0 - pad <= other.z1() && other.z0 <= r.z1() + pad
                && r.y0 - pad <= other.ceiling() && other.y0 <= r.ceiling() + pad {
                return false;
            }
        }
        for x in r.x0 - 3..=r.x1() + 3 {
            for z in r.z0 - 3..=r.z1() + 3 {
                for y in r.y0 - 3..=r.ceiling() + 3 {
                    let lava_near = x >= r.x0 - 2 && x <= r.x1() + 2 && z >= r.z0 - 2 && z <= r.z1() + 2 && y >= r.y0 - 2 && y <= r.ceiling() + 2;
                    if lava_near && w.liquid_at(x, y, z).0 == LIQ_LAVA && w.liquid_at(x, y, z).1 > 0 {
                        return false;
                    }
                    if ids.blacklist.get(w.get(x, y, z) as usize).copied().unwrap_or(false) {
                        return false;
                    }
                }
            }
        }
    }
    true
}

/// Terraria's HouseUtils.GetHouseType: what the ground round the rooms is
/// mostly made of. Wood: dirt and stone; Ice: snow and ice; Desert: sand,
/// hardened sand and sandstone; Jungle: mud and jungle grass (x10); Mushroom:
/// mud and mushroom grass (x10); Granite; Marble. Ties go to the first.
pub fn house_type(w: &World, rooms: &[Room]) -> Kind {
    let names = ["dirt", "stone", "snow_block", "ice_block", "hardened_sand", "sandstone", "sand", "mud", "jungle_grass", "mushroom_grass", "granite", "marble"];
    let ids: Vec<u16> = names.iter().map(|n| w.id_of(n)).collect();
    let mut counts = [0i64; 12];
    for r in rooms {
        let s = SURROUNDINGS;
        for x in r.x0 - s..=r.x1() + s {
            for z in r.z0 - s..=r.z1() + s {
                for y in r.y0 - s..=r.ceiling() + s {
                    let b = w.get(x, y, z);
                    if b == 0 {
                        continue;
                    }
                    if let Some(k) = ids.iter().position(|&id| id == b) {
                        counts[k] += 1;
                    }
                }
            }
        }
    }
    let c = |n: &str| counts[names.iter().position(|&m| m == n).unwrap()];
    let scores = [
        (Kind::Wood, c("dirt") + c("stone")),
        (Kind::Ice, c("snow_block") + c("ice_block")),
        (Kind::Desert, c("hardened_sand") + c("sandstone") + c("sand")),
        (Kind::Jungle, c("mud") + c("jungle_grass") * 10),
        (Kind::Mushroom, c("mud") + c("mushroom_grass") * 10),
        (Kind::Granite, c("granite")),
        (Kind::Marble, c("marble")),
    ];
    let mut best = scores[0];
    for &s in &scores[1..] {
        if s.1 > best.1 {
            best = s;
        }
    }
    best.0
}

fn put(w: &mut World, x: i32, y: i32, z: i32, id: u16) {
    if w.in_bounds(x, y, z) {
        let i = w.idx(x, y, z);
        w.blocks[i] = id;
        w.liquid[i] = 0;
        w.shapes.remove(&i);
    }
}

fn face_index(d: (i32, i32)) -> i32 {
    FACING.iter().position(|&f| f == d).unwrap_or(0) as i32
}

/// A cabin of the style's kind (HouseBuilder.Place and the kind's builder).
fn build(w: &mut World, rng: &mut Rng, ids: &Ids, style: &Style, cx: &mut Context, rooms: &[Room]) {
    // Empty rooms: the shell, then the inside cleared.
    for r in rooms {
        for x in r.x0..=r.x1() {
            for z in r.z0..=r.z1() {
                for y in r.y0..=r.ceiling() {
                    let edge_x = x == r.x0 || x == r.x1();
                    let edge_z = z == r.z0 || z == r.z1();
                    let id = if !r.is_shell(x, y, z) {
                        0
                    } else if y == r.y0 || y == r.ceiling() || (edge_x && edge_z) {
                        style.frame
                    } else {
                        style.lining
                    };
                    put(w, x, y, z, id);
                }
            }
        }
    }
    // The walls' outer layer of the frame, floor to ceiling all round.
    for r in rooms {
        for x in r.x0 - 1..=r.x1() + 1 {
            for z in r.z0 - 1..=r.z1() + 1 {
                if r.holds_column(x, z) {
                    continue;
                }
                for y in r.y0..=r.ceiling() {
                    put(w, x, y, z, style.frame);
                }
            }
        }
    }
    let mut keep_clear: Vec<(i32, i32, i32)> = Vec::new();
    place_stairs(w, style, rooms, &mut keep_clear);
    place_doors(w, ids, style, rooms, &mut keep_clear);
    place_hatches(w, style, rooms);
    place_beams(w, style, rooms);
    // PlaceBiomeSpecificPriorityTool: a Desert cabin's Bast Statue, while
    // the world has fewer than its limit; on a floor, else on the roof.
    if style.kind == Kind::Desert && cx.bast_statues < cx.bast_statue_max && place_tool(w, rng, ids.bast_statue, rooms, &keep_clear, true) {
        cx.bast_statues += 1;
    }
    for r in rooms {
        fill_room(w, rng, ids, style, r, &keep_clear);
    }
    for r in rooms {
        match style.kind {
            Kind::Ice => age_ice(w, rng, ids, style, r),
            Kind::Desert => age_desert(w, rng, ids, style, r),
            Kind::Jungle => age_jungle(w, rng, ids, style, r),
            _ => age_wood(w, rng, ids, style, r),
        }
    }
    let chest_style = if style.kind == Kind::Desert && rooms[rooms.len() - 1].y0 < cx.desert_deep_below { CHEST_SANDSTONE_DEEP } else { style.chest_style };
    place_chest(w, rng, style, chest_style, rooms, &keep_clear);
    // PlaceBiomeSpecificTool: the first 2-4 Jungle cabins get a Sharpening
    // Station, the first 2-4 Desert cabins an Extractinator.
    if style.kind == Kind::Jungle && cx.sharpeners < rng.range(2, 5) && place_tool(w, rng, ids.sharpening_station, rooms, &keep_clear, false) {
        cx.sharpeners += 1;
    }
    if style.kind == Kind::Desert && cx.extractinators < rng.range(2, 5) && place_tool(w, rng, ids.extractinator, rooms, &keep_clear, false) {
        cx.extractinators += 1;
    }
}

/// Between each pair of stacked rooms: platform stairs in the lower room from
/// its floor up to under its ceiling against one end wall, and a hatch of
/// platforms in the ceiling over their top (HouseBuilder.PlaceStairs). The
/// stairs go up toward the end the room above reaches out over less.
fn place_stairs(w: &mut World, style: &Style, rooms: &[Room], keep_clear: &mut Vec<(i32, i32, i32)>) {
    for i in 1..rooms.len() {
        let (lower, upper) = (rooms[i], rooms[i - 1]);
        let overhang = (upper.x0 - lower.x0) - (lower.x1() - upper.x1());
        let (wall, dir) = if overhang > 0 { (lower.x1(), -1) } else { (lower.x0, 1) };
        // Two wide, against the back wall of both rooms.
        let zs = lower.z0.max(upper.z0) + 1;
        if zs + 1 >= lower.z1().min(upper.z1()) {
            continue;
        }
        let rises = if dir < 0 { SHAPE_RAMP + 1 } else { SHAPE_RAMP + 3 }; // toward the wall
        let steps = lower.h - 2;
        for k in 0..steps {
            let x = wall + dir * (k + 1);
            let y = lower.ceiling() - 1 - k;
            for z in zs..zs + 2 {
                put(w, x, y, z, style.platform);
                w.set_shape(x, y, z, rises);
                keep_clear.push((x, y, z));
            }
        }
        // The hatch over the top step: 3 blocks along (4 tiles).
        for k in 1..=3 {
            let x = wall + dir * k;
            for z in zs..zs + 2 {
                put(w, x, lower.ceiling(), z, style.platform);
            }
        }
    }
}

/// Doors in the walls, at the floor, where there's open cave outside
/// (HouseBuilder.FindSideExit / PlaceDoors: Terraria tries each side wall of
/// each room; here all four). The middle of the wall first, then out from it.
fn place_doors(w: &mut World, ids: &Ids, style: &Style, rooms: &[Room], keep_clear: &mut Vec<(i32, i32, i32)>) {
    if style.door == 0 || ids.door_top == 0 {
        return;
    }
    for r in rooms {
        // Each wall: its cell at position t along it, the way out, and t's range.
        for side in 0..4 {
            let (out, lo, hi) = match side {
                0 => ((1, 0), r.z0, r.z1()),
                1 => ((-1, 0), r.z0, r.z1()),
                2 => ((0, 1), r.x0, r.x1()),
                _ => ((0, -1), r.x0, r.x1()),
            };
            let cell = |t: i32| match side {
                0 => (r.x1(), t),
                1 => (r.x0, t),
                2 => (t, r.z1()),
                _ => (t, r.z0),
            };
            let mid = (lo + hi) / 2;
            let mut order: Vec<i32> = Vec::new();
            for k in 0..=(hi - lo) {
                for t in [mid - k, mid + k] {
                    if t > lo + 1 && t < hi - 1 && !order.contains(&t) {
                        order.push(t);
                    }
                }
            }
            for t in order {
                // The door goes in the outer layer, the lining behind it open.
                let (wx, wz) = cell(t);
                let (x, z) = (wx + out.0, wz + out.1);
                let y = r.y0 + 1;
                let inside = (wx - out.0, y, wz - out.1);
                if keep_clear.contains(&inside) || w.get(inside.0, y, inside.2) != 0 {
                    continue;
                }
                // Open outside: any open cell 3 out and 2 up (4 x 3 tiles).
                let open = (1..=3).any(|k| (0..2).any(|dy| !w.is_solid(x + out.0 * k, y + dy, z + out.1 * k)));
                if !open {
                    continue;
                }
                put(w, x, y, z, style.door);
                put(w, x, y + 1, z, ids.door_top);
                put(w, wx, y, wz, 0);
                put(w, wx, y + 1, wz, 0);
                w.decorations.push(Decoration { kind: "rotation".into(), pos: (x, y, z), style: face_index(out) });
                keep_clear.push(inside);
                keep_clear.push((wx, y, wz));
                break;
            }
        }
    }
}

/// A hatch of platforms (2 x 2: 3 tiles) in the top room's ceiling where it's
/// open above, and in the bottom room's floor where it's open below
/// (HouseBuilder.CreatePlatformsList / FindVerticalExit).
fn place_hatches(w: &mut World, style: &Style, rooms: &[Room]) {
    let (top, bottom) = (rooms[0], rooms[rooms.len() - 1]);
    for (r, y, dy) in [(top, top.ceiling(), 1), (bottom, bottom.y0, -1)] {
        'search: for x in (r.x0 + 1..r.x1() - 1).rev() {
            for z in (r.z0 + 1..r.z1() - 1).rev() {
                let open = (1..=3).any(|k| (0..2).any(|a| (0..2).any(|b| !w.is_solid(x + a, y + dy * k, z + b))));
                if open {
                    for a in 0..2 {
                        for b in 0..2 {
                            put(w, x + a, y, z + b, style.platform);
                        }
                    }
                    break 'search;
                }
            }
        }
    }
}

/// Beams from under the floor down to the ground (up to 33 blocks: 50
/// tiles), every 3-4 blocks (4-6 tiles) across the cabin both ways
/// (HouseBuilder.CreateSupportBeamList / PlaceSupportBeams).
fn place_beams(w: &mut World, style: &Style, rooms: &[Room]) {
    if style.beam == 0 {
        return;
    }
    let spacing = |lo: i32, hi: i32| {
        let mut s = 4;
        while s > 3 && (hi - lo) % s != 0 {
            s -= 1;
        }
        s
    };
    let (x_lo, x_hi) = (rooms.iter().map(|r| r.x0 - 1).min().unwrap(), rooms.iter().map(|r| r.x1() + 1).max().unwrap());
    let (z_lo, z_hi) = (rooms.iter().map(|r| r.z0 - 1).min().unwrap(), rooms.iter().map(|r| r.z1() + 1).max().unwrap());
    let (sx, sz) = (spacing(x_lo, x_hi), spacing(z_lo, z_hi));
    let mut x = x_lo;
    while x <= x_hi {
        let mut z = z_lo;
        while z <= z_hi {
            for (i, r) in rooms.iter().enumerate() {
                if !r.covers_column(x, z) {
                    continue;
                }
                let top = r.y0 - 1;
                // Not down into a room below.
                let mut reach = BEAM_REACH;
                for below in &rooms[i + 1..] {
                    if below.covers_column(x, z) {
                        reach = reach.min(top - below.ceiling());
                    }
                }
                if reach <= 0 || w.is_platform(x, r.y0, z) {
                    continue;
                }
                let ground = (0..reach).find(|&k| w.is_solid(x, top - k, z)).map(|k| top - k).or(if reach < BEAM_REACH { Some(top - reach) } else { None });
                if let Some(g) = ground {
                    if top - g > 1 {
                        for y in g + 1..=top {
                            put(w, x, y, z, style.beam);
                        }
                    }
                }
            }
            z += sz;
        }
        x += sx;
    }
}

/// A random cell inside the room against one of its walls, on the floor, and
/// the way into the room from it.
fn wall_spot(rng: &mut Rng, r: &Room) -> ((i32, i32, i32), (i32, i32)) {
    let y = r.y0 + 1;
    match rng.range(0, 4) {
        0 => ((r.x0 + 1, y, rng.range(r.z0 + 1, r.z1())), (1, 0)),
        1 => ((r.x1() - 1, y, rng.range(r.z0 + 1, r.z1())), (-1, 0)),
        2 => ((rng.range(r.x0 + 1, r.x1()), y, r.z0 + 1), (0, 1)),
        _ => ((rng.range(r.x0 + 1, r.x1()), y, r.z1() - 1), (0, -1)),
    }
}

/// Room for a piece of furniture at `p`: it and the cell over it open, not on
/// the stairs or in a doorway.
fn fits(w: &World, p: (i32, i32, i32), keep_clear: &[(i32, i32, i32)]) -> bool {
    let (x, y, z) = p;
    w.get(x, y, z) == 0 && w.get(x, y + 1, z) == 0 && w.is_solid(x, y - 1, z) && !keep_clear.contains(&p)
}

/// HouseBuilder.FillRooms: along the room, wall decorations (paintings, not in
/// the game yet) taking turns with unlit chandeliers, then a handful of
/// things on the floor: a pile, a big pile, a statue (none of those in the
/// game yet) or a piece of furniture.
fn fill_room(w: &mut World, rng: &mut Rng, ids: &Ids, style: &Style, r: &Room, keep_clear: &[(i32, i32, i32)]) {
    let tiles = |blocks: i32| blocks * 3 / 2;
    let n = tiles(r.w) / 8;
    let step = r.w / (n + 1);
    let first = rng.range(0, 2);
    for i in 0..n {
        let x = r.x0 + (i + 1) * step;
        if (i + first) % 2 == 1 {
            let kind = rng.range(0, 6) as usize;
            let id = ids.chandeliers.get(kind).copied().unwrap_or(0);
            let (y, z) = (r.ceiling() - 1, r.z0 + r.d / 2);
            if id != 0 && w.get(x, y, z) == 0 && w.is_solid(x, y + 1, z) {
                put(w, x, y, z, id);
            }
        }
    }
    // Terraria's width / 8 + 3 tries along its one back wall; a 3D room has a
    // long wall each side.
    let tries = (tiles(r.w) / 8 + 3) + (tiles(r.d) / 8 + 3);
    for _ in 0..tries {
        let (p, into) = wall_spot(rng, r);
        if rng.range(0, 4) != 3 {
            continue; // a pile, a big pile or a statue
        }
        let id = style.furniture[rng.range(0, style.furniture.len() as i32) as usize];
        if id != 0 && fits(w, p, keep_clear) {
            put(w, p.0, p.1, p.2, id);
            w.decorations.push(Decoration { kind: "rotation".into(), pos: p, style: face_index(into) });
        }
    }
}

/// A biome's piece of furniture (Bast Statue, Extractinator, Sharpening
/// Station: PlaceBiomeSpecificTool): 10 random spots on each room's floor,
/// then every spot along it; the Bast Statue then tries the roofs. True if
/// it went in.
fn place_tool(w: &mut World, rng: &mut Rng, id: u16, rooms: &[Room], keep_clear: &[(i32, i32, i32)], roof: bool) -> bool {
    if id == 0 {
        return false;
    }
    let put_at = |w: &mut World, p: (i32, i32, i32), into: (i32, i32)| {
        put(w, p.0, p.1, p.2, id);
        w.decorations.push(Decoration { kind: "rotation".into(), pos: p, style: face_index(into) });
    };
    let floors: Vec<i32> = rooms.iter().map(|r| r.y0 + 1).collect();
    let roofs: Vec<i32> = rooms.iter().map(|r| r.ceiling() + 1).collect();
    for levels in if roof { vec![floors, roofs] } else { vec![floors] } {
        for (r, &y) in rooms.iter().zip(&levels) {
            for _ in 0..10 {
                let (p, into) = wall_spot(rng, r);
                let p = (p.0, y, p.2);
                if fits(w, p, keep_clear) {
                    put_at(w, p, into);
                    return true;
                }
            }
            for x in r.x0 + 1..r.x1() {
                let p = (x, y, r.z0 + 1);
                if fits(w, p, keep_clear) {
                    put_at(w, p, (0, 1));
                    return true;
                }
            }
        }
    }
    false
}

/// Terraria's Dither(fail) then Blotches(2, chance) over `cells` (its
/// WorldUtils.Gen with those modifiers): a cell passes the dither 1 - fail of
/// the time, then `chance` of the time spreads to a patch round it (each way
/// 1-2 blocks, toward a random side), else is hit alone. `act` gets each cell hit.
fn dither_blotches(w: &mut World, rng: &mut Rng, cells: &[(i32, i32, i32)], fail: f64, chance: f64, act: &mut dyn FnMut(&mut World, &mut Rng, (i32, i32, i32))) {
    for &(x, y, z) in cells {
        if rng.unit() < fail {
            continue;
        }
        if rng.unit() < chance {
            let (x0, x1) = (x - rng.range(0, 2), x + rng.range(0, 2));
            let (y0, y1) = (y - rng.range(0, 2), y + rng.range(0, 2));
            let (z0, z1) = (z - rng.range(0, 2), z + rng.range(0, 2));
            for px in x0..=x1 {
                for py in y0..=y1 {
                    for pz in z0..=z1 {
                        act(w, rng, (px, py, pz));
                    }
                }
            }
        } else {
            act(w, rng, (x, y, z));
        }
    }
}

/// The room's box and the walls' outer layer round it.
fn box_cells(r: &Room) -> Vec<(i32, i32, i32)> {
    let mut cells = Vec::new();
    for x in r.x0 - 1..=r.x1() + 1 {
        for z in r.z0 - 1..=r.z1() + 1 {
            for y in r.y0..=r.ceiling() {
                cells.push((x, y, z));
            }
        }
    }
    cells
}

/// Where the room's frame is: its floor, ceiling and corner posts, and the
/// walls' outer layer.
fn frame_cells(r: &Room) -> Vec<(i32, i32, i32)> {
    let lining: std::collections::HashSet<_> = lining_cells(r).into_iter().collect();
    box_cells(r).into_iter().filter(|&(x, y, z)| !lining.contains(&(x, y, z)) && (!r.holds_column(x, z) || r.is_shell(x, y, z))).collect()
}

/// The walls between the corner posts (where the room's background wall is).
fn lining_cells(r: &Room) -> Vec<(i32, i32, i32)> {
    let mut cells = Vec::new();
    for x in r.x0..=r.x1() {
        for z in r.z0..=r.z1() {
            for y in r.y0 + 1..r.ceiling() {
                if r.is_shell(x, y, z) {
                    cells.push((x, y, z));
                }
            }
        }
    }
    cells
}

/// The inside of the ceiling and the floor (Terraria's top and bottom rows
/// less the corners), each with the cell beneath it.
fn ceiling_and_floor(r: &Room) -> Vec<(i32, i32, i32)> {
    let mut cells = Vec::new();
    for x in r.x0 + 1..r.x1() {
        for z in r.z0 + 1..r.z1() {
            cells.push((x, r.ceiling(), z));
            cells.push((x, r.y0, z));
        }
    }
    cells
}

/// Patches of the room's wall turned to `to` (Terraria: Dither then Blotches,
/// then a wall of another kind there).
fn age_walls(w: &mut World, rng: &mut Rng, r: &Room, lining: u16, fail: f64, chance: f64, to: u16) {
    if to == 0 {
        return;
    }
    // Terraria's wall fills the room's back, a flat 2D patch of it; here it's
    // the lining, flat round the walls: patches start on it.
    let cells = lining_cells(r);
    dither_blotches(w, rng, &cells, fail, chance, &mut |w, _, (x, y, z)| {
        if w.get(x, y, z) == lining && r.holds_column(x, z) && r.is_shell(x, y, z) {
            put(w, x, y, z, to);
        }
    });
}

/// Patches of the frame turned to `to`, `then` taking a share of them (1 -
/// `then_fail`): Terraria's OnlyTiles(TileType), SetTile, Dither, SetTile.
fn age_frame(w: &mut World, rng: &mut Rng, r: &Room, frame: u16, fail: f64, chance: f64, to: u16, then_fail: f64, then: u16) {
    let cells = frame_cells(r);
    let on_frame: std::collections::HashSet<(i32, i32, i32)> = cells.iter().copied().collect();
    dither_blotches(w, rng, &cells, fail, chance, &mut |w, rng, p| {
        if !on_frame.contains(&p) || w.get(p.0, p.1, p.2) != frame {
            return;
        }
        if to != 0 {
            put(w, p.0, p.1, p.2, to);
        }
        if then != 0 && rng.unit() >= then_fail {
            put(w, p.0, p.1, p.2, then);
        }
    });
}

/// Stalactites hanging under half the ceiling (and the floor) where it's
/// `on` (ActionStalagtite: WorldGen.PlaceTight, large or small at even odds).
fn hang_stalactites(w: &mut World, rng: &mut Rng, r: &Room, on: &[u16], kinds: [u16; 2]) {
    for (x, y, z) in ceiling_and_floor(r) {
        if rng.unit() < 0.5 || !on.contains(&w.get(x, y, z)) || w.get(x, y - 1, z) != 0 {
            continue;
        }
        let id = kinds[rng.range(0, 2) as usize];
        if id != 0 {
            put(w, x, y - 1, z, id);
        }
    }
}

/// WoodHouseBuilder.AgeRoom: cobwebs in blotches (2 x 2, half filled), the
/// Planked Wall gone to dirt in patches, and 5% of the Wood frame gone.
fn age_wood(w: &mut World, rng: &mut Rng, ids: &Ids, style: &Style, r: &Room) {
    if ids.cobweb != 0 {
        for _ in 0..(r.w * r.h * r.d) / 64 {
            let (x, y, z) = (rng.range(r.x0 + 1, r.x1()), rng.range(r.y0 + 1, r.ceiling()), rng.range(r.z0 + 1, r.z1()));
            for (a, b, c) in [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (1, 0, 1), (0, 1, 1), (1, 1, 1)] {
                let (px, py, pz) = (x + a, y + b, z + c);
                if rng.chance(0.5) && px < r.x1() && py < r.ceiling() && pz < r.z1() && w.get(px, py, pz) == 0 {
                    put(w, px, py, pz, ids.cobweb);
                }
            }
        }
    }
    // The dirt wall underground (Dither 0.85, Blotches 0.3).
    age_walls(w, rng, r, style.lining, 0.85, 0.3, ids.dirt);
    // Holes: 5% of the frame (its outer layer too).
    for (x, y, z) in frame_cells(r) {
        if w.get(x, y, z) == style.frame && rng.chance(0.05) {
            put(w, x, y, z, 0);
        }
    }
}

/// IceHouseBuilder.AgeRoom: the Boreal Wood frame turned to ice in patches
/// (Dither 0.6, Blotches 0.6), a fifth of that to snow; icicles under half the
/// icy ceiling; the wall gone to snow in patches underground (Dither 0.85,
/// Blotches 0.8; Terraria's snow wall).
fn age_ice(w: &mut World, rng: &mut Rng, ids: &Ids, style: &Style, r: &Room) {
    age_frame(w, rng, r, style.frame, 0.6, 0.6, ids.ice, 0.8, ids.snow);
    hang_stalactites(w, rng, r, &[ids.ice], ids.icicles);
    age_walls(w, rng, r, style.lining, 0.85, 0.8, ids.snow);
}

/// DesertHouseBuilder.AgeRoom: a little of the Sandstone frame (Dither 0.8,
/// Blotches 0.2) half turned to hardened sand; sandstone stalactites under half
/// the ceiling; patches of the wall turned to hardened sand wall (Dither 0.8,
/// Blotches 0.3).
fn age_desert(w: &mut World, rng: &mut Rng, ids: &Ids, style: &Style, r: &Room) {
    age_frame(w, rng, r, style.frame, 0.8, 0.2, 0, 0.5, ids.hardened_sand);
    hang_stalactites(w, rng, r, &[ids.sandstone, ids.hardened_sand], ids.sand_stalactites);
    age_walls(w, rng, r, style.lining, 0.8, 0.3, ids.hardened_sand);
}

/// JungleHouseBuilder.AgeRoom: the Rich Mahogany frame turned to jungle grass
/// in patches (Dither 0.6, Blotches 0.6), a fifth of that to mud; jungle vines
/// 3 tiles to the room's height long down from half the grassy ceiling; the
/// jungle wall in patches (Dither 0.85, Blotches 0.3).
fn age_jungle(w: &mut World, rng: &mut Rng, ids: &Ids, style: &Style, r: &Room) {
    age_frame(w, rng, r, style.frame, 0.6, 0.6, ids.jungle_grass, 0.8, ids.mud);
    if ids.jungle_vines != 0 {
        for (x, y, z) in ceiling_and_floor(r) {
            if rng.unit() < 0.5 || w.get(x, y, z) != ids.jungle_grass {
                continue;
            }
            let len = rng.range(2, r.h + 1);
            for k in 1..=len {
                if w.get(x, y - k, z) != 0 {
                    break;
                }
                put(w, x, y - k, z, ids.jungle_vines);
            }
        }
    }
    age_walls(w, rng, r, style.lining, 0.85, 0.3, ids.mud);
}

/// The cabin's chest (HouseBuilder.PlaceChests: every cabin has one, the
/// kind's): 10 random spots on each room's floor, then every spot, then on the
/// roof.
fn place_chest(w: &mut World, rng: &mut Rng, style: &Style, chest_style: i32, rooms: &[Room], keep_clear: &[(i32, i32, i32)]) {
    let put_chest = |w: &mut World, p: (i32, i32, i32), into: (i32, i32)| {
        put(w, p.0, p.1, p.2, style.chest);
        w.decorations.push(Decoration { kind: "chest".into(), pos: p, style: chest_style });
        w.decorations.push(Decoration { kind: "rotation".into(), pos: p, style: face_index(into) });
    };
    for r in rooms {
        for _ in 0..10 {
            let (p, into) = wall_spot(rng, r);
            if fits(w, p, keep_clear) {
                put_chest(w, p, into);
                return;
            }
        }
        for x in r.x0 + 1..r.x1() {
            for z in r.z0 + 1..r.z1() {
                let p = (x, r.y0 + 1, z);
                if fits(w, p, keep_clear) {
                    let into = if x == r.x0 + 1 { (1, 0) } else if x == r.x1() - 1 { (-1, 0) } else if z == r.z0 + 1 { (0, 1) } else { (0, -1) };
                    put_chest(w, p, into);
                    return;
                }
            }
        }
    }
    for r in rooms {
        for x in r.x0 + 1..r.x1() {
            for z in r.z0 + 1..r.z1() {
                let p = (x, r.ceiling() + 1, z);
                if fits(w, p, keep_clear) {
                    put_chest(w, p, (0, 1));
                    return;
                }
            }
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE, RENDER_CUTOUT};

    /// Registers the blocks cabins are built from after the world's own.
    pub(crate) fn add_cabin_defs(w: &mut World) {
        let mut id = w.defs.len() as u16;
        let mut add = |w: &mut World, name: &str, render: u8, solid: bool, platform: bool| {
            if w.id_of(name) != 0 {
                return;
            }
            w.set_def(id, BlockDef { name: name.into(), render, solid, opaque: solid && render == RENDER_CUBE, platform, variants: 1, ..Default::default() });
            id += 1;
        };
        for name in ["wood", "planked_wall", "wooden_beam", "boreal_wood", "boreal_wood_wall", "boreal_beam", "sandstone", "sandstone_wall", "sandstone_column",
                "rich_mahogany", "rich_mahogany_wall", "rich_mahogany_beam", "dirt", "snow_block", "ice_block", "hardened_sand", "mud", "jungle_grass"] {
            add(w, name, RENDER_CUBE, true, false);
        }
        for wood in ["wood", "boreal_wood", "sandstone", "rich_mahogany"] {
            add(w, &format!("{wood}_platform"), RENDER_CUTOUT, false, true);
        }
        for name in ["wooden_door", "boreal_wood_door", "sandstone_door", "rich_mahogany_door", "door_top", "gold_chest", "frozen_chest", "sandstone_chest", "rich_mahogany_chest"] {
            add(w, name, RENDER_CUTOUT, true, false);
        }
        for m in ["copper", "silver", "gold", "tin", "tungsten", "platinum"] {
            add(w, &format!("{m}_chandelier_off"), RENDER_CUTOUT, false, false);
        }
        for name in ["wooden_table", "iron_anvil", "work_bench", "loom", "piano", "keg", "bookcase", "bast_statue", "extractinator", "sharpening_station"] {
            add(w, name, RENDER_CUTOUT, false, false);
        }
        for wood in ["boreal_wood", "sandstone", "rich_mahogany"] {
            for piece in ["table", "work_bench", "piano", "bookcase"] {
                add(w, &format!("{wood}_{piece}"), RENDER_CUTOUT, false, false);
            }
        }
        for name in ["cobweb", "icicle", "small_icicle", "sandstone_stalactite", "small_sandstone_stalactite", "jungle_vines"] {
            add(w, name, RENDER_CROSS, false, false);
        }
    }

    /// Stone 128 x 96 x 128 with a big cave (x, z 20..108, y 20..70) whose
    /// floor is y 19.
    fn cave_world() -> World {
        let mut w = World::new();
        w.set_def(1, BlockDef { name: "stone".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        add_cabin_defs(&mut w);
        w.resize(128, 96, 128);
        let stone = w.id_of("stone");
        for x in 0..128 {
            for z in 0..128 {
                for y in 0..96 {
                    let open = (20..108).contains(&x) && (20..108).contains(&z) && (20..70).contains(&y);
                    let i = w.idx(x, y, z);
                    w.blocks[i] = if open { 0 } else { stone };
                }
            }
        }
        w
    }

    fn layers() -> Layers {
        Layers { underworld_top: 2, cavern_top: 40, surface_base: 90, space_top: 95 }
    }

    /// A cabin built at (64, 40, 64) with the first seed that stacks a room on
    /// the main one.
    fn stacked_cabin() -> (World, Vec<Room>) {
        for seed in 0..200u64 {
            let mut w = cave_world();
            let ids = Ids::new(&w);
            let mut rng = Rng::new(seed);
            if let Some(rooms) = try_cabin(&mut w, &mut rng, &ids, &mut Context::default(), (64, 40, 64), &layers(), &[], &[]) {
                if rooms.len() == 2 {
                    return (w, rooms);
                }
            }
        }
        panic!("no seed stacked a room");
    }

    #[test]
    fn the_main_room_is_terrarias_smallest_on_the_ground() {
        let w = cave_world();
        // Searching from the floor block itself finds walls straight away:
        // 15 x 8 tiles, here 10 x 10 x 6, standing on the floor (y 19).
        let r = find_room(&w, (64, 19, 64));
        assert_eq!((r.w, r.d, r.h, r.y0), (10, 10, 6, 20));
        assert_eq!((r.x0, r.z0), (54, 54), "it spans toward -x and -z from the spot");
        // Out in the open cave a room reaches the widest (30 tiles: 20) and
        // as tall as the search for a ceiling reaches (10 tiles: 7).
        let open = find_room(&w, (64, 30, 64));
        assert_eq!((open.w, open.d, open.h), (20, 20, 7));
    }

    #[test]
    fn a_wooden_cabin_in_a_cave() {
        let (w, rooms) = stacked_cabin();
        let (upper, main) = (rooms[0], rooms[1]);
        let id = |n: &str| w.id_of(n);
        assert_eq!(upper.y0, main.ceiling(), "the room above stands on the main room's ceiling");
        assert_eq!(main.y0, 18, "sunk 2 blocks into the ground");
        // The frame and walls: the floors mostly Wood (holes and hatches
        // aside), the side walls Planked Wall gone to dirt here and there.
        let mut floor = 0;
        let mut wood = 0;
        for x in main.x0..=main.x1() {
            for z in main.z0..=main.z1() {
                floor += 1;
                if w.get(x, main.y0, z) == id("wood") {
                    wood += 1;
                }
            }
        }
        assert!(wood * 100 >= floor * 80, "the floor is Wood ({wood} of {floor})");
        let mut planked = 0;
        let mut dirt = 0;
        for r in &rooms {
            for x in r.x0..=r.x1() {
                for z in r.z0..=r.z1() {
                    for y in r.y0 + 1..r.ceiling() {
                        match w.get(x, y, z) {
                            b if b == id("planked_wall") => planked += 1,
                            b if b == id("dirt") => dirt += 1,
                            _ => {}
                        }
                    }
                }
            }
        }
        assert!(planked > 0 && dirt > 0 && dirt * 100 < (planked + dirt) * 40, "walls: {planked} planked, {dirt} gone to dirt");
        // Outside, the walls are Wood (or a door, or a hole), never the lining.
        for r in &rooms {
            for x in r.x0 - 1..=r.x1() + 1 {
                for z in r.z0 - 1..=r.z1() + 1 {
                    if r.holds_column(x, z) {
                        continue;
                    }
                    for y in r.y0..=r.ceiling() {
                        let b = w.get(x, y, z);
                        assert!(b != id("planked_wall") && b != id("dirt"), "the outside at {x},{y},{z} is the lining");
                    }
                }
            }
        }
        // Stairs up from the main room into the room above: a ramp each step,
        // two wide, and a hatch of platforms over them.
        let ramps = w.shapes.values().filter(|s| (SHAPE_RAMP..SHAPE_RAMP + 4).contains(*s)).count() as i32;
        assert_eq!(ramps, (main.h - 2) * 2, "a stair of platforms");
        let hatch = (main.x0..=main.x1()).flat_map(|x| (main.z0..=main.z1()).map(move |z| (x, z))).filter(|&(x, z)| w.get(x, main.ceiling(), z) == id("wood_platform")).count();
        assert!(hatch >= 6, "a hatch in the ceiling over the stairs ({hatch})");
        // Doors out into the cave, standing on the floor.
        let doors: Vec<_> = w.decorations.iter().filter(|d| d.kind == "rotation" && w.get(d.pos.0, d.pos.1, d.pos.2) == id("wooden_door")).collect();
        assert!(!doors.is_empty(), "doors out into the cave");
        assert!(doors.iter().all(|d| w.get(d.pos.0, d.pos.1 + 1, d.pos.2) == id("door_top") && rooms.iter().any(|r| d.pos.1 == r.y0 + 1)), "doors stand on the floor");
        // The room above is wider: Wooden Beams hold it up, down to the ground.
        let beams = (0..128).flat_map(|x| (0..128).map(move |z| (x, z))).filter(|&(x, z)| w.get(x, upper.y0 - 1, z) == id("wooden_beam")).count();
        assert!(beams > 0, "beams under the overhang");
        assert!((0..128).all(|x| (0..128).all(|z| w.get(x, upper.y0 - 1, z) != id("wooden_beam") || w.is_solid(x, 19, z))), "beams reach the ground");
        // One Gold Chest, on a floor, a worldgen chest of style 3.
        let chests: Vec<_> = w.decorations.iter().filter(|d| d.kind == "chest").collect();
        assert_eq!(chests.len(), 1);
        let (cx, cy, cz) = chests[0].pos;
        assert!(w.get(cx, cy, cz) == id("gold_chest") && chests[0].style == 3 && w.is_solid(cx, cy - 1, cz));
        // Cobwebs, and nothing but cabin inside.
        let webs = rooms.iter().map(|r| (r.x0..=r.x1()).flat_map(|x| (r.z0..=r.z1()).flat_map(move |z| (r.y0..=r.ceiling()).map(move |y| (x, y, z)))).filter(|&(x, y, z)| w.get(x, y, z) == id("cobweb")).count()).sum::<usize>();
        assert!(webs > 0, "cobwebs");
    }

    #[test]
    fn chandeliers_hang_unlit_and_furniture_stands_against_the_walls() {
        let mut lit = 0;
        let mut furniture = 0;
        for seed in 0..40u64 {
            let mut w = cave_world();
            let ids = Ids::new(&w);
            let mut rng = Rng::new(seed);
            let Some(rooms) = try_cabin(&mut w, &mut rng, &ids, &mut Context::default(), (64, 40, 64), &layers(), &[], &[]) else { continue };
            for r in &rooms {
                for x in r.x0 + 1..r.x1() {
                    for z in r.z0 + 1..r.z1() {
                        let top = w.get(x, r.ceiling() - 1, z);
                        if ids.chandeliers.contains(&top) {
                            lit += 1;
                            assert!(w.is_solid(x, r.ceiling(), z) || w.get(x, r.ceiling(), z) == 0, "hung from the ceiling");
                        }
                        let b = w.get(x, r.y0 + 1, z);
                        if ids.style(Kind::Wood).unwrap().furniture.contains(&b) {
                            furniture += 1;
                            let against = x == r.x0 + 1 || x == r.x1() - 1 || z == r.z0 + 1 || z == r.z1() - 1;
                            assert!(against, "furniture stands against a wall");
                        }
                    }
                }
            }
        }
        assert!(lit > 0 && furniture > 0, "{lit} chandeliers, {furniture} pieces of furniture");
    }

    #[test]
    fn the_ground_round_it_decides_its_kind() {
        let mut w = cave_world();
        let rooms = vec![find_room(&w, (64, 19, 64))];
        assert_eq!(house_type(&w, &rooms), Kind::Wood);
        let snow = w.id_of("snow_block");
        for i in 0..w.blocks.len() {
            if w.blocks[i] != 0 {
                w.blocks[i] = snow;
            }
        }
        assert_eq!(house_type(&w, &rooms), Kind::Ice);
        let fill = |w: &mut World, name: &str| {
            let id = w.id_of(name);
            for i in 0..w.blocks.len() {
                if w.blocks[i] != 0 {
                    w.blocks[i] = id;
                }
            }
        };
        fill(&mut w, "hardened_sand");
        assert_eq!(house_type(&w, &rooms), Kind::Desert);
        fill(&mut w, "mud");
        assert_eq!(house_type(&w, &rooms), Kind::Jungle, "mud: the Jungle (ties go to the first)");
    }

    /// The cave world with its stone all `fill`, and the first cabin built in
    /// it at (64, 40, 64) with seeds from `seed` on.
    fn biome_cabin(fill: &str, seed: u64, cx: &mut Context) -> (World, Vec<Room>, Ids) {
        for seed in seed..seed + 200 {
            let mut w = cave_world();
            let id = w.id_of(fill);
            for i in 0..w.blocks.len() {
                if w.blocks[i] != 0 {
                    w.blocks[i] = id;
                }
            }
            let ids = Ids::new(&w);
            if let Some(rooms) = try_cabin(&mut w, &mut Rng::new(seed), &ids, cx, (64, 40, 64), &layers(), &[], &[]) {
                return (w, rooms, ids);
            }
        }
        panic!("no cabin in {fill}");
    }

    /// How many of `cells` hold each of `names`.
    fn tally(w: &World, cells: &[(i32, i32, i32)], names: &[&str]) -> Vec<usize> {
        names.iter().map(|n| cells.iter().filter(|&&(x, y, z)| w.get(x, y, z) == w.id_of(n)).count()).collect()
    }

    fn all_cells(rooms: &[Room]) -> Vec<(i32, i32, i32)> {
        rooms.iter().flat_map(|r| (r.x0..=r.x1()).flat_map(move |x| (r.z0..=r.z1()).flat_map(move |z| (r.y0..=r.ceiling()).map(move |y| (x, y, z))))).collect()
    }

    /// The cabin's chest decoration, and what's in its cell.
    fn the_chest(w: &World) -> (i32, u16) {
        let chests: Vec<_> = w.decorations.iter().filter(|d| d.kind == "chest").collect();
        assert_eq!(chests.len(), 1, "one chest");
        let (x, y, z) = chests[0].pos;
        assert!(w.is_solid(x, y - 1, z), "the chest stands on something");
        (chests[0].style, w.get(x, y, z))
    }

    /// Whatever hangs (stalactites, vines) hangs from something solid or more of it.
    fn hangs_from(w: &World, cells: &[(i32, i32, i32)], kinds: &[u16], from: &[u16]) -> usize {
        let mut n = 0;
        for &(x, y, z) in cells {
            if kinds.contains(&w.get(x, y, z)) {
                let mut k = 1;
                while kinds.contains(&w.get(x, y + k, z)) {
                    k += 1;
                }
                assert!(from.contains(&w.get(x, y + k, z)), "hangs at {x},{y},{z} from {}", w.get(x, y + k, z));
                n += 1;
            }
        }
        n
    }

    #[test]
    fn an_ice_cabin_in_the_snow() {
        let (w, rooms, ids) = biome_cabin("snow_block", 0, &mut Context::default());
        let frame: Vec<_> = rooms.iter().flat_map(frame_cells).collect();
        let t = tally(&w, &frame, &["boreal_wood", "ice_block", "snow_block"]);
        // Dither 0.6 then Blotches 0.6: most of the frame goes to ice, a fifth of that snow.
        assert!(t[1] + t[2] > t[0] && t[2] > 0 && t[2] < t[1], "frame: {} boreal, {} ice, {} snow", t[0], t[1], t[2]);
        let lining: Vec<_> = rooms.iter().flat_map(lining_cells).collect();
        let l = tally(&w, &lining, &["boreal_wood_wall", "snow_block"]);
        // Dither 0.85, Blotches 0.8: about 2 in 5 of the wall.
        assert!(l[1] * 100 > (l[0] + l[1]) * 15 && l[1] * 100 < (l[0] + l[1]) * 60, "walls: {} boreal wall, {} snow", l[0], l[1]);
        let cells = all_cells(&rooms);
        let icicles = hangs_from(&w, &cells, &ids.icicles, &[ids.ice]);
        assert!(icicles > 3, "icicles under the ice ({icicles})");
        assert_eq!(tally(&w, &cells, &["cobweb"])[0], 0, "no cobwebs but in a wooden cabin");
        let (style, chest) = the_chest(&w);
        assert_eq!((style, chest), (CHEST_FROZEN, w.id_of("frozen_chest")), "a Frozen Chest with the ice loot");
        // Boreal Wood furniture, platforms and door, Boreal Beams.
        let wooden = tally(&w, &cells, &["wooden_table", "work_bench", "piano", "bookcase", "wood_platform"]);
        assert!(wooden.iter().all(|&n| n == 0), "nothing of plain wood: {wooden:?}");
        assert!(w.blocks.iter().any(|&b| b == w.id_of("boreal_wood_platform")) && w.blocks.iter().any(|&b| b == w.id_of("boreal_wood_door")));
    }

    #[test]
    fn a_desert_cabin_under_the_desert() {
        let mut cx = Context { bast_statue_max: 2, desert_deep_below: 0, ..Default::default() };
        let (w, rooms, ids) = biome_cabin("hardened_sand", 0, &mut cx);
        let frame: Vec<_> = rooms.iter().flat_map(frame_cells).collect();
        let t = tally(&w, &frame, &["sandstone", "hardened_sand"]);
        // Dither 0.8, Blotches 0.2, half of that: a little hardened sand.
        assert!(t[1] > 0 && t[1] * 3 < t[0], "frame: {} sandstone, {} hardened sand", t[0], t[1]);
        let lining: Vec<_> = rooms.iter().flat_map(lining_cells).collect();
        let l = tally(&w, &lining, &["sandstone_wall", "hardened_sand"]);
        assert!(l[0] > l[1] && l[1] > 0, "walls: {} sandstone wall, {} hardened sand", l[0], l[1]);
        let cells = all_cells(&rooms);
        let stalactites = hangs_from(&w, &cells, &ids.sand_stalactites, &[ids.sandstone, ids.hardened_sand]);
        assert!(stalactites > 3, "stalactites under the sandstone ({stalactites})");
        assert_eq!(the_chest(&w), (CHEST_SANDSTONE, w.id_of("sandstone_chest")), "a Sandstone Chest, the upper desert's loot");
        // The first desert cabins: a Bast Statue and an Extractinator.
        let extras = tally(&w, &all_cells(&rooms).into_iter().chain(rooms.iter().flat_map(|r| (r.x0..=r.x1()).flat_map(move |x| (r.z0..=r.z1()).map(move |z| (x, r.ceiling() + 1, z))))).collect::<Vec<_>>(), &["bast_statue", "extractinator"]);
        assert_eq!(extras, vec![1, 1], "a Bast Statue and an Extractinator");
        assert_eq!((cx.bast_statues, cx.extractinators), (1, 1));
        // The world's Bast Statues run out.
        let mut full = Context { bast_statues: 2, bast_statue_max: 2, extractinators: 9, ..Default::default() };
        let (w, rooms, _) = biome_cabin("hardened_sand", 0, &mut full);
        assert_eq!(tally(&w, &all_cells(&rooms), &["bast_statue", "extractinator"]), vec![0, 0]);
        // Deep in the desert, the Sandstone Chest holds the deeper loot.
        let (w, _, _) = biome_cabin("hardened_sand", 0, &mut Context { desert_deep_below: 90, ..Default::default() });
        assert_eq!(the_chest(&w).0, CHEST_SANDSTONE_DEEP);
    }

    #[test]
    fn a_jungle_cabin_in_the_mud() {
        let mut cx = Context::default();
        let (w, rooms, ids) = biome_cabin("mud", 0, &mut cx);
        let frame: Vec<_> = rooms.iter().flat_map(frame_cells).collect();
        let t = tally(&w, &frame, &["rich_mahogany", "jungle_grass", "mud"]);
        assert!(t[1] + t[2] > t[0] && t[2] > 0 && t[2] < t[1], "frame: {} mahogany, {} jungle grass, {} mud", t[0], t[1], t[2]);
        let lining: Vec<_> = rooms.iter().flat_map(lining_cells).collect();
        let l = tally(&w, &lining, &["rich_mahogany_wall", "mud"]);
        assert!(l[0] > l[1] && l[1] > 0, "walls: {} mahogany wall, {} jungle wall", l[0], l[1]);
        let cells = all_cells(&rooms);
        let vines = hangs_from(&w, &cells, &[ids.jungle_vines], &[ids.jungle_grass]);
        assert!(vines > 6, "jungle vines down from the grass ({vines})");
        assert_eq!(the_chest(&w), (CHEST_GOLD, w.id_of("rich_mahogany_chest")), "a Rich Mahogany Chest, an underground chest's loot");
        assert_eq!(tally(&w, &cells, &["sharpening_station"])[0], 1, "the first jungle cabins' Sharpening Station");
        assert_eq!(cx.sharpeners, 1);
    }

    #[test]
    fn cabins_keep_clear_of_chests_lava_and_each_other() {
        let ids = Ids::new(&cave_world());
        let mut w = cave_world();
        assert!(try_cabin(&mut w, &mut Rng::new(3), &ids, &mut Context::default(), (64, 40, 64), &layers(), &[], &[(70, 30, 70)]).is_none(), "a chest within 17 blocks");
        let mut w = cave_world();
        let i = w.idx(57, 20, 57);
        w.liquid[i] = crate::world::liq_pack(LIQ_LAVA, crate::world::LIQ_MAX);
        assert!(try_cabin(&mut w, &mut Rng::new(3), &ids, &mut Context::default(), (64, 40, 64), &layers(), &[], &[]).is_none(), "lava in the room");
        let mut w = cave_world();
        let first = try_cabin(&mut w, &mut Rng::new(3), &ids, &mut Context::default(), (64, 40, 64), &layers(), &[], &[]).expect("a cabin");
        assert!(try_cabin(&mut w, &mut Rng::new(4), &ids, &mut Context::default(), (66, 40, 66), &layers(), &[first], &[]).is_none(), "not on top of another");
    }
}
