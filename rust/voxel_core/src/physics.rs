//! Voxel raycasts and axis-separated AABB movement with Terraria-style step-up.

use crate::world::{ramp_height, ramp_t, World, SHAPE_CEILING, SHAPE_FULL, SHAPE_HALF, SHAPE_RAMP};

pub struct RayHit {
    pub block: (i32, i32, i32),
    pub normal: (i32, i32, i32),
    pub id: u16,
    pub distance: f32,
    /// Liquid type in the hit cell (0 if it was a block hit).
    pub liquid: u8,
}

/// Amanatides & Woo grid traversal. Hits any block that renders (plants, torches
/// too) and, with `liquids`, cells holding liquid.
pub fn raycast(w: &World, origin: [f32; 3], dir: [f32; 3], max_dist: f32, liquids: bool) -> Option<RayHit> {
    let len = (dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2]).sqrt();
    if len == 0.0 {
        return None;
    }
    let d = dir.map(|v| v / len);
    let mut cell = origin.map(|v| v.floor() as i32);
    let step = d.map(|v| if v > 0.0 { 1 } else { -1 });
    let mut t_max = [0f32; 3];
    let mut t_delta = [0f32; 3];
    for i in 0..3 {
        if d[i] == 0.0 {
            t_max[i] = f32::INFINITY;
            t_delta[i] = f32::INFINITY;
        } else {
            let next = if d[i] > 0.0 { cell[i] as f32 + 1.0 } else { cell[i] as f32 };
            t_max[i] = (next - origin[i]) / d[i];
            t_delta[i] = 1.0 / d[i].abs();
        }
    }
    let mut normal = (0, 0, 0);
    let mut t = 0.0;
    while t <= max_dist {
        let id = w.get(cell[0], cell[1], cell[2]);
        let (lt, la) = w.liquid_at(cell[0], cell[1], cell[2]);
        if (id != 0 && w.def(id).render != 0) || (liquids && la > 0) {
            return Some(RayHit {
                block: (cell[0], cell[1], cell[2]),
                normal,
                id,
                distance: t,
                liquid: if id != 0 && w.def(id).render != 0 { 0 } else { lt },
            });
        }
        let axis = if t_max[0] < t_max[1] {
            if t_max[0] < t_max[2] { 0 } else { 2 }
        } else if t_max[1] < t_max[2] {
            1
        } else {
            2
        };
        t = t_max[axis];
        t_max[axis] += t_delta[axis];
        cell[axis] += step[axis];
        let mut n = [0; 3];
        n[axis] = -step[axis];
        normal = (n[0], n[1], n[2]);
    }
    None
}

pub struct MoveResult {
    pub pos: [f32; 3],
    pub blocked: [bool; 3],
    pub on_floor: bool,
}

const EPS: f32 = 1e-3;

/// Does the box (min..max, world space) overlap the solid part of a hammered
/// block at (x, y, z)? A half block fills the bottom half; a ramp fills below
/// its pixel staircase (the box's highest point along it counts); a ceiling
/// ramp fills above its upside-down staircase.
fn overlaps_shape(shape: u8, (x, y, z): (i32, i32, i32), min: [f32; 3], max: [f32; 3]) -> bool {
    let l0 = [(min[0] - x as f32).clamp(0.0, 1.0), min[1] - y as f32, (min[2] - z as f32).clamp(0.0, 1.0)];
    let l1 = [(max[0] - x as f32).clamp(0.0, 1.0), max[1] - y as f32, (max[2] - z as f32).clamp(0.0, 1.0)];
    match shape {
        SHAPE_HALF => l0[1] < 0.5,
        s if s >= SHAPE_RAMP && s < SHAPE_CEILING => {
            let d = s - SHAPE_RAMP;
            let t = ramp_t(d, l0[0], l0[2]).max(ramp_t(d, l1[0], l1[2]));
            l0[1] < ramp_height(t)
        }
        s if s >= SHAPE_CEILING => {
            let d = s - SHAPE_CEILING;
            let t = ramp_t(d, l0[0], l0[2]).max(ramp_t(d, l1[0], l1[2]));
            l1[1] > 1.0 - ramp_height(t)
        }
        _ => true,
    }
}

/// `pos` is the bottom-centre of the box; `half` is (half width, height, half depth).
/// Returns (overlaps anything solid, a hammered block among what it overlaps).
fn overlap(w: &World, pos: [f32; 3], half: [f32; 3]) -> (bool, bool) {
    let min = [pos[0] - half[0] + EPS, pos[1] + EPS, pos[2] - half[2] + EPS];
    let max = [pos[0] + half[0] - EPS, pos[1] + half[1] - EPS, pos[2] + half[2] - EPS];
    let mut hit = false;
    let mut shaped = false;
    for x in min[0].floor() as i32..=max[0].floor() as i32 {
        for y in min[1].floor() as i32..=max[1].floor() as i32 {
            for z in min[2].floor() as i32..=max[2].floor() as i32 {
                if !w.is_solid(x, y, z) {
                    continue;
                }
                let shape = w.shape_at(x, y, z);
                if shape == SHAPE_FULL {
                    hit = true;
                } else if overlaps_shape(shape, (x, y, z), min, max) {
                    hit = true;
                    shaped = true;
                }
            }
        }
    }
    (hit, shaped)
}

fn overlaps_solid(w: &World, pos: [f32; 3], half: [f32; 3]) -> bool {
    overlap(w, pos, half).0
}

/// Moves along one axis, stopping flush against the first solid block.
fn sweep_axis(w: &World, pos: &mut [f32; 3], half: [f32; 3], axis: usize, amount: f32) -> bool {
    if amount == 0.0 {
        return false;
    }
    // Sub-step so fast movers can't tunnel through 1-block walls.
    let steps = (amount.abs() / 0.45).ceil().max(1.0) as i32;
    let inc = amount / steps as f32;
    for _ in 0..steps {
        let mut next = *pos;
        next[axis] += inc;
        let (hit, shaped) = overlap(w, next, half);
        if hit && shaped {
            // A hammered block's surface isn't on the grid: close in on it.
            let (mut lo, mut hi) = (0.0f32, 1.0f32);
            for _ in 0..16 {
                let mid = (lo + hi) * 0.5;
                let mut p = *pos;
                p[axis] += inc * mid;
                if overlaps_solid(w, p, half) {
                    hi = mid;
                } else {
                    lo = mid;
                }
            }
            pos[axis] += inc * lo;
            return true;
        }
        if hit {
            // Snap flush to the blocking face.
            let lo = if axis == 1 { 0.0 } else { half[axis] };
            let hi = half[axis];
            if inc > 0.0 {
                let edge = next[axis] + hi;
                pos[axis] = edge.floor() - hi;
            } else {
                let edge = next[axis] - lo;
                pos[axis] = edge.floor() + 1.0 + lo;
            }
            if overlaps_solid(w, *pos, half) {
                // Snapping failed (e.g. spawned inside a block); just refuse the move.
                pos[axis] = next[axis] - inc;
            }
            return true;
        }
        *pos = next;
    }
    false
}

/// The top of a platform cell under the box (min..max, world space): its top
/// face, or for a platform stair (a platform with a ramp shape) its staircase
/// at the box's highest point over it.
fn platform_top(w: &World, (x, y, z): (i32, i32, i32), min: [f32; 3], max: [f32; 3]) -> f32 {
    let s = w.shape_at(x, y, z);
    if (SHAPE_RAMP..SHAPE_CEILING).contains(&s) {
        let d = s - SHAPE_RAMP;
        let t0 = ramp_t(d, (min[0] - x as f32).clamp(0.0, 1.0), (min[2] - z as f32).clamp(0.0, 1.0));
        let t1 = ramp_t(d, (max[0] - x as f32).clamp(0.0, 1.0), (max[2] - z as f32).clamp(0.0, 1.0));
        y as f32 + ramp_height(t0.max(t1))
    } else {
        (y + 1) as f32
    }
}

/// The top of the highest platform the box's feet cross going from `from` down
/// to `to` (its bottom passes through the platform's top), if any.
fn platform_landing(w: &World, pos: [f32; 3], half: [f32; 3], from: f32, to: f32) -> Option<f32> {
    let (x0, x1) = ((pos[0] - half[0] + EPS).floor() as i32, (pos[0] + half[0] - EPS).floor() as i32);
    let (z0, z1) = ((pos[2] - half[2] + EPS).floor() as i32, (pos[2] + half[2] - EPS).floor() as i32);
    let (min, max) = ([pos[0] - half[0] + EPS, 0.0, pos[2] - half[2] + EPS], [pos[0] + half[0] - EPS, 0.0, pos[2] + half[2] - EPS]);
    let mut best: Option<f32> = None;
    for y in (to.floor() as i32 - 1)..=(from.floor() as i32) {
        for x in x0..=x1 {
            for z in z0..=z1 {
                if !w.is_platform(x, y, z) {
                    continue;
                }
                let top = platform_top(w, (x, y, z), min, max);
                if from < top - EPS || to >= top {
                    continue;
                }
                if best.map_or(true, |b| top > b) {
                    best = Some(top);
                }
            }
        }
    }
    best
}

/// The top of a platform at the box's feet that it can step up onto (within
/// `step_height`, with room above), if any.
fn platform_step(w: &World, pos: [f32; 3], half: [f32; 3], step_height: f32) -> Option<f32> {
    let (x0, x1) = ((pos[0] - half[0] + EPS).floor() as i32, (pos[0] + half[0] - EPS).floor() as i32);
    let (z0, z1) = ((pos[2] - half[2] + EPS).floor() as i32, (pos[2] + half[2] - EPS).floor() as i32);
    let (min, max) = ([pos[0] - half[0] + EPS, 0.0, pos[2] - half[2] + EPS], [pos[0] + half[0] - EPS, 0.0, pos[2] + half[2] - EPS]);
    let mut best: Option<f32> = None;
    for y in (pos[1] + EPS).floor() as i32..=(pos[1] + step_height).floor() as i32 {
        for x in x0..=x1 {
            for z in z0..=z1 {
                if !w.is_platform(x, y, z) {
                    continue;
                }
                let top = platform_top(w, (x, y, z), min, max);
                if top <= pos[1] + EPS || top > pos[1] + step_height + EPS {
                    continue;
                }
                if best.map_or(true, |b| top > b) {
                    best = Some(top);
                }
            }
        }
    }
    best.filter(|&top| !overlaps_solid(w, [pos[0], top, pos[2]], half))
}

/// Moves a box through the world. Platforms (World::is_platform) hold it up
/// from above, like Terraria's: falling onto one lands on its top, while it
/// passes through them going up or sideways - and on the ground it steps up
/// onto one at its feet (platform stairs). With `drop` it falls through them
/// instead (holding down in Terraria).
pub fn move_aabb(w: &World, start: [f32; 3], half: [f32; 3], motion: [f32; 3], step_height: f32, drop: bool) -> MoveResult {
    let mut pos = start;
    let mut blocked = [false; 3];
    blocked[1] = sweep_axis(w, &mut pos, half, 1, motion[1]);
    if motion[1] < 0.0 && !drop {
        if let Some(top) = platform_landing(w, pos, half, start[1], pos[1]) {
            pos[1] = top;
            blocked[1] = true;
        }
    }
    let on_floor = blocked[1] && motion[1] < 0.0;

    let before = pos;
    blocked[0] = sweep_axis(w, &mut pos, half, 0, motion[0]);
    blocked[2] = sweep_axis(w, &mut pos, half, 2, motion[2]);

    // Step up single blocks while walking on the ground.
    if step_height > 0.0 && on_floor && (blocked[0] || blocked[2]) {
        let mut up = before;
        if !sweep_axis(w, &mut up, half, 1, step_height) {
            let mut b = [false; 3];
            b[0] = sweep_axis(w, &mut up, half, 0, motion[0]);
            b[2] = sweep_axis(w, &mut up, half, 2, motion[2]);
            let moved_further = (up[0] - before[0]).abs() + (up[2] - before[2]).abs()
                > (pos[0] - before[0]).abs() + (pos[2] - before[2]).abs() + EPS;
            if moved_further {
                sweep_axis(w, &mut up, half, 1, -step_height);
                pos = up;
                blocked[0] = b[0];
                blocked[2] = b[2];
            }
        }
    }
    // Walking into a platform at the feet: up onto it.
    if step_height > 0.0 && on_floor && !drop && (motion[0] != 0.0 || motion[2] != 0.0) {
        if let Some(top) = platform_step(w, pos, half, step_height) {
            pos[1] = top;
        }
    }
    MoveResult { pos, blocked, on_floor }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::tests::test_world;

    const PLAYER: [f32; 3] = [0.3, 1.8, 0.3];

    #[test]
    fn raycast_hits_ground_top_face() {
        let w = test_world();
        let hit = raycast(&w, [10.5, 35.0, 10.5], [0.0, -1.0, 0.0], 10.0, false).unwrap();
        assert_eq!(hit.block, (10, 31, 10));
        assert_eq!(hit.normal, (0, 1, 0));
        assert!((hit.distance - 3.0).abs() < 1e-4);
        assert!(raycast(&w, [10.5, 35.0, 10.5], [0.0, 1.0, 0.0], 10.0, false).is_none());
        let mut w = w;
        w.set_liquid(10, 33, 10, crate::world::LIQ_WATER, 40);
        assert!(raycast(&w, [10.5, 35.0, 10.5], [0.0, -1.0, 0.0], 10.0, false).unwrap().block == (10, 31, 10));
        let h = raycast(&w, [10.5, 35.0, 10.5], [0.0, -1.0, 0.0], 10.0, true).unwrap();
        assert_eq!((h.block, h.liquid), ((10, 33, 10), crate::world::LIQ_WATER));
    }

    #[test]
    fn falling_lands_flush_on_ground() {
        let w = test_world();
        let r = move_aabb(&w, [10.5, 33.0, 10.5], PLAYER, [0.0, -5.0, 0.0], 0.0, false);
        assert!(r.on_floor);
        assert!((r.pos[1] - 32.0).abs() < 1e-4, "{:?}", r.pos);
    }

    #[test]
    fn walls_block_and_single_steps_are_climbed() {
        let mut w = test_world();
        // One-block step at x=12.
        w.set(12, 32, 10, 1);
        let r = move_aabb(&w, [10.5, 32.0, 10.5], PLAYER, [1.5, -0.01, 0.0], 0.0, false);
        assert!(r.blocked[0]);
        assert!((r.pos[0] - 11.7).abs() < 1e-3, "{:?}", r.pos);
        let r = move_aabb(&w, [10.5, 32.0, 10.5], PLAYER, [1.5, -0.01, 0.0], 1.05, false);
        assert!(!r.blocked[0]);
        assert!((r.pos[1] - 33.0).abs() < 1e-3, "{:?}", r.pos);
        // Two-block wall can't be stepped.
        w.set(12, 33, 10, 1);
        w.set(12, 34, 10, 1);
        let r = move_aabb(&w, [10.5, 32.0, 10.5], PLAYER, [1.5, -0.01, 0.0], 1.05, false);
        assert!(r.blocked[0]);
    }

    /// A world with a wooden platform (id 9) at (10, 34, 10).
    fn platform_world() -> World {
        let mut w = test_world();
        w.set_def(9, crate::world::BlockDef { name: "platform".into(), render: crate::world::RENDER_MODEL, solid: false, opaque: false, variants: 1, platform: true, ..Default::default() });
        w.set(10, 34, 10, 9);
        w
    }

    #[test]
    fn platforms_hold_you_from_above_only() {
        let w = platform_world();
        // Falling onto it: lands on its top.
        let r = move_aabb(&w, [10.5, 37.0, 10.5], PLAYER, [0.0, -5.0, 0.0], 0.0, false);
        assert!((r.pos[1] - 35.0).abs() < 1e-4 && r.on_floor, "lands on the platform ({:?})", r.pos);
        // Standing on it stays put.
        let r = move_aabb(&w, [10.5, 35.0, 10.5], PLAYER, [0.0, -0.05, 0.0], 0.0, false);
        assert!((r.pos[1] - 35.0).abs() < 1e-4 && r.on_floor);
        // Holding down: falls through to the ground.
        let r = move_aabb(&w, [10.5, 35.0, 10.5], PLAYER, [0.0, -5.0, 0.0], 0.0, true);
        assert!((r.pos[1] - 32.0).abs() < 1e-4, "drops through ({:?})", r.pos);
        // Jumping from below: goes up through it.
        let r = move_aabb(&w, [10.5, 32.0, 10.5], PLAYER, [0.0, 4.0, 0.0], 0.0, false);
        assert!((r.pos[1] - 36.0).abs() < 1e-4 && !r.blocked[1], "jumps through ({:?})", r.pos);
        // Sideways at head height: walks under it.
        let r = move_aabb(&w, [8.5, 32.0, 10.5], PLAYER, [3.0, -0.01, 0.0], 0.0, false);
        assert!((r.pos[0] - 11.5).abs() < 1e-4 && (r.pos[1] - 32.0).abs() < 1e-4, "walks under ({:?})", r.pos);
    }

    #[test]
    fn walking_into_a_platform_at_your_feet_steps_up() {
        let mut w = platform_world();
        w.set(10, 34, 10, 0);
        w.set(10, 32, 10, 9);
        let r = move_aabb(&w, [8.5, 32.0, 10.5], PLAYER, [2.0, -0.01, 0.0], 1.05, false);
        assert!((r.pos[1] - 33.0).abs() < 1e-4, "up the platform stair ({:?})", r.pos);
        let r = move_aabb(&w, [8.5, 32.0, 10.5], PLAYER, [2.0, -0.01, 0.0], 1.05, true);
        assert!((r.pos[1] - 32.0).abs() < 1e-4, "not while holding down ({:?})", r.pos);
    }

    #[test]
    fn platform_stairs_are_walked_up_and_dropped_through() {
        let mut w = platform_world();
        // On the ground (its top is y 32): two stairs rising toward +x,
        // (10, 32, 12) and (11, 33, 12), and a flat platform at the top.
        w.set(10, 32, 12, 9);
        assert!(w.set_shape(10, 32, 12, SHAPE_RAMP + 1), "a platform takes a ramp");
        w.set(11, 33, 12, 9);
        assert!(w.set_shape(11, 33, 12, SHAPE_RAMP + 1));
        w.set(12, 33, 12, 9);
        // Walking along +x from their foot climbs them, step by step.
        let mut pos = [9.4, 32.0, 12.5];
        let mut highest: f32 = 32.0;
        for _ in 0..90 {
            let r = move_aabb(&w, pos, PLAYER, [0.04, -0.05, 0.0], 0.6, false);
            pos = r.pos;
            highest = highest.max(pos[1]);
        }
        assert!(highest > 33.99 && pos[0] > 12.5 && (pos[1] - 34.0).abs() < 1e-3, "walked up the stairs onto the platform ({:?})", pos);
        // Halfway along it you stand on its staircase, not its top.
        let r = move_aabb(&w, [10.5, 34.0, 12.5], PLAYER, [0.0, -2.0, 0.0], 0.0, false);
        assert!(r.on_floor && r.pos[1] > 32.3 && r.pos[1] < 33.0, "lands on the staircase ({:?})", r.pos);
        // A stair in the air (the platform at (10, 34, 10) hammered): holding
        // down drops through it, and it doesn't stop you from below.
        assert!(w.set_shape(10, 34, 10, SHAPE_RAMP + 1));
        let r = move_aabb(&w, [10.5, 35.2, 10.5], PLAYER, [0.0, -2.0, 0.0], 0.0, true);
        assert!(r.pos[1] < 34.0, "dropped through ({:?})", r.pos);
        let r = move_aabb(&w, [10.5, 32.0, 10.5], PLAYER, [0.0, 3.5, 0.0], 0.0, false);
        assert!(r.pos[1] > 35.4, "jumped up through it ({:?})", r.pos);
        // A platform can't be a half block or an upside-down ramp.
        assert!(!w.set_shape(10, 34, 10, SHAPE_HALF) && !w.set_shape(10, 34, 10, SHAPE_CEILING));
    }

    #[test]
    fn hammered_blocks_collide_in_their_shape() {
        use crate::world::{SHAPE_HALF, SHAPE_RAMP};
        let mut w = test_world();
        // A half block: you land on its middle.
        w.set(10, 32, 10, 1);
        assert!(w.set_shape(10, 32, 10, SHAPE_HALF));
        let r = move_aabb(&w, [10.5, 35.0, 10.5], PLAYER, [0.0, -5.0, 0.0], 0.0, false);
        assert!((r.pos[1] - 32.5).abs() < 2e-3 && r.on_floor, "lands on the half block ({:?})", r.pos);
        // Walking into it from the ground steps up onto it.
        let r = move_aabb(&w, [8.5, 32.0, 10.5], PLAYER, [1.6, -0.01, 0.0], 1.05, false);
        assert!((r.pos[1] - 32.5).abs() < 2e-3, "steps up half a block ({:?})", r.pos);
        // A ramp rising toward +x (dir 1): walking up it climbs smoothly.
        w.set(12, 32, 14, 1);
        assert!(w.set_shape(12, 32, 14, SHAPE_RAMP + 1));
        w.set(13, 32, 14, 1);
        let mut pos = [11.0, 32.0, 14.5];
        let mut heights = Vec::new();
        for _ in 0..40 {
            let r = move_aabb(&w, pos, PLAYER, [0.06, -0.05, 0.0], 1.05, false);
            pos = r.pos;
            heights.push(pos[1]);
        }
        assert!((pos[1] - 33.0).abs() < 2e-3, "up the ramp onto the block behind it ({:?})", pos);
        let max_jump = heights.windows(2).map(|p| p[1] - p[0]).fold(0.0f32, f32::max);
        assert!(max_jump < 0.15, "smoothly, without big steps (largest {max_jump})");
        // Standing on the slope: partway up.
        let r = move_aabb(&w, [12.5, 34.0, 14.5], PLAYER, [0.0, -5.0, 0.0], 0.0, false);
        assert!(r.pos[1] > 32.3 && r.pos[1] < 32.9, "stands partway up the slope ({:?})", r.pos);
    }
}
