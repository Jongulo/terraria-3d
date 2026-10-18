//! XNB container reader (XNA 4.0 / FNA) with LZX decompression and the
//! handful of content types Terraria uses: Texture2D, SoundEffect, SpriteFont.

use anyhow::{Context, Result, anyhow, bail};
use lzxd::{Lzxd, WindowSize};

pub struct Reader<'a> {
    pub data: &'a [u8],
    pub pos: usize,
}

impl<'a> Reader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }
    pub fn bytes(&mut self, n: usize) -> Result<&'a [u8]> {
        let end = self.pos + n;
        if end > self.data.len() {
            bail!("unexpected end of data (want {n} at {})", self.pos);
        }
        let s = &self.data[self.pos..end];
        self.pos = end;
        Ok(s)
    }
    pub fn u8(&mut self) -> Result<u8> {
        Ok(self.bytes(1)?[0])
    }
    pub fn u16(&mut self) -> Result<u16> {
        Ok(u16::from_le_bytes(self.bytes(2)?.try_into()?))
    }
    pub fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.bytes(4)?.try_into()?))
    }
    pub fn i32(&mut self) -> Result<i32> {
        Ok(self.u32()? as i32)
    }
    pub fn f32(&mut self) -> Result<f32> {
        Ok(f32::from_bits(self.u32()?))
    }
    pub fn var_u32(&mut self) -> Result<u32> {
        let mut result = 0u32;
        let mut shift = 0;
        loop {
            let b = self.u8()?;
            result |= ((b & 0x7f) as u32) << shift;
            if b & 0x80 == 0 {
                return Ok(result);
            }
            shift += 7;
        }
    }
    pub fn string(&mut self) -> Result<String> {
        let len = self.var_u32()? as usize;
        Ok(String::from_utf8_lossy(self.bytes(len)?).into_owned())
    }
    /// A .NET `char` as written by BinaryWriter (UTF-8 encoded).
    pub fn utf8_char(&mut self) -> Result<char> {
        let b0 = self.u8()?;
        let len = match b0 {
            0x00..=0x7f => 1,
            0xc0..=0xdf => 2,
            0xe0..=0xef => 3,
            _ => 4,
        };
        let mut buf = vec![b0];
        buf.extend_from_slice(self.bytes(len - 1)?);
        std::str::from_utf8(&buf)?
            .chars()
            .next()
            .ok_or_else(|| anyhow!("bad char"))
    }
}

/// Returns the decompressed XNB payload (everything after the header).
pub fn decompress(file: &[u8]) -> Result<Vec<u8>> {
    if file.len() < 10 || &file[0..3] != b"XNB" {
        bail!("not an XNB file");
    }
    let flags = file[5];
    let file_size = u32::from_le_bytes(file[6..10].try_into()?) as usize;
    if flags & 0x80 == 0 && flags & 0x40 == 0 {
        return Ok(file[10..].to_vec());
    }
    if flags & 0x40 != 0 {
        bail!("LZ4-compressed XNB not supported");
    }
    let out_size = u32::from_le_bytes(file[10..14].try_into()?) as usize;
    let end = file_size.min(file.len());
    let mut pos = 14;
    let mut out = Vec::with_capacity(out_size);
    let mut lzx = Lzxd::new(WindowSize::KB64);
    while pos + 2 <= end && out.len() < out_size {
        let mut hi = file[pos] as usize;
        let mut lo = file[pos + 1] as usize;
        let mut block_size = (hi << 8) | lo;
        let mut frame_size = 0x8000;
        if hi == 0xff {
            hi = lo;
            lo = file[pos + 2] as usize;
            frame_size = (hi << 8) | lo;
            block_size = ((file[pos + 3] as usize) << 8) | file[pos + 4] as usize;
            pos += 5;
        } else {
            pos += 2;
        }
        if block_size == 0 || frame_size == 0 {
            break;
        }
        let frame_size = frame_size.min(out_size - out.len());
        let chunk = file
            .get(pos..pos + block_size)
            .context("truncated LZX block")?;
        let decoded = lzx
            .decompress_next(chunk, frame_size)
            .map_err(|e| anyhow!("lzx: {e:?}"))?;
        out.extend_from_slice(decoded);
        pos += block_size;
    }
    if out.len() != out_size {
        bail!("decompressed {} bytes, expected {out_size}", out.len());
    }
    Ok(out)
}

pub struct Texture {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

pub struct Sound {
    pub format: Vec<u8>,
    pub data: Vec<u8>,
    pub loop_start: i32,
    pub loop_length: i32,
    pub duration_ms: i32,
}

pub struct FontPage {
    pub texture: Texture,
    pub glyphs: Vec<[i32; 4]>,
    pub cropping: Vec<[i32; 4]>,
    pub chars: Vec<char>,
    pub kerning: Vec<[f32; 3]>,
}

pub struct Font {
    pub line_spacing: i32,
    pub spacing: f32,
    pub default_char: Option<char>,
    pub pages: Vec<FontPage>,
}

pub enum Content {
    Texture(Texture),
    Sound(Sound),
    Font(Font),
}

pub fn parse(payload: &[u8]) -> Result<Content> {
    let mut r = Reader::new(payload);
    let n = r.var_u32()?;
    let mut readers = Vec::new();
    for _ in 0..n {
        readers.push(r.string()?);
        r.i32()?;
    }
    let _shared = r.var_u32()?;
    let id = r.var_u32()? as usize;
    let name = readers
        .get(id.wrapping_sub(1))
        .ok_or_else(|| anyhow!("null root object"))?;
    if name.contains("Texture2DReader") {
        Ok(Content::Texture(read_texture(&mut r)?))
    } else if name.contains("SoundEffectReader") {
        let fmt_len = r.u32()? as usize;
        let format = r.bytes(fmt_len)?.to_vec();
        let data_len = r.u32()? as usize;
        let data = r.bytes(data_len)?.to_vec();
        Ok(Content::Sound(Sound {
            format,
            data,
            loop_start: r.i32()?,
            loop_length: r.i32()?,
            duration_ms: r.i32()?,
        }))
    } else if name.contains("DynamicSpriteFontReader") {
        // ReLogic (Terraria) paged sprite font.
        let spacing = r.f32()?;
        let line_spacing = r.i32()?;
        let default_char = Some(r.utf8_char()?);
        let page_count = r.i32()?;
        let mut pages = Vec::new();
        for _ in 0..page_count {
            r.var_u32()?;
            let texture = read_texture(&mut r)?;
            let glyphs = read_rects(&mut r)?;
            let cropping = read_rects(&mut r)?;
            r.var_u32()?;
            let count = r.u32()?;
            let chars = (0..count)
                .map(|_| r.utf8_char())
                .collect::<Result<Vec<_>>>()?;
            r.var_u32()?;
            let count = r.u32()?;
            let mut kerning = Vec::with_capacity(count as usize);
            for _ in 0..count {
                kerning.push([r.f32()?, r.f32()?, r.f32()?]);
            }
            if glyphs.len() != chars.len() || cropping.len() != chars.len() {
                bail!("font page list lengths disagree");
            }
            pages.push(FontPage {
                texture,
                glyphs,
                cropping,
                chars,
                kerning,
            });
        }
        Ok(Content::Font(Font {
            line_spacing,
            spacing,
            default_char,
            pages,
        }))
    } else {
        bail!("unsupported content type {name}")
    }
}

fn read_rects(r: &mut Reader) -> Result<Vec<[i32; 4]>> {
    r.var_u32()?;
    let count = r.u32()?;
    (0..count)
        .map(|_| Ok([r.i32()?, r.i32()?, r.i32()?, r.i32()?]))
        .collect()
}

fn read_texture(r: &mut Reader) -> Result<Texture> {
    let format = r.i32()?;
    let width = r.u32()?;
    let height = r.u32()?;
    let _mips = r.u32()?;
    let size = r.u32()? as usize;
    let data = r.bytes(size)?;
    let mut rgba = match format {
        0 => data.to_vec(),
        4 | 5 | 6 => decode_dxt(format, width, height, data)?,
        _ => bail!("unsupported surface format {format}"),
    };
    unpremultiply(&mut rgba);
    Ok(Texture {
        width,
        height,
        rgba,
    })
}

/// XNA's content pipeline stores textures with premultiplied alpha.
pub fn unpremultiply(rgba: &mut [u8]) {
    for px in rgba.chunks_exact_mut(4) {
        let a = px[3] as u32;
        if a == 0 {
            px[0] = 0;
            px[1] = 0;
            px[2] = 0;
        } else if a < 255 {
            for c in &mut px[0..3] {
                *c = ((*c as u32 * 255 + a / 2) / a).min(255) as u8;
            }
        }
    }
}

fn rgb565(c: u16) -> [u32; 3] {
    let r = (c >> 11) as u32 & 31;
    let g = (c >> 5) as u32 & 63;
    let b = c as u32 & 31;
    [(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)]
}

/// Decodes DXT1 (4), DXT3 (5) or DXT5 (6) into RGBA8.
fn decode_dxt(format: i32, width: u32, height: u32, data: &[u8]) -> Result<Vec<u8>> {
    let (w, h) = (width as usize, height as usize);
    let block_bytes = if format == 4 { 8 } else { 16 };
    let (bw, bh) = (w.div_ceil(4), h.div_ceil(4));
    if data.len() < bw * bh * block_bytes {
        bail!("DXT data too short");
    }
    let mut out = vec![0u8; w * h * 4];
    for by in 0..bh {
        for bx in 0..bw {
            let blk = &data[(by * bw + bx) * block_bytes..][..block_bytes];
            let (alpha_blk, color_blk) = if format == 4 {
                (&blk[0..0], &blk[0..8])
            } else {
                (&blk[0..8], &blk[8..16])
            };
            let c0 = u16::from_le_bytes([color_blk[0], color_blk[1]]);
            let c1 = u16::from_le_bytes([color_blk[2], color_blk[3]]);
            let (p0, p1) = (rgb565(c0), rgb565(c1));
            let mut pal = [[0u32; 4]; 4];
            pal[0] = [p0[0], p0[1], p0[2], 255];
            pal[1] = [p1[0], p1[1], p1[2], 255];
            if format != 4 || c0 > c1 {
                for i in 0..3 {
                    pal[2][i] = (2 * p0[i] + p1[i]) / 3;
                    pal[3][i] = (p0[i] + 2 * p1[i]) / 3;
                }
                pal[2][3] = 255;
                pal[3][3] = 255;
            } else {
                for i in 0..3 {
                    pal[2][i] = (p0[i] + p1[i]) / 2;
                }
                pal[2][3] = 255;
                pal[3] = [0, 0, 0, 0];
            }
            let indices = u32::from_le_bytes(color_blk[4..8].try_into()?);
            let mut alphas = [255u32; 16];
            if format == 5 {
                let bits = u64::from_le_bytes(alpha_blk.try_into()?);
                for (i, a) in alphas.iter_mut().enumerate() {
                    *a = ((bits >> (i * 4)) & 15) as u32 * 17;
                }
            } else if format == 6 {
                let (a0, a1) = (alpha_blk[0] as u32, alpha_blk[1] as u32);
                let mut ap = [a0, a1, 0, 0, 0, 0, 0, 0];
                if a0 > a1 {
                    for i in 1..7 {
                        ap[i + 1] = ((7 - i as u32) * a0 + i as u32 * a1) / 7;
                    }
                } else {
                    for i in 1..5 {
                        ap[i + 1] = ((5 - i as u32) * a0 + i as u32 * a1) / 5;
                    }
                    ap[6] = 0;
                    ap[7] = 255;
                }
                let mut bits = 0u64;
                for (i, b) in alpha_blk[2..8].iter().enumerate() {
                    bits |= (*b as u64) << (8 * i);
                }
                for (i, a) in alphas.iter_mut().enumerate() {
                    *a = ap[((bits >> (i * 3)) & 7) as usize];
                }
            }
            for py in 0..4 {
                for px in 0..4 {
                    let (x, y) = (bx * 4 + px, by * 4 + py);
                    if x >= w || y >= h {
                        continue;
                    }
                    let i = py * 4 + px;
                    let c = pal[((indices >> (i * 2)) & 3) as usize];
                    let a = if format == 4 { c[3] } else { alphas[i] };
                    out[(y * w + x) * 4..][..4]
                        .copy_from_slice(&[c[0] as u8, c[1] as u8, c[2] as u8, a as u8]);
                }
            }
        }
    }
    Ok(out)
}
