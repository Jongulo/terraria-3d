//! Terraria's paintings in the world: which one goes where, roll for roll
//! (WorldGen.RandHousePicture for cabins, RandHousePictureDesert for desert
//! cabins, RandHellPicture for the Underworld's forts; the Dungeon's
//! Paintings_RandomDungeonPainting in its brick parts and
//! Paintings_RandomBonePainting elsewhere), and hanging one on a wall in 3D.
//!
//! A painting is Terraria's tile 240 (3x3), 241 (4x3), 242 (6x4), 245 (2x3)
//! or 246 (3x2) and a style; here a wall block (blocks.json "painting") whose
//! art, two tiles a block, is centred on its cell, so it covers the cells
//! round it too. Terraria's PlaceTile needs every tile of it empty with a
//! wall behind; here every cell it covers is empty with a solid block of the
//! building behind it (`backing`). Its callers' Terraria checks: nearPicture
//! (no tiles in the 8 x 6 tiles round it: `clear`) and nearPicture2 (no
//! other painting within 8 tiles across and 5 up or down, the Dungeon's
//! brick 15 and 10: `near`).

use std::collections::{HashMap, HashSet};

use crate::world::{Decoration, World};
use crate::worldgen::{Rng, FACING};

/// Terraria's tile and style.
pub type Pick = (u16, u16);

/// The paintings worldgen hangs, by tile and style (blocks.json's names).
const NAMES: &[(u16, u16, &str)] = &[
    (240, 12, "blood_moon_rising"),
    (240, 13, "the_hanged_man"),
    (240, 14, "glory_of_the_fire"),
    (240, 15, "bone_warp"),
    (240, 16, "wall_skeleton"),
    (240, 17, "hanging_skeleton"),
    (240, 18, "skellington_j_skellingsworth"),
    (240, 19, "the_cursed_man"),
    (240, 20, "sunflowers_painting"),
    (240, 21, "terrarian_gothic"),
    (240, 22, "guide_picasso"),
    (240, 23, "the_guardians_gaze"),
    (240, 24, "father_of_someone"),
    (240, 25, "nurse_lisa"),
    (240, 26, "discover_painting"),
    (240, 27, "hand_earth"),
    (240, 28, "old_miner"),
    (240, 29, "skelehead_painting"),
    (240, 30, "imp_face"),
    (240, 31, "ominous_presence"),
    (240, 32, "shining_moon"),
    (240, 33, "the_merchant"),
    (240, 34, "crowno_devours_his_lunch"),
    (240, 35, "rare_enchantment"),
    (240, 63, "andrew_sphinx"),
    (240, 64, "watchful_antlion"),
    (240, 65, "burning_spirit"),
    (240, 66, "jaws_of_death"),
    (240, 67, "the_sands_of_slime"),
    (240, 68, "snakes_i_hate_snakes"),
    (240, 76, "outcast_painting"),
    (240, 77, "fairy_guides"),
    (240, 78, "a_horrible_night_for_alchemy"),
    (240, 79, "morning_hunt"),
    (240, 82, "cat_sword"),
    (240, 96, "banner_of_the_beast"),
    (240, 98, "bould_and_bash"),
    (240, 100, "remix_painting"),
    (241, 0, "catacomb_painting"),
    (241, 1, "catacomb_painting_2"),
    (241, 2, "catacomb_painting_3"),
    (241, 3, "catacomb_painting_4"),
    (241, 4, "catacomb_painting_5"),
    (241, 5, "catacomb_painting_6"),
    (241, 6, "catacomb_painting_7"),
    (241, 7, "catacomb_painting_8"),
    (241, 8, "catacomb_painting_9"),
    (242, 0, "the_eye_sees_the_end"),
    (242, 1, "something_evil_is_watching_you"),
    (242, 2, "the_twins_have_awoken"),
    (242, 3, "the_screamer"),
    (242, 4, "goblins_playing_poker"),
    (242, 5, "dryadisque_painting"),
    (242, 6, "impact_painting"),
    (242, 7, "powered_by_birds"),
    (242, 8, "the_destroyer"),
    (242, 9, "the_persistency_of_eyes"),
    (242, 10, "unicorn_crossing_the_hallows"),
    (242, 11, "great_wave"),
    (242, 12, "starry_night"),
    (242, 13, "facing_the_cerebral_mastermind"),
    (242, 14, "lake_of_fire"),
    (242, 15, "trio_super_heroes"),
    (242, 16, "the_creation_of_the_guide"),
    (242, 30, "sparky_painting"),
    (242, 37, "life_above_the_sand"),
    (242, 38, "oasis_painting"),
    (242, 39, "prehistory_preserved"),
    (242, 40, "ancient_tablet"),
    (242, 41, "uluru_painting"),
    (242, 42, "visiting_the_pyramids"),
    (245, 0, "waldo_painting"),
    (245, 1, "darkness_painting"),
    (245, 2, "dark_soul_reaper"),
    (245, 3, "land_painting"),
    (245, 4, "trapped_ghost"),
    (245, 5, "american_explosive"),
    (245, 6, "glorious_night"),
    (245, 7, "bandage_boy"),
    (245, 8, "divine_eye"),
    (245, 14, "sufficiently_advanced"),
    (245, 15, "strange_growth"),
    (245, 16, "strange_growth_2"),
    (245, 17, "strange_growth_3"),
    (245, 18, "strange_growth_4"),
    (245, 19, "happy_little_tree"),
    (245, 20, "strange_dead_fellows"),
    (245, 21, "secrets_painting"),
    (246, 0, "demons_eye"),
    (246, 1, "finding_gold"),
    (246, 16, "living_gore"),
    (246, 17, "flowing_magma"),
    (246, 30, "bioluminescence_painting"),
    (246, 31, "wildflowers_painting"),
    (246, 32, "viking_voyage"),
    (246, 33, "bifrost_painting"),
    (246, 34, "heartlands_painting"),
    (246, 35, "forest_troll"),
    (246, 36, "aurora_borealis"),
];

/// A painting tile's size in tiles (across, up).
pub fn tiles(tile: u16) -> (i32, i32) {
    match tile {
        240 => (3, 3),
        241 => (4, 3),
        242 => (6, 4),
        245 => (2, 3),
        _ => (3, 2),
    }
}

/// The cells a painting `n` tiles long covers that way, as offsets from its
/// own: n / 2 blocks centred on the cell's middle.
pub fn span(n: i32) -> (i32, i32) {
    let half = n as f64 / 4.0;
    ((0.5 - half + 1e-3).floor() as i32, (0.5 + half - 1e-3).floor() as i32)
}

/// WorldGen.RandHousePicture.
pub fn house(rng: &mut Rng) -> Pick {
    let mut kind = rng.range(0, 4);
    if kind >= 3 && rng.range(0, 2) != 0 {
        kind = rng.range(0, 3);
    }
    if kind <= 1 {
        const S: [u16; 18] = [26, 28, 20, 21, 22, 24, 25, 33, 34, 35, 76, 77, 78, 79, 82, 96, 98, 100];
        (240, S[rng.range(0, 18) as usize])
    } else if kind == 2 {
        let mut n = rng.range(0, 9);
        if n == 0 && rng.range(0, 3) != 0 {
            n = rng.range(0, 9);
        }
        let style = match n {
            0 => 0,
            1 => 3,
            2 => 5,
            3 => 6,
            4 => 14,
            5 => 15 + rng.range(0, 4) as u16,
            6 => 19,
            7 => 20,
            _ => 21,
        };
        (245, style)
    } else {
        const S: [u16; 8] = [1, 30, 31, 32, 33, 34, 35, 36];
        (246, S[rng.range(0, 8) as usize])
    }
}

/// WorldGen.RandHousePictureDesert.
pub fn desert(rng: &mut Rng) -> Pick {
    match rng.range(0, 4) {
        0 | 1 => (240, 63 + rng.range(0, 6) as u16),
        2 => (245, 7 + rng.range(0, 2) as u16),
        _ => (242, 37 + rng.range(0, 6) as u16),
    }
}

/// WorldGen.RandHellPicture.
pub fn hell(rng: &mut Rng) -> Pick {
    let mut kind = rng.range(0, 4);
    if kind == 1 {
        kind = rng.range(0, 4);
    }
    match kind {
        0 => (240, [27, 29, 30, 31, 32][rng.range(0, 5) as usize]),
        1 => (242, 14),
        2 => (245, [1, 2, 4][rng.range(0, 3) as usize]),
        _ => (246, [0, 16, 17][rng.range(0, 3) as usize]),
    }
}

/// DungeonGlobalPaintings.Paintings_RandomDungeonPainting.
pub fn dungeon(rng: &mut Rng) -> Pick {
    if rng.range(0, 3) <= 1 {
        let mut n = rng.range(0, 7);
        if n == 6 {
            n = rng.range(0, 7);
        }
        (240, [12, 13, 14, 15, 18, 19, 23][n as usize])
    } else {
        let n = rng.range(0, 17) as u16;
        (242, match n {
            14 => 15,
            15 => 16,
            16 => 30,
            _ => n,
        })
    }
}

/// DungeonGlobalPaintings.Paintings_RandomBonePainting.
pub fn bone(rng: &mut Rng) -> Pick {
    if rng.range(0, 2) == 0 {
        (240, 16 + rng.range(0, 2) as u16)
    } else {
        (241, rng.range(0, 9) as u16)
    }
}

/// The painting blocks of this world.
pub struct Paintings {
    by: HashMap<Pick, u16>,
    all: HashSet<u16>,
}

impl Paintings {
    pub fn of(w: &World) -> Self {
        let by: HashMap<Pick, u16> = NAMES.iter().map(|&(t, s, n)| ((t, s), w.id_of(n))).filter(|&(_, id)| id != 0).collect();
        let all = by.values().copied().collect();
        Paintings { by, all }
    }

    pub fn id(&self, p: Pick) -> u16 {
        self.by.get(&p).copied().unwrap_or(0)
    }

    pub fn is(&self, b: u16) -> bool {
        b != 0 && self.all.contains(&b)
    }

    /// The cells painting block `b` covers round its own: along its wall
    /// and up, as offset ranges (`span`).
    pub fn cover(&self, b: u16) -> ((i32, i32), (i32, i32)) {
        let tile = self.by.iter().find(|&(_, &id)| id == b).map_or(240, |(p, _)| p.0);
        let (tw, th) = tiles(tile);
        (span(tw), span(th))
    }

    /// Whether painting `p` fits at `at`, facing `out` (out of its wall):
    /// every cell its art covers empty and dry with a block `backing` takes
    /// behind it, and the cells round it on the wall (`clear`: along it from
    /// .0 to .1, down to .2 and up to .3, as offsets) empty.
    pub fn fits(&self, w: &World, at: (i32, i32, i32), out: (i32, i32), p: Pick, backing: &dyn Fn(u16) -> bool, clear: (i32, i32, i32, i32)) -> bool {
        if self.id(p) == 0 {
            return false;
        }
        let along = (-out.1, out.0);
        let cell = |k: i32, j: i32| (at.0 + along.0 * k, at.1 + j, at.2 + along.1 * k);
        let ((k0, k1), (j0, j1)) = self.cover(self.id(p));
        for k in k0..=k1 {
            for j in j0..=j1 {
                let c = cell(k, j);
                if !w.in_bounds(c.0, c.1, c.2) || w.get(c.0, c.1, c.2) != 0 || w.liquid_at(c.0, c.1, c.2).1 > 0 || !backing(w.get(c.0 - out.0, c.1, c.2 - out.1)) {
                    return false;
                }
            }
        }
        self.clear(w, at, out, clear)
    }

    /// nearPicture: the cells round `at` on its wall (facing `out`) empty,
    /// from `clear.0` to `clear.1` along it and `clear.2` to `clear.3` up.
    pub fn clear(&self, w: &World, at: (i32, i32, i32), out: (i32, i32), clear: (i32, i32, i32, i32)) -> bool {
        let along = (-out.1, out.0);
        (clear.0..=clear.1).all(|k| (clear.2..=clear.3).all(|j| w.get(at.0 + along.0 * k, at.1 + j, at.2 + along.1 * k) == 0))
    }

    /// nearPicture2: another painting within `r` across and `ry` up or down.
    pub fn near(&self, w: &World, at: (i32, i32, i32), r: i32, ry: i32) -> bool {
        (-r..=r).any(|dx| (-ry..=ry).any(|dy| (-r..=r).any(|dz| self.is(w.get(at.0 + dx, at.1 + dy, at.2 + dz)))))
    }

    /// Whether a painting may cover cell `c`: one in it or next to it (the
    /// most any covers round its own), so nothing else goes there.
    pub fn covers(&self, w: &World, c: (i32, i32, i32)) -> bool {
        (-1..=1).any(|dx| (-1..=1).any(|dy| (-1..=1).any(|dz| self.is(w.get(c.0 + dx, c.1 + dy, c.2 + dz)))))
    }

    /// Hangs painting `p` at `at`, facing `out`.
    pub fn hang(&self, w: &mut World, at: (i32, i32, i32), out: (i32, i32), p: Pick) {
        let id = self.id(p);
        if id == 0 || !w.in_bounds(at.0, at.1, at.2) {
            return;
        }
        let i = w.idx(at.0, at.1, at.2);
        w.blocks[i] = id;
        w.liquid[i] = 0;
        w.shapes.remove(&i);
        let style = FACING.iter().position(|&f| f == out).unwrap_or(0) as i32;
        w.decorations.push(Decoration { kind: "rotation".into(), pos: at, style });
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CUTOUT};

    /// The painting blocks for test worlds (the game has them in blocks.json).
    pub(crate) fn add_painting_defs(w: &mut World) {
        for &(_, _, name) in NAMES {
            if w.id_of(name) == 0 {
                let id = w.defs.len() as u16;
                w.set_def(id, BlockDef { name: name.into(), render: RENDER_CUTOUT, solid: false, opaque: false, variants: 1, ..Default::default() });
            }
        }
    }

    #[test]
    fn every_pick_has_a_block() {
        let names: HashSet<Pick> = NAMES.iter().map(|&(t, s, _)| (t, s)).collect();
        let mut rng = Rng::new(3);
        let mut seen = HashSet::new();
        for _ in 0..20000 {
            for p in [house(&mut rng), desert(&mut rng), hell(&mut rng), dungeon(&mut rng), bone(&mut rng)] {
                assert!(names.contains(&p), "no block for {p:?}");
                seen.insert(p);
            }
        }
        assert_eq!(seen.len(), names.len(), "every painting in the table comes up");
    }

    #[test]
    fn art_covers_the_cells_round_its_own() {
        assert_eq!(span(3), (-1, 1)); // 1.5 blocks
        assert_eq!(span(6), (-1, 1)); // 3 blocks
        assert_eq!(span(2), (0, 0)); // 1 block
        assert_eq!(span(4), (-1, 1)); // 2 blocks
    }
}
