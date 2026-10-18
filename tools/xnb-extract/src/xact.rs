//! XACT wave bank (.xwb) and sound bank (.xsb) parsing for Terraria's music.

use crate::xnb::Reader;
use anyhow::{Result, bail};

pub struct Wave<'a> {
    pub channels: u16,
    pub rate: u32,
    pub block_align: u16,
    pub data: &'a [u8],
}

/// Returns every entry of a (non-compact) v46 wave bank as an MS-ADPCM description.
pub fn read_wave_bank(file: &[u8]) -> Result<Vec<Wave<'_>>> {
    let mut r = Reader::new(file);
    if r.bytes(4)? != b"WBND" {
        bail!("not a wave bank");
    }
    let _tool = r.u32()?;
    let _header = r.u32()?;
    let mut segs = [(0usize, 0usize); 5];
    for s in &mut segs {
        *s = (r.u32()? as usize, r.u32()? as usize);
    }
    r.pos = segs[0].0;
    let flags = r.u32()?;
    let count = r.u32()? as usize;
    if flags & 0x20000 != 0 {
        bail!("compact wave banks not supported");
    }
    r.bytes(64)?; // bank name
    let entry_size = r.u32()? as usize;

    let mut waves = Vec::with_capacity(count);
    for i in 0..count {
        r.pos = segs[1].0 + i * entry_size;
        let _flags_duration = r.u32()?;
        let fmt = r.u32()?;
        let offset = r.u32()? as usize;
        let length = r.u32()? as usize;
        let tag = fmt & 3;
        let channels = ((fmt >> 2) & 7) as u16;
        let rate = (fmt >> 5) & 0x3ffff;
        let align = ((fmt >> 23) & 0xff) as u16;
        if tag != 2 {
            bail!("wave {i}: unsupported codec tag {tag}");
        }
        let start = segs[4].0 + offset;
        waves.push(Wave {
            channels,
            rate,
            block_align: (align + 22) * channels,
            data: &file[start..start + length],
        });
    }
    Ok(waves)
}

/// Builds a RIFF/WAVE file with an MS-ADPCM fmt chunk around raw ADPCM blocks.
pub fn adpcm_wav(w: &Wave) -> Vec<u8> {
    const COEFS: [(i16, i16); 7] = [
        (256, 0),
        (512, -256),
        (0, 0),
        (192, 64),
        (240, 0),
        (460, -208),
        (392, -232),
    ];
    let ch = w.channels as u32;
    let samples_per_block = (w.block_align as u32 - 7 * ch) * 8 / (4 * ch) + 2;
    let avg_bytes = w.rate * w.block_align as u32 / samples_per_block;
    let mut fmt = Vec::new();
    fmt.extend_from_slice(&2u16.to_le_bytes());
    fmt.extend_from_slice(&w.channels.to_le_bytes());
    fmt.extend_from_slice(&w.rate.to_le_bytes());
    fmt.extend_from_slice(&avg_bytes.to_le_bytes());
    fmt.extend_from_slice(&w.block_align.to_le_bytes());
    fmt.extend_from_slice(&4u16.to_le_bytes());
    fmt.extend_from_slice(&32u16.to_le_bytes());
    fmt.extend_from_slice(&(samples_per_block as u16).to_le_bytes());
    fmt.extend_from_slice(&7u16.to_le_bytes());
    for (a, b) in COEFS {
        fmt.extend_from_slice(&a.to_le_bytes());
        fmt.extend_from_slice(&b.to_le_bytes());
    }
    riff_wav(&fmt, w.data)
}

pub fn riff_wav(fmt: &[u8], data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() + fmt.len() + 28);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&((20 + fmt.len() + data.len()) as u32).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&(fmt.len() as u32).to_le_bytes());
    out.extend_from_slice(fmt);
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(data);
    out
}

/// Maps cue names (e.g. "Music_1") to wave bank indices. Only simple cues
/// pointing at simple (single-wave) sounds are supported, which is all Terraria uses.
pub fn read_sound_bank(file: &[u8]) -> Result<Vec<(String, usize)>> {
    let mut r = Reader::new(file);
    if r.bytes(4)? != b"SDBK" {
        bail!("not a sound bank");
    }
    r.pos = 0x13;
    let simple = r.u16()? as usize;
    let complex = r.u16()? as usize;
    r.u16()?;
    let total = r.u16()? as usize;
    if complex != 0 || simple != total {
        bail!("complex cues not supported");
    }
    r.pos = 0x22;
    let simple_off = r.u32()? as usize;
    r.u32()?;
    let names_off = r.u32()? as usize;

    r.pos = names_off;
    let mut names = Vec::with_capacity(total);
    for _ in 0..total {
        let start = r.pos;
        while r.u8()? != 0 {}
        names.push(String::from_utf8_lossy(&file[start..r.pos - 1]).into_owned());
    }

    let mut cues = Vec::with_capacity(total);
    for (i, name) in names.into_iter().enumerate() {
        r.pos = simple_off + i * 5;
        r.u8()?;
        let sound_off = r.u32()? as usize;
        r.pos = sound_off;
        let flags = r.u8()?;
        if flags & 1 != 0 {
            bail!("cue {name}: complex sound not supported");
        }
        r.pos = sound_off + 9;
        cues.push((name, r.u16()? as usize));
    }
    Ok(cues)
}
