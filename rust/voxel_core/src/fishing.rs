//! Terraria's fishing pond measure (Projectile.GetFishingPondState and
//! GetFishingPondWidth): how much liquid a bobber sits in.

use crate::world::{World, LIQ_HONEY, LIQ_LAVA};

/// The pond through one vertical slice: Terraria's 2D measure, run in the
/// plane through (x, y, z) along x (`along_x`) or z.
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct Pond {
    /// Liquid cells: the row the bobber is in, out to where the liquid ends
    /// (or a solid block), and each of its columns down to where the
    /// liquid ends; x1.5 if any of it is honey (Terraria's numWaters).
    pub cells: i32,
    pub lava: bool,
    pub honey: bool,
}

fn wet(w: &World, x: i32, y: i32, z: i32) -> bool {
    w.in_bounds(x, y, z) && w.liquid_at(x, y, z).1 > 0 && !w.is_solid(x, y, z)
}

/// Stops counting past `cap` cells (fishing only needs to know up to 1000).
pub fn pond(w: &World, x: i32, y: i32, z: i32, along_x: bool, cap: i32) -> Pond {
    let mut p = Pond::default();
    let (dx, dz) = if along_x { (1, 0) } else { (0, 1) };
    let at = |k: i32| (x + dx * k, z + dz * k);
    // GetFishingPondWidth: out each way while the row stays liquid.
    let mut lo = 0;
    while wet(w, at(lo).0, y, at(lo).1) {
        lo -= 1;
    }
    let mut hi = 0;
    while wet(w, at(hi).0, y, at(hi).1) {
        hi += 1;
    }
    'cols: for k in lo..=hi {
        let (cx, cz) = at(k);
        let mut cy = y;
        while wet(w, cx, cy, cz) {
            p.cells += 1;
            match w.liquid_at(cx, cy, cz).0 {
                LIQ_LAVA => p.lava = true,
                LIQ_HONEY => p.honey = true,
                _ => {}
            }
            if p.cells >= cap {
                break 'cols;
            }
            cy -= 1;
        }
    }
    if p.honey {
        p.cells = (p.cells as f64 * 1.5) as i32;
    }
    p
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{BlockDef, LIQ_WATER, RENDER_CUBE};

    /// Stone with a 12 x 4 deep x 6 pond dug in its top, full of `liquid`.
    fn pond_world(liquid: u8) -> World {
        let mut w = World::new();
        w.set_def(1, BlockDef { name: "stone".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        w.resize(32, 32, 32);
        for x in 0..32 {
            for z in 0..32 {
                for y in 0..20 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 1;
                }
            }
        }
        for x in 10..22 {
            for z in 10..16 {
                for y in 16..20 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 0;
                    w.set_liquid(x, y, z, liquid, 63);
                }
            }
        }
        w
    }

    #[test]
    fn measures_both_slices() {
        let w = pond_world(LIQ_WATER);
        // Along x: 12 columns 4 deep; along z: 6 columns.
        assert_eq!(pond(&w, 15, 19, 12, true, 10000), Pond { cells: 48, lava: false, honey: false });
        assert_eq!(pond(&w, 15, 19, 12, false, 10000).cells, 24);
        // From lower down only what's below counts (Terraria counts down from the bobber's row).
        assert_eq!(pond(&w, 15, 17, 12, true, 10000).cells, 24);
        // Out of the water: nothing.
        assert_eq!(pond(&w, 15, 21, 12, true, 10000).cells, 0);
        assert_eq!(pond(&w, 15, 19, 12, true, 30).cells, 30);
    }

    #[test]
    fn honey_counts_half_again_and_lava_is_flagged() {
        let h = pond(&pond_world(LIQ_HONEY), 15, 19, 12, true, 10000);
        assert_eq!((h.cells, h.honey), (72, true));
        assert!(pond(&pond_world(LIQ_LAVA), 15, 19, 12, true, 10000).lava);
    }
}
