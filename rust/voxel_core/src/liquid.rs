//! Terraria-style finite liquids. Each cell holds 0..=LIQ_MAX of water, lava
//! or honey; volume is conserved as it falls and levels out sideways. Only
//! "active" cells (recently changed, or next to a change) are simulated, so
//! settled pools cost nothing. Two liquids meeting make a block, as in
//! Terraria (Liquid.GetLiquidMergeTypes): water and lava obsidian (where the
//! lava was), water and honey a honey block (where the honey was), lava and
//! honey crispy honey (where the lava was).

use crate::world::{LIQ_HONEY, LIQ_LAVA, LIQ_MAX, LIQ_NONE, LIQ_WATER, World};

const SIDES: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];
/// Lava only moves every Nth tick and needs a bigger level difference to spread.
const LAVA_TICKS: u64 = 3;
/// Honey moves about half as often again (Terraria: lava every 6th update,
/// honey every 11th) and spreads like lava.
const HONEY_TICKS: u64 = 6;
/// Liquid at or below this amount that can't go anywhere slowly evaporates.
const PUDDLE: u8 = 2;
/// A cell needs at least this much to harden into a block when liquids meet.
const OBSIDIAN_MIN: u8 = 12;

/// The blocks liquids make when they meet.
#[derive(Clone, Copy)]
struct Merge {
    obsidian: u16,
    honey_block: u16,
    crispy_honey: u16,
}

impl Merge {
    /// Which of two liquids hardens, and into what block (0: none here).
    fn of(&self, a: u8, b: u8) -> (u8, u16) {
        let has = |t: u8| a == t || b == t;
        if has(LIQ_LAVA) && has(LIQ_WATER) {
            (LIQ_LAVA, self.obsidian)
        } else if has(LIQ_LAVA) && has(LIQ_HONEY) {
            (LIQ_LAVA, self.crispy_honey)
        } else {
            (LIQ_HONEY, self.honey_block)
        }
    }
}

impl World {
    /// Advances the liquid simulation one tick, processing at most `max_cells`
    /// active cells. Returns how many cells remain active.
    pub fn step_liquids(&mut self, max_cells: usize) -> usize {
        self.liquid_tick += 1;
        let mut cells: Vec<(i32, i32, i32)> = self.liquid_active.drain().collect();
        // Bottom-up so falling liquid moves through a column in one tick; the
        // full key keeps the simulation deterministic (the set's own order
        // changes from run to run).
        cells.sort_unstable_by_key(|c| (c.1, c.2, c.0));
        if cells.len() > max_cells {
            for c in cells.drain(max_cells..) {
                self.liquid_active.insert(c);
            }
        }
        let merge = Merge { obsidian: self.id_of("obsidian"), honey_block: self.id_of("honey_block"), crispy_honey: self.id_of("crispy_honey_block") };
        for (x, y, z) in cells {
            self.update_liquid_cell(x, y, z, merge);
        }
        self.liquid_active.len()
    }

    fn update_liquid_cell(&mut self, x: i32, y: i32, z: i32, merge: Merge) {
        let (t, mut a) = self.liquid_at(x, y, z);
        if a == 0 {
            return;
        }
        if self.is_solid(x, y, z) {
            self.set_liquid(x, y, z, LIQ_NONE, 0);
            return;
        }
        if (t == LIQ_LAVA && self.liquid_tick % LAVA_TICKS != 0) || (t == LIQ_HONEY && self.liquid_tick % HONEY_TICKS != 0) {
            self.liquid_active.insert((x, y, z));
            return;
        }

        // Two liquids touching: one hardens (or fizzles if it's a trickle).
        for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
            let (nx, ny, nz) = (x + dx, y + dy, z + dz);
            let (nt, na) = self.liquid_at(nx, ny, nz);
            if na == 0 || nt == t {
                continue;
            }
            let (hard, block) = merge.of(t, nt);
            let (lx, ly, lz, la) = if t == hard { (x, y, z, a) } else { (nx, ny, nz, na) };
            self.set_liquid(lx, ly, lz, LIQ_NONE, 0);
            if la >= OBSIDIAN_MIN && block != 0 {
                self.set(lx, ly, lz, block);
            }
            if t == hard {
                return;
            }
        }

        let mut changed = false;
        // 1. Fall.
        if self.in_bounds(x, y - 1, z) && !self.is_solid(x, y - 1, z) {
            let (bt, ba) = self.liquid_at(x, y - 1, z);
            if ba == 0 || bt == t {
                let moved = a.min(LIQ_MAX - ba);
                if moved > 0 {
                    self.set_liquid(x, y - 1, z, t, ba + moved);
                    a -= moved;
                    changed = true;
                }
            }
        }

        // 2. Level out with lower horizontal neighbours.
        if a > 0 {
            let threshold = if t == LIQ_WATER { 2 } else { 4 };
            let mut targets: Vec<(i32, i32, u8)> = Vec::with_capacity(4);
            for (dx, dz) in SIDES {
                let (nx, nz) = (x + dx, z + dz);
                if !self.in_bounds(nx, y, nz) || self.is_solid(nx, y, nz) {
                    continue;
                }
                let (nt, na) = self.liquid_at(nx, y, nz);
                if (na == 0 || nt == t) && na + threshold <= a {
                    targets.push((nx, nz, na));
                }
            }
            if !targets.is_empty() {
                // Equal shares; leftover units go to the neighbours one each
                // (keeping them here would leave this cell perpetually higher).
                let total: u32 = a as u32 + targets.iter().map(|t| t.2 as u32).sum::<u32>();
                let n = targets.len() as u32 + 1;
                let share = (total / n) as u8;
                let mut rest = (total % n) as u8;
                for &(nx, nz, na) in &targets {
                    let v = share + if rest > 0 { rest -= 1; 1 } else { 0 };
                    if v != na {
                        self.set_liquid(nx, y, nz, t, v);
                        changed = true;
                    }
                }
                if share != a {
                    a = share;
                    changed = true;
                }
            }
        }

        // 3. Puddles that can't flow anywhere evaporate over time.
        if !changed && a <= PUDDLE {
            let r = (x as u64).wrapping_mul(73856093) ^ (z as u64).wrapping_mul(19349663) ^ self.liquid_tick.wrapping_mul(83492791);
            if r % 16 == 0 {
                a = 0;
                changed = true;
            } else {
                self.liquid_active.insert((x, y, z));
            }
        }

        if changed {
            self.set_liquid(x, y, z, t, a);
            self.liquid_active.insert((x, y, z));
        }
    }

    /// Fills the basin reachable from `seed` (through empty cells at or below
    /// `level`) with liquid, but only if it is fully enclosed below that level
    /// and no bigger than `max_cells`, so generated pools don't drain on load.
    pub fn fill_basin(&mut self, seed: (i32, i32, i32), level: i32, t: u8, max_cells: usize) -> usize {
        let (sx, sy, sz) = seed;
        if !self.in_bounds(sx, sy, sz) || sy > level || self.get(sx, sy, sz) != 0 {
            return 0;
        }
        let mut seen = std::collections::HashSet::new();
        let mut stack = vec![seed];
        seen.insert(seed);
        while let Some((x, y, z)) = stack.pop() {
            for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1), (0, 1, 0)] {
                let (nx, ny, nz) = (x + dx, y + dy, z + dz);
                if ny > level || seen.contains(&(nx, ny, nz)) {
                    continue;
                }
                if !self.in_bounds(nx, ny, nz) {
                    return 0; // would leak out of the world
                }
                let b = self.get(nx, ny, nz);
                if b != 0 {
                    if !self.is_solid(nx, ny, nz) {
                        return 0; // plants/torches would let it leak; skip this spot
                    }
                    continue;
                }
                seen.insert((nx, ny, nz));
                if seen.len() > max_cells {
                    return 0;
                }
                stack.push((nx, ny, nz));
            }
        }
        for &(x, y, z) in &seen {
            let i = self.idx(x, y, z);
            self.liquid[i] = crate::world::liq_pack(t, LIQ_MAX);
        }
        seen.len()
    }

    /// After loading: wakes liquid that may still be flowing (partly filled cells
    /// or cells over empty space). Full, supported cells inside pools stay asleep.
    pub fn activate_unsettled_liquid(&mut self) {
        let (sx, sy) = (self.sx, self.sy);
        for i in 0..self.liquid.len() {
            let (_, a) = crate::world::liq_unpack(self.liquid[i]);
            if a == 0 {
                continue;
            }
            let y = (i % sy as usize) as i32;
            let col = (i / sy as usize) as i32;
            let (x, z) = (col % sx, col / sx);
            let below_open = y > 0 && !self.is_solid(x, y - 1, z) && self.liquid_at(x, y - 1, z).1 < LIQ_MAX;
            if a < LIQ_MAX || below_open {
                self.liquid_active.insert((x, y, z));
            }
        }
    }

    /// Total liquid volume of a type (tests and debugging).
    pub fn liquid_volume(&self, t: u8) -> u64 {
        self.liquid
            .iter()
            .map(|&v| crate::world::liq_unpack(v))
            .filter(|&(lt, _)| lt == t)
            .map(|(_, a)| a as u64)
            .sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{BlockDef, LIQ_WATER, RENDER_CUBE, unpack_light};

    fn world() -> World {
        let mut w = crate::world::tests::test_world(); // stone up to y=31, torch id 2
        w.set_def(3, BlockDef { name: "obsidian".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        w
    }

    fn settle(w: &mut World, ticks: usize) {
        for _ in 0..ticks {
            if w.step_liquids(100_000) == 0 {
                break;
            }
        }
    }

    /// A 5x5 pit 3 deep with its floor at y=29.
    fn dig_pit(w: &mut World) {
        for x in 10..15 {
            for z in 10..15 {
                for y in 29..32 {
                    w.set(x, y, z, 0);
                }
            }
        }
    }

    #[test]
    fn water_falls_spreads_and_conserves_volume() {
        let mut w = world();
        dig_pit(&mut w);
        w.set_liquid(12, 40, 12, LIQ_WATER, LIQ_MAX);
        w.set_liquid(12, 41, 12, LIQ_WATER, LIQ_MAX);
        let before = w.liquid_volume(LIQ_WATER);
        settle(&mut w, 2000);
        assert_eq!(w.step_liquids(100_000), 0, "pool settles");
        // Fell into the pit and levelled out across its floor.
        assert_eq!(w.liquid_at(12, 40, 12).1, 0);
        let floor: Vec<u8> = (10..15).flat_map(|x| (10..15).map(move |z| (x, z))).map(|(x, z)| w.liquid_at(x, 29, z).1).collect();
        assert!(floor.iter().all(|&a| a > 0), "spread over the whole floor: {floor:?}");
        let (lo, hi) = (*floor.iter().min().unwrap(), *floor.iter().max().unwrap());
        assert!(hi - lo <= 2, "level surface: {lo}..{hi}");
        assert_eq!(w.liquid_volume(LIQ_WATER), before, "volume conserved");
    }

    #[test]
    fn water_pours_off_ledges() {
        let mut w = world();
        // Shelf at y=32 over open ground at x>=20.
        for x in 10..20 {
            w.set(x, 32, 10, 1);
        }
        w.set_liquid(15, 33, 10, LIQ_WATER, LIQ_MAX);
        settle(&mut w, 3000);
        let on_ground: u64 = (20..40).map(|x| w.liquid_at(x, 32, 10).1 as u64).sum::<u64>()
            + (0..10).map(|x| w.liquid_at(x, 32, 10).1 as u64).sum::<u64>();
        assert!(on_ground > 0 || w.liquid_volume(LIQ_WATER) < LIQ_MAX as u64, "water left the shelf");
    }

    #[test]
    fn lava_glows_and_water_turns_it_to_obsidian() {
        let mut w = world();
        dig_pit(&mut w);
        w.set_liquid(10, 29, 10, LIQ_LAVA, LIQ_MAX);
        assert_eq!(unpack_light(w.light_at(12, 29, 10))[1], LAVA_EMIT_R - 2);
        w.set_liquid(11, 29, 10, LIQ_WATER, LIQ_MAX);
        settle(&mut w, 50);
        assert_eq!(w.get(10, 29, 10), 3, "lava became obsidian");
        assert_eq!(w.liquid_at(10, 29, 10).1, 0);
        assert_eq!(unpack_light(w.light_at(12, 29, 10))[1], 0, "glow removed");
    }

    const LAVA_EMIT_R: u8 = crate::world::LAVA_EMIT[0];

    #[test]
    fn honey_meeting_water_or_lava_makes_honey_blocks_or_crispy_honey() {
        use crate::world::LIQ_HONEY;
        let mut w = world();
        w.set_def(4, BlockDef { name: "honey_block".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        w.set_def(5, BlockDef { name: "crispy_honey_block".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        dig_pit(&mut w);
        w.set_liquid(10, 29, 10, LIQ_HONEY, LIQ_MAX);
        w.set_liquid(11, 29, 10, LIQ_WATER, LIQ_MAX);
        w.set_liquid(14, 29, 14, LIQ_HONEY, LIQ_MAX);
        w.set_liquid(13, 29, 14, LIQ_LAVA, LIQ_MAX);
        settle(&mut w, 60);
        assert_eq!(w.get(10, 29, 10), 4, "honey and water: a honey block where the honey was");
        assert_eq!(w.get(13, 29, 14), 5, "honey and lava: crispy honey where the lava was");
    }

    #[test]
    fn honey_flows_slower_than_water() {
        use crate::world::LIQ_HONEY;
        let mut w = world();
        dig_pit(&mut w);
        let mut v = world();
        dig_pit(&mut v);
        w.set_liquid(10, 29, 10, LIQ_WATER, LIQ_MAX);
        v.set_liquid(10, 29, 10, LIQ_HONEY, LIQ_MAX);
        for _ in 0..12 {
            w.step_liquids(100_000);
            v.step_liquids(100_000);
        }
        let spread = |w: &World| (10..15).flat_map(|x| (10..15).map(move |z| (x, z))).filter(|&(x, z)| w.liquid_at(x, 29, z).1 > 0).count();
        assert!(spread(&v) < spread(&w), "honey {} cells, water {}", spread(&v), spread(&w));
    }

    #[test]
    fn placing_a_block_displaces_liquid_and_digging_releases_it() {
        let mut w = world();
        dig_pit(&mut w);
        assert_eq!(w.fill_basin((12, 29, 12), 30, LIQ_WATER, 1000), 50);
        assert_eq!(w.step_liquids(100_000), 0, "generated pools start settled");
        w.set(12, 30, 12, 1);
        assert_eq!(w.liquid_at(12, 30, 12).1, 0);
        // Open the pit wall: water starts flowing again.
        w.set(15, 30, 12, 0);
        assert!(w.step_liquids(100_000) > 0);
    }

    #[test]
    fn basins_that_would_leak_are_rejected() {
        let mut w = world();
        dig_pit(&mut w);
        // Level above the pit rim: the region reaches open air and is too large.
        assert_eq!(w.fill_basin((12, 29, 12), 33, LIQ_WATER, 500), 0);
    }
}

