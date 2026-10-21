//! Terraria's surface caves and tunnels, in 3D: its TileRunner (a blob that
//! wanders, shrinking from its strength to nothing over its steps, digging
//! out or heaping up the ground it covers), and the passes that use it on
//! the surface:
//!   SurfaceCaves  holes going down from the surface: many small ones (3-6
//!                 strong, 5-50 steps), fewer larger (10-15, 50-130), a few
//!                 huge (12-25, 150-500, with two more runners from the same
//!                 mouth), and straight shafts (7-12, 150-250, never turning
//!                 aside). Kept off the beaches and the middle of the world.
//!   MountainCaveOpenings  each mountain dug into: a tunnel from its middle
//!                 out through its side (CaveOpenater: 7-12 across, a little
//!                 uphill, until it breaks out into the open), then a cave
//!                 winding down into it from there (Cavinator: 7-15 across,
//!                 20-40 steps, sloping down).
//!   Tunnels       Terraria heaps dirt 11-16 tiles over the ground along a
//!                 path of 10 points 5-10 apart, which in its side view is a
//!                 tunnel under a bridge of dirt. Here: a dirt ridge heaped
//!                 along a winding path, a walkable tunnel bored through it.
//! Terraria's counts are per world width (its worlds are a slice); here they
//! go per 640 x 640 blocks of map, twice over (a 3D surface has far more
//! ground for them to hide in).

use crate::world::World;
use crate::worldgen::{Coast, Layers, Rng};

/// What a runner does to the cells it covers.
#[derive(Clone, Copy)]
pub enum Op {
    /// Dig them out (not liquid, not the cells `keep` says to keep).
    Dig,
    /// Fill the empty ones with this block.
    Add(u16),
}

/// Terraria's TileRunner in 3D. From `pos`, `steps` times: covers a ball
/// (strength x the steps left / steps across, its edge a little ragged),
/// moves by its velocity, and turns it a little (each part by up to 0.5 a
/// step, held within 1 a step; with `straight` the up-down part never turns,
/// though the velocity is still held within 1 once the ball is small).
/// Velocity in blocks a step (y up). `keep`: cells (x, y, z, block) a Dig
/// leaves alone.
pub fn runner(w: &mut World, rng: &mut Rng, pos: (f32, f32, f32), strength: f32, steps: i32, vel: (f32, f32, f32), straight: bool, op: Op, keep: &dyn Fn(i32, i32, i32, u16) -> bool) {
    let (mut p, mut v) = (pos, vel);
    let total = steps.max(1) as f32;
    let mut left = steps as f32;
    while left > 0.0 {
        let size = strength * (left / total);
        if size <= 0.0 {
            break;
        }
        left -= 1.0;
        ball(w, rng, p, size * 0.5, op, keep);
        p = (p.0 + v.0, p.1 + v.1, p.2 + v.2);
        let turn = |rng: &mut Rng| rng.range(-10, 11) as f32 * 0.05;
        v.0 = (v.0 + turn(rng)).clamp(-1.0, 1.0);
        v.2 = (v.2 + turn(rng)).clamp(-1.0, 1.0);
        if !straight {
            v.1 = (v.1 + turn(rng)).clamp(-1.0, 1.0);
        } else if size < 3.0 {
            v.1 = v.1.clamp(-1.0, 1.0);
        }
    }
}

/// One of a runner's balls: radius `r`, each cell's reach jittered by up to
/// 15% (Terraria's ragged edges).
fn ball(w: &mut World, rng: &mut Rng, c: (f32, f32, f32), r: f32, op: Op, keep: &dyn Fn(i32, i32, i32, u16) -> bool) {
    let n = r.ceil() as i32 + 1;
    let (cx, cy, cz) = (c.0.floor() as i32, c.1.floor() as i32, c.2.floor() as i32);
    for y in (cy - n).max(1)..=(cy + n).min(w.sy - 2) {
        for z in (cz - n).max(1)..=(cz + n).min(w.sz - 2) {
            for x in (cx - n).max(1)..=(cx + n).min(w.sx - 2) {
                let d = ((x as f32 + 0.5 - c.0).powi(2) + (y as f32 + 0.5 - c.1).powi(2) + (z as f32 + 0.5 - c.2).powi(2)).sqrt();
                if d >= r * (1.0 + rng.range(-10, 11) as f32 * 0.015) {
                    continue;
                }
                let i = w.idx(x, y, z);
                match op {
                    Op::Dig => {
                        let b = w.blocks[i];
                        if b != 0 && w.liquid[i] == 0 && !keep(x, y, z, b) {
                            w.blocks[i] = 0;
                        }
                    }
                    Op::Add(id) => {
                        if w.blocks[i] == 0 && w.liquid[i] == 0 {
                            w.blocks[i] = id;
                        }
                    }
                }
            }
        }
    }
}

/// A heading on the ground at random (a unit vector, x and z).
fn heading(rng: &mut Rng) -> (f32, f32) {
    let a = rng.range(0, 6283) as f32 / 1000.0;
    (a.cos(), a.sin())
}

/// How many of a thing Terraria puts `per_4200` of in a small world (4200
/// wide), for this world: per 640 x 640 blocks of map, twice over.
fn count(w: &World, per_4200: f32) -> usize {
    (per_4200 * 2.0 * (w.sx * w.sz) as f32 / (640.0 * 640.0)).round() as usize
}

/// Where a surface feature may start: inland of the beach by 20, and not in
/// the middle of the world (Terraria keeps them out of its middle 10-20%).
fn site_ok(w: &World, coast: &Coast, x: i32, z: i32, middle: f32) -> bool {
    let inland = coast.inland(x, z);
    let (mx, mz) = ((x - w.sx / 2) as f32, (z - w.sz / 2) as f32);
    inland > coast.ocean.width + coast.ocean.beach + 20.0 && (mx * mx + mz * mz).sqrt() > w.sx.min(w.sz) as f32 * middle
}

/// Terraria's SurfaceCaves pass.
pub fn surface_caves(w: &mut World, rng: &mut Rng, coast: &Coast, keep: &dyn Fn(i32, i32, i32, u16) -> bool) -> usize {
    // (count per 4200 columns, strength, steps, down speed, straight down)
    let kinds: [(f32, (i32, i32), (i32, i32), f32, bool); 4] = [
        (8.4, (3, 6), (5, 50), 1.0, false),
        (2.94, (10, 15), (50, 130), 2.0, false),
        (1.26, (12, 25), (150, 500), 4.0, false),
        (1.68, (7, 12), (150, 250), 1.0, true),
    ];
    let mut made = 0;
    for (k, &(per, strength, steps, down, straight)) in kinds.iter().enumerate() {
        for _ in 0..count(w, per) {
            let mut tries = 50;
            let (mut x, mut z) = (0, 0);
            while tries > 0 {
                tries -= 1;
                x = rng.range(1, w.sx - 1);
                z = rng.range(1, w.sz - 1);
                if site_ok(w, coast, x, z, if k == 0 { 0.05 } else { 0.07 }) {
                    break;
                }
            }
            if tries == 0 {
                continue;
            }
            let y = w.surface_y(x, z);
            if y < 2 {
                continue;
            }
            let start = (x as f32 + 0.5, y as f32 + 0.5, z as f32 + 0.5);
            let (hx, hz) = heading(rng);
            let side = if straight { 0.0 } else { rng.range(-10, 11) as f32 * 0.1 };
            let vel = (hx * side, -down, hz * side);
            let (s, n) = (rng.range(strength.0, strength.1 + 1) as f32, rng.range(steps.0, steps.1 + 1));
            runner(w, rng, start, s, n, vel, straight, Op::Dig, keep);
            if k == 2 {
                // The huge ones: two more from the same mouth.
                for &(s, n) in &[((8, 17), (60, 200)), ((5, 13), (40, 170))] {
                    let side = rng.range(-10, 11) as f32 * 0.1;
                    let (hx, hz) = heading(rng);
                    let (s, n) = (rng.range(s.0, s.1) as f32, rng.range(n.0, n.1));
                    runner(w, rng, start, s, n, (hx * side, -2.0, hz * side), false, Op::Dig, keep);
                }
            }
            made += 1;
        }
    }
    made
}

/// Terraria's MountainCaveOpenings, for each mountain peak (x, z): from
/// inside the mountain, a little below its top, a tunnel out through its side
/// and a cave winding down into it. Returns how many.
pub fn mountain_caves(w: &mut World, rng: &mut Rng, peaks: &[(i32, i32)], keep: &dyn Fn(i32, i32, i32, u16) -> bool) -> usize {
    let mut made = 0;
    for &(px, pz) in peaks {
        let top = w.surface_y(px, pz);
        if top < 12 {
            continue;
        }
        // CaveOpenater: from 8-14 under the top, outward (a little uphill)
        // until it's out in the open, 100 steps at most.
        let depth = rng.range(8, 15);
        let mut p = (px as f32 + 0.5, (top - depth) as f32, pz as f32 + 0.5);
        let start = p;
        let (hx, hz) = heading(rng);
        let mut v = (hx, 0.0f32, hz);
        let size = rng.range(7, 12) as f32;
        for _ in 0..100 {
            let r = size * rng.range(80, 120) as f32 * 0.01 * 0.4;
            ball(w, rng, p, r, Op::Dig, keep);
            p = (p.0 + v.0, p.1 + v.1, p.2 + v.2);
            let turn = |rng: &mut Rng| rng.range(-10, 11) as f32 * 0.05;
            v.0 = (v.0 + turn(rng)).clamp(hx - 0.5, hx + 0.5);
            v.2 = (v.2 + turn(rng)).clamp(hz - 0.5, hz + 0.5);
            v.1 = (v.1 + turn(rng)).clamp(0.0, 0.5);
            let (cx, cy, cz) = (p.0 as i32, p.1 as i32, p.2 as i32);
            if !w.in_bounds(cx, cy, cz) {
                break;
            }
            // Out in the open: nothing over it.
            if w.surface_y(cx, cz) < cy {
                break;
            }
        }
        // Cavinator: from the start, a cave winding down into the mountain.
        let (hx, hz) = heading(rng);
        let strength = rng.range(7, 15) as f32;
        let (n, down) = (rng.range(20, 40), rng.range(10, 20) as f32 * 0.01);
        runner(w, rng, start, strength * 0.8, n, (hx, -down, hz), false, Op::Dig, keep);
        made += 1;
    }
    made
}

/// Surface tunnels: a dirt ridge heaped up along a winding path of 10 points
/// 5-10 blocks apart, with a tunnel (about 4-5 blocks across, its floor at
/// the ground) bored along it. `dirt` heaps it, `ok` says whether a column
/// is ground to build on (not sand, as Terraria's go elsewhere when a point
/// lands on sand). Returns how many.
pub fn tunnels(w: &mut World, rng: &mut Rng, coast: &Coast, l: &Layers, dirt: u16, ok: &dyn Fn(u16) -> bool, keep: &dyn Fn(i32, i32, i32, u16) -> bool) -> usize {
    let mut made = 0;
    for _ in 0..count(w, 6.3) {
        for _try in 0..20 {
            let (mut x, mut z) = (rng.range(1, w.sx - 1) as f32, rng.range(1, w.sz - 1) as f32);
            if !site_ok(w, coast, x as i32, z as i32, 0.1) {
                continue;
            }
            let (mut hx, mut hz) = heading(rng);
            let mut points = Vec::new();
            let mut good = true;
            for _ in 0..10 {
                let (ix, iz) = (x as i32, z as i32);
                if !w.in_bounds(ix, 1, iz) || !site_ok(w, coast, ix, iz, 0.1) {
                    good = false;
                    break;
                }
                let y = w.surface_y(ix, iz);
                if y <= l.cavern_top || !ok(w.get(ix, y, iz)) {
                    good = false;
                    break;
                }
                points.push((x, y, z));
                let step = rng.range(5, 11) as f32;
                x += hx * step;
                z += hz * step;
                // A gentle bend.
                let a = rng.range(-35, 36) as f32 * 0.01;
                (hx, hz) = (hx * a.cos() - hz * a.sin(), hx * a.sin() + hz * a.cos());
            }
            if !good {
                continue;
            }
            // The ridge: balls of dirt on the ground along the path (and
            // between its points, so it's one piece).
            let mut route = Vec::new();
            for pair in points.windows(2) {
                let ((x0, y0, z0), (x1, y1, z1)) = (pair[0], pair[1]);
                let n = (((x1 - x0).powi(2) + (z1 - z0).powi(2)).sqrt() / 1.5).ceil().max(1.0) as i32;
                for k in 0..n {
                    let t = k as f32 / n as f32;
                    route.push((x0 + (x1 - x0) * t, y0 as f32 + (y1 - y0) as f32 * t, z0 + (z1 - z0) * t));
                }
            }
            let tall = rng.range(50, 75) as f32 * 0.1;
            for (k, &(x, y, z)) in route.iter().enumerate() {
                // Thinner toward its ends.
                let f = (k.min(route.len() - 1 - k) as f32 / 4.0).min(1.0);
                let r = 2.5 + (tall - 2.5) * f;
                ball(w, rng, (x, y + 1.0 + r * 0.45, z), r, Op::Add(dirt), &|_, _, _, _| false);
            }
            // The bore, its floor at the ground.
            for &(x, y, z) in &route {
                ball(w, rng, (x, y + 2.6, z), 2.3, Op::Dig, keep);
            }
            made += 1;
            break;
        }
    }
    made
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CUBE};
    use crate::worldgen::layers;

    /// A flat world of dirt (top at y 60) with stone below 40, 256 across.
    fn flat() -> World {
        let mut w = World::new();
        w.set_def(1, BlockDef { name: "dirt".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        w.set_def(2, BlockDef { name: "stone".into(), render: RENDER_CUBE, solid: true, opaque: true, variants: 1, ..Default::default() });
        w.resize(256, 128, 256);
        for z in 0..256 {
            for x in 0..256 {
                for y in 1..=60 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = if y < 40 { 2 } else { 1 };
                }
            }
        }
        w
    }

    #[test]
    fn a_runner_digs_a_shrinking_trail() {
        let mut w = flat();
        let mut rng = Rng::new(1);
        runner(&mut w, &mut rng, (128.0, 50.0, 128.0), 10.0, 30, (1.0, 0.0, 0.0), true, Op::Dig, &|_, _, _, _| false);
        // Its first ball (5 across) is out; it goes on along +x, narrower.
        assert!((-2..=2).all(|d| w.get(128 + d, 50, 128) == 0), "its first ball");
        // (It wanders a little sideways: count across each slice of x.)
        let dug = |x0: i32| (x0..x0 + 4).map(|x| (40..60).flat_map(|y| (100..156).map(move |z| (y, z))).filter(|&(y, z)| w.get(x, y, z) == 0).count()).sum::<usize>();
        assert!(dug(126) > dug(142) && dug(142) > 0, "{} then {}", dug(126), dug(142));
        // Never digs what it's told to keep.
        let mut w = flat();
        runner(&mut w, &mut rng, (128.0, 50.0, 128.0), 10.0, 10, (1.0, 0.0, 0.0), false, Op::Dig, &|_, _, _, b| b == 1);
        assert_eq!(w.get(128, 50, 128), 1);
    }

    #[test]
    fn surface_caves_go_down_from_the_surface() {
        let mut w = flat();
        let coast = Coast::new(3, w.sx, w.sy, w.sz);
        let n = surface_caves(&mut w, &mut Rng::new(3), &coast, &|_, _, _, _| false);
        assert!(n >= 4, "{n} caves");
        // Mouths in the ground, and some going deep (the shafts and big ones).
        let mouths = (0..256).flat_map(|x| (0..256).map(move |z| (x, z))).filter(|&(x, z)| w.get(x, 60, z) == 0).count();
        let deep = (0..256).flat_map(|x| (0..256).map(move |z| (x, z))).filter(|&(x, z)| (20..40).any(|y| w.get(x, y, z) == 0)).count();
        assert!(mouths > 20 && deep > 20, "mouths {mouths}, deep {deep}");
    }

    #[test]
    fn mountains_get_a_cave_out_through_their_side() {
        let mut w = flat();
        // A cone 30 tall round (128, 128).
        for z in 98..158 {
            for x in 98..158 {
                let d = (((x - 128) as f32).powi(2) + ((z - 128) as f32).powi(2)).sqrt();
                for y in 61..=(60 + (30.0 - d).max(0.0) as i32) {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = 1;
                }
            }
        }
        assert_eq!(mountain_caves(&mut w, &mut Rng::new(5), &[(128, 128)], &|_, _, _, _| false), 1);
        // Hollow inside, under the mountain's own ground...
        let inside = (100..156).flat_map(|x| (100..156).map(move |z| (x, z)))
            .map(|(x, z)| (61..w.surface_y(x, z)).filter(|&y| w.get(x, y, z) == 0).count()).sum::<usize>();
        assert!(inside > 150, "a cave inside ({inside})");
        // ...and open to the outside: a cell next to the cave that's under the open sky.
        let open = (100..156).flat_map(|x| (100..156).map(move |z| (x, z))).any(|(x, z)| {
            let top = w.surface_y(x, z);
            (62..top).any(|y| w.get(x, y, z) == 0 && [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|&(dx, dz)| w.surface_y(x + dx, z + dz) < y))
        });
        assert!(open, "its mouth opens out of its side");
    }

    #[test]
    fn tunnels_run_through_dirt_ridges() {
        let mut w = flat();
        let coast = Coast::new(4, w.sx, w.sy, w.sz);
        let l = layers(w.sy);
        let n = tunnels(&mut w, &mut Rng::new(4), &coast, &l, 1, &|b| b == 1, &|_, _, _, _| false);
        assert!(n >= 1, "{n} tunnels");
        // Dirt heaped over the ground, and passages under it at ground level.
        let heaped = w.blocks.iter().enumerate().filter(|&(i, &b)| b == 1 && (i as i32 % w.sy) > 64).count();
        let covered = (0..256).flat_map(|x| (0..256).map(move |z| (x, z))).filter(|&(x, z)| w.get(x, 61, z) == 0 && w.get(x, 62, z) == 0 && (64..72).any(|y| w.get(x, y, z) == 1)).count();
        assert!(heaped > 200 && covered > 30, "heaped {heaped}, covered passage {covered}");
    }
}
