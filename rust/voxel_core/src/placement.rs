//! Terraria's placement passes (its Statues, Pots, Piles, Dye Plants,
//! ShellPiles, CactusPalmTreesAndCoral, Seaweed and Speleothems passes), in
//! 3D. Terraria's tiles are 2/3 of a block here.
//!
//! - **Statues** (Statues): 2 of each of its 73 statues (GenVars.statueList:
//!   the Armor to the Piranha Statue, the Mushroom Statue, the Shark, the
//!   critters', the Wall Creeper to the Blood Zombie, the Seagull and
//!   Dragonfly, the Heart and Star Statues twice) in a small world, here that
//!   many in each 640 x 640 blocks, as the cabins count; on cave floors from
//!   a third of the way down to the rock layer to 100 tiles over the
//!   Underworld, each in turn. (Its statues with traps aren't wired: statues
//!   don't spawn on a signal yet.)
//! - **Pots** (PotsGraveyardsAndBoulderPiles): on cave floors, the first
//!   floor under a spot (in the last 7% of them a spot in the Underworld,
//!   in the 18% before a spot at the surface), styled by what they stand on
//!   (PlacePot's style): snow and ice the ice pots, jungle grass the
//!   jungle's, the Dungeon's brick the Dungeon's, the Corruption's and the
//!   Crimson's ground theirs, Lihzahrd brick, marble and the underground
//!   desert theirs (Terraria's desert walls: here its sand, hardened sand,
//!   sandstone and fossil under the surface); in the Underworld its pots;
//!   else the four plain ones.
//! - **Piles** (Piles): big piles (3 x 2 tiles) and small ones (1 x 1 and 2
//!   x 1) on the floors, by what they stand on: under the surface, a big
//!   pile of bones, rocks (1 in 75 of those the Enchanted Sword in stone),
//!   relics or coins (those dropping coins: Check3x2), 1 in 5 on stone, dirt
//!   or moss a cave's ruins; small rocks, clods, bones, bloody bones and
//!   debris, a pile of rocks, bones, coins or gems. On snow and ice, ice; on
//!   jungle grass, the jungle's; on ash and hellstone, 2 in 3 the
//!   Underworld's; on mushroom grass, mushrooms; on Lihzahrd brick, the
//!   Temple's; on the desert's sand and sandstone, the desert's; on granite
//!   and marble, theirs; in the Dungeon (1 in 3 of them not at all), the
//!   Underworld, on wood, ebonstone and crimstone, bones. Each big pile of
//!   bones has 1-4 small bones within 10 tiles. On the surface, a big pile of
//!   rocks (grassy rocks by grass, sandy piles on sand), small rocks and
//!   piles (grassy by grass). Terraria's counts (0.06, 0.01, 0.03 and 0.0035
//!   big piles and 0.6, 0.02 and 0.15 small ones a tile of its width) are a
//!   line's; here PILE_SHARE of that for each column.
//! - **Dye Plants** (plantDye): each no nearer another than 90 tiles. On the
//!   surface: on grass a Yellow Marigold (1 in 4 Blue Berries), on jungle
//!   grass a Sky Blue Flower or Blue Berries, on sand deep under water a Sky
//!   Blue Flower, on a cactus a Pink Prickly Pear. Underground: on jungle
//!   grass a Sky Blue Flower (half), Teal or Green Mushroom; on dirt, stone
//!   and mud a Teal or Green Mushroom; on anything else deep under water Lime
//!   Kelp; under dirt an Orange Bloodroot hanging.
//! - **Shell piles** (ShellPiles): half the time on each side, a few mounds
//!   of Shell Pile (sand round them, hardened sand under) at the water's
//!   edge on the beach; here round the island's coast.
//! - **Sea shells, coral and sea oats** (CactusPalmTreesAndCoral): on the
//!   beach's sand, some columns (1 in 3-12) a Seashell or Starfish (a
//!   Lightning Whelk or Tulip Shell 1 in 10, a Junonia 1 in 50), under 3 of
//!   water half the time coral (worldgen's corals); the rest sea oats.
//! - **Seaweed** (GrowCheckSeaweed): from sand under the water, 2 in 3 of it,
//!   a stalk growing a cell at a time while it's under 17 - rand(20) tall
//!   and 3 deep in water, at most 30 within 4 tiles.
//! - **Speleothems** (PlaceTight): 1 in 5 of the open cells under the
//!   surface (here 1 in SPELEOTHEM_ONE_IN): under stone, moss and the evils' stone a stone stalactite,
//!   under snow and ice an icicle, under hive a honey drip; on stone a
//!   stalagmite, on hive a honey drip (half of them small). Over the surface,
//!   icicles under snow and ice and both on the evils' stone. (The desert's,
//!   granite's, marble's and the spider caves' come with them.)

use crate::dungeon::depth_y;
use crate::world::{World, LIQ_LAVA, LIQ_MAX, LIQ_SHIMMER, LIQ_WATER, RENDER_CUBE};
use crate::worldgen::{Coast, Layers, Rng};

type P = (i32, i32, i32);

/// A Terraria tile, in blocks.
const TILE: f64 = 2.0 / 3.0;

/// Terraria's per-tile pile counts are along its world's width; here this
/// share of that for each column of the world (about one pile in 60 cells of
/// cave floor, Terraria's one in 20 of its floor tiles made rarer as
/// SPELEOTHEM_ONE_IN is).
const PILE_SHARE: f64 = 0.3;

/// Terraria's speleothems go in 1 in 5 open cells by their rock; here 3 times
/// rarer (a cave in 3D shows far more of its ceiling and floor at once than
/// a line of tiles does).
const SPELEOTHEM_ONE_IN: i32 = 15;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Ground {
    Other,
    Stone,
    Moss,
    Dirt,
    Grass,
    Mud,
    Snow,
    Jungle,
    Dungeon,
    Corrupt,
    Crimson,
    Lihzahrd,
    Marble,
    Granite,
    Sand,
    Desert,
    Ash,
    Mushroom,
    Hive,
    Wood,
    Cactus,
}

struct Ids {
    ground: Vec<Ground>,
    plants: Vec<bool>,
    pots: [u16; 11],
    statues: Vec<u16>,
    large: Vec<(&'static str, u16)>,
    small: Vec<(&'static str, u16)>,
    sword: u16,
    speleothems: [u16; 8],
    dye: [u16; 8],
    shells: [u16; 5],
    sea_oats: [u16; 3],
    coral: u16,
    shell_pile: u16,
    sand: u16,
    hardened_sand: u16,
    seaweed: u16,
    dirt: u16,
    /// Ebonstone and crimstone (Terraria's 25 and 203).
    evil_stone: [u16; 2],
    /// Ebonsand and crimsand (112, 234).
    evil_sand: [u16; 2],
}

/// The statues, in Terraria's statueList order.
const STATUES: [&str; 73] = [
    "armor_statue", "angel_statue", "star_statue", "sword_statue", "slime_statue", "goblin_statue", "shield_statue",
    "bat_statue", "fish_statue", "bunny_statue", "skeleton_statue", "reaper_statue", "woman_statue", "imp_statue",
    "gargoyle_statue", "gloom_statue", "hornet_statue", "bomb_statue", "crab_statue", "hammer_statue", "potion_statue",
    "spear_statue", "cross_statue", "jellyfish_statue", "bow_statue", "boomerang_statue", "boot_statue", "chest_statue",
    "bird_statue", "axe_statue", "corrupt_statue", "tree_statue", "anvil_statue", "pickaxe_statue", "mushroom_statue",
    "eyeball_statue", "pillar_statue", "heart_statue", "pot_statue", "sunflower_statue", "king_statue", "queen_statue",
    "piranha_statue", "shark_statue", "wall_creeper_statue", "unicorn_statue", "drippler_statue", "wraith_statue",
    "undead_viking_statue", "medusa_statue", "harpy_statue", "pigron_statue", "hoplite_statue", "granite_golem_statue",
    "blood_zombie_statue", "squirrel_statue", "butterfly_statue", "worm_statue", "firefly_statue", "scorpion_statue",
    "snail_statue", "grasshopper_statue", "mouse_statue", "duck_statue", "penguin_statue", "frog_statue",
    "buggy_statue", "seagull_statue", "dragonfly_statue", "bone_skeleton_statue", "zombie_arm_statue",
    "heart_statue", "star_statue",
];

impl Ids {
    fn new(w: &World) -> Ids {
        let id = |n: &str| w.id_of(n);
        let mut ground = vec![Ground::Other; w.defs.len()];
        let mut set = |names: &[&str], g: Ground| {
            for n in names {
                let i = w.id_of(n) as usize;
                if i != 0 {
                    ground[i] = g;
                }
            }
        };
        set(&["stone"], Ground::Stone);
        set(&["green_moss", "brown_moss", "red_moss", "blue_moss", "purple_moss", "lava_moss", "krypton_moss", "xenon_moss", "argon_moss",
            "violet_moss"], Ground::Moss);
        set(&["dirt"], Ground::Dirt);
        set(&["grass"], Ground::Grass);
        set(&["mud"], Ground::Mud);
        set(&["snow_block", "ice_block", "thin_ice"], Ground::Snow);
        set(&["jungle_grass"], Ground::Jungle);
        set(&["blue_brick", "green_brick", "pink_brick", "cracked_blue_brick", "cracked_green_brick", "cracked_pink_brick"], Ground::Dungeon);
        set(&["ebonstone", "corrupt_grass", "ebonsand", "demonite_ore"], Ground::Corrupt);
        set(&["crimstone", "crimson_grass", "crimsand", "crimtane_ore"], Ground::Crimson);
        set(&["lihzahrd_brick"], Ground::Lihzahrd);
        set(&["marble"], Ground::Marble);
        set(&["granite"], Ground::Granite);
        set(&["sand"], Ground::Sand);
        set(&["hardened_sand", "sandstone", "desert_fossil"], Ground::Desert);
        set(&["ash", "hellstone"], Ground::Ash);
        set(&["mushroom_grass"], Ground::Mushroom);
        set(&["hive"], Ground::Hive);
        set(&["cactus"], Ground::Cactus);
        for (i, d) in w.defs.iter().enumerate() {
            if d.name == "wood" || d.name.ends_with("_platform") {
                ground[i] = Ground::Wood;
            }
        }
        // What a dye plant may take the place of (plantDye: grass plants,
        // cobwebs, jungle plants, Long Moss).
        let mut plants = vec![false; w.defs.len()];
        for (i, d) in w.defs.iter().enumerate() {
            let n = d.name.as_str();
            plants[i] = ["tall_grass", "taller_grass", "jungle_plants", "cobweb"].iter().any(|p| n == *p || n.starts_with(&format!("{p}_")))
                || n.starts_with("long_moss_");
        }
        let names = |list: &[&'static str]| list.iter().map(|n| (*n, id(n))).collect::<Vec<_>>();
        Ids {
            ground,
            plants,
            pots: ["pot", "ice_pot", "jungle_pot", "dungeon_pot", "underworld_pot", "corruption_pot", "crimson_pot", "lihzahrd_pot",
                "marble_pot", "desert_pot", "spider_pot"].map(id),
            statues: STATUES.iter().map(|n| id(n)).collect(),
            large: names(&["bone_pile", "large_rocks", "large_relic_rocks", "copper_rock_pile", "silver_rock_pile", "gold_rock_pile",
                "ice_pile", "mushroom_pile", "jungle_pile", "ash_pile", "grassy_rocks", "lihzahrd_pile", "cave_ruins", "desert_pile",
                "granite_pile", "marble_pile", "sand_pile"]),
            small: names(&["small_rocks", "dirt_clods", "small_bones", "bloody_bones", "small_debris", "small_ice_rocks",
                "small_granite_rocks", "small_marble_rocks", "small_desert_rocks", "rock_pile", "bone_heap", "bloody_bone_heap",
                "copper_coin_stash", "silver_coin_stash", "gold_coin_stash", "amethyst_pile", "topaz_pile", "sapphire_pile",
                "emerald_pile", "ruby_pile", "diamond_pile", "ice_rock_pile", "grassy_rock_pile", "granite_rock_pile",
                "marble_rock_pile", "desert_rock_pile"]),
            sword: id("sword_in_stone"),
            speleothems: ["stone_stalactite", "small_stone_stalactite", "stone_stalagmite", "small_stone_stalagmite", "icicle",
                "small_icicle", "honey_stalactite", "honey_stalagmite"].map(id),
            dye: ["teal_mushroom", "green_mushroom", "sky_blue_flower", "yellow_marigold", "blue_berries", "lime_kelp",
                "pink_prickly_pear", "orange_bloodroot"].map(id),
            shells: ["seashell", "starfish", "lightning_whelk_shell", "tulip_shell", "junonia_shell"].map(id),
            sea_oats: ["sea_oats", "sea_oats_grown", "sea_oats_tall"].map(id),
            coral: id("coral"),
            shell_pile: id("shell_pile"),
            sand: id("sand"),
            hardened_sand: id("hardened_sand"),
            seaweed: id("seaweed"),
            dirt: id("dirt"),
            evil_stone: [id("ebonstone"), id("crimstone")],
            evil_sand: [id("ebonsand"), id("crimsand")],
        }
    }

    fn ground(&self, b: u16) -> Ground {
        self.ground.get(b as usize).copied().unwrap_or(Ground::Other)
    }

    fn large(&self, name: &str) -> u16 {
        self.large.iter().find(|(n, _)| *n == name).map_or(0, |e| e.1)
    }

    fn small(&self, name: &str) -> u16 {
        self.small.iter().find(|(n, _)| *n == name).map_or(0, |e| e.1)
    }
}

/// Terraria's tiles to blocks here, rounded.
fn b(tiles: f64) -> i32 {
    (tiles * TILE).round() as i32
}

/// A floor here: open (no lava or shimmer in it) over a solid cube.
fn floor_at(w: &World, (x, y, z): P) -> bool {
    if !w.in_bounds(x, y, z) || y < 1 || w.get(x, y, z) != 0 {
        return false;
    }
    let under = w.get(x, y - 1, z);
    let (t, a) = w.liquid_at(x, y, z);
    w.is_solid(x, y - 1, z) && w.def(under).render == RENDER_CUBE && !(a > 0 && (t == LIQ_LAVA || t == LIQ_SHIMMER))
}

/// Down from an open cell to the floor under it.
fn down_to_floor(w: &World, (x, mut y, z): P) -> Option<P> {
    if !w.in_bounds(x, y, z) || w.get(x, y, z) != 0 {
        return None;
    }
    while y > 1 && w.get(x, y - 1, z) == 0 {
        y -= 1;
    }
    floor_at(w, (x, y, z)).then_some((x, y, z))
}

/// Under the ground (a solid block somewhere over it), not out on the surface.
fn covered(w: &World, (x, y, z): P) -> bool {
    w.surface_y(x, z) > y
}

fn put(w: &mut World, (x, y, z): P, id: u16) {
    if id != 0 && w.in_bounds(x, y, z) {
        let i = w.idx(x, y, z);
        w.blocks[i] = id;
    }
}

/// The world's area in Terraria small worlds' worth (640 x 640 blocks each,
/// as the cabins count).
fn worlds(w: &World) -> f64 {
    (w.sx as f64 * w.sz as f64) / (640.0 * 640.0)
}

/// Terraria's Statues pass: each statue in turn, twice over in a small world.
pub fn statues(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast) -> usize {
    let ids = Ids::new(w);
    let list: Vec<u16> = ids.statues.iter().copied().filter(|&s| s != 0).collect();
    if list.is_empty() {
        return 0;
    }
    // From (2 worldSurface + rockLayer) / 3 to 300 tiles over the bottom
    // (100 over the Underworld).
    let (y_hi, y_lo) = (depth_y(l, 130.0 / 3.0), depth_y(l, 610.0));
    let n = (STATUES.len() as f64 * 2.0 * worlds(w)).round() as usize;
    let (mut placed, mut k) = (0, 0);
    for _ in 0..n {
        let s = list[k % list.len()];
        for _ in 0..10_000 {
            let p = (rng.range(13, w.sx - 13), rng.range(y_lo, y_hi), rng.range(13, w.sz - 13));
            if coast.inland(p.0, p.2) < coast.ocean.width {
                continue;
            }
            let Some(f) = down_to_floor(w, p) else { continue };
            if f.1 < y_lo || w.get(f.0, f.1 + 1, f.2) != 0 || w.liquid_at(f.0, f.1, f.2).1 > 0 {
                continue;
            }
            put(w, f, s);
            w.decorations.push(crate::world::Decoration { kind: "rotation".into(), pos: f, style: rng.range(0, 4) });
            placed += 1;
            k += 1;
            break;
        }
    }
    placed
}

/// The pot for what it stands on (PlacePot's style), or the plain one.
fn pot_for(ids: &Ids, g: Ground, y: i32, l: &Layers) -> u16 {
    let [plain, ice, jungle, dungeon, hell, corrupt, crimson, lihzahrd, marble, desert, _] = ids.pots;
    let pick = |p: u16| if p != 0 { p } else { plain };
    if y < l.underworld_top {
        return pick(hell);
    }
    match g {
        Ground::Snow => pick(ice),
        Ground::Jungle => pick(jungle),
        Ground::Dungeon => pick(dungeon),
        Ground::Corrupt => pick(corrupt),
        Ground::Crimson => pick(crimson),
        Ground::Lihzahrd => pick(lihzahrd),
        Ground::Marble => pick(marble),
        Ground::Sand | Ground::Desert if y < l.surface_base => pick(desert),
        _ => plain,
    }
}

/// Terraria's pots: `count` of them on cave floors.
pub fn pots(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast, count: usize) -> usize {
    let ids = Ids::new(w);
    if ids.pots[0] == 0 {
        return 0;
    }
    let mut placed = 0;
    for i in 0..count {
        let f = i as f64 / count as f64;
        for _ in 0..1000 {
            let (x, z) = (rng.range(10, w.sx - 10), rng.range(10, w.sz - 10));
            if coast.inland(x, z) < coast.ocean.width {
                continue;
            }
            let y = if f > 0.93 {
                rng.range(3, l.underworld_top)
            } else if f > 0.75 {
                l.surface_base
            } else {
                rng.range(l.underworld_top / 2, l.surface_base + 20)
            };
            // Down to the first open floor under the spot.
            let mut y = y.min(w.sy - 2);
            while y > 2 && !(w.get(x, y, z) == 0 && w.is_solid(x, y - 1, z)) {
                y -= 1;
            }
            let p = (x, y, z);
            if !floor_at(w, p) || !covered(w, p) {
                continue;
            }
            let pot = pot_for(&ids, ids.ground(w.get(x, y - 1, z)), y, l);
            put(w, p, pot);
            placed += 1;
            break;
        }
    }
    placed
}

/// A big pile's kind for what it stands on (`on`), under the surface (Piles'
/// first two passes), or None.
fn large_pile(ids: &Ids, rng: &mut Rng, on: u16, deep: bool) -> Option<&'static str> {
    let g = ids.ground(on);
    // 0-21, 16-22 rolled again once: bones (0-6), rocks (7-12), relics
    // (13-15), coins (16-21).
    let mut s = rng.range(0, 22);
    if (16..=22).contains(&s) {
        s = rng.range(0, 22);
    }
    let mut kind = match s {
        0..=6 => "bone_pile",
        7..=12 => "large_rocks",
        13..=15 => "large_relic_rocks",
        16..=17 => "copper_rock_pile",
        18..=19 => "silver_rock_pile",
        _ => "gold_rock_pile",
    };
    if matches!(g, Ground::Dirt | Ground::Stone | Ground::Moss) && rng.range(0, 5) == 0 {
        kind = "cave_ruins";
    }
    if deep || matches!(g, Ground::Dungeon | Ground::Wood) || ids.evil_stone.contains(&on) {
        kind = "bone_pile";
    }
    kind = match g {
        Ground::Snow => "ice_pile",
        Ground::Jungle => "jungle_pile",
        Ground::Ash if rng.range(0, 3) < 2 => "ash_pile",
        Ground::Lihzahrd => "lihzahrd_pile",
        Ground::Mushroom => "mushroom_pile",
        Ground::Desert => "desert_pile",
        Ground::Granite => "granite_pile",
        Ground::Marble => "marble_pile",
        _ => kind,
    };
    (ids.large(kind) != 0).then_some(kind)
}

/// Small piles 1 x 1 by Terraria's style: rocks, clods, bones, bloody bones,
/// debris.
fn small_one(s: i32) -> &'static str {
    match s {
        0..=5 => "small_rocks",
        6..=11 => "dirt_clods",
        12..=19 => "small_bones",
        20..=27 => "bloody_bones",
        _ => "small_debris",
    }
}

/// Small piles 2 x 1 by Terraria's style.
fn small_two(s: i32) -> &'static str {
    match s {
        0..=5 => "rock_pile",
        6..=11 => "bone_heap",
        12..=15 => "bloody_bone_heap",
        16 => "copper_coin_stash",
        17 => "silver_coin_stash",
        18 => "gold_coin_stash",
        19 => "amethyst_pile",
        20 => "topaz_pile",
        21 => "sapphire_pile",
        22 => "emerald_pile",
        23 => "ruby_pile",
        _ => "diamond_pile",
    }
}

/// A small pile's kind for what it stands on (`on`), under the surface
/// (Piles' fifth pass), with its Terraria style and whether it's 2 x 1.
fn small_pile(ids: &Ids, rng: &mut Rng, on: u16, deep: bool, wet: bool) -> (&'static str, i32, bool) {
    let g = ids.ground(on);
    let wide = rng.range(0, 2) == 1;
    // 1 x 1: 0-35 (28-35 rolled again); 2 x 1: 0-24 (16-24 rolled again).
    let mut s = if wide { rng.range(0, 25) } else { rng.range(0, 36) };
    if !wide && (28..=35).contains(&s) {
        s = rng.range(0, 36);
    }
    if wide && (16..=24).contains(&s) {
        s = rng.range(0, 25);
    }
    if deep {
        s = if wide { rng.range(6, 16) } else { rng.range(12, 28) };
    }
    if g == Ground::Wood || ids.evil_stone.contains(&on) {
        if !wide && s < 12 {
            s += 12;
        }
        if wide && s < 6 {
            s += 6;
        }
        if wide && s >= 17 {
            s -= 10;
        }
    }
    let kind = match g {
        Ground::Snow if !wide && s < 12 => "small_ice_rocks",
        Ground::Snow if wide && (s < 6 || s >= 20) => "ice_rock_pile",
        Ground::Sand | Ground::Desert if !wet => if wide { "desert_rock_pile" } else { "small_desert_rocks" },
        Ground::Granite => if wide { "granite_rock_pile" } else { "small_granite_rocks" },
        Ground::Marble => if wide { "marble_rock_pile" } else { "small_marble_rocks" },
        _ if wide => small_two(s),
        _ => small_one(s),
    };
    (kind, s, wide)
}

/// Bones round a big pile of bones: 1-4 small piles (styles 12-35: bones,
/// bloody bones, debris) within 10 tiles, from up to 5 over it.
fn bones_round(w: &mut World, rng: &mut Rng, ids: &Ids, (x, y, z): P) {
    for _ in 0..rng.range(1, 5) {
        let q = (x + rng.range(-b(10.0), b(10.0) + 1), y + rng.range(0, b(5.0) + 1), z + rng.range(-b(10.0), b(10.0) + 1));
        let kind = small_one(rng.range(12, 36));
        if let Some(f) = down_to_floor(w, q) {
            put(w, f, ids.small(kind));
        }
    }
}

/// Terraria's Piles pass.
pub fn piles(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast) -> (usize, usize) {
    let ids = Ids::new(w);
    let cols = w.sx as f64 * w.sz as f64;
    let ocean = |x: i32, z: i32| coast.inland(x, z) < coast.ocean.width;
    let (mut big, mut small) = (0, 0);
    // Under the surface and in the Underworld: Terraria's 0.06 and 0.01 big
    // piles and 0.6 small ones a tile of its width.
    let under = (l.underworld_top + 2, l.surface_base - 2);
    for (share, lo, hi, large) in [(0.06, under.0, under.1, true), (0.01, 2, l.underworld_top, true), (0.6, 2, under.1, false)] {
        let n = (share * PILE_SHARE * cols) as usize;
        for _ in 0..n {
            let p = (rng.range(13, w.sx - 13), rng.range(lo, hi), rng.range(13, w.sz - 13));
            if ocean(p.0, p.2) {
                continue;
            }
            let Some(f) = down_to_floor(w, p) else { continue };
            if !covered(w, f) {
                continue;
            }
            let on = w.get(f.0, f.1 - 1, f.2);
            let deep = f.1 < l.underworld_top;
            // The Dungeon: no small piles on its brick; 2 in 3 of its big ones
            // go.
            if ids.ground(on) == Ground::Dungeon && (!large || rng.range(0, 3) != 0) {
                continue;
            }
            if large {
                let Some(kind) = large_pile(&ids, rng, on, deep) else { continue };
                let mut id = ids.large(kind);
                // 1 in 75 piles of rocks the Enchanted Sword in stone.
                if (kind == "large_rocks" || kind == "large_relic_rocks") && rng.range(0, 75) == 0 && ids.sword != 0 {
                    id = ids.sword;
                }
                put(w, f, id);
                big += 1;
                if kind == "bone_pile" {
                    bones_round(w, rng, &ids, f);
                }
            } else {
                let wet = w.liquid_at(f.0, f.1, f.2).1 > 0;
                let (kind, s, wide) = small_pile(&ids, rng, on, deep, wet);
                put(w, f, ids.small(kind));
                small += 1;
                if wide && (6..=15).contains(&s) {
                    bones_round(w, rng, &ids, f);
                }
            }
        }
    }
    // On the surface: 0.03 + 0.0035 big piles, 0.02 + 0.15 small ones.
    for (share, large) in [(0.0335, true), (0.17, false)] {
        let n = (share * PILE_SHARE * cols) as usize;
        for _ in 0..n {
            let (x, z) = (rng.range(13, w.sx - 13), rng.range(13, w.sz - 13));
            if ocean(x, z) {
                continue;
            }
            let p = (x, w.surface_y(x, z) + 1, z);
            if !floor_at(w, p) || w.liquid_at(p.0, p.1, p.2).1 > 0 {
                continue;
            }
            let on = w.get(x, p.1 - 1, z);
            let g = ids.ground(on);
            if g == Ground::Dungeon || g == Ground::Wood || ids.evil_stone.contains(&on) || ids.evil_sand.contains(&on) {
                continue;
            }
            let grassy = g == Ground::Grass || [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|&(dx, dz)| w.get(x + dx, p.1 - 1, z + dz) != 0
                && ids.ground(w.get(x + dx, p.1 - 1, z + dz)) == Ground::Grass);
            let id = if large {
                let kind = match g {
                    Ground::Snow => "ice_pile",
                    Ground::Sand => "sand_pile",
                    _ if grassy => "grassy_rocks",
                    _ => "large_rocks",
                };
                ids.large(kind)
            } else {
                // 1 x 1: rocks or clods (0-10); 2 x 1: rocks (0-4).
                let wide = rng.range(0, 2) == 1;
                let kind = match g {
                    Ground::Snow => if wide { "ice_rock_pile" } else { "small_ice_rocks" },
                    Ground::Sand | Ground::Desert => if wide { "desert_rock_pile" } else { "small_desert_rocks" },
                    Ground::Grass if wide => "grassy_rock_pile",
                    _ if wide => "rock_pile",
                    _ => small_one(rng.range(0, 11)),
                };
                ids.small(kind)
            };
            if id == 0 {
                continue;
            }
            put(w, p, id);
            if large {
                big += 1;
            } else {
                small += 1;
            }
        }
    }
    (big, small)
}

/// Terraria's Dye Plants pass: a try for each tile of its width, each no
/// nearer another than 90 tiles.
pub fn dye_plants(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast) -> usize {
    let ids = Ids::new(w);
    let [teal, green, sky, marigold, berries, kelp, pear, bloodroot] = ids.dye;
    let apart = b(90.0);
    let mut placed: Vec<P> = Vec::new();
    let tries = (4200.0 * worlds(w)) as usize;
    let deep_water = |w: &World, (x, y, z): P| (0..2).all(|k| w.liquid_at(x, y + k, z) == (LIQ_WATER, LIQ_MAX));
    for _ in 0..tries {
        let (x, z) = (rng.range(b(100.0), w.sx - b(100.0)), rng.range(b(100.0), w.sz - b(100.0)));
        let y = rng.range(l.underworld_top + 1, w.surface_y(x, z) + 2);
        let up = rng.range(0, 2) == 0;
        // The ground under the spot (a plant on it), or for an Orange
        // Bloodroot a dirt ceiling over it.
        let spot = if up && y < l.surface_base {
            let mut c = y;
            while c < w.sy - 1 && w.get(x, c + 1, z) == 0 {
                c += 1;
            }
            if w.get(x, c, z) != 0 || w.get(x, c + 1, z) != ids.dirt {
                continue;
            }
            (x, c, z)
        } else {
            let mut c = y;
            while c > 1 && (w.get(x, c - 1, z) == 0 || ids.plants[w.get(x, c - 1, z) as usize]) {
                c -= 1;
            }
            let here = w.get(x, c, z);
            if (here != 0 && !ids.plants[here as usize]) || (!w.is_solid(x, c - 1, z) && ids.ground(w.get(x, c - 1, z)) != Ground::Cactus) {
                continue;
            }
            (x, c, z)
        };
        if placed.iter().any(|q| (q.0 - spot.0).abs() < apart && (q.1 - spot.1).abs() < apart && (q.2 - spot.2).abs() < apart) {
            continue;
        }
        let (sx_, sy_, sz_) = spot;
        let (t, a) = w.liquid_at(sx_, sy_, sz_);
        if a > 0 && t != LIQ_WATER {
            continue;
        }
        let surface = sy_ >= l.surface_base;
        let plant = if up && !surface {
            bloodroot
        } else {
            let g = ids.ground(w.get(sx_, sy_ - 1, sz_));
            if surface {
                match g {
                    Ground::Grass => if rng.range(0, 4) == 0 { berries } else { marigold },
                    Ground::Jungle => if rng.range(0, 2) == 0 { sky } else { berries },
                    Ground::Sand if deep_water(w, spot) && coast.inland(sx_, sz_) < coast.ocean.width => sky,
                    Ground::Cactus => pear,
                    _ => continue,
                }
            } else {
                match g {
                    Ground::Jungle => match rng.range(0, 4) { 0 | 1 => sky, 2 => teal, _ => green },
                    Ground::Dirt | Ground::Stone | Ground::Mud => if rng.range(0, 2) == 0 { teal } else { green },
                    _ if deep_water(w, spot) => kelp,
                    _ => continue,
                }
            }
        };
        if plant == 0 {
            continue;
        }
        put(w, spot, plant);
        placed.push(spot);
    }
    placed.len()
}

/// Terraria's Speleothems: 1 in 5 open cells under a ceiling or on a floor of
/// their kind.
pub fn speleothems(w: &mut World, rng: &mut Rng, l: &Layers) -> usize {
    let ids = Ids::new(w);
    let [tite, small_tite, mite, small_mite, icicle, small_icicle, honey_tite, honey_mite] = ids.speleothems;
    let mut n = 0;
    for z in 1..w.sz - 1 {
        for x in 1..w.sx - 1 {
            let top = w.surface_y(x, z);
            for y in 2..(top.min(w.sy - 2)) {
                let i = w.idx(x, y, z);
                if w.blocks[i] != 0 {
                    continue;
                }
                let (t, a) = w.liquid_at(x, y, z);
                if a > 0 && t == LIQ_SHIMMER {
                    continue;
                }
                let (over, under) = (w.get(x, y + 1, z), w.get(x, y - 1, z));
                let (go, gu) = (ids.ground(over), ids.ground(under));
                let hanging = w.is_solid(x, y + 1, z) && w.def(over).render == RENDER_CUBE && w.get(x, y - 1, z) == 0;
                let standing = !hanging && w.is_solid(x, y - 1, z) && w.def(under).render == RENDER_CUBE && w.get(x, y + 1, z) == 0;
                if !(hanging || standing) || rng.range(0, SPELEOTHEM_ONE_IN) != 0 {
                    continue;
                }
                let small = rng.range(0, 2) == 0;
                let surface = y >= l.surface_base;
                let id = if hanging {
                    match go {
                        Ground::Snow => if small { small_icicle } else { icicle },
                        _ if ids.evil_stone.contains(&over) => if small { small_tite } else { tite },
                        Ground::Stone | Ground::Moss if !surface => if small { small_tite } else { tite },
                        Ground::Hive if !surface => honey_tite,
                        _ => 0,
                    }
                } else {
                    match gu {
                        _ if ids.evil_stone.contains(&under) => if small { small_mite } else { mite },
                        Ground::Stone | Ground::Moss if !surface => if small { small_mite } else { mite },
                        Ground::Hive if !surface => honey_mite,
                        _ => 0,
                    }
                };
                if id != 0 {
                    w.blocks[i] = id;
                    n += 1;
                }
            }
        }
    }
    n
}

/// Terraria's ShellPile: a mound of Shell Pile at `at` on the beach, sand
/// round it and hardened sand under, sliding down a few steps.
fn shell_pile(w: &mut World, rng: &mut Rng, ids: &Ids, (x0, y0, z0): P) {
    let r = (rng.range(2, 4) + if rng.range(0, 10) == 0 { 1 } else { 0 }) as f64 * TILE;
    let (mut cx, mut cy, mut cz) = (x0 as f64, y0 as f64, z0 as f64);
    let ang = rng.unit() * std::f64::consts::TAU;
    let (mut vh, mut vy) = (rng.unit() * 0.6 - 0.3, -(rng.unit() * 0.5 + 0.5));
    for _ in 0..rng.range(3, 6) {
        let reach = (r * 4.0).ceil() as i32;
        for dx in -reach..=reach {
            for dz in -reach..=reach {
                for dy in -reach..=reach {
                    let (x, y, z) = (cx as i32 + dx, cy as i32 + dy, cz as i32 + dz);
                    let h = (((x as f64 - cx).powi(2) + (z as f64 - cz).powi(2)).sqrt()) * 0.6;
                    let d = (h * h + (y as f64 - cy).powi(2)).sqrt();
                    if !w.in_bounds(x, y, z) || d >= r * rng.range(70, 91) as f64 * 0.01 {
                        continue;
                    }
                    if y >= y0 - 1 || rng.range(0, 6) == 0 {
                        put(w, (x, y, z), ids.shell_pile);
                        for (k, fill) in [(1, ids.shell_pile), (2, ids.sand), (3, ids.hardened_sand)] {
                            if w.get(x, y - k, z) != 0 {
                                break;
                            }
                            put(w, (x, y - k, z), fill);
                        }
                    } else if w.get(x, y, z) != ids.shell_pile {
                        put(w, (x, y, z), ids.sand);
                    }
                    let i = w.idx(x, y, z);
                    w.liquid[i] = 0;
                }
            }
        }
        cx += vh * ang.cos() / TILE;
        cz += vh * ang.sin() / TILE;
        cy += vy * TILE;
        vh += rng.unit() * 0.2 - 0.1;
        vy += rng.unit() * 0.2 - 0.1;
    }
}

/// Terraria's RollRandomSeaShellStyle: a Seashell or Starfish, a Lightning
/// Whelk or Tulip Shell 1 in 10 each, a Junonia 1 in 50.
fn sea_shell(ids: &Ids, rng: &mut Rng) -> u16 {
    let mut s = rng.range(0, 2) as usize;
    if rng.range(0, 10) == 0 {
        s = 2;
    }
    if rng.range(0, 10) == 0 {
        s = 3;
    }
    if rng.range(0, 50) == 0 {
        s = 4;
    }
    ids.shells[s]
}

/// The beach: shell piles at the water's edge, sea shells and sea oats on its
/// sand and seaweed on the sea floor. Returns (shell piles, shells, oats,
/// seaweed stalks).
pub fn beach(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast) -> (usize, usize, usize, usize) {
    let ids = Ids::new(w);
    let sea = coast.ocean;
    let (mut piles, mut shells, mut oats, mut weeds) = (0, 0, 0, 0);
    // Shell piles: Terraria's two beaches, half the time each, 1 and up to 5
    // more mounds 10-125 tiles along; here a beach each 600 blocks of coast.
    if ids.shell_pile != 0 {
        let beaches = ((w.sx + w.sz) as f64 * 2.0 / 600.0).round() as usize;
        for _ in 0..beaches {
            if rng.range(0, 2) != 0 {
                continue;
            }
            let more = rng.range(2, 4);
            let mut spots = vec![0];
            for k in 0..5 {
                if rng.range(0, more) == 0 {
                    spots.push([rng.range(10, 35), rng.range(40, 65), rng.range(70, 95), rng.range(100, 125), -rng.range(10, 25)][k]);
                }
            }
            // A spot on the world's edge, and from there in toward the middle
            // to the water's edge (the first dry sand); the mounds along the
            // coast from it.
            let t = rng.range(0, 2 * (w.sx + w.sz));
            let edge = if t < w.sx { (t, 0) } else if t < 2 * w.sx { (t - w.sx, w.sz - 1) } else if t < 2 * w.sx + w.sz { (0, t - 2 * w.sx) } else { (w.sx - 1, t - 2 * w.sx - w.sz) };
            let (cx, cz) = (w.sx as f64 / 2.0, w.sz as f64 / 2.0);
            let (dx, dz) = (cx - edge.0 as f64, cz - edge.1 as f64);
            let len = (dx * dx + dz * dz).sqrt().max(1.0);
            let (ix, iz) = (dx / len, dz / len);
            for along in spots {
                let off = b(along as f64) as f64;
                let (mut x, mut z) = (edge.0 as f64 - iz * off, edge.1 as f64 + ix * off);
                let mut found = None;
                for _ in 0..(sea.width + sea.beach) as i32 + 40 {
                    let (xi, zi) = (x as i32, z as i32);
                    if w.in_bounds(xi, 0, zi) {
                        let y = w.surface_y(xi, zi);
                        if y > 0 && w.liquid_at(xi, y + 1, zi).1 == 0 && w.get(xi, y + 1, zi) == 0 {
                            if w.get(xi, y, zi) == ids.sand {
                                found = Some((xi, y + 1, zi));
                            }
                            break;
                        }
                    }
                    x += ix;
                    z += iz;
                }
                if let Some(p) = found {
                    shell_pile(w, rng, &ids, p);
                    piles += 1;
                }
            }
        }
    }
    // Shells, coral and sea oats on the beach's sand (the coral is worldgen's
    // corals, on the sea floor).
    let per_side = [rng.range(3, 13), rng.range(3, 13), rng.range(3, 13), rng.range(3, 13)];
    for z in 1..w.sz - 1 {
        for x in 1..w.sx - 1 {
            let inland = coast.inland(x, z);
            if inland >= sea.width + sea.beach {
                continue;
            }
            let y = w.surface_y(x, z);
            if y < 1 || y + 2 >= w.sy || w.get(x, y, z) != ids.sand || w.get(x, y + 1, z) != 0 {
                continue;
            }
            // Its side's 1 in 3-12, and as the 3D beach is an area, 6 times
            // rarer.
            let side = [x, w.sx - x, z, w.sz - z].iter().enumerate().min_by_key(|e| *e.1).map_or(0, |e| e.0);
            let one_in = per_side[side] * 6;
            let wet = w.liquid_at(x, y + 1, z).1 > 0;
            if rng.range(0, one_in) == 0 {
                if (2..5).all(|k| w.liquid_at(x, y + k, z) == (LIQ_WATER, LIQ_MAX)) {
                    if rng.range(0, 2) == 0 && ids.coral != 0 {
                        put(w, (x, y + 1, z), ids.coral);
                    } else {
                        put(w, (x, y + 1, z), sea_shell(&ids, rng));
                        shells += 1;
                    }
                } else if !wet && y >= l.surface_base {
                    put(w, (x, y + 1, z), sea_shell(&ids, rng));
                    shells += 1;
                }
            } else if !wet && inland >= sea.width && ids.sea_oats[0] != 0 && rng.range(0, 6) == 0 {
                // PlantSeaOat on dry beach sand; GrowSeaOat half the time,
                // twice over.
                let mut stage = 0;
                if rng.range(0, 2) == 0 {
                    stage += 1;
                }
                if rng.range(0, 2) == 0 {
                    stage += 1;
                }
                put(w, (x, y + 1, z), ids.sea_oats[stage]);
                oats += 1;
            }
        }
    }
    // Seaweed from sand under the water: 2 in 3 of it (here a tenth of that,
    // the sea floor being an area), at most 30 cells within 4 tiles.
    if ids.seaweed != 0 {
        for z in 1..w.sz - 1 {
            for x in 1..w.sx - 1 {
                let y = w.surface_y(x, z);
                if y < 1 || y >= l.surface_base || w.get(x, y, z) != ids.sand || w.get(x, y + 1, z) != 0 || rng.range(0, 15) != 0 {
                    continue;
                }
                if !(1..4).all(|k| w.liquid_at(x, y + k, z) == (LIQ_WATER, LIQ_MAX)) {
                    continue;
                }
                let r = b(4.0);
                let near = (-r..=r).flat_map(|dx| (-r..=r).map(move |dz| (dx, dz)))
                    .map(|(dx, dz)| (y + 1..y + 1 + b(12.0)).filter(|&yy| w.get(x + dx, yy, z + dz) == ids.seaweed).count())
                    .sum::<usize>();
                if near > 30 {
                    continue;
                }
                let mut top = y;
                while top + 3 < w.sy && w.get(x, top + 1, z) == 0 && (1..4).all(|k| w.liquid_at(x, top + k, z) == (LIQ_WATER, LIQ_MAX))
                    && ((top - y) as f64) < b((17 - rng.range(0, 20)) as f64) as f64
                {
                    put(w, (x, top + 1, z), ids.seaweed);
                    top += 1;
                }
                if top > y {
                    weeds += 1;
                }
            }
        }
    }
    (piles, shells, oats, weeds)
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS};
    use crate::worldgen::layers;

    pub const STATUE_NAMES: [&str; 73] = STATUES;

    /// The placement passes' blocks, for worldgen's test worlds.
    pub fn add_placement_defs(w: &mut World) {
        let mut names: Vec<String> = STATUES.iter().map(|s| s.to_string()).collect();
        names.extend(["pot", "spider_pot", "ice_pot", "jungle_pot", "dungeon_pot", "underworld_pot", "corruption_pot", "crimson_pot", "lihzahrd_pot", "marble_pot",
            "desert_pot", "bone_pile", "large_relic_rocks", "copper_rock_pile", "silver_rock_pile", "gold_rock_pile", "ice_pile",
            "mushroom_pile", "jungle_pile", "ash_pile", "grassy_rocks", "lihzahrd_pile", "cave_ruins", "desert_pile", "granite_pile",
            "marble_pile", "sand_pile", "dirt_clods", "small_bones", "bloody_bones", "small_debris", "small_ice_rocks",
            "small_granite_rocks", "small_marble_rocks", "small_desert_rocks", "rock_pile", "bone_heap", "bloody_bone_heap",
            "amethyst_pile", "topaz_pile", "sapphire_pile", "emerald_pile", "ruby_pile", "diamond_pile", "ice_rock_pile",
            "grassy_rock_pile", "granite_rock_pile", "marble_rock_pile", "desert_rock_pile", "stone_stalactite",
            "small_stone_stalactite", "stone_stalagmite", "small_stone_stalagmite", "icicle", "small_icicle", "honey_stalactite",
            "honey_stalagmite", "teal_mushroom", "green_mushroom", "sky_blue_flower", "yellow_marigold", "blue_berries", "lime_kelp",
            "pink_prickly_pear", "orange_bloodroot", "seashell", "starfish", "lightning_whelk_shell", "tulip_shell", "junonia_shell",
            "seaweed", "coral", "antlion_eggs"].map(String::from));
        for name in names {
            if w.id_of(&name) == 0 {
                let id = w.defs.len() as u16;
                w.set_def(id, BlockDef { name, render: RENDER_CROSS, solid: false, opaque: false, variants: 1, ..Default::default() });
            }
        }
        for name in ["thin_ice", "gold_coin_pile", "iridescent_brick", "mudstone_block", "rich_mahogany", "tin_brick", "gold_brick"] {
            if w.id_of(name) == 0 {
                let id = w.defs.len() as u16;
                w.set_def(id, BlockDef { name: name.into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
            }
        }
        for name in ["detonator", "dead_mans_chest", "campfire_off", "minecart_track", "green_wall_torch", "rolling_cactus"] {
            if w.id_of(name) == 0 {
                let id = w.defs.len() as u16;
                w.set_def(id, BlockDef { name: name.into(), render: crate::world::RENDER_CUTOUT, solid: false, opaque: false, variants: 1, ..Default::default() });
            }
        }
        if w.id_of("shell_pile") == 0 {
            let id = w.defs.len() as u16;
            w.set_def(id, BlockDef { name: "shell_pile".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        }
    }

    fn flat(w: &mut World, ground: &str) -> u16 {
        let g = w.id_of(ground);
        for z in 0..w.sz {
            for x in 0..w.sx {
                for y in 0..4 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = g;
                }
            }
        }
        g
    }

    fn small_world() -> World {
        let mut w = World::new();
        for (i, name) in ["stone", "dirt", "snow_block", "ice_block", "jungle_grass", "blue_brick", "ebonstone", "marble", "granite",
            "sand", "hardened_sand", "ash", "hive", "lihzahrd_brick", "mushroom_grass", "large_rocks", "small_rocks", "pot",
            "copper_coin_stash", "silver_coin_stash", "gold_coin_stash", "sword_in_stone"].iter().enumerate() {
            let cube = i < 15;
            w.set_def(i as u16 + 1, BlockDef { name: name.to_string(), render: if cube { RENDER_CUBE } else { RENDER_CROSS }, solid: cube, opaque: cube,
                variants: 1, ..Default::default() });
        }
        add_placement_defs(&mut w);
        w.resize(64, 64, 64);
        w
    }

    /// Pots take the style of what they stand on (PlacePot): snow the ice
    /// pots, the Dungeon's brick its own; in the Underworld its own.
    #[test]
    fn pots_by_what_they_stand_on() {
        let l = layers(64);
        let ids = |w: &World| Ids::new(w);
        let mut w = small_world();
        for (ground, pot) in [("snow_block", "ice_pot"), ("jungle_grass", "jungle_pot"), ("blue_brick", "dungeon_pot"), ("ebonstone", "corruption_pot"),
            ("marble", "marble_pot"), ("lihzahrd_brick", "lihzahrd_pot"), ("stone", "pot"), ("hardened_sand", "desert_pot")] {
            let g = w.id_of(ground);
            assert_eq!(pot_for(&ids(&w), ids(&w).ground(g), l.surface_base - 5, &l), w.id_of(pot), "{ground}");
        }
        assert_eq!(pot_for(&ids(&w), Ground::Stone, l.underworld_top - 2, &l), w.id_of("underworld_pot"), "the Underworld's");
        // Sand on the surface is the beach, not the desert's caves.
        assert_eq!(pot_for(&ids(&w), Ground::Sand, l.surface_base + 2, &l), w.id_of("pot"));
        let _ = flat(&mut w, "stone");
    }

    /// Big piles by their ground: ice on snow, the jungle's on its grass,
    /// bones in the Underworld and on ebonstone, granite's and marble's.
    #[test]
    fn piles_by_what_they_stand_on() {
        let w = small_world();
        let ids = Ids::new(&w);
        let mut rng = Rng::new(7);
        let kinds = |rng: &mut Rng, ground: &str, deep: bool| -> Vec<&'static str> {
            (0..200).filter_map(|_| large_pile(&ids, rng, w.id_of(ground), deep)).collect()
        };
        assert!(kinds(&mut rng, "snow_block", false).iter().all(|k| *k == "ice_pile"));
        assert!(kinds(&mut rng, "jungle_grass", false).iter().all(|k| *k == "jungle_pile"));
        assert!(kinds(&mut rng, "ebonstone", false).iter().all(|k| *k == "bone_pile"));
        assert!(kinds(&mut rng, "granite", false).iter().all(|k| *k == "granite_pile"));
        let deep = kinds(&mut rng, "stone", true);
        assert!(deep.iter().all(|k| *k == "bone_pile"), "bones in the Underworld");
        let ash = kinds(&mut rng, "ash", true);
        let share = ash.iter().filter(|k| **k == "ash_pile").count() as f64 / ash.len() as f64;
        assert!((0.55..0.78).contains(&share), "2 in 3 on ash its own ({share})");
        let stone = kinds(&mut rng, "stone", false);
        for k in ["bone_pile", "large_rocks", "large_relic_rocks", "copper_rock_pile", "cave_ruins"] {
            assert!(stone.contains(&k), "{k} on stone");
        }
        // Small: the evils' stone turns rocks to bones; snow, ice rocks.
        let small: Vec<_> = (0..300).map(|_| small_pile(&ids, &mut rng, w.id_of("ebonstone"), false, false).0).collect();
        assert!(small.iter().all(|k| !["small_rocks", "dirt_clods", "rock_pile"].contains(k)), "{small:?}");
        let snow: Vec<_> = (0..300).map(|_| small_pile(&ids, &mut rng, w.id_of("snow_block"), false, false).0).collect();
        assert!(snow.contains(&"small_ice_rocks") && snow.contains(&"ice_rock_pile"));
        let any: Vec<_> = (0..3000).map(|_| small_pile(&ids, &mut rng, w.id_of("stone"), false, false).0).collect();
        for k in ["small_rocks", "dirt_clods", "small_bones", "bloody_bones", "rock_pile", "bone_heap", "copper_coin_stash", "diamond_pile"] {
            assert!(any.contains(&k), "{k} in the caves");
        }
    }

    /// Speleothems: stone stalactites under stone, icicles under ice,
    /// stalagmites on stone, none in a one-high gap.
    #[test]
    fn speleothems_hang_and_stand() {
        let mut w = small_world();
        let l = layers(64);
        let (stone, ice) = (w.id_of("stone"), w.id_of("ice_block"));
        // Floors at 1-3, a cave 4-9, a ceiling of stone (x < 32) or ice at
        // 10-12, a one-high gap at 13, rock over it; a surface far up.
        for z in 0..64 {
            for x in 0..64 {
                for y in (0..4).chain(10..13).chain(14..l.surface_base + 2) {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = if (10..13).contains(&y) && x >= 32 { ice } else { stone };
                }
            }
        }
        let n = speleothems(&mut w, &mut Rng::new(3), &l);
        let ids = Ids::new(&w);
        let [tite, small_tite, mite, small_mite, icicle, small_icicle, ..] = ids.speleothems;
        let count = |w: &World, y: i32, set: &[u16], xs: std::ops::Range<i32>| xs.flat_map(|x| (0..64).map(move |z| (x, z))).filter(|&(x, z)| set.contains(&w.get(x, y, z))).count();
        let cells = 32 * 64;
        let under_stone = count(&w, 9, &[tite, small_tite], 0..32);
        let under_ice = count(&w, 9, &[icicle, small_icicle], 32..64);
        let on_floor = count(&w, 4, &[mite, small_mite], 0..64);
        let one_in = SPELEOTHEM_ONE_IN as usize;
        let near = |got: usize, want: usize| got * 10 > want * 7 && got * 10 < want * 13;
        assert!(n > 0 && near(under_stone, cells / one_in), "1 in {one_in} under stone ({under_stone})");
        assert!(near(under_ice, cells / one_in), "1 in {one_in} under ice ({under_ice})");
        assert!(near(on_floor, 2 * cells / one_in), "1 in {one_in} on the floor ({on_floor})");
        assert_eq!(count(&w, 13, &ids.speleothems, 0..64), 0, "none in a one-high gap");
    }
}
