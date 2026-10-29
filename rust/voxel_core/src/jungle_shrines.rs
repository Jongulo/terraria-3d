//! Terraria's Jungle Shrines (its Jungle Chests pass, and Jungle Chests
//! Placement for their Ivy Chests), in 3D:
//!
//! - **The material:** one for the whole world (GenVars.jungleHut, picked at
//!   its Reset): Iridescent Brick, Mudstone Brick, Rich Mahogany, Tin Brick
//!   or Gold Brick, evenly.
//! - **How many:** 7-11 in a small world (x maxTilesX / 4200); here that many
//!   in each 640 x 640 blocks, as the cabins count. Each gets up to
//!   maxTilesX x 10 tries, then it's given up.
//! - **Where:** on the Jungle's side (Terraria: the half away from the
//!   Dungeon; here in the Jungle, as the hives), from halfway between the
//!   surface and the cavern layer down to 400 tiles above the world's bottom;
//!   the spot itself jungle grass. Not within 30 tiles of hive, honey or
//!   Lihzahrd blocks, or of a shrine of Iridescent Brick or Mudstone (the two
//!   materials Terraria checks for), or overlapping another structure.
//! - **The shrine:** a room 2-3 tiles out from the spot each way (here 3 or 5
//!   blocks across, square, and 3 or 5 tall), walled a tile thick with the
//!   material, no liquid in it. Its bottom 3 tiles (2 blocks) open out
//!   through its walls: Terraria's 2D room is open at both sides, here each
//!   side, between the corner posts. Under its floor, mud down to the ground
//!   (4 tiles at most); over its roof, a stepped pyramid of the material,
//!   each step 1-2 in from the last. A Green Torch on a wall above the
//!   doorways (its back wall in Terraria; here a wall of the room).
//! - **The Ivy Chest** (AddBuriedChest, style 10: jungle loot) on its floor in
//!   the middle.
//! - The room is kept from the structures after it.
//! - **Living Mahogany Wands** (AddBuriedChest's jungle chests): the first
//!   Ivy Chest of the world has the Living Mahogany Wand and the Rich
//!   Mahogany Leaf Wand, each after it 1 in 5 (here marked on the chests at
//!   the end of this pass, when they're all placed: MAHOGANY_WANDS).

use crate::world::{Decoration, World};
use crate::worldgen::{biome_regions, Layers, Rng, BIOME_JUNGLE, FACING};

type P = (i32, i32, i32);

/// Terraria's tiles to blocks here, rounded.
fn b(tiles: i32) -> i32 {
    (tiles as f64 * 2.0 / 3.0).round() as i32
}

/// The shrines' materials, in Terraria's order (GenVars.jungleHut 0-4).
pub const MATERIALS: [&str; 5] = ["iridescent_brick", "mudstone_block", "rich_mahogany", "tin_brick", "gold_brick"];

/// A worldgen chest's style bit: the Living Mahogany Wands in it (chests.gd).
pub const MAHOGANY_WANDS: i32 = 256;

/// The world's Jungle Shrines. Returns the cells of their chests.
pub fn jungle_shrines(w: &mut World, rng: &mut Rng, l: &Layers) -> Vec<P> {
    let mut chests = Vec::new();
    let material = w.id_of(MATERIALS[rng.range(0, 5) as usize]);
    let (mud, jgrass, chest, torch) = (w.id_of("mud"), w.id_of("jungle_grass"), w.id_of("ivy_chest"), w.id_of("green_wall_torch"));
    if material == 0 || mud == 0 || jgrass == 0 || chest == 0 {
        return chests;
    }
    let Some(&(_, jx, jz, jr)) = biome_regions(w.sx, w.sz, w.seed).iter().find(|r| r.0 == BIOME_JUNGLE) else { return chests };
    // Blocks a shrine keeps 30 tiles from.
    let shun: Vec<u16> = ["hive", "honey_block", "lihzahrd_brick", "iridescent_brick", "mudstone_block"].iter().map(|n| w.id_of(n)).filter(|&t| t != 0).collect();
    let (y_lo, y_hi) = (crate::dungeon::depth_y(l, 510.0), crate::dungeon::depth_y(l, 65.0));
    let area = w.sx as f64 * w.sz as f64 / (640.0 * 640.0);
    let want = (rng.range(7, 12) as f64 * area).round() as usize;
    for _ in 0..want {
        for _ in 0..w.sx * 10 {
            let a = rng.unit() * std::f64::consts::TAU;
            let d = rng.unit().sqrt() * jr as f64;
            let (x, y, z) = (jx + (a.cos() * d) as i32, rng.range(y_lo, y_hi.max(y_lo + 1)), jz + (a.sin() * d) as i32);
            // Half its width and its height inside, in blocks.
            let half = (b(2 * rng.range(2, 4) + 1) - 1) / 2;
            let tall = b(2 * rng.range(2, 4) + 1);
            if !w.in_bounds(x, y, z) || w.get(x, y, z) != jgrass {
                continue;
            }
            let y0 = y - (tall - 1) / 2;
            let roof = half + 1;
            let bx = ((x - half - 1, y0 - 1, z - half - 1), (x + half + 1, y0 + tall + roof, z + half + 1));
            if !w.in_bounds(bx.0 .0 - 1, bx.0 .1 - 4, bx.0 .2 - 1) || !w.in_bounds(bx.1 .0 + 1, bx.1 .1, bx.1 .2 + 1) {
                continue;
            }
            let r = b(30);
            let near = (-r..r).step_by(2).any(|dx| {
                (-r..r).step_by(2).any(|dy| (-r..r).step_by(2).any(|dz| shun.contains(&w.get(x + dx, y + dy, z + dz))))
            });
            let (lo, hi) = ((bx.0 .0 - 1, bx.0 .1 - 1, bx.0 .2 - 1), (bx.1 .0 + 1, bx.1 .1 + 1, bx.1 .2 + 1));
            if near || w.structures.iter().any(|&(a, c)| lo.0 <= c.0 && a.0 <= hi.0 && lo.1 <= c.1 && a.1 <= hi.1 && lo.2 <= c.2 && a.2 <= hi.2) {
                continue;
            }
            build(w, rng, (x, y0, z), half, tall, material, mud, torch);
            w.set(x, y0, z, chest);
            w.decorations.push(Decoration { kind: "chest".into(), pos: (x, y0, z), style: 2 });
            w.structures.push(bx);
            chests.push((x, y0, z));
            break;
        }
    }
    // The wands: in the first Ivy Chest, then 1 in 5.
    let mut first = true;
    for d in w.decorations.iter_mut().filter(|d| d.kind == "chest" && d.style & 63 == 2) {
        if first || rng.range(0, 5) == 0 {
            d.style |= MAHOGANY_WANDS;
        }
        first = false;
    }
    chests
}

/// A shrine round (x, y0, z), y0 its floor's top: `half` blocks out from the
/// middle inside, `tall` blocks high inside.
fn build(w: &mut World, rng: &mut Rng, (x, y0, z): P, half: i32, tall: i32, material: u16, mud: u16, torch: u16) {
    let door = b(3);
    for i in x - half - 1..=x + half + 1 {
        for k in z - half - 1..=z + half + 1 {
            let post = (i - x).abs() == half + 1 && (k - z).abs() == half + 1;
            let shell = (i - x).abs() == half + 1 || (k - z).abs() == half + 1;
            for j in y0 - 1..=y0 + tall {
                let inside = !shell && j >= y0 && j < y0 + tall;
                let doorway = shell && !post && j >= y0 && j < y0 + door;
                w.set(i, j, k, if inside || doorway { 0 } else { material });
                w.set_liquid(i, j, k, 0, 0);
            }
            // Mud under the floor, down to the ground.
            for j in (y0 - 1 - b(4)..y0 - 1).rev() {
                if w.is_solid(i, j, k) {
                    break;
                }
                w.set(i, j, k, mud);
                w.set_liquid(i, j, k, 0, 0);
            }
        }
    }
    // The roof: steps 1-2 in from the last.
    let mut r = half + 1 - rng.range(1, 3);
    let mut j = y0 + tall + 1;
    while r >= 1 {
        for i in x - r..=x + r {
            for k in z - r..=z + r {
                w.set(i, j, k, material);
                w.set_liquid(i, j, k, 0, 0);
            }
        }
        r -= rng.range(1, 3);
        j += 1;
    }
    // A Green Torch on a wall, over the doorways.
    if torch != 0 && tall > door {
        let f = rng.range(0, 4) as usize;
        let (fx, fz) = FACING[f];
        let along = rng.range(-half, half + 1);
        let (i, k) = (x - fx * half + fz * along, z - fz * half + fx * along);
        let j = rng.range(y0 + door, y0 + tall);
        w.set(i, j, k, torch);
        w.decorations.push(Decoration { kind: "rotation".into(), pos: (i, j, k), style: f as i32 });
    }
}
