//! Shrinking a supersampled render to sprite pixels without blur (the NPC
//! picker's "rendered" method, NPCRenders): each output pixel takes the colour
//! covering most of its `factor` x `factor` block of samples, and is opaque only
//! if at least half the block is, so the shrunk sprite has crisp pixel-art
//! edges and no colours blended across a pixel's edge.

/// `data`: RGBA8, `w` x `h`; returns RGBA8 of (w / factor) x (h / factor).
pub fn shrink_majority(data: &[u8], w: usize, h: usize, factor: usize) -> Vec<u8> {
    let f = factor.max(1);
    let (ow, oh) = (w / f, h / f);
    let mut out = vec![0u8; ow * oh * 4];
    let mut counts: Vec<([u8; 3], usize)> = Vec::with_capacity(f * f);
    for oy in 0..oh {
        for ox in 0..ow {
            counts.clear();
            let mut cover = 0;
            for y in oy * f..(oy + 1) * f {
                for x in ox * f..(ox + 1) * f {
                    let i = (y * w + x) * 4;
                    if data[i + 3] < 128 {
                        continue;
                    }
                    cover += 1;
                    let c = [data[i], data[i + 1], data[i + 2]];
                    match counts.iter_mut().find(|e| e.0 == c) {
                        Some(e) => e.1 += 1,
                        None => counts.push((c, 1)),
                    }
                }
            }
            if cover * 2 < f * f {
                continue;
            }
            // The most common colour (the first seen of equals).
            let best = counts.iter().fold(counts[0], |a, b| if b.1 > a.1 { *b } else { a });
            let o = (oy * ow + ox) * 4;
            out[o..o + 3].copy_from_slice(&best.0);
            out[o + 3] = 255;
        }
    }
    out
}

/// Draws a one-pixel outline round the opaque parts of an RGBA8 image (`w` x
/// `h`), as Terraria's sprites have: each see-through pixel beside an opaque one
/// (left, right, above or below) takes the mean colour of those neighbours
/// times `shade`, opaque (the NPC picker's rendered "outline", on every shot).
pub fn outline(data: &[u8], w: usize, h: usize, shade: f32) -> Vec<u8> {
    let mut out = data.to_vec();
    let opaque = |x: usize, y: usize| data[(y * w + x) * 4 + 3] >= 128;
    for y in 0..h {
        for x in 0..w {
            if opaque(x, y) {
                continue;
            }
            let mut sum = [0f32; 3];
            let mut n = 0;
            let mut near = |nx: usize, ny: usize| {
                if opaque(nx, ny) {
                    let i = (ny * w + nx) * 4;
                    for c in 0..3 {
                        sum[c] += data[i + c] as f32;
                    }
                    n += 1;
                }
            };
            if x > 0 {
                near(x - 1, y);
            }
            if x + 1 < w {
                near(x + 1, y);
            }
            if y > 0 {
                near(x, y - 1);
            }
            if y + 1 < h {
                near(x, y + 1);
            }
            if n == 0 {
                continue;
            }
            let i = (y * w + x) * 4;
            for c in 0..3 {
                out[i + c] = (sum[c] / n as f32 * shade).round().clamp(0.0, 255.0) as u8;
            }
            out[i + 3] = 255;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_pixel_takes_its_blocks_main_colour_and_crisp_alpha() {
        // A 4x2 image shrunk by 2: block 0 mostly red with one green sample,
        // block 1 only one sample covered (under half: clear).
        let (r, g, clear) = ([255, 0, 0, 255], [0, 255, 0, 255], [9, 9, 9, 0]);
        let px = [r, r, g, clear, r, g, clear, clear];
        let data: Vec<u8> = px.iter().flatten().copied().collect();
        let out = shrink_majority(&data, 4, 2, 2);
        assert_eq!(out, vec![255, 0, 0, 255, 0, 0, 0, 0]);
        // Exactly half covered is opaque, in the covering colour.
        let px = [g, clear, g, clear];
        let data: Vec<u8> = px.iter().flatten().copied().collect();
        assert_eq!(shrink_majority(&data, 2, 2, 2), vec![0, 255, 0, 255]);
    }

    #[test]
    fn outline_rings_opaque_pixels() {
        // One opaque pixel in the middle of 3 x 3: its four sides get the
        // outline (its colour, darkened), the corners stay see-through.
        let mut img = vec![0u8; 3 * 3 * 4];
        img[16..20].copy_from_slice(&[200, 100, 40, 255]);
        let out = outline(&img, 3, 3, 0.25);
        for (x, y) in [(1, 0), (0, 1), (2, 1), (1, 2)] {
            let i = (y * 3 + x) * 4;
            assert_eq!(&out[i..i + 4], &[50, 25, 10, 255]);
        }
        for (x, y) in [(0, 0), (2, 0), (0, 2), (2, 2)] {
            assert_eq!(out[(y * 3 + x) * 4 + 3], 0);
        }
        assert_eq!(&out[16..20], &[200, 100, 40, 255]);
    }
}
