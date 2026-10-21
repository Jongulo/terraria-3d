//! Terraria's surface (TerrainPass), in 3D.
//!
//! Terraria walks across its world a column at a time, in stretches of 5-40
//! columns each holding one feature: a plateau (nearly flat, and lasting up to
//! 6 times longer), a hill or a dale (climbing or falling about 1.3 tiles a
//! column) or a mountain or a valley (about 2 a column; none near spawn,
//! whose middle is flat). The height a feature leaves is where the next one
//! starts, so the surface is long flats at different levels joined by
//! straight slopes, not one rolling texture.
//!
//! Here the map is split into regions (a jittered grid of sites, its borders
//! warped by noise): each region is one of those features, at its own level
//! (a broad rise and fall of the land plus the feature's step up or down).
//! Between two regions the ground slopes from one level to the other at the
//! steeper of their features' slopes, centred on the border; inside a region
//! a mountain is a massif: broad shoulders with one to three peaks round its
//! middle, cones at Terraria's mountain slope (1.6-2 blocks a block) that
//! merge into ridges, rounded only at the tips (a hill rises to a low dome, a
//! valley or dale sinks to a hollow). Then a little noise, and a
//! light blur that rounds off the corners where slopes meet flats.

use crate::worldgen::{noise, Layers};
use fastnoise_lite::FastNoiseLite;
use rayon::prelude::*;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Feature {
    Plateau,
    Hill,
    Dale,
    Mountain,
    Valley,
}

impl Feature {
    /// Terraria's slope for it, in blocks of height per block across.
    fn slope(self) -> f32 {
        match self {
            Feature::Plateau => 1.0,
            Feature::Hill | Feature::Dale => 1.3,
            Feature::Mountain | Feature::Valley => 2.0,
        }
    }
}

/// Regions this many blocks apart (on average).
const CELL: f32 = 64.0;
/// How far the region borders wander (blocks).
const WARP: f32 = 22.0;
/// The narrowest slope between two regions' levels (blocks across): Terraria
/// keeps a slope up for 5-40 columns, so a change of level is a ramp, not a
/// wall (mountains still rise steeply to their peaks).
const MIN_RAMP: f32 = 14.0;
/// The flat middle (Terraria flattens the middle 4% of its world and keeps
/// mountains and valleys out of the middle 10%): within this share of the
/// world's width of its middle the ground is flat, blending back to the
/// regions' over as far again; within MIDDLE_PLATEAU of it the regions are
/// plateaus, within MIDDLE_GENTLE no mountains or valleys.
const SPAWN_FLAT: f32 = 0.025;
const MIDDLE_PLATEAU: f32 = 0.05;
const MIDDLE_GENTLE: f32 = 0.1;

#[derive(Clone, Copy)]
struct Site {
    x: f32,
    z: f32,
    level: f32,
    feature: Feature,
    /// How far a mountain's peak (or a valley's hollow...) rises (falls)
    /// above (below) its level, at most.
    peak: f32,
    /// A mountain's slope (blocks of height per block across), and its peaks:
    /// (x, z, height above its level), the first peak_count of them.
    steep: f32,
    peaks: [(f32, f32, f32); 3],
    peak_count: usize,
    /// Its weight in the split (a power diagram): heavier sites claim bigger
    /// regions, so they come in many sizes (Terraria's stretches run 5-40
    /// columns, its plateaus up to 6 times that).
    weight: f32,
}

pub struct Terrain {
    seed: u64,
    base: f32,
    lo: f32,
    hi: f32,
    center: (f32, f32),
    /// The world's narrower side (the middle's sizes are shares of it).
    width: f32,
    land: FastNoiseLite,
    warp_x: FastNoiseLite,
    warp_z: FastNoiseLite,
    roll: FastNoiseLite,
    detail: FastNoiseLite,
    ridge: FastNoiseLite,
}

fn hash(seed: u64, gx: i32, gz: i32, salt: u64) -> u64 {
    let mut z = seed ^ (gx as u64).wrapping_mul(0x9e3779b97f4a7c15) ^ (gz as u64).wrapping_mul(0xc2b2ae3d27d4eb4f) ^ salt.wrapping_mul(0x165667b19e3779f9);
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
    z ^ (z >> 31)
}

fn unit(h: u64) -> f32 {
    (h >> 40) as f32 / (1u64 << 24) as f32
}

impl Terrain {
    /// The surface for a world `sx` x `sz`: its land between `surface_base`
    /// - 9 and 5 below the Space layer (the range the other passes expect).
    pub fn new(seed: i32, l: &Layers, sx: i32, sz: i32) -> Terrain {
        let base = l.surface_base as f32;
        Terrain {
            seed: seed as u64 ^ 0x7e44_a1d5_3a5c_0001,
            base: base + 4.0,
            lo: base - 9.0,
            hi: l.space_top as f32 - 5.0,
            center: (sx as f32 * 0.5, sz as f32 * 0.5),
            width: sx.min(sz) as f32,
            land: noise(seed + 40, 1.0 / 350.0, 2),
            warp_x: noise(seed + 41, 1.0 / 120.0, 2),
            warp_z: noise(seed + 42, 1.0 / 120.0, 2),
            roll: noise(seed + 43, 0.012, 2),
            detail: noise(seed + 44, 0.035, 2),
            ridge: noise(seed + 45, 0.06, 2),
        }
    }

    /// A grid cell's site: its spot, feature and level.
    fn site(&self, gx: i32, gz: i32) -> Site {
        let r = |salt: u64| unit(hash(self.seed, gx, gz, salt));
        let x = (gx as f32 + 0.15 + 0.7 * r(1)) * CELL;
        let z = (gz as f32 + 0.15 + 0.7 * r(2)) * CELL;
        let f = r(3);
        // Terraria picks each of its five features equally often, but its
        // plateaus run longer: here a third of the land.
        let mut feature = if f < 0.32 {
            Feature::Plateau
        } else if f < 0.52 {
            Feature::Hill
        } else if f < 0.68 {
            Feature::Dale
        } else if f < 0.84 {
            Feature::Mountain
        } else {
            Feature::Valley
        };
        let from_middle = ((x - self.center.0).powi(2) + (z - self.center.1).powi(2)).sqrt();
        if from_middle < (self.width * MIDDLE_PLATEAU).max(CELL * 0.5) {
            feature = Feature::Plateau;
        } else if from_middle < self.width * MIDDLE_GENTLE && matches!(feature, Feature::Mountain | Feature::Valley) {
            feature = if feature == Feature::Mountain { Feature::Hill } else { Feature::Dale };
        }
        let a = r(4);
        let b = r(5);
        let (step, peak) = match feature {
            Feature::Plateau => (0.0, 0.0),
            Feature::Hill => (3.0 + 5.0 * a, 5.0 + 5.0 * b),
            Feature::Dale => (-(3.0 + 4.0 * a), 2.0 + 3.0 * b),
            // (Mostly climbed on its own slope: a small step to its foot.)
            Feature::Mountain => (2.0 + 4.0 * a, 16.0 + 12.0 * b),
            Feature::Valley => (-(6.0 + 5.0 * a), 4.0 + 5.0 * b),
        };
        let size = if feature == Feature::Plateau { 0.5 + 0.5 * r(6) } else { 0.6 * r(6) };
        // A mountain's peaks: the tallest near its middle, the others lower
        // and off to the sides.
        let mut peaks = [(x, z, peak); 3];
        for (k, p) in peaks.iter_mut().enumerate().skip(1) {
            let a = r(10 + k as u64) * std::f32::consts::TAU;
            let d = CELL * (0.12 + 0.18 * r(20 + k as u64));
            *p = (x + a.cos() * d, z + a.sin() * d, peak * (0.55 + 0.3 * r(30 + k as u64)));
        }
        Site {
            x,
            z,
            level: self.base + self.land.get_noise_2d(x, z) * 4.0 + step,
            feature,
            peak,
            steep: 1.6 + 0.4 * r(7),
            peaks,
            peak_count: 1 + (r(8) * 3.0) as usize,
            weight: (size * CELL * 0.7).powi(2),
        }
    }

    /// The ground's height (blocks, before the blur) at (x, z).
    pub fn raw_height(&self, x: f32, z: f32) -> f32 {
        let wx = x + self.warp_x.get_noise_2d(x, z) * WARP;
        let wz = z + self.warp_z.get_noise_2d(x, z) * WARP;
        let (gx, gz) = ((wx / CELL).floor() as i32, (wz / CELL).floor() as i32);
        let mut sites = [Site { x: 0.0, z: 0.0, level: 0.0, feature: Feature::Plateau, peak: 0.0, steep: 0.0, peaks: [(0.0, 0.0, 0.0); 3], peak_count: 0, weight: 0.0 }; 25];
        let mut d2 = [0.0f32; 25];
        let mut near = 0;
        for k in 0..25 {
            let s = self.site(gx + k as i32 % 5 - 2, gz + k as i32 / 5 - 2);
            d2[k] = (s.x - wx).powi(2) + (s.z - wz).powi(2) - s.weight;
            sites[k] = s;
            if d2[k] < d2[near] {
                near = k;
            }
        }
        let own = sites[near];
        let mut h = own.level;
        // Toward each neighbouring region's level over a slope centred on the
        // border (half of the way on each side), and the distance to the
        // nearest border.
        let mut edge = f32::INFINITY;
        for k in 0..25 {
            if k == near {
                continue;
            }
            let s = sites[k];
            let apart = ((s.x - own.x).powi(2) + (s.z - own.z).powi(2)).sqrt().max(1e-3);
            let e = (d2[k] - d2[near]) / (2.0 * apart);
            edge = edge.min(e);
            let rise = s.level - own.level;
            let half = (rise.abs() / own.feature.slope().max(s.feature.slope())).max(MIN_RAMP) * 0.5;
            if e < half {
                h += rise * 0.5 * (1.0 - e / half);
            }
        }
        // The region's own shape, growing from nothing at its border.
        let shape = |slope: f32, cap: f32| cap * (1.0 - (-edge.max(0.0) * slope / cap.max(1e-3)).exp());
        h += match own.feature {
            Feature::Plateau => 0.0,
            Feature::Hill => shape(0.6, own.peak),
            Feature::Dale => -shape(0.5, own.peak),
            Feature::Mountain => {
                // Its shoulders, then its peaks: cones round its middle
                // (roughened, so the ridges wander) merged smoothly, the tips
                // rounded, their feet eased into the shoulders and faded out
                // near the region's border.
                let rough = self.ridge.get_noise_2d(x, z) * 3.0;
                let mut sum = 0.0;
                for (k, &(px, pz, ph)) in own.peaks.iter().enumerate() {
                    if k >= own.peak_count {
                        break;
                    }
                    let d = ((px - wx).powi(2) + (pz - wz).powi(2) + 4.0).sqrt() + rough;
                    sum += ((ph - d * own.steep) / 2.0).exp();
                }
                let cone = 2.0 * (1.0 + sum).ln();
                shape(0.7, 8.0) + cone * (edge / 6.0).clamp(0.0, 1.0)
            }
            Feature::Valley => -shape(1.0, own.peak),
        };
        h += self.roll.get_noise_2d(x, z) * 2.5 + self.detail.get_noise_2d(x, z) * 1.0;
        // The flat middle.
        let from_middle = ((x - self.center.0).powi(2) + (z - self.center.1).powi(2)).sqrt();
        let flat = self.base + self.land.get_noise_2d(self.center.0, self.center.1) * 5.0;
        let r = (self.width * SPAWN_FLAT).max(8.0);
        let k = ((from_middle - r) / r).clamp(0.0, 1.0);
        let k = k * k * (3.0 - 2.0 * k);
        h = flat + (h - flat) * k;
        // Eased into the top of the band (no flat-cut peaks).
        let knee = self.hi - 6.0;
        if h > knee {
            h = knee + 6.0 * ((h - knee) / 6.0).tanh();
        }
        h.clamp(self.lo, self.hi)
    }

    /// The feature of the region (x, z) lies in.
    pub fn feature_at(&self, x: f32, z: f32) -> Feature {
        let wx = x + self.warp_x.get_noise_2d(x, z) * WARP;
        let wz = z + self.warp_z.get_noise_2d(x, z) * WARP;
        let (gx, gz) = ((wx / CELL).floor() as i32, (wz / CELL).floor() as i32);
        let mut best = (f32::INFINITY, Feature::Plateau);
        for k in 0..25 {
            let s = self.site(gx + k % 5 - 2, gz + k / 5 - 2);
            let d = (s.x - wx).powi(2) + (s.z - wz).powi(2) - s.weight;
            if d < best.0 {
                best = (d, s.feature);
            }
        }
        best.1
    }

    /// Each mountain's peak (x, z): the highest column (of `heights`, from
    /// heights()) within 16 blocks of its site, unwarped back to the map.
    pub fn mountain_peaks(&self, heights: &[f32], sx: i32, sz: i32) -> Vec<(i32, i32)> {
        let mut out = Vec::new();
        for gz in -1..=(sz as f32 / CELL).ceil() as i32 {
            for gx in -1..=(sx as f32 / CELL).ceil() as i32 {
                let s = self.site(gx, gz);
                if s.feature != Feature::Mountain {
                    continue;
                }
                // The map spot the warp sends to the site (a few steps of
                // undoing it).
                let (mut x, mut z) = (s.x, s.z);
                for _ in 0..6 {
                    let (nx, nz) = (s.x - self.warp_x.get_noise_2d(x, z) * WARP, s.z - self.warp_z.get_noise_2d(x, z) * WARP);
                    (x, z) = (nx, nz);
                }
                let mut best: Option<(f32, i32, i32)> = None;
                for dz in -16..=16 {
                    for dx in -16..=16 {
                        let (px, pz) = (x as i32 + dx, z as i32 + dz);
                        if px < 0 || pz < 0 || px >= sx || pz >= sz {
                            continue;
                        }
                        let h = heights[(px + pz * sx) as usize];
                        if best.map_or(true, |b| h > b.0) {
                            best = Some((h, px, pz));
                        }
                    }
                }
                if let Some((_, px, pz)) = best {
                    if self.feature_at(px as f32, pz as f32) == Feature::Mountain {
                        out.push((px, pz));
                    }
                }
            }
        }
        out
    }

    /// Every column's height (x fastest), blurred a little (two passes of a
    /// 5-wide box each way) to round off where slopes meet.
    pub fn heights(&self, sx: i32, sz: i32) -> Vec<f32> {
        let mut h: Vec<f32> = (0..sx * sz)
            .into_par_iter()
            .map(|i| self.raw_height((i % sx) as f32, (i / sx) as f32))
            .collect();
        for _ in 0..2 {
            h = blur(&h, sx, sz, 2);
        }
        h
    }
}

/// A box blur of radius `r`, across then along (edges clamped).
fn blur(h: &[f32], sx: i32, sz: i32, r: i32) -> Vec<f32> {
    let n = (2 * r + 1) as f32;
    let across: Vec<f32> = (0..sx * sz)
        .into_par_iter()
        .map(|i| {
            let (x, z) = (i % sx, i / sx);
            (-r..=r).map(|d| h[((x + d).clamp(0, sx - 1) + z * sx) as usize]).sum::<f32>() / n
        })
        .collect();
    (0..sx * sz)
        .into_par_iter()
        .map(|i| {
            let (x, z) = (i % sx, i / sx);
            (-r..=r).map(|d| across[(x + (z + d).clamp(0, sz - 1) * sx) as usize]).sum::<f32>() / n
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::worldgen::layers;

    fn terrain(seed: i32) -> (Terrain, Layers) {
        let l = layers(384);
        (Terrain::new(seed, &l, 768, 768), l)
    }

    #[test]
    fn stays_in_its_band() {
        let (t, l) = terrain(7);
        let h = t.heights(768, 768);
        let (lo, hi) = h.iter().fold((f32::INFINITY, f32::NEG_INFINITY), |a, &v| (a.0.min(v), a.1.max(v)));
        assert!(lo >= l.surface_base as f32 - 9.0 && hi <= l.space_top as f32 - 5.0, "{lo}..{hi}");
        // And uses it: well over 30 blocks between the lowest valleys and the peaks.
        assert!(hi - lo > 30.0, "{lo}..{hi}");
    }

    #[test]
    fn every_feature_and_flats() {
        let (t, _) = terrain(7);
        let mut seen = std::collections::HashSet::new();
        for z in (0..768).step_by(16) {
            for x in (0..768).step_by(16) {
                seen.insert(format!("{:?}", t.feature_at(x as f32, z as f32)));
            }
        }
        assert_eq!(seen.len(), 5, "{seen:?}");
        // A good share of the land is near flat (Terraria's plateaus), and
        // some of it steep (its mountains: 2 a block).
        let h = t.heights(768, 768);
        let (mut flat, mut steep, mut n) = (0, 0, 0);
        for z in 1..767 {
            for x in 1..767 {
                let i = (x + z * 768) as usize;
                let g = ((h[i + 1] - h[i - 1]).powi(2) + (h[i + 768] - h[i - 768]).powi(2)).sqrt() * 0.5;
                flat += (g < 0.25) as i32;
                steep += (g > 1.0) as i32;
                n += 1;
            }
        }
        assert!(flat as f32 > n as f32 * 0.2 && steep as f32 > n as f32 * 0.02, "flat {flat}, steep {steep} of {n}");
    }

    #[test]
    fn flat_middle_and_deterministic() {
        let (t, _) = terrain(11);
        let c = 384.0;
        let mid = t.raw_height(c, c);
        for (dx, dz) in [(12.0, 0.0), (0.0, -15.0), (-10.0, 10.0)] {
            assert!((t.raw_height(c + dx, c + dz) - mid).abs() < 3.5, "spawn is flat");
        }
        let (t2, _) = terrain(11);
        assert_eq!(t.raw_height(100.0, 200.0), t2.raw_height(100.0, 200.0));
    }
}
