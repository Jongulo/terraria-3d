//! World save files: header, LZ4-compressed block array, decorations and an
//! opaque metadata string owned by the game scripts (chests, time, bosses...).
//! Light is not stored; it is recomputed on load (from the stored sky floor:
//! the ground as the world was made, see World::sky_floor).

use crate::world::{Decoration, World};
use std::io::{self, Read, Write};

const MAGIC: &[u8; 4] = b"T3DW";
/// v2 added liquids, v3 the sky floor; older files still load (without liquid;
/// the sky floor taken from the blocks as saved).
const VERSION: u32 = 3;

fn w32(out: &mut impl Write, v: i32) -> io::Result<()> {
    out.write_all(&v.to_le_bytes())
}

fn r32(inp: &mut impl Read) -> io::Result<i32> {
    let mut b = [0; 4];
    inp.read_exact(&mut b)?;
    Ok(i32::from_le_bytes(b))
}

/// The block array as little-endian bytes: the array itself on little-endian
/// machines (no copy: a large world's blocks are gigabytes), else a copy.
fn block_bytes(blocks: &[u16]) -> std::borrow::Cow<'_, [u8]> {
    if cfg!(target_endian = "little") {
        // SAFETY: u16 has no padding and any byte pattern is valid; the slice
        // covers exactly the array's memory.
        std::borrow::Cow::Borrowed(unsafe { std::slice::from_raw_parts(blocks.as_ptr() as *const u8, blocks.len() * 2) })
    } else {
        std::borrow::Cow::Owned(blocks.iter().flat_map(|b| b.to_le_bytes()).collect())
    }
}

fn wstr(out: &mut impl Write, s: &str) -> io::Result<()> {
    w32(out, s.len() as i32)?;
    out.write_all(s.as_bytes())
}

fn rstr(inp: &mut impl Read) -> io::Result<String> {
    let n = r32(inp)? as usize;
    let mut b = vec![0; n];
    inp.read_exact(&mut b)?;
    String::from_utf8(b).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}

pub fn save(w: &World, meta: &str, out: &mut impl Write) -> io::Result<()> {
    out.write_all(MAGIC)?;
    w32(out, VERSION as i32)?;
    for v in [w.sx, w.sy, w.sz, w.seed, w.spawn.0, w.spawn.1, w.spawn.2] {
        w32(out, v)?;
    }
    let packed = lz4_flex::compress_prepend_size(&block_bytes(&w.blocks));
    w32(out, packed.len() as i32)?;
    out.write_all(&packed)?;
    let packed = lz4_flex::compress_prepend_size(&w.liquid);
    w32(out, packed.len() as i32)?;
    out.write_all(&packed)?;
    let floor: Vec<u8> = w.sky_floor.iter().flat_map(|v| v.to_le_bytes()).collect();
    let packed = lz4_flex::compress_prepend_size(&floor);
    w32(out, packed.len() as i32)?;
    out.write_all(&packed)?;
    w32(out, w.decorations.len() as i32)?;
    for d in &w.decorations {
        wstr(out, &d.kind)?;
        for v in [d.pos.0, d.pos.1, d.pos.2, d.style] {
            w32(out, v)?;
        }
    }
    wstr(out, meta)
}

/// Loads into `w` (block definitions are kept) and returns the metadata string.
pub fn load(w: &mut World, inp: &mut impl Read) -> io::Result<String> {
    let bad = |m: &str| io::Error::new(io::ErrorKind::InvalidData, m.to_string());
    let mut magic = [0; 4];
    inp.read_exact(&mut magic)?;
    if &magic != MAGIC {
        return Err(bad("not a world file"));
    }
    let version = r32(inp)? as u32;
    if version == 0 || version > VERSION {
        return Err(bad("unsupported world version"));
    }
    let (sx, sy, sz) = (r32(inp)?, r32(inp)?, r32(inp)?);
    let seed = r32(inp)?;
    let spawn = (r32(inp)?, r32(inp)?, r32(inp)?);
    let mut packed = vec![0; r32(inp)? as usize];
    inp.read_exact(&mut packed)?;
    // Straight into the block array (the size is prepended, little-endian).
    let cells = sx as usize * sy as usize * sz as usize;
    if packed.len() < 4 || u32::from_le_bytes([packed[0], packed[1], packed[2], packed[3]]) as usize != cells * 2 {
        return Err(bad("block data size mismatch"));
    }
    w.resize(sx, sy, sz);
    w.seed = seed;
    w.spawn = spawn;
    // SAFETY: as in block_bytes; every byte pattern is a valid u16.
    let out = unsafe { std::slice::from_raw_parts_mut(w.blocks.as_mut_ptr() as *mut u8, cells * 2) };
    let n = lz4_flex::block::decompress_into(&packed[4..], out).map_err(|e| bad(&e.to_string()))?;
    if n != cells * 2 {
        return Err(bad("block data size mismatch"));
    }
    drop(packed);
    if cfg!(target_endian = "big") {
        for b in w.blocks.iter_mut() {
            *b = u16::from_le(*b);
        }
    }
    if version >= 2 {
        let mut packed = vec![0; r32(inp)? as usize];
        inp.read_exact(&mut packed)?;
        let liquid = lz4_flex::decompress_size_prepended(&packed).map_err(|e| bad(&e.to_string()))?;
        if liquid.len() != w.liquid.len() {
            return Err(bad("liquid data size mismatch"));
        }
        w.liquid = liquid;
    }
    if version >= 3 {
        let mut packed = vec![0; r32(inp)? as usize];
        inp.read_exact(&mut packed)?;
        let floor = lz4_flex::decompress_size_prepended(&packed).map_err(|e| bad(&e.to_string()))?;
        // (Empty when saved before any relight: taken from the blocks below.)
        if floor.len() == (sx * sz) as usize * 2 {
            w.sky_floor = floor.chunks_exact(2).map(|b| i16::from_le_bytes([b[0], b[1]])).collect();
        }
    }
    for _ in 0..r32(inp)? {
        let kind = rstr(inp)?;
        let pos = (r32(inp)?, r32(inp)?, r32(inp)?);
        let style = r32(inp)?;
        w.decorations.push(Decoration { kind, pos, style });
    }
    let meta = rstr(inp)?;
    w.compute_all_light();
    w.activate_unsettled_liquid();
    Ok(meta)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::tests::test_world;

    #[test]
    fn round_trip() {
        let mut w = test_world();
        w.set(3, 40, 3, 2);
        // A dug shaft: dim below the ground, after loading too.
        for y in 24..32 {
            w.set(9, y, 9, 0);
        }
        w.set_liquid(5, 32, 5, crate::world::LIQ_LAVA, 30);
        w.decorations.push(Decoration {
            kind: "chest".into(),
            pos: (1, 2, 3),
            style: 4,
        });
        let mut buf = Vec::new();
        save(&w, "{\"time\":1}", &mut buf).unwrap();
        let mut w2 = test_world();
        let meta = load(&mut w2, &mut buf.as_slice()).unwrap();
        assert_eq!(meta, "{\"time\":1}");
        assert!(w.blocks == w2.blocks);
        assert!(w.light == w2.light);
        assert!(w.sky_floor == w2.sky_floor && w2.sky_floor_at(9, 9) == 31);
        assert_eq!(crate::world::unpack_light(w2.light_at(9, 24, 9))[0], 7);
        assert!(w.liquid == w2.liquid);
        assert_eq!(w2.decorations[0].pos, (1, 2, 3));
    }
}
