//! Skinned, walking people from a humans pack (docs/RENDERER.md): the walk
//! cycle (a skinning matrix per person, frame and bone) and the texture
//! atlas their meshes sample. The wgpu renderer uploads both; each walker
//! entity only says which person it is and how far it has walked.

use crate::vfs;
use std::collections::HashMap;
use std::path::Path;

// The matrices and atlas are only read by the wgpu renderer.
#[cfg_attr(not(all(feature = "wgpu-postcard", not(target_arch = "wasm32"))), allow(dead_code))]
pub struct Humans {
    pub people: u32,
    pub frames: u32,
    pub bones: u32,
    /// Metres walked per cycle, per person: the stride that keeps feet planted.
    pub cycle: Vec<f32>,
    /// Rows of 3x4 matrices (game axes), [person][frame][bone]: `frames`
    /// of the walk cycle, then one standing pose.
    pub poses: Vec<[f32; 4]>,
    /// RGBA8 sRGB mip chain, largest first.
    pub atlas: Vec<Mip>,
    /// Mesh id -> person, for the near and far meshes of each.
    pub meshes: HashMap<usize, u32>,
    /// Bumped on every load so the renderer re-uploads.
    pub rev: u64,
}

impl Humans {
    pub fn load(dir: &Path) -> Result<Humans, String> {
        let poses = vfs::read(&dir.join("humans_poses.bin")).map_err(|e| format!("humans_poses.bin: {e}"))?;
        let word = |b: &[u8], at: usize| u32::from_le_bytes(b[at..at + 4].try_into().unwrap());
        if poses.len() < 16 || &poses[..4] != b"HPOS" {
            return Err("humans_poses.bin: bad header".into());
        }
        let (people, frames, bones) = (word(&poses, 4), word(&poses, 8), word(&poses, 12));
        if people == 0 || people > 255 || frames == 0 || frames > 255 || bones == 0 || bones > 32 {
            return Err(format!("humans_poses.bin: {people} people, {frames} frames, {bones} bones is out of range"));
        }
        let floats: Vec<f32> = poses[16..].as_chunks::<4>().0.iter().map(|c| f32::from_le_bytes(*c)).collect();
        let want = people as usize * (1 + (frames as usize + 1) * bones as usize * 12);
        if floats.len() != want {
            return Err(format!("humans_poses.bin: {} floats, expected {want}", floats.len()));
        }
        let (cycle, rest) = floats.split_at(people as usize);
        if cycle.iter().any(|&c| !(c > 0.1 && c < 5.0)) {
            return Err("humans_poses.bin: cycle length out of range".into());
        }
        let atlas = read_atlas(&dir.join("humans_atlas.rgba"))?;
        Ok(Humans {
            people,
            frames,
            bones,
            cycle: cycle.to_vec(),
            poses: rest.as_chunks::<4>().0.to_vec(),
            atlas,
            meshes: HashMap::new(),
            rev: 0,
        })
    }

    #[cfg_attr(not(all(feature = "wgpu-postcard", not(target_arch = "wasm32"))), allow(dead_code))]
    /// Where `person` is in its walk cycle after walking `walked` metres (0..1).
    pub fn phase(&self, person: u32, walked: f32) -> f32 {
        let c = self.cycle.get(person as usize).copied().unwrap_or(1.4);
        (walked / c).rem_euclid(1.0)
    }
}

/// One level of a texture: width, height, RGBA8 bytes (rows top first).
pub type Mip = (u32, u32, Vec<u8>);

/// An atlas file (people's, cars'): "HATL", width, height (u32 LE), then
/// RGBA8 rows, colour in sRGB. Returned with its mip chain.
pub fn read_atlas(path: &Path) -> Result<Vec<Mip>, String> {
    let name = path.file_name().map_or_else(String::new, |n| n.to_string_lossy().into_owned());
    let atlas = vfs::read(path).map_err(|e| format!("{name}: {e}"))?;
    if atlas.len() < 12 || &atlas[..4] != b"HATL" {
        return Err(format!("{name}: bad header"));
    }
    let word = |at: usize| u32::from_le_bytes(atlas[at..at + 4].try_into().unwrap());
    let (w, h) = (word(4), word(8));
    if w == 0 || h == 0 || w > 8192 || h > 8192 || atlas.len() != 12 + (w as usize * h as usize * 4) {
        return Err(format!("{name}: {w}x{h} does not match its size"));
    }
    Ok(mips(w, h, atlas[12..].to_vec()))
}

/// A box-filtered mip chain down to 1 px (in sRGB bytes: close enough for
/// clothes seen from the street; alpha is averaged, so hair thins far off).
fn mips(w: u32, h: u32, top: Vec<u8>) -> Vec<Mip> {
    let mut out = vec![(w, h, top)];
    loop {
        let (w, h, ref src) = *out.last().unwrap();
        if w == 1 && h == 1 {
            return out;
        }
        let (nw, nh) = ((w / 2).max(1), (h / 2).max(1));
        let mut dst = vec![0u8; (nw * nh * 4) as usize];
        for y in 0..nh {
            for x in 0..nw {
                for c in 0..4 {
                    let mut sum = 0u32;
                    for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                        let sx = (x * 2 + dx).min(w - 1);
                        let sy = (y * 2 + dy).min(h - 1);
                        sum += src[((sy * w + sx) * 4 + c) as usize] as u32;
                    }
                    dst[((y * nw + x) * 4 + c) as usize] = ((sum + 2) / 4) as u8;
                }
            }
        }
        out.push((nw, nh, dst));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mip_chain_halves_to_one_pixel() {
        let m = mips(4, 2, vec![255; 4 * 2 * 4]);
        assert_eq!(m.iter().map(|(w, h, _)| (*w, *h)).collect::<Vec<_>>(), [(4, 2), (2, 1), (1, 1)]);
        assert!(m[2].2.iter().all(|&b| b == 255));
    }

    #[test]
    fn phase_wraps_backwards_too() {
        let h = Humans { people: 1, frames: 1, bones: 1, cycle: vec![2.0], poses: vec![], atlas: vec![], meshes: HashMap::new(), rev: 0 };
        assert!((h.phase(0, 3.0) - 0.5).abs() < 1e-6);
        assert!((h.phase(0, -0.5) - 0.75).abs() < 1e-6);
    }
}
