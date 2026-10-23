//! Terraria's herbs as worldgen plants them (its Herbs pass: WorldGen.
//! PlantAlch, maxTilesX x 1.7 tries; here that many per 640 x 640 blocks, as
//! the cave cabins are counted). Each try: a random column, a random height
//! (1 in 40 deep in the caverns and the Underworld, 1 in 10 anywhere, else
//! under the surface), down from there to the first block; with nothing and
//! no liquid over it and fewer than 5 herbs within 15 tiles (here 10 blocks),
//! the herb that grows on it goes in as a sprout (PlaceSuitableHerbHere,
//! PlaceAlch): Daybloom on grass, Moonglow on jungle grass, Blinkroot on dirt
//! or mud, Deathweed on corrupt or crimson grass and stone, Waterleaf on
//! sand (not by the sea), Fireblossom on ash, Shiverthorn on snow or ice.
//! The game grows them (scripts/world/herbs.gd).

use crate::world::World;
use crate::worldgen::{Layers, Rng};

pub const HERBS: [&str; 7] = ["daybloom", "moonglow", "blinkroot", "deathweed", "waterleaf", "fireblossom", "shiverthorn"];

/// What each herb grows on (block names), in HERBS' order.
pub const SOILS: [&[&str]; 7] = [
    &["grass", "clay_pot"],
    &["jungle_grass", "clay_pot"],
    &["dirt", "mud", "clay_pot"],
    &["corrupt_grass", "ebonstone", "crimson_grass", "crimstone", "clay_pot"],
    &["sand", "clay_pot"],
    &["ash", "ash_grass", "clay_pot"],
    &["snow_block", "ice_block", "clay_pot"],
];

/// Herbs within this many blocks each way count toward the 5 (15 tiles).
const NEAR: i32 = 10;

pub fn herbs_pass(w: &mut World, rng: &mut Rng, l: &Layers) -> usize {
    let sprouts: Vec<u16> = HERBS.iter().map(|h| w.id_of(&format!("{h}_sprout"))).collect();
    if sprouts.iter().any(|&s| s == 0) {
        return 0;
    }
    let all: Vec<u16> = HERBS.iter().flat_map(|h| [format!("{h}_sprout"), format!("{h}_mature"), h.to_string()]).map(|n| w.id_of(&n)).filter(|&i| i != 0).collect();
    // Soils (not the clay pot: worldgen puts herbs only in the wild).
    let soils: Vec<Vec<u16>> = SOILS.iter().map(|s| s.iter().filter(|n| **n != "clay_pot").map(|n| w.id_of(n)).filter(|&i| i != 0).collect()).collect();
    let tries = (4200.0 * 1.7 * (w.sx as f64) * (w.sz as f64) / (640.0 * 640.0)) as usize;
    let beach = crate::worldgen::ocean(w.sx, w.sy, w.sz).width as i32;
    let mut placed = 0;
    for _ in 0..tries {
        let (x, z) = (rng.range(3, w.sx - 3), rng.range(3, w.sz - 3));
        let top = (w.sy - 20).max(6);
        let mut y = if rng.range(0, 40) == 0 {
            rng.range(5, ((l.cavern_top + 5) / 2).max(6))
        } else if rng.range(0, 10) == 0 {
            rng.range(5, top)
        } else {
            rng.range(5, l.surface_base.max(6))
        };
        while y > 2 && w.get(x, y, z) == 0 {
            y -= 1;
        }
        if !w.is_solid(x, y, z) || w.get(x, y + 1, z) != 0 || w.liquid_at(x, y + 1, z).1 > 0 {
            continue;
        }
        let ground = w.get(x, y, z);
        let Some(style) = soils.iter().position(|s| s.contains(&ground)) else { continue };
        // Waterleaf: not on the beach (Terraria's beachDistance).
        if style == 4 && (x < beach || z < beach || x >= w.sx - beach || z >= w.sz - beach) {
            continue;
        }
        let mut near = 0;
        'count: for dx in -NEAR..=NEAR {
            for dy in -NEAR..=NEAR {
                for dz in -NEAR..=NEAR {
                    if all.contains(&w.get(x + dx, y + 1 + dy, z + dz)) {
                        near += 1;
                        if near >= 5 {
                            break 'count;
                        }
                    }
                }
            }
        }
        if near >= 5 {
            continue;
        }
        let i = w.idx(x, y + 1, z);
        w.blocks[i] = sprouts[style];
        placed += 1;
    }
    placed
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE};

    #[test]
    fn herbs_sprout_on_their_soils() {
        let mut w = World::new();
        let mut id = 1u16;
        for (name, solid) in [("grass", true), ("jungle_grass", true), ("dirt", true), ("sand", true), ("ash", true), ("snow_block", true), ("stone", true)] {
            w.set_def(id, BlockDef { name: name.into(), render: RENDER_CUBE, solid, opaque: solid, variants: 1, ..Default::default() });
            id += 1;
        }
        for h in HERBS {
            for n in [format!("{h}_sprout"), format!("{h}_mature"), h.to_string()] {
                w.set_def(id, BlockDef { name: n, render: RENDER_CROSS, solid: false, opaque: false, variants: 1, ..Default::default() });
                id += 1;
            }
        }
        w.resize(128, 64, 128);
        // Strips of each soil at the surface (y 30), stone under it.
        let soils = ["grass", "jungle_grass", "dirt", "sand", "ash", "snow_block"];
        for x in 0..128 {
            for z in 0..128 {
                for y in 0..30 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = w.id_of("stone");
                }
                let i = w.idx(x, 30, z);
                w.blocks[i] = w.id_of(soils[(x / 22) as usize % soils.len()]);
            }
        }
        let l = Layers { underworld_top: 4, cavern_top: 20, surface_base: 40, space_top: 60 };
        let n = herbs_pass(&mut w, &mut Rng::new(5), &l);
        assert!(n > 20, "{n} herbs");
        // Each on the soil it grows on.
        for x in 0..128 {
            for z in 0..128 {
                let b = w.get(x, 31, z);
                if b == 0 {
                    continue;
                }
                let name = w.def(b).name.clone();
                let herb = HERBS.iter().position(|h| name == format!("{h}_sprout")).expect("only herb sprouts go in");
                let ground = w.def(w.get(x, 30, z)).name.clone();
                assert!(SOILS[herb].contains(&ground.as_str()), "{name} on {ground}");
            }
        }
    }
}
