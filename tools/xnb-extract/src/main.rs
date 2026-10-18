//! Extracts Terraria's content into formats Godot can load at runtime.
//!
//! usage: xnb-extract <Terraria/Content dir> <output dir> [--no-music]

mod xact;
mod xnb;

use anyhow::{Context, Result, bail};
use rayon::prelude::*;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        bail!("usage: xnb-extract <Terraria/Content dir> <output dir> [--no-music]");
    }
    if args[1] == "--dump" {
        let payload = xnb::decompress(&fs::read(&args[2])?)?;
        let mut r = xnb::Reader::new(&payload);
        for _ in 0..r.var_u32()? {
            println!("reader: {}", r.string()?);
            r.i32()?;
        }
        let start = r.pos;
        for row in payload[start..payload.len().min(start + 256)].chunks(32) {
            println!("{}", row.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().join(" "));
        }
        return Ok(());
    }
    let content = PathBuf::from(&args[1]);
    let out = PathBuf::from(&args[2]);
    let music = !args.iter().any(|a| a == "--no-music");

    extract_xnb(&content, &out)?;
    if music {
        extract_music(&content, &out.join("Music"))?;
    }
    Ok(())
}

fn up_to_date(src: &Path, dst: &Path) -> bool {
    match (fs::metadata(src), fs::metadata(dst)) {
        (Ok(s), Ok(d)) => match (s.modified(), d.modified()) {
            (Ok(s), Ok(d)) => d >= s,
            _ => false,
        },
        _ => false,
    }
}

fn extract_xnb(content: &Path, out: &Path) -> Result<()> {
    let files: Vec<PathBuf> = walkdir::WalkDir::new(content)
        .into_iter()
        .filter_map(|e| e.ok())
        .map(|e| e.into_path())
        .filter(|p| p.extension().is_some_and(|e| e == "xnb"))
        .collect();

    let done = [(); 4].map(|_| AtomicUsize::new(0)); // textures, sounds, fonts, skipped
    let errors: Vec<String> = files
        .par_iter()
        .filter_map(|src| {
            let rel = src.strip_prefix(content).unwrap();
            let dst = out.join(rel);
            match convert(src, &dst) {
                Ok(Some(kind)) => {
                    done[kind].fetch_add(1, Ordering::Relaxed);
                    None
                }
                Ok(None) => {
                    done[3].fetch_add(1, Ordering::Relaxed);
                    None
                }
                // Compiled shaders aren't usable outside XNA; skip them.
                Err(e) if e.to_string().contains("EffectReader") => None,
                Err(e) => Some(format!("{}: {e:#}", rel.display())),
            }
        })
        .collect();

    let [t, s, f, k] = done.map(|d| d.into_inner());
    println!("xnb: {t} textures, {s} sounds, {f} fonts written, {k} up to date");
    for e in &errors {
        eprintln!("error: {e}");
    }
    println!("xnb: {} errors", errors.len());
    Ok(())
}

/// Converts one XNB; returns the content kind index written, or None if skipped.
fn convert(src: &Path, dst_base: &Path) -> Result<Option<usize>> {
    let png = dst_base.with_extension("png");
    let wav = dst_base.with_extension("wav");
    let json = dst_base.with_extension("json");
    if up_to_date(src, &png) || up_to_date(src, &wav) || (src.to_string_lossy().contains("Fonts") && up_to_date(src, &json)) {
        return Ok(None);
    }
    let payload = xnb::decompress(&fs::read(src)?)?;
    if let Some(dir) = png.parent() {
        fs::create_dir_all(dir)?;
    }
    match xnb::parse(&payload)? {
        xnb::Content::Texture(t) => {
            write_png(&png, &t)?;
            Ok(Some(0))
        }
        xnb::Content::Sound(s) => {
            fs::write(&wav, xact::riff_wav(&s.format, &s.data))?;
            if s.loop_length > 0 {
                let meta = serde_json::json!({
                    "loop_start": s.loop_start,
                    "loop_length": s.loop_length,
                    "duration_ms": s.duration_ms,
                });
                fs::write(dst_base.with_extension("json"), meta.to_string())?;
            }
            Ok(Some(1))
        }
        xnb::Content::Font(f) => {
            // Fonts/<Name>.json + Fonts/<Name>/page_<n>.png
            let dir = dst_base.with_extension("");
            fs::create_dir_all(&dir)?;
            let mut chars = Vec::new();
            for (p, page) in f.pages.iter().enumerate() {
                write_png(&dir.join(format!("page_{p}.png")), &page.texture)?;
                for i in 0..page.chars.len() {
                    chars.push(serde_json::json!({
                        "char": page.chars[i] as u32,
                        "page": p,
                        "glyph": page.glyphs[i],
                        "crop": page.cropping[i],
                        "kerning": page.kerning[i],
                    }));
                }
            }
            let meta = serde_json::json!({
                "line_spacing": f.line_spacing,
                "spacing": f.spacing,
                "default_char": f.default_char.map(|c| c as u32),
                "pages": f.pages.len(),
                "chars": chars,
            });
            fs::write(dst_base.with_extension("json"), meta.to_string())?;
            Ok(Some(2))
        }
    }
}

fn write_png(path: &Path, t: &xnb::Texture) -> Result<()> {
    let file = fs::File::create(path)?;
    let mut enc = png::Encoder::new(std::io::BufWriter::new(file), t.width, t.height);
    enc.set_color(png::ColorType::Rgba);
    enc.set_depth(png::BitDepth::Eight);
    enc.set_compression(png::Compression::Fast);
    enc.write_header()?.write_image_data(&t.rgba)?;
    Ok(())
}

fn extract_music(content: &Path, out: &Path) -> Result<()> {
    let bank = fs::read(content.join("Wave Bank.xwb")).context("reading wave bank")?;
    let waves = xact::read_wave_bank(&bank)?;
    let cues = xact::read_sound_bank(&fs::read(content.join("Sound Bank.xsb"))?)?;
    fs::create_dir_all(out)?;

    let errors: Vec<String> = cues
        .par_iter()
        .filter_map(|(name, index)| {
            let dst = out.join(format!("{name}.ogg"));
            if dst.exists() {
                return None;
            }
            let wave = waves.get(*index)?;
            encode_ogg(&xact::adpcm_wav(wave), &dst)
                .err()
                .map(|e| format!("{name}: {e:#}"))
        })
        .collect();
    for e in &errors {
        eprintln!("error: {e}");
    }
    println!(
        "music: {} cues, {} waves, {} errors",
        cues.len(),
        waves.len(),
        errors.len()
    );
    Ok(())
}

fn encode_ogg(wav: &[u8], dst: &Path) -> Result<()> {
    let tmp = dst.with_extension("ogg.part");
    let mut child = Command::new("ffmpeg")
        .args(["-v", "error", "-y", "-f", "wav", "-i", "pipe:0"])
        .args(["-c:a", "libvorbis", "-q:a", "5", "-f", "ogg"])
        .arg(&tmp)
        .stdin(Stdio::piped())
        .spawn()
        .context("spawning ffmpeg")?;
    child.stdin.take().unwrap().write_all(wav)?;
    if !child.wait()?.success() {
        bail!("ffmpeg failed");
    }
    fs::rename(tmp, dst)?;
    Ok(())
}
