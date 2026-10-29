//! Terraria's minecart tracks (TrackGenerator, its Micro Biomes pass), in 3D:
//! a track runs along x or z, a cell a block, level or up or down a cell at a
//! time (45 degrees, as Terraria's slopes); the game draws each cell from the
//! track cells next to it (tracks.gd).
//!
//! - **Where:** a spot under the surface (above the Underworld); down from it
//!   to just over the ground (Terraria's FindSuitableOrigin), heading for the
//!   world's middle along x or z. 1-2 long tracks (400-1000 tiles) and 4-7
//!   standard ones (150-300 tiles) in a small world; here that many in each
//!   640 x 640 blocks, as the cabins count.
//! - **The path** (FindPath): each step down a cell if the last went down or
//!   was level, level after a rise; where that would run into rock
//!   (solid within 6 tiles over the track), the last downward steps turn
//!   level, then the last level ones rise (TryRewriteHistoryToAvoidTiles);
//!   still blocked, it tunnels (CreateTunnel): of rising, level and falling,
//!   the way that's out of the rock soonest within 10 steps, through the rock.
//!   Not where it can't go (CalculateStateForLocation): out of the world's
//!   middle depths, the ocean, the Aether, the structures (the Dungeon, the
//!   Temple, cabins...), next to chests and furniture, within 30 tiles of
//!   another track. Short of its least length, no track.
//! - **Smoothed** (SmoothTrack): a dip it climbs out of within 15 steps is
//!   filled level.
//! - **Laid** (PlacePath): the rock over each cell cut 5-8 tiles high (a new
//!   height 1 time in 7; sand left over the cut hardened, so it doesn't fall
//!   onto the track), and the track in it. Terraria's cut is the track's own
//!   width; here it's 3 blocks wide (a block to each side of the track, from
//!   its level up), roomy enough to ride from first person.

use crate::world::{World, RENDER_CUBE};
use crate::worldgen::{Coast, Layers, Rng};
use std::collections::HashMap;

type P = (i32, i32, i32);

/// How far the cut reaches to each side of the track, in blocks.
const CUT_SIDE: i32 = 1;

/// Terraria's tiles to blocks here, rounded.
fn b(tiles: i32) -> i32 {
    (tiles as f64 * 2.0 / 3.0).round() as i32
}

/// CalculateStateForLocation's answers.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum State {
    Free,
    Blocked,
    Invalid,
}

#[derive(Clone, Copy, Debug)]
struct Step {
    p: P,
    /// -1 up, 0 level, 1 down (Terraria's TrackSlope; its y runs down).
    slope: i32,
    tunnel: bool,
}

/// Placed track cells, by 20-block square, for the spacing check.
struct Placed {
    cells: HashMap<(i32, i32), Vec<P>>,
}

impl Placed {
    fn near(&self, p: P, r: i32) -> bool {
        let g = |v: i32| v.div_euclid(20);
        for gx in g(p.0 - r)..=g(p.0 + r) {
            for gz in g(p.2 - r)..=g(p.2 + r) {
                if let Some(v) = self.cells.get(&(gx, gz)) {
                    if v.iter().any(|q| (q.0 - p.0).abs() <= r && (q.1 - p.1).abs() <= r && (q.2 - p.2).abs() <= r) {
                        return true;
                    }
                }
            }
        }
        false
    }

    fn add(&mut self, p: P) {
        self.cells.entry((p.0.div_euclid(20), p.2.div_euclid(20))).or_default().push(p);
    }
}

struct Gen<'a> {
    w: &'a World,
    l: &'a Layers,
    coast: &'a Coast,
    aether: Option<crate::shimmer::Aether>,
    /// Blocks a track keeps off (chests, furniture, the Dungeon's and the
    /// Temple's brick, wood).
    avoid: Vec<bool>,
    placed: &'a Placed,
}

impl Gen<'_> {
    /// IsLocationInvalid.
    fn invalid(&self, (x, y, z): P) -> bool {
        let w = self.w;
        if !w.in_bounds(x, y, z) || x < 5 || z < 5 || x >= w.sx - 5 || z >= w.sz - 5 || y <= self.l.underworld_top || y >= self.l.surface_base {
            return true;
        }
        if self.coast.inland(x, z) < self.coast.ocean.width {
            return true;
        }
        if let Some(a) = &self.aether {
            let r = b(75);
            if (x - a.center.0).abs() < r && (z - a.center.2).abs() < r && (y - a.center.1).abs() < r {
                return true;
            }
        }
        if w.structures.iter().any(|&(lo, hi)| x >= lo.0 && x <= hi.0 && y >= lo.1 && y <= hi.1 && z >= lo.2 && z <= hi.2) {
            return true;
        }
        [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|&(dx, dz)| self.avoid[w.get(x + dx, y, z + dz) as usize])
    }

    /// CalculateStateForLocation: invalid if a cell of the 6 tiles at and
    /// over it is, or a track is near; blocked if one is solid.
    fn state(&self, (x, y, z): P) -> State {
        let h = b(6);
        if (0..h).any(|k| self.invalid((x, y + k, z))) || self.placed.near((x, y, z), b(30)) {
            return State::Invalid;
        }
        if (0..h).any(|k| self.w.is_solid(x, y + k, z)) {
            return State::Blocked;
        }
        State::Free
    }
}

/// A track's run: from `origin` along (dx, dz), `min`-`max` cells.
fn find_path(g: &Gen, origin: P, dir: (i32, i32), min: usize, max: usize) -> Option<Vec<Step>> {
    let mut h: Vec<Step> = vec![Step { p: origin, slope: 1, tunnel: false }];
    let segment = |h: &[Step], from: usize| -> State {
        let mut s = State::Free;
        for st in &h[from..] {
            match g.state(st.p) {
                State::Invalid => return State::Invalid,
                State::Blocked if !st.tunnel => s = State::Blocked,
                _ => {}
            }
        }
        s
    };
    let append = |h: &mut Vec<Step>, slope: i32, tunnel: bool| {
        let last = h[h.len() - 1].p;
        h.push(Step { p: (last.0 + dir.0, last.1 - slope, last.2 + dir.1), slope, tunnel });
    };
    // RewriteSlopeDirection: step `i` to `slope`, the rest moved with it.
    let rewrite = |h: &mut Vec<Step>, i: usize, slope: i32| {
        let d = slope - h[i].slope;
        h[i].slope = slope;
        for st in h[i..].iter_mut() {
            st.p.1 -= d;
        }
    };
    let mut kept = h.len();
    while h.len() < 2000 {
        let last = h[h.len() - 1].slope;
        append(&mut h, if last == -1 { 0 } else { 1 }, false);
        // TryRewriteHistoryToAvoidTiles: over the last 25 steps.
        let n = h.len();
        let window = n.min(25);
        let saved: Vec<Step> = h[n - window..].to_vec();
        let mut state = State::Blocked;
        let mut i = n - 1;
        let mut done = false;
        while i + window >= n && !done {
            if h[i].slope == 1 {
                let s = segment(&h, i);
                if s == State::Free {
                    state = s;
                    done = true;
                    break;
                }
                rewrite(&mut h, i, 0);
            }
            if i == 0 {
                break;
            }
            i -= 1;
        }
        if !done {
            state = segment(&h, n - window);
            if state != State::Free {
                let mut i = n - 1;
                while i >= n - window + 1 {
                    if h[i].slope == 0 {
                        let s = segment(&h, n - window);
                        if s == State::Free {
                            state = s;
                            done = true;
                            break;
                        }
                        rewrite(&mut h, i, -1);
                    }
                    i -= 1;
                }
                if !done {
                    h.truncate(n - window);
                    h.extend(saved);
                    let last = h.len() - 1;
                    rewrite(&mut h, last, 0);
                    state = segment(&h, last);
                }
            }
        }
        if state == State::Invalid {
            break;
        }
        kept = h.len();
        // CreateTunnel, while blocked.
        let mut s = state;
        while s == State::Blocked {
            let last = h[h.len() - 1].p;
            let (mut best_slope, mut best_len, mut best) = (0, 10, State::Invalid);
            for slope in -1..=1 {
                let mut found = State::Invalid;
                let mut k = 1;
                while k < 10 {
                    let q = (last.0 + dir.0 * k, last.1 - slope * k, last.2 + dir.1 * k);
                    let st = g.state(q);
                    if st == State::Invalid {
                        break;
                    }
                    if st == State::Free {
                        found = State::Free;
                        break;
                    }
                    k += 1;
                }
                if k == 10 && found == State::Invalid {
                    found = State::Blocked;
                }
                let better = match (best, found) {
                    (_, State::Invalid) => false,
                    (State::Invalid, _) => true,
                    (State::Blocked, State::Free) => true,
                    (State::Free, State::Free) => k < best_len,
                    (State::Blocked, State::Blocked) => slope == 0,
                    _ => false,
                };
                if better {
                    best_slope = slope;
                    best_len = if found == State::Free { k } else { 10 };
                    best = found;
                }
            }
            // CanSlopesTouch: no straight up after straight down.
            let li = h.len() - 1;
            if h[li].slope != 0 && best_slope != 0 && h[li].slope != best_slope {
                rewrite(&mut h, li, 0);
            }
            h[li].tunnel = true;
            for _ in 1..best_len {
                append(&mut h, best_slope, true);
            }
            s = best;
            if s == State::Invalid {
                break;
            }
            kept = h.len();
        }
        if h.len() >= max || s == State::Invalid {
            break;
        }
    }
    h.truncate(kept.min(max));
    if h.len() < min {
        return None;
    }
    smooth(&mut h);
    (segment(&h, 0) != State::Invalid).then_some(h)
}

/// SmoothTrack: a dip the track climbs back out of within 15 steps, filled
/// level.
fn smooth(h: &mut [Step]) {
    let n = h.len();
    for i in 0..n {
        let y = h[i].p.1;
        let end = (i + 15).min(n - 1);
        if let Some(j) = (i + 2..=end).find(|&j| h[j].p.1 == y) {
            if (i + 1..j).any(|k| h[k].p.1 < y) {
                for st in h[i + 1..j].iter_mut() {
                    st.p.1 = y;
                    st.slope = 0;
                }
            }
        }
    }
}

/// Terraria's minecart tracks (its Micro Biomes pass's long and standard
/// tracks). Returns how many were laid.
pub fn tracks(w: &mut World, rng: &mut Rng, l: &Layers, coast: &Coast) -> usize {
    let track = w.id_of("minecart_track");
    if track == 0 {
        return 0;
    }
    let mut avoid = vec![false; w.defs.len()];
    for (i, d) in w.defs.iter().enumerate() {
        let n = d.name.as_str();
        avoid[i] = i == track as usize || n.ends_with("chest") || n == "wood" || n.ends_with("_platform") || n == "lihzahrd_brick"
            || n.ends_with("altar") || n == "explosives" || n == "detonator"
            || ["blue_brick", "green_brick", "pink_brick", "cracked_blue_brick", "cracked_green_brick", "cracked_pink_brick"].contains(&n)
            || (d.render != RENDER_CUBE && d.solid);
    }
    // Sand and the like over a cut would fall onto the track: hardened.
    let falling: Vec<u16> = ["sand", "ebonsand", "crimsand", "pearlsand", "silt", "slush"].iter().map(|n| w.id_of(n)).filter(|&t| t != 0).collect();
    let hard = match w.id_of("hardened_sand") {
        0 => w.id_of("stone"),
        h => h,
    };
    let aether = crate::shimmer::of(w);
    let area = (w.sx as f64 * w.sz as f64) / (640.0 * 640.0);
    let mut placed = Placed { cells: HashMap::new() };
    let mut laid = 0;
    // Long tracks, then standard ones.
    for (lo_n, hi_n, min_len, max_len) in [(1, 2, 400, 1000), (4, 7, 150, 300)] {
        let want = (rng.range(lo_n, hi_n + 1) as f64 * area).round() as usize;
        let (min, max) = (b(min_len) as usize, b(max_len) as usize);
        let mut made = 0;
        let mut fails = 0;
        while made < want {
            let p = (rng.range(b(10), w.sx - b(10)), rng.range(l.underworld_top + 5, l.surface_base), rng.range(b(10), w.sz - b(10)));
            let len = rng.range(min as i32, max as i32 + 1) as usize;
            let path = {
                let g = Gen { w, l, coast, aether: aether.clone(), avoid: avoid.clone(), placed: &placed };
                // FindSuitableOrigin: down to the ground, one over it free.
                let mut q = p;
                let mut s = g.state(q);
                while s == State::Free {
                    q.1 -= 1;
                    s = g.state(q);
                }
                if s == State::Blocked && g.state((q.0, q.1 + 1, q.2)) == State::Free {
                    let origin = (q.0, q.1 + 1, q.2);
                    // Toward the middle, along x or z.
                    let dir = if rng.range(0, 2) == 0 {
                        (if origin.0 > w.sx / 2 { -1 } else { 1 }, 0)
                    } else {
                        (0, if origin.2 > w.sz / 2 { -1 } else { 1 })
                    };
                    find_path(&g, origin, dir, min, len)
                } else {
                    None
                }
            };
            let Some(path) = path else {
                fails += 1;
                if fails > w.sx / 2 {
                    made += 1;
                    fails = 0;
                }
                continue;
            };
            fails = 0;
            // PlacePath: the rock over it cut 5-8 tiles high (and to each
            // side, across the way it runs), the track laid.
            let (ax, az) = if path.len() > 1 && path[1].p.0 != path[0].p.0 { (0, 1) } else { (1, 0) };
            let mut height = b(rng.range(5, 9));
            for st in &path {
                if rng.range(0, 7) == 0 {
                    height = b(rng.range(5, 9));
                }
                let (x, y, z) = st.p;
                for side in -CUT_SIDE..=CUT_SIDE {
                    let (cx, cz) = (x + ax * side, z + az * side);
                    if !w.in_bounds(cx, y, cz) || w.structures.iter().any(|&(lo, hi)| cx >= lo.0 && cx <= hi.0 && y >= lo.1 && y <= hi.1 && cz >= lo.2 && cz <= hi.2) {
                        continue;
                    }
                    for k in (if side == 0 { 1 } else { 0 })..height {
                        if !w.in_bounds(cx, y + k, cz) {
                            break;
                        }
                        let i = w.idx(cx, y + k, cz);
                        if w.blocks[i] != 0 && !avoid[w.blocks[i] as usize] {
                            w.blocks[i] = 0;
                        }
                    }
                    if w.in_bounds(cx, y + height, cz) && falling.contains(&w.get(cx, y + height, cz)) {
                        let i = w.idx(cx, y + height, cz);
                        w.blocks[i] = hard;
                    }
                }
                let i = w.idx(x, y, z);
                w.blocks[i] = track;
                w.liquid[i] = 0;
                placed.add(st.p);
            }
            laid += 1;
            made += 1;
        }
    }
    laid
}
