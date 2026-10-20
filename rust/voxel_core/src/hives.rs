//! Terraria's bee hives (its Hives pass: HiveBiome and HoneyPatchBiome, then
//! the Larva pass), in 3D.
//!
//! - Terraria makes 1 + 5-7 (x maxTilesX / 4200) hives, each at a random spot
//!   from halfway between the surface and the cavern layer down to 100 tiles
//!   above the Underworld, kept only where the ground within 15 tiles is at
//!   least three quarters mud and jungle grass (with some jungle grass), not
//!   overlapping another structure, not within 150 tiles of the world's evil
//!   (its walls; the temple isn't in this game). Its worlds are a 2D slice,
//!   so here that many go in each 640 x 640 blocks of the map (as the cabins
//!   do), all in the Jungle, where they can be.
//! - A hive is 2-4 steps; each step is 2-4 tunnels from the same point, the
//!   last one's end the next step's start (and a honey cube's spot). A
//!   tunnel is 10-20 balls 12-20 tiles across (each 20% bigger or smaller),
//!   drifting a random way that turns a little each ball: inside 40% of a
//!   ball it's hollow, out to 75% hive blocks (not where another ball
//!   hollowed it out), and a third of the hollow fills with honey, which
//!   settles to the bottom (here it's laid down settled). A tunnel stops
//!   near the world's edge, 50 tiles above the Underworld, or before it
//!   would break out of the ground.
//! - From each step's end, along a random way across, the first spot in
//!   solid hive takes a honey cube: 4 hive blocks a side round 2 of honey.
//! - The larva stands at the hive's last end, on a 3 x 3 floor of hive with
//!   3 blocks clear above (here above the honey). Its 100-tile box round the
//!   hive is kept from the structures after it.
//! - Up to 4 honey patches round each hive, 30-90 tiles out: where the ground
//!   is jungle too, a ball of the ground 8 tiles round turns to honey blocks
//!   (fewer further out), with a little pool of honey in it, mud under it.
//!
//! Terraria's tiles are 2/3 of a block here (the player's own scale).

use crate::world::{liq_pack, liq_unpack, World, LIQ_HONEY, LIQ_MAX, LIQ_NONE};
use crate::worldgen::{biome_regions, Layers, Rng, BIOME_JUNGLE};

type P = (i32, i32, i32);
type V = (f64, f64, f64);

/// A Terraria tile, in blocks.
pub const TILE: f64 = 2.0 / 3.0;

pub struct Ids {
    hive: u16,
    honey_block: u16,
    mud: u16,
    jungle_grass: u16,
    larva: u16,
    /// The world's evil stone (hives keep 150 tiles from it).
    evil: Vec<u16>,
}

impl Ids {
    pub fn new(w: &World) -> Self {
        Ids {
            hive: w.id_of("hive"),
            honey_block: w.id_of("honey_block"),
            mud: w.id_of("mud"),
            jungle_grass: w.id_of("jungle_grass"),
            larva: w.id_of("larva"),
            evil: ["ebonstone", "crimstone"].iter().map(|n| w.id_of(n)).filter(|&b| b != 0).collect(),
        }
    }
}

/// The world's hives and honey patches. Returns each hive's larva.
pub fn hives(w: &mut World, rng: &mut Rng, l: &Layers) -> Vec<P> {
    let ids = Ids::new(w);
    let mut larvae = Vec::new();
    if ids.hive == 0 || ids.mud == 0 {
        return larvae;
    }
    let Some(&(_, jx, jz, jr)) = biome_regions(w.sx, w.sz, w.seed).iter().find(|r| r.0 == BIOME_JUNGLE) else { return larvae };
    let k = w.sx.min(w.sz) as f64 / 768.0;
    let per_world = 1 + rng.range((5.0 * k) as i32, (8.0 * k) as i32);
    let want = (per_world as f64 * w.sx as f64 * w.sz as f64 / (640.0 * 640.0)).round() as usize;
    let (y_lo, y_hi) = (crate::dungeon::depth_y(l, 610.0), crate::dungeon::depth_y(l, 65.0));
    for _ in 0..10_000 {
        if larvae.len() >= want {
            break;
        }
        // A spot in the Jungle (Terraria tries the whole world; only the
        // Jungle passes).
        let a = rng.unit() * std::f64::consts::TAU;
        let d = rng.unit().sqrt() * jr as f64;
        let at = (jx + (a.cos() * d) as i32, rng.range(y_lo, y_hi.max(y_lo + 1)), jz + (a.sin() * d) as i32);
        let Some(larva) = hive_at(w, rng, &ids, l, at, false, 1.0) else { continue };
        larvae.push(larva);
        // Honey patches round it.
        let patches = rng.range(0, 5);
        let (mut made, mut tries) = (0, 10_000);
        while made < patches && tries > 0 {
            tries -= 1;
            let dist = (rng.unit() * 60.0 + 30.0) * TILE;
            let (up, around) = (rng.unit() * std::f64::consts::TAU, rng.unit() * std::f64::consts::TAU);
            let p = (at.0 + (up.cos() * around.cos() * dist) as i32, at.1 + (up.sin() * dist) as i32, at.2 + (up.cos() * around.sin() * dist) as i32);
            if honey_patch(w, rng, &ids, l, p) {
                made += 1;
            }
        }
    }
    larvae
}

/// HiveBiome.Place at `at`: the hive, its honey and its larva; `force` skips
/// the checks of where it can go (the test world's), `scale` sizes its balls.
/// Returns the larva's cell, or None if it can't go there.
pub fn hive_at(w: &mut World, rng: &mut Rng, ids: &Ids, l: &Layers, at: P, force: bool, scale: f64) -> Option<P> {
    let half = (50.0 * TILE) as i32;
    let bx = ((at.0 - half, at.1 - half, at.2 - half), (at.0 + half, at.1 + half, at.2 + half));
    if !force && (overlaps_structure(w, bx) || !jungle_ground(w, ids, at) || near_evil(w, ids, at)) {
        return None;
    }
    let mut hollow = vec![false; w.blocks.len()];
    let mut cells: Vec<usize> = Vec::new();
    let mut tops = Tops(vec![i32::MIN; (w.sx * w.sz) as usize]);
    let mut pos: V = (at.0 as f64, at.1 as f64, at.2 as f64);
    let mut ends = Vec::new();
    for _ in 0..rng.range(2, 5) {
        let mut last = pos;
        for _ in 0..rng.range(2, 5) {
            last = tunnel(w, rng, ids, l, pos, scale, &mut tops, &mut hollow, &mut cells);
        }
        pos = last;
        ends.push(pos);
    }
    settle_honey(w, &cells);
    for &e in &ends {
        honey_cube(w, rng, ids, (e.0 as i32, e.1 as i32, e.2 as i32));
    }
    let larva = larva_stand(w, ids, &hollow, (pos.0 as i32, pos.1 as i32, pos.2 as i32));
    if !force {
        w.structures.push(bx);
    }
    Some(larva)
}

fn overlaps_structure(w: &World, (lo, hi): (P, P)) -> bool {
    w.structures.iter().any(|&(a, b)| lo.0 <= b.0 && a.0 <= hi.0 && lo.1 <= b.1 && a.1 <= hi.1 && lo.2 <= b.2 && a.2 <= hi.2)
}

/// Terraria's check: of the solid ground within 15 tiles, three quarters mud
/// or jungle grass, and at least two jungle grass.
fn jungle_ground(w: &World, ids: &Ids, at: P) -> bool {
    let r = 15.0 * TILE;
    let ri = r.ceil() as i32;
    let (mut solid, mut jungle, mut grass) = (0, 0, 0);
    for dx in -ri..=ri {
        for dy in -ri..=ri {
            for dz in -ri..=ri {
                if ((dx * dx + dy * dy + dz * dz) as f64) > r * r {
                    continue;
                }
                let (x, y, z) = (at.0 + dx, at.1 + dy, at.2 + dz);
                if !w.in_bounds(x, y, z) || !w.is_solid(x, y, z) {
                    continue;
                }
                solid += 1;
                let b = w.get(x, y, z);
                if b == ids.mud || b == ids.jungle_grass {
                    jungle += 1;
                }
                if b == ids.jungle_grass {
                    grass += 1;
                }
            }
        }
    }
    solid > 0 && jungle as f64 / solid as f64 >= 0.75 && grass >= 2
}

/// Any of the world's evil within 150 tiles (Terraria looks every 10).
fn near_evil(w: &World, ids: &Ids, at: P) -> bool {
    let r = (150.0 * TILE) as i32;
    let step = (10.0 * TILE) as usize;
    for dx in (-r..=r).step_by(step) {
        for dy in (-r..=r).step_by(step) {
            for dz in (-r..=r).step_by(step) {
                let (x, y, z) = (at.0 + dx, at.1 + dy, at.2 + dz);
                if w.in_bounds(x, y, z) && ids.evil.contains(&w.get(x, y, z)) {
                    return true;
                }
            }
        }
    }
    false
}

/// HiveBiome.CreateHiveTunnel from `start`: returns where it ended. Hollowed
/// cells are marked in `hollow` (and listed in `cells`).
/// Each column's surface (its topmost solid block), looked up once.
struct Tops(Vec<i32>);

impl Tops {
    fn get(&mut self, w: &World, x: i32, z: i32) -> i32 {
        let i = (z * w.sx + x) as usize;
        if self.0[i] == i32::MIN {
            self.0[i] = w.surface_y(x, z);
        }
        self.0[i]
    }
}

#[allow(clippy::too_many_arguments)]
fn tunnel(w: &mut World, rng: &mut Rng, ids: &Ids, l: &Layers, start: V, scale: f64, tops: &mut Tops, hollow: &mut [bool], cells: &mut Vec<usize>) -> V {
    let base = rng.range(12, 21) as f64;
    let mut size = base;
    let mut steps = rng.range(10, 21);
    let mut pos = start;
    let mut vel = (rng.range(-10, 11) as f64 * 0.2, rng.range(-10, 11) as f64 * 0.2, rng.range(-10, 11) as f64 * 0.2);
    let floor = crate::dungeon::depth_y(l, 660.0);
    let margin = 10;
    while size > 0.0 && steps > 0 {
        if pos.1 < floor as f64 {
            steps = 0;
        }
        size = base * (1.0 + rng.range(-20, 20) as f64 * 0.01);
        steps -= 1;
        let r = size * TILE * scale;
        let ri = r.ceil() as i32;
        let (cx, cy, cz) = (pos.0 as i32, pos.1 as i32, pos.2 as i32);
        for x in cx - ri..=cx + ri {
            for z in cz - ri..=cz + ri {
                if x < margin || z < margin || x >= w.sx - margin || z >= w.sz - margin {
                    steps = 0;
                    continue;
                }
                // Not out of the ground: stop short of the surface.
                let top = tops.get(w, x, z) - 4;
                for y in (cy - ri).max(2)..=(cy + ri).min(w.sy - 2) {
                    if y >= top {
                        steps = 0;
                        continue;
                    }
                    let d = (((x as f64 - pos.0).powi(2) + (y as f64 - pos.1).powi(2) + (z as f64 - pos.2).powi(2))).sqrt();
                    let i = w.idx(x, y, z);
                    if d < r * 0.4 * jitter(rng) {
                        w.blocks[i] = 0;
                        if !hollow[i] {
                            hollow[i] = true;
                            cells.push(i);
                        }
                    } else if d < r * 0.75 * jitter(rng) {
                        if !hollow[i] {
                            w.blocks[i] = ids.hive;
                            w.liquid[i] = 0;
                        }
                    }
                }
            }
        }
        pos = (pos.0 + vel.0 * TILE * scale, pos.1 + vel.1 * TILE * scale, pos.2 + vel.2 * TILE * scale);
        vel = (vel.0 + rng.range(-10, 11) as f64 * 0.05, vel.1 + rng.range(-10, 11) as f64 * 0.05, vel.2 + rng.range(-10, 11) as f64 * 0.05);
    }
    pos
}

/// Terraria's 1 + Next(-10, 11) * 0.005.
fn jitter(rng: &mut Rng) -> f64 {
    1.0 + rng.range(-10, 11) as f64 * 0.005
}

/// A third of the hollow fills with honey (and any liquid already in it turns
/// to honey), laid down as it would settle: from the lowest hollow cells up.
fn settle_honey(w: &mut World, cells: &[usize]) {
    let sy = w.sy as usize;
    let mut open: Vec<usize> = cells.iter().copied().filter(|&i| w.blocks[i] == 0).collect();
    let extra: usize = open.iter().map(|&i| liq_unpack(w.liquid[i]).1 as usize).sum::<usize>() / LIQ_MAX as usize;
    for &i in &open {
        w.liquid[i] = 0;
    }
    let mut left = open.len() / 3 + extra;
    open.sort_unstable_by_key(|&i| (i % sy, i));
    for i in open {
        if left == 0 {
            break;
        }
        w.liquid[i] = liq_pack(LIQ_HONEY, LIQ_MAX);
        left -= 1;
    }
}

/// HiveBiome's honey cube from a step's end: along a random way across, the
/// first spot with 2 x 2 x 2 solid, one on; there, if the 4 x 4 x 4 round it
/// is only hive (or open), hive blocks round 2 x 2 x 2 honey.
fn honey_cube(w: &mut World, rng: &mut Rng, ids: &Ids, from: P) {
    let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    let (dx, dz) = dirs[rng.range(0, 4) as usize];
    let (mut x, y, mut z) = from;
    let solid2 = |w: &World, x: i32, y: i32, z: i32| (0..2).all(|a| (0..2).all(|b| (0..2).all(|c| w.is_solid(x + a, y + b, z + c))));
    let reach = (50.0 * TILE) as i32;
    let mut n = 0;
    while !solid2(w, x, y, z) {
        x += dx;
        z += dz;
        n += 1;
        if n > reach || !w.in_bounds(x, y, z) {
            return;
        }
    }
    x += dx;
    z += dz;
    for a in -1..3 {
        for b in -1..3 {
            for c in -1..3 {
                let (px, py, pz) = (x + a, y + b, z + c);
                if !w.in_bounds(px, py, pz) || (w.get(px, py, pz) != 0 && w.get(px, py, pz) != ids.hive) {
                    return;
                }
            }
        }
    }
    for a in -1..3 {
        for b in -1..3 {
            for c in -1..3 {
                let i = w.idx(x + a, y + b, z + c);
                if (0..2).contains(&a) && (0..2).contains(&b) && (0..2).contains(&c) {
                    w.blocks[i] = 0;
                    w.liquid[i] = liq_pack(LIQ_HONEY, LIQ_MAX);
                } else {
                    w.blocks[i] = ids.hive;
                    w.liquid[i] = 0;
                }
            }
        }
    }
}

/// HiveBiome.CreateStandForLarva at the hive's last end (moved into its
/// hollow, and up out of the honey): a 3 x 3 hive floor, 3 x 3 x 3 clear above
/// it, the larva on it. Returns the larva's cell.
fn larva_stand(w: &mut World, ids: &Ids, hollow: &[bool], end: P) -> P {
    let mut p = end;
    // Into the hollow: the nearest hollowed cell.
    if !w.in_bounds(p.0, p.1, p.2) || !hollow[w.idx(p.0, p.1, p.2)] {
        'find: for r in 1..12 {
            for dx in -r..=r {
                for dy in -r..=r {
                    for dz in -r..=r {
                        let q = (end.0 + dx, end.1 + dy, end.2 + dz);
                        if w.in_bounds(q.0, q.1, q.2) && hollow[w.idx(q.0, q.1, q.2)] {
                            p = q;
                            break 'find;
                        }
                    }
                }
            }
        }
    }
    // Up out of the honey: no honey round it at its height.
    let wet = |w: &World, (x, y, z): P| (-2..=2).any(|a| (-2..=2).any(|c| w.liquid_at(x + a, y, z + c).1 > 0));
    while p.1 < w.sy - 4 && wet(w, p) {
        p.1 += 1;
    }
    let (x, y, z) = p;
    for a in -1..=1 {
        for c in -1..=1 {
            if !w.in_bounds(x + a, y - 1, z + c) {
                continue;
            }
            let i = w.idx(x + a, y - 1, z + c);
            w.blocks[i] = ids.hive;
            w.liquid[i] = 0;
            for b in 0..3 {
                if w.in_bounds(x + a, y + b, z + c) {
                    let j = w.idx(x + a, y + b, z + c);
                    w.blocks[j] = 0;
                    w.liquid[j] = 0;
                }
            }
        }
    }
    if ids.larva != 0 {
        let i = w.idx(x, y, z);
        w.blocks[i] = ids.larva;
    }
    // (No honey left hanging over the clearing.)
    for a in -1..=1 {
        for c in -1..=1 {
            let mut b = 3;
            while w.in_bounds(x + a, y + b, z + c) && w.liquid_at(x + a, y + b, z + c).1 > 0 {
                let j = w.idx(x + a, y + b, z + c);
                w.liquid[j] = 0;
                b += 1;
            }
        }
    }
    p
}

/// HoneyPatchBiome.Place at `at`: on the ground below it (a block in), where
/// that's jungle too, honey blocks in a ball of the ground 8 tiles round
/// (fewer the further out), and a little pool of honey (4 tiles across, 3
/// deep) with mud under it and honey blocks round it. False if it can't go
/// there.
pub fn honey_patch(w: &mut World, rng: &mut Rng, ids: &Ids, l: &Layers, at: P) -> bool {
    if !w.in_bounds(at.0, at.1, at.2) || w.is_solid(at.0, at.1, at.2) || ids.honey_block == 0 {
        return false;
    }
    let mut y = at.1;
    let lowest = at.1 - (80.0 * TILE) as i32;
    while y > lowest.max(1) && !w.is_solid(at.0, y, at.2) {
        y -= 1;
    }
    if !w.is_solid(at.0, y, at.2) {
        return false;
    }
    let c = (at.0, y - 1, at.2);
    if c.1 < crate::dungeon::depth_y(l, 680.0) || !jungle_ground(w, ids, c) {
        return false;
    }
    let r = 8.0 * TILE;
    let ri = r.ceil() as i32;
    let ball = |d2: i32| (d2 as f64) <= r * r;
    let (mut solid, mut all) = (0, 0);
    for dx in -ri..=ri {
        for dy in -ri..=ri {
            for dz in -ri..=ri {
                if ball(dx * dx + dy * dy + dz * dz) {
                    all += 1;
                    if w.is_solid(c.0 + dx, c.1 + dy, c.2 + dz) {
                        solid += 1;
                    }
                }
            }
        }
    }
    // Terraria: 20 of its circle's ~200 tiles solid.
    if solid * 10 < all {
        return false;
    }
    let half = (8.0 * TILE) as i32;
    let bx = ((c.0 - half, c.1 - half, c.2 - half), (c.0 + half, c.1 + half, c.2 + half));
    if overlaps_structure(w, bx) || near_evil(w, ids, c) {
        return false;
    }
    for dx in -ri..=ri {
        for dy in -ri..=ri {
            for dz in -ri..=ri {
                let d2 = dx * dx + dy * dy + dz * dz;
                let (x, y, z) = (c.0 + dx, c.1 + dy, c.2 + dz);
                if !ball(d2) || !w.in_bounds(x, y, z) || !w.is_solid(x, y, z) {
                    continue;
                }
                // RadialDither(0, 10): kept less often further out.
                if rng.unit() > (d2 as f64).sqrt() / (10.0 * TILE) {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = ids.honey_block;
                }
            }
        }
    }
    // The pool: the lower half of a ball 4 tiles across, 3 deep.
    let (pw, ph) = (4.0 * TILE, 3.0 * TILE);
    let (pwi, phi) = (pw.ceil() as i32, ph.ceil() as i32);
    let mut pool: Vec<P> = Vec::new();
    for dx in -pwi..=pwi {
        for dz in -pwi..=pwi {
            for dy in -phi..=0 {
                let e = (dx * dx + dz * dz) as f64 / (pw * pw) + (dy * dy) as f64 / (ph * ph);
                let (x, y, z) = (c.0 + dx, c.1 + dy, c.2 + dz);
                if e < 1.0 && w.in_bounds(x, y, z) {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 0;
                    w.liquid[i] = liq_pack(LIQ_HONEY, LIQ_MAX);
                    pool.push((x, y, z));
                }
            }
        }
    }
    // Mud under it, honey blocks round it (up to its rim).
    for &(x, y, z) in &pool {
        if w.in_bounds(x, y - 1, z) && !w.is_solid(x, y - 1, z) && !pool.contains(&(x, y - 1, z)) {
            let i = w.idx(x, y - 1, z);
            w.blocks[i] = ids.mud;
            w.liquid[i] = 0;
        }
        for a in -1..=1 {
            for b in -1..=0 {
                for d in -1..=1 {
                    let q = (x + a, y + b, z + d);
                    if !w.in_bounds(q.0, q.1, q.2) || q.1 > c.1 || pool.contains(&q) || w.is_solid(q.0, q.1, q.2) {
                        continue;
                    }
                    let i = w.idx(q.0, q.1, q.2);
                    if liq_unpack(w.liquid[i]).0 != LIQ_HONEY {
                        w.blocks[i] = ids.honey_block;
                        w.liquid[i] = liq_pack(LIQ_NONE, 0);
                    }
                }
            }
        }
    }
    w.structures.push(bx);
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE};

    /// A world of mud with jungle grass on a cave floor through it.
    fn jungle() -> World {
        let mut w = World::new();
        w.seed = 7;
        let cube = |n: &str| BlockDef { name: n.into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() };
        w.set_def(1, cube("mud"));
        w.set_def(2, cube("jungle_grass"));
        w.set_def(3, cube("hive"));
        w.set_def(4, cube("honey_block"));
        w.set_def(5, BlockDef { name: "larva".into(), render: RENDER_CROSS, solid: false, opaque: false, variants: 1, ..Default::default() });
        w.resize(96, 96, 96);
        for x in 0..96 {
            for z in 0..96 {
                for y in 0..90 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 1;
                }
                for y in 40..44 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 0;
                }
                let i = w.idx(x, 39, z);
                w.blocks[i] = 2;
            }
        }
        w
    }

    #[test]
    fn a_hive_has_its_shell_honey_and_larva() {
        let mut w = jungle();
        let ids = Ids::new(&w);
        let l = crate::worldgen::layers(w.sy);
        let mut rng = Rng::new(3);
        let larva = hive_at(&mut w, &mut rng, &ids, &l, (48, 40, 48), false, 0.6).expect("jungle ground takes a hive");
        assert_eq!(w.get(larva.0, larva.1, larva.2), ids.larva, "the larva");
        assert!((-1..=1).all(|a| (-1..=1).all(|c| w.get(larva.0 + a, larva.1 - 1, larva.2 + c) == ids.hive)), "on a 3 x 3 hive floor");
        assert!((0..3).all(|b| w.liquid_at(larva.0 + 1, larva.1 + b, larva.2).1 == 0 && w.get(larva.0 + 1, larva.1 + b, larva.2) == 0), "clear and dry round it");
        let hive = w.blocks.iter().filter(|&&b| b == ids.hive).count();
        let honey = w.liquid_volume(LIQ_HONEY) / LIQ_MAX as u64;
        assert!(hive > 500, "a shell of hive blocks ({hive})");
        assert!(honey > 30, "honey in it ({honey} cells)");
        // Laid down settled: every honey cell is full and rests on something.
        for x in 0..w.sx {
            for z in 0..w.sz {
                for y in 1..w.sy {
                    let (t, a) = w.liquid_at(x, y, z);
                    if t == LIQ_HONEY {
                        assert_eq!(a, LIQ_MAX);
                        assert!(w.is_solid(x, y - 1, z) || w.liquid_at(x, y - 1, z).1 > 0, "honey at {x},{y},{z} rests on something");
                    }
                }
            }
        }
        assert_eq!(w.structures.len(), 1, "its box is kept from later structures");
        assert!(hive_at(&mut w, &mut rng, &ids, &l, (50, 40, 50), false, 0.6).is_none(), "and no second hive in it");
    }

    #[test]
    fn hives_need_jungle_ground() {
        let mut w = jungle();
        for b in w.blocks.iter_mut() {
            if *b == 1 || *b == 2 {
                *b = 3; // all hive, no mud
            }
        }
        let ids = Ids::new(&w);
        let l = crate::worldgen::layers(w.sy);
        assert!(hive_at(&mut w, &mut Rng::new(1), &ids, &l, (48, 40, 48), false, 0.6).is_none());
    }

    #[test]
    fn a_honey_patch_is_honey_blocks_round_a_pool() {
        let mut w = jungle();
        let ids = Ids::new(&w);
        let l = crate::worldgen::layers(w.sy);
        assert!(honey_patch(&mut w, &mut Rng::new(5), &ids, &l, (48, 42, 48)));
        assert!(w.blocks.iter().filter(|&&b| b == ids.honey_block).count() > 40, "honey blocks");
        assert!(w.liquid_volume(LIQ_HONEY) > 0, "a pool of honey");
        let before = w.liquid_volume(LIQ_HONEY);
        for _ in 0..400 {
            w.step_liquids(100_000);
        }
        assert_eq!(w.liquid_volume(LIQ_HONEY), before, "it holds its honey");
    }
}
