//! Terraria's surface features, in 3D: its lakes (Lakes pass, SonOfLakinater),
//! stone and ore patches on the grass (SurfaceOreAndStone: StonePatch,
//! OrePatch) and its forest's groves (the Trees pass: GrowEpicTree in a run
//! of columns, then AddTrees everywhere else).

use crate::caves::{ball, count, heading, site_ok, Op};
use crate::world::{World, LIQ_WATER};
use crate::worldgen::{noise, Coast, Rng};
use fastnoise_lite::FastNoiseLite;

/// Terraria's lakes: 3-6 in its small world (here per 640 x 640 blocks), on
/// open, fairly flat ground away from the mountains, tunnels, beaches, the
/// world's middle and each other. Each is dug as Terraria digs one: a basin
/// 15-30 strong (1.3 times that 1 in 5) sinking over 30-60 steps, wide and
/// shallow at first and rounder as it goes down (its reach across and down
/// eased from 0.3 / 5 to 0.6 / 1.4 of the distance), its banks cut back in a
/// slope above the water, and any cave it opens into sealed off round it
/// with `seal` (Terraria turns the walls there back into ground); then
/// flooded to its rim. Here its water line is the lowest point of its rim,
/// so it never spills down a slope. `avoid`: (x, z) it keeps 60 from.
/// Returns how many.
pub fn lakes(w: &mut World, rng: &mut Rng, coast: &Coast, avoid: &[(i32, i32)], ok: &dyn Fn(u16) -> bool, seal: u16) -> usize {
    let want = rng.range(3, 7) as f32;
    let mut made: Vec<(i32, i32)> = Vec::new();
    for _ in 0..count(w, want / 2.0).max(1) {
        for _try in 0..60 {
            let (x, z) = (rng.range(1, w.sx - 1), rng.range(1, w.sz - 1));
            if !site_ok(w, coast, x, z, 0.06) || avoid.iter().chain(made.iter()).any(|&(ax, az)| (ax - x).pow(2) + (az - z).pow(2) < 60 * 60) {
                continue;
            }
            let strength = rng.range(15, 31) as f32 * if rng.range(0, 5) == 0 { 1.3 } else { 1.0 };
            let steps = rng.range(30, 61) as f32 * if strength > 30.0 { 1.3 } else { 1.0 };
            // Its top reaches 0.4 strength / 0.3 across.
            let reach = strength * 0.4 / 0.3;
            let center = w.surface_y(x, z);
            if center < 2 || !ok(w.get(x, center, z)) {
                continue;
            }
            // The rim: the ground round it, just past its reach.
            let mut rim = i32::MAX;
            let mut lowest = i32::MAX;
            let mut highest = i32::MIN;
            for k in 0..32 {
                let a = k as f32 / 32.0 * std::f32::consts::TAU;
                let (rx, rz) = ((x as f32 + a.cos() * (reach + 3.0)) as i32, (z as f32 + a.sin() * (reach + 3.0)) as i32);
                if !w.in_bounds(rx, 1, rz) {
                    rim = i32::MIN;
                    break;
                }
                let g = w.surface_y(rx, rz);
                rim = rim.min(g);
                lowest = lowest.min(g);
                highest = highest.max(g);
            }
            // Fairly flat (Terraria: the ground 20 either side within 10),
            // and open to the sky over it (no overhang).
            if rim == i32::MIN || highest - lowest > 10 || center - rim > 8 {
                continue;
            }
            let level = rim - 1;
            dig_lake(w, rng, (x, level, z), strength, steps, seal);
            let filled = w.fill_basin((x, level, z), level, LIQ_WATER, 400_000);
            if filled > 0 {
                made.push((x, z));
                break;
            }
        }
    }
    made.len()
}

/// SonOfLakinater from (x, its water line, z).
fn dig_lake(w: &mut World, rng: &mut Rng, (x0, level, z0): (i32, i32, i32), strength: f32, steps: f32, seal: u16) {
    let (mut size, mut left) = (strength, steps);
    let mut p = (x0 as f32 + 0.5, level as f32 + 0.5, z0 as f32 + 0.5);
    let (hx, hz) = heading(rng);
    let (mut drift, wander) = if rng.range(0, 4) == 0 { (rng.range(-50, 51) as f32 * 0.01, rng.unit() as f32 * 0.004 + 0.001) } else { (rng.range(-15, 16) as f32 * 0.01, rng.unit() as f32 * 0.002) };
    let mut down = rng.range(0, 101) as f32 * 0.01;
    let mut first = true;
    let mut lake = std::collections::HashSet::new();
    let mut shell = Vec::new();
    while size > 3.0 && left > 0.0 {
        size -= rng.range(0, 11) as f32 * 0.1;
        left -= 1.0;
        let t = left / steps;
        // Across and down: wide and flat at first, rounder later.
        let (fa, fd) = (0.6 + (0.3 - 0.6) * t, 1.4 + (5.0 - 1.4) * t);
        let r = (size * 4.0).ceil() as i32;
        let (cx, cy, cz) = (p.0 as i32, p.1 as i32, p.2 as i32);
        for y in (cy - (size * 3.0) as i32).max(1)..=(cy + (size * 2.0) as i32).min(w.sy - 2) {
            for z in (cz - r).max(1)..=(cz + r).min(w.sz - 2) {
                for xx in (cx - r).max(1)..=(cx + r).min(w.sx - 2) {
                    let across = (((xx as f32 + 0.5 - p.0).powi(2) + (z as f32 + 0.5 - p.2).powi(2)).sqrt()) * fa;
                    let d = (across.powi(2) + ((y as f32 + 0.5 - p.1) * fd).powi(2)).sqrt();
                    let i = w.idx(xx, y, z);
                    if d < size * 0.4 {
                        if y <= level && w.liquid[i] == 0 {
                            w.blocks[i] = 0;
                            lake.insert((xx, y, z));
                        }
                    } else if d < size && y <= level {
                        shell.push((xx, y, z));
                    }
                }
            }
        }
        if first {
            // Its banks: cut back above the water in a slope, so it's open
            // to the sky (Terraria's first step).
            first = false;
            let top = size * 0.4 / fa;
            for y in level + 1..=(level + 12).min(w.sy - 2) {
                let reach = top + (y - level) as f32 * 1.2;
                let rr = reach.ceil() as i32;
                for z in (z0 - rr).max(1)..=(z0 + rr).min(w.sz - 2) {
                    for xx in (x0 - rr).max(1)..=(x0 + rr).min(w.sx - 2) {
                        if (((xx - x0).pow(2) + (z - z0).pow(2)) as f32).sqrt() < reach {
                            let i = w.idx(xx, y, z);
                            w.blocks[i] = 0;
                        }
                    }
                }
            }
        }
        p.0 += hx * drift;
        p.2 += hz * drift;
        p.1 -= down;
        drift = (drift + rng.range(-100, 101) as f32 * wander).clamp(-1.0, 1.0);
        down = (down + rng.range(-100, 101) as f32 * 0.01).clamp(0.5 * (1.0 - t), 1.0);
    }
    // Sealed round: open cells about it below the water line (caves it broke
    // into) filled in.
    for c in shell {
        if !lake.contains(&c) && w.in_bounds(c.0, c.1, c.2) {
            let i = w.idx(c.0, c.1, c.2);
            if w.blocks[i] == 0 && w.liquid[i] == 0 {
                w.blocks[i] = seal;
            }
        }
    }
}

/// Terraria's StonePatch: 1-7 in its small world (here twice that per 640 x
/// 640 blocks), on grass with grass either side: the ground turned to stone
/// along a short run going down from it (13-18 strong, 13-19 steps, a ball
/// 0.21-0.39 of that across, twice it 1 in 8), and rubble (`rocks`: the small
/// and large rocks) on the stone 1 in 7. Returns how many.
pub fn stone_patches(w: &mut World, rng: &mut Rng, coast: &Coast, grass: u16, stone: u16, rocks: (u16, u16), plant: &dyn Fn(u16) -> bool) -> usize {
    let want = rng.range(1, 7) as f32;
    let mut made = 0;
    for _ in 0..count(w, want) {
        for _try in 0..30 {
            let (x, z) = (rng.range(2, w.sx - 2), rng.range(2, w.sz - 2));
            let y = w.surface_y(x, z);
            if y < 2 || !site_ok(w, coast, x, z, 0.02) || [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|&(dx, dz)| w.get(x + dx, w.surface_y(x + dx, z + dz), z + dz) != grass) {
                continue;
            }
            let strength = rng.range(13, 18) as f32 + if rng.range(0, 3) == 0 { rng.range(0, 3) as f32 } else { 0.0 };
            let steps = rng.range(13, 19) + if rng.range(0, 3) == 0 { rng.range(0, 3) } else { 0 };
            paint_run(w, rng, (x, y, z), strength * 0.3, steps, stone, plant);
            // Rubble on its top.
            for dz in -12..=12 {
                for dx in -12..=12 {
                    let (px, pz) = (x + dx, z + dz);
                    let top = w.surface_y(px, pz);
                    if top > 0 && w.get(px, top, pz) == stone && w.get(px, top + 1, pz) == 0 && rng.range(0, 7) == 0 {
                        let r = if rng.range(0, 3) == 0 { rocks.1 } else { rocks.0 };
                        if r != 0 {
                            put(w, (px, top + 1, pz), r);
                        }
                    }
                }
            }
            made += 1;
            break;
        }
    }
    made
}

/// Terraria's OrePatch: 5-10 in its small world, 200 apart (here per 640 x
/// 640 blocks, 100 apart), on grass: the world's first-tier ore (its second
/// 1 in 3) showing at the surface, a vein of it 8-12 down from there with
/// bits beside it, and a run of it under that (5-9 strong, 9-14 steps).
/// Returns how many.
pub fn ore_patches(w: &mut World, rng: &mut Rng, coast: &Coast, grass: u16, ores: (u16, u16), plant: &dyn Fn(u16) -> bool) -> usize {
    let want = rng.range(5, 11) as f32;
    let mut spots: Vec<(i32, i32)> = Vec::new();
    for _ in 0..count(w, want / 2.0) {
        for _try in 0..30 {
            let (x, z) = (rng.range(2, w.sx - 2), rng.range(2, w.sz - 2));
            let y = w.surface_y(x, z);
            if y < 14 || !site_ok(w, coast, x, z, 0.03) || w.get(x, y, z) != grass || spots.iter().any(|&(sx, sz)| (sx - x).pow(2) + (sz - z).pow(2) < 100 * 100) {
                continue;
            }
            let ore = if rng.range(0, 3) == 0 { ores.1 } else { ores.0 };
            // The vein from the surface down.
            let (mut vx, mut vy, mut vz) = (x, y, z);
            let bottom = y - rng.range(8, 13);
            while vy > bottom {
                set_ground(w, (vx, vy, vz), ore, plant);
                if rng.range(0, 3) == 0 {
                    set_ground(w, (vx + rng.range(-1, 2), vy, vz + rng.range(-1, 2)), ore, plant);
                }
                if rng.range(0, 4) == 0 {
                    set_ground(w, (vx + rng.range(-2, 3), vy - rng.range(0, 2), vz + rng.range(-2, 3)), ore, plant);
                }
                vx += rng.range(-1, 2);
                vz += rng.range(-1, 2);
                vy -= rng.range(1, 3);
            }
            let strength = rng.range(5, 9) as f32 + if rng.range(0, 3) == 0 { rng.range(0, 2) as f32 } else { 0.0 };
            let steps = rng.range(9, 14) + if rng.range(0, 3) == 0 { rng.range(0, 2) } else { 0 };
            paint_run(w, rng, (vx, vy, vz), strength * 0.3, steps, ore, plant);
            spots.push((x, z));
            break;
        }
    }
    spots.len()
}

/// A block of ground turned to `id` (a plant on it goes).
fn set_ground(w: &mut World, (x, y, z): (i32, i32, i32), id: u16, plant: &dyn Fn(u16) -> bool) {
    if !w.in_bounds(x, y + 1, z) || !w.is_solid(x, y, z) {
        return;
    }
    put(w, (x, y, z), id);
    if plant(w.get(x, y + 1, z)) {
        put(w, (x, y + 1, z), 0);
    }
}

/// StonePatch's and OrePatch's run: balls of `radius` (0.7-1.3 of it, twice
/// it 1 in 8) going down from `start` (0.5-1 a step, 0.3 either way across,
/// turning by up to 0.1), turning the ground they cover to `id`; plants left
/// on it go.
fn paint_run(w: &mut World, rng: &mut Rng, start: (i32, i32, i32), radius: f32, steps: i32, id: u16, plant: &dyn Fn(u16) -> bool) {
    let mut p = (start.0 as f32 + 0.5, start.1 as f32 + 0.5, start.2 as f32 + 0.5);
    let (hx, hz) = heading(rng);
    let side = rng.unit() as f32 * 0.6 - 0.3;
    let mut v = (hx * side, -(rng.unit() as f32 * 0.5 + 0.5), hz * side);
    for _ in 0..steps {
        let mut r = radius * (0.7 + rng.unit() as f32 * 0.6);
        if rng.range(0, 8) == 0 {
            r *= 2.0;
        }
        ball(w, rng, p, r, Op::Paint(id), &|_, _, _, _| false);
        p = (p.0 + v.0, p.1 + v.1, p.2 + v.2);
        let turn = |rng: &mut Rng| rng.unit() as f32 * 0.2 - 0.1;
        v = (v.0 + turn(rng), v.1 + turn(rng), v.2 + turn(rng));
    }
    // Plants standing on what it turned.
    let r = (radius * 2.5).ceil() as i32 + 6;
    for z in (start.2 - r)..=(start.2 + r) {
        for x in (start.0 - r)..=(start.0 + r) {
            for y in (start.1 - 2)..=(start.1 + 3) {
                if w.in_bounds(x, y + 1, z) && w.get(x, y, z) == id && plant(w.get(x, y + 1, z)) {
                    put(w, (x, y + 1, z), 0);
                }
            }
        }
    }
}

/// A block written straight in (worldgen: no light or liquid updates).
fn put(w: &mut World, (x, y, z): (i32, i32, i32), id: u16) {
    if w.in_bounds(x, y, z) {
        let i = w.idx(x, y, z);
        w.blocks[i] = id;
    }
}

/// The forest's trees, Terraria's way: groves of tall trees (its GrowEpicTree
/// on every column of a 50-100 wide run, 0.003 of its width of them: here
/// that many per 640 x 640 blocks, twice over, 25-50 blocks round), and
/// elsewhere trees wherever there's room, thicker in places and thinner in
/// others (meadows) as Terraria's terrain and features leave gaps.
pub struct Forest {
    groves: Vec<(f32, f32, f32)>,
    density: FastNoiseLite,
}

impl Forest {
    pub fn new(seed: i32, w: &World, rng: &mut Rng) -> Forest {
        let mut groves = Vec::new();
        for _ in 0..count(w, 0.003 * 4200.0) {
            groves.push((rng.range(0, w.sx) as f32, rng.range(0, w.sz) as f32, rng.range(25, 51) as f32));
        }
        Forest { groves, density: noise(seed + 50, 1.0 / 90.0, 2) }
    }

    /// At (x, z): the chance of a tree in a 5 x 5 cell, and whether it's a
    /// grove's tall tree.
    pub fn at(&self, x: f32, z: f32) -> (f32, bool) {
        if self.groves.iter().any(|&(gx, gz, r)| (gx - x).powi(2) + (gz - z).powi(2) < r * r) {
            return (0.75, true);
        }
        let n = self.density.get_noise_2d(x, z);
        ((0.3 + 0.35 * n).clamp(0.03, 0.55), false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{BlockDef, RENDER_CROSS, RENDER_CUBE};

    /// A flat world: grass on top at 60 over dirt, stone below 40; 256 across.
    /// Blocks: 1 dirt, 2 stone, 3 grass, 4 copper, 5 iron, 6 small rocks,
    /// 7 large rocks, 8 tall grass (a plant).
    fn flat() -> World {
        let mut w = World::new();
        for (i, (name, solid)) in [("dirt", true), ("stone", true), ("grass", true), ("copper_ore", true), ("iron_ore", true), ("small_rocks", false),
                ("large_rocks", false), ("tall_grass", false)].iter().enumerate() {
            w.set_def(i as u16 + 1, BlockDef { name: name.to_string(), render: if *solid { RENDER_CUBE } else { RENDER_CROSS }, solid: *solid, opaque: *solid, variants: 1, ..Default::default() });
        }
        w.resize(256, 128, 256);
        for z in 0..256 {
            for x in 0..256 {
                for y in 1..=60 {
                    let i = w.idx(x, y, z);
                    w.blocks[i] = if y < 40 { 2 } else if y == 60 { 3 } else { 1 };
                }
                if (x + z) % 3 == 0 {
                    let i = w.idx(x, 61, z);
                    w.blocks[i] = 8;
                }
            }
        }
        w
    }

    #[test]
    fn lakes_are_dug_and_flooded_to_their_rim() {
        let mut w = flat();
        let coast = Coast::new(9, w.sx, w.sy, w.sz);
        let n = lakes(&mut w, &mut Rng::new(9), &coast, &[], &|b| b == 3 || b == 1, 1);
        assert!(n >= 1, "{n} lakes");
        let water: Vec<(i32, i32, i32)> = (0..256).flat_map(|x| (0..256).map(move |z| (x, z)))
            .flat_map(|(x, z)| (1..80).map(move |y| (x, y, z))).filter(|&(x, y, z)| w.liquid_at(x, y, z).0 == LIQ_WATER).collect();
        let top = water.iter().map(|p| p.1).max().unwrap_or(0);
        let deep = top - water.iter().map(|p| p.1).min().unwrap_or(0);
        // Its water reaches up to just under the old ground, and goes down a way.
        assert!(water.len() > 2000 && top <= 60 && top >= 58 && deep >= 4, "{} cells, top {top}, {deep} deep", water.len());
    }

    #[test]
    fn stone_and_ore_show_on_the_grass() {
        let mut w = flat();
        let coast = Coast::new(2, w.sx, w.sy, w.sz);
        let plant = |b: u16| b >= 6;
        let stones = stone_patches(&mut w, &mut Rng::new(2), &coast, 3, 2, (6, 7), &plant);
        let ores = ore_patches(&mut w, &mut Rng::new(3), &coast, 3, (4, 5), &plant);
        let at_top = |id: u16| (0..256).flat_map(|x| (0..256).map(move |z| (x, z))).filter(|&(x, z)| w.get(x, w.surface_y(x, z), z) == id || w.get(x, 60, z) == id).count();
        let rubble = w.blocks.iter().filter(|&&b| b == 6 || b == 7).count();
        assert!(stones >= 1 && at_top(2) > 20 && rubble > 0, "{stones} stone patches, {} stone at the top, {rubble} rubble", at_top(2));
        assert!(ores >= 1 && at_top(4) + at_top(5) > 0, "{ores} ore patches showing ({} + {})", at_top(4), at_top(5));
        // No plant left standing on them.
        let floating = (0..256).flat_map(|x| (0..256).map(move |z| (x, z))).filter(|&(x, z)| w.get(x, 61, z) == 8 && w.get(x, 60, z) != 3).count();
        assert_eq!(floating, 0);
    }

    #[test]
    fn groves_and_meadows() {
        let w = flat();
        let forest = Forest::new(4, &w, &mut Rng::new(4));
        let (mut grove, mut sparse, mut n) = (0, 0, 0);
        for z in (0..256).step_by(4) {
            for x in (0..256).step_by(4) {
                let (chance, tall) = forest.at(x as f32, z as f32);
                grove += tall as i32;
                sparse += (chance < 0.15) as i32;
                n += 1;
            }
        }
        assert!(grove > n / 20 && grove < n * 2 / 3 && sparse > 0, "groves {grove}, meadows {sparse} of {n}");
    }
}
