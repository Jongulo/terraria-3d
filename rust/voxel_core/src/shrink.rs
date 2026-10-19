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
}
