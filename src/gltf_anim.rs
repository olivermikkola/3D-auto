//! glTF 2.0 animation clips: names, duration, and linear sampling of
//! translation / rotation / scale channels. Skinning applies the resulting
//! joint poses (see Mesh::apply_skin). Lua: `engine.load_anim_clips(path)`.

use crate::vfs;
use base64::Engine as _;
use serde_json::Value;
use std::path::Path;

// Channel data and sampling are only read by tests until skinned characters
// are drawn (Mesh::apply_skin is not wired to the renderer yet).
#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct AnimChannel {
    pub node: usize,
    pub path: AnimPath,
    pub times: Vec<f32>,
    /// translation/scale: xyz triples; rotation: xyzw quaternions.
    pub values: Vec<f32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AnimPath {
    Translation,
    Rotation,
    Scale,
}

#[derive(Clone, Debug)]
pub struct AnimClip {
    pub name: String,
    pub duration: f32,
    pub channels: Vec<AnimChannel>,
}

pub fn load_clips(path: &Path) -> Result<Vec<AnimClip>, String> {
    let bytes = vfs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let is_glb = path.extension().and_then(|e| e.to_str()).is_some_and(|e| e.eq_ignore_ascii_case("glb")) || bytes.starts_with(b"glTF");
    if is_glb {
        let (json, bin) = split_glb(&bytes)?;
        return parse_clips(&json, Some(&bin));
    }
    let src = String::from_utf8(bytes).map_err(|e| format!("{}: {e}", path.display()))?;
    let dir = path.parent().unwrap_or(Path::new("."));
    parse_clips(&src, None).or_else(|_| {
        // External buffers: only needed if accessors aren't in a data URI; rare for anim-only tests.
        let _ = dir;
        parse_clips(&src, None)
    })
}

fn split_glb(bytes: &[u8]) -> Result<(String, Vec<u8>), String> {
    if bytes.len() < 12 || &bytes[0..4] != b"glTF" {
        return Err("glb: bad magic".into());
    }
    let total = u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;
    let mut off = 12;
    let mut json = None;
    let mut bin = Vec::new();
    while off + 8 <= total.min(bytes.len()) {
        let chunk_len = u32::from_le_bytes(bytes[off..off + 4].try_into().unwrap()) as usize;
        let ty = &bytes[off + 4..off + 8];
        off += 8;
        if off + chunk_len > bytes.len() {
            return Err("glb: chunk past end".into());
        }
        let data = &bytes[off..off + chunk_len];
        off += chunk_len;
        match ty {
            b"JSON" => json = Some(std::str::from_utf8(data).map_err(|e| format!("glb json: {e}"))?.to_string()),
            b"BIN\0" => bin = data.to_vec(),
            _ => {}
        }
    }
    Ok((json.ok_or("glb: no JSON")?, bin))
}

fn decode_data_uri(uri: &str) -> Option<Result<Vec<u8>, String>> {
    let rest = uri.strip_prefix("data:")?;
    let b64 = rest.split(',').nth(1)?;
    Some(base64::engine::general_purpose::STANDARD.decode(b64.trim()).map_err(|e| format!("gltf base64: {e}")))
}

pub fn parse_clips(src: &str, glb_bin: Option<&[u8]>) -> Result<Vec<AnimClip>, String> {
    let root: Value = serde_json::from_str(src).map_err(|e| format!("gltf json: {e}"))?;
    let buffers_json = root.get("buffers").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let mut buffers = Vec::new();
    for (i, b) in buffers_json.iter().enumerate() {
        if let Some(uri) = b.get("uri").and_then(|u| u.as_str()) {
            buffers.push(match decode_data_uri(uri) {
                Some(d) => d?,
                None => return Err(format!("gltf anim: external buffer {i} not supported here")),
            });
        } else if let Some(bin) = glb_bin {
            let want = b.get("byteLength").and_then(|v| v.as_u64()).unwrap_or(bin.len() as u64) as usize;
            buffers.push(bin[..want.min(bin.len())].to_vec());
        } else {
            return Err(format!("gltf anim: buffer {i} has no data"));
        }
    }
    let views = root.get("bufferViews").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let accessors = root.get("accessors").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let anims = root.get("animations").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let mut out = Vec::with_capacity(anims.len());
    for (ai, anim) in anims.iter().enumerate() {
        let name = anim.get("name").and_then(|v| v.as_str()).map(|s| s.to_string()).unwrap_or_else(|| format!("anim_{ai}"));
        let samplers = anim.get("samplers").and_then(|v| v.as_array()).cloned().unwrap_or_default();
        let channels_json = anim.get("channels").and_then(|v| v.as_array()).cloned().unwrap_or_default();
        let mut channels = Vec::new();
        let mut duration = 0.0f32;
        for ch in &channels_json {
            let sampler_i = ch.get("sampler").and_then(|v| v.as_u64()).ok_or("anim: channel sampler")? as usize;
            let target = ch.get("target").ok_or("anim: channel target")?;
            let node = target.get("node").and_then(|v| v.as_u64()).ok_or("anim: target node")? as usize;
            let path = match target.get("path").and_then(|v| v.as_str()).unwrap_or("") {
                "translation" => AnimPath::Translation,
                "rotation" => AnimPath::Rotation,
                "scale" => AnimPath::Scale,
                other => return Err(format!("anim: unsupported path '{other}'")),
            };
            let sam = samplers.get(sampler_i).ok_or("anim: missing sampler")?;
            let input_i = sam.get("input").and_then(|v| v.as_u64()).ok_or("anim: sampler input")? as usize;
            let output_i = sam.get("output").and_then(|v| v.as_u64()).ok_or("anim: sampler output")? as usize;
            let times = read_f32s(&accessors, &views, &buffers, input_i, 1)?;
            let comps = match path {
                AnimPath::Rotation => 4,
                _ => 3,
            };
            let values = read_f32s(&accessors, &views, &buffers, output_i, comps)?;
            if let Some(&t) = times.last() {
                duration = duration.max(t);
            }
            channels.push(AnimChannel { node, path, times, values });
        }
        out.push(AnimClip { name, duration, channels });
    }
    Ok(out)
}

/// Linear sample of a channel at time `t` (clamped). Returns 3 or 4 floats.
#[allow(dead_code)] // see AnimChannel
pub fn sample_channel(ch: &AnimChannel, t: f32) -> Result<Vec<f32>, String> {
    let comps = match ch.path {
        AnimPath::Rotation => 4,
        _ => 3,
    };
    if ch.times.is_empty() || ch.values.len() < comps {
        return Err("anim: empty channel".into());
    }
    if ch.times.len() == 1 {
        return Ok(ch.values[..comps].to_vec());
    }
    let t = t.clamp(ch.times[0], *ch.times.last().unwrap());
    let mut i = 0;
    while i + 1 < ch.times.len() && ch.times[i + 1] < t {
        i += 1;
    }
    if i + 1 >= ch.times.len() {
        let start = i * comps;
        return Ok(ch.values[start..start + comps].to_vec());
    }
    let t0 = ch.times[i];
    let t1 = ch.times[i + 1];
    let u = if (t1 - t0).abs() < 1e-8 { 0.0 } else { (t - t0) / (t1 - t0) };
    let a = &ch.values[i * comps..(i + 1) * comps];
    let b = &ch.values[(i + 1) * comps..(i + 2) * comps];
    Ok(a.iter().zip(b).map(|(x, y)| x + (y - x) * u).collect())
}

fn read_f32s(accessors: &[Value], views: &[Value], buffers: &[Vec<u8>], index: usize, comps: usize) -> Result<Vec<f32>, String> {
    let acc = accessors.get(index).ok_or_else(|| format!("anim: missing accessor {index}"))?;
    let count = acc.get("count").and_then(|v| v.as_u64()).ok_or("anim: count")? as usize;
    let component_type = acc.get("componentType").and_then(|v| v.as_u64()).ok_or("anim: componentType")? as u32;
    if component_type != 5126 {
        return Err(format!("anim: expected FLOAT accessor, got {component_type}"));
    }
    let view_i = acc.get("bufferView").and_then(|v| v.as_u64()).ok_or("anim: bufferView")? as usize;
    let acc_off = acc.get("byteOffset").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
    let view = views.get(view_i).ok_or("anim: missing view")?;
    let buf_i = view.get("buffer").and_then(|v| v.as_u64()).ok_or("anim: buffer")? as usize;
    let view_off = view.get("byteOffset").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
    let stride = view.get("byteStride").and_then(|v| v.as_u64()).map(|s| s as usize).unwrap_or(comps * 4);
    let buf = buffers.get(buf_i).ok_or("anim: missing buffer")?;
    let mut out = Vec::with_capacity(count * comps);
    for i in 0..count {
        let off = view_off + acc_off + i * stride;
        if off + comps * 4 > buf.len() {
            return Err("anim: accessor past end".into());
        }
        for k in 0..comps {
            let o = off + k * 4;
            out.push(f32::from_le_bytes(buf[o..o + 4].try_into().unwrap()));
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_vuena_hero_clip_names_and_samples_walk() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tools/cache/characters/vuena-blocky/GLB/blocky_01_hero.glb");
        if !path.exists() {
            eprintln!("skip: fetch_characters.py not run");
            return;
        }
        let clips = load_clips(&path).unwrap();
        let names: Vec<_> = clips.iter().map(|c| c.name.as_str()).collect();
        assert!(names.contains(&"walk"), "{names:?}");
        assert!(names.contains(&"idle"), "{names:?}");
        let walk = clips.iter().find(|c| c.name == "walk").unwrap();
        assert!(walk.duration > 0.5, "duration {}", walk.duration);
        assert!(!walk.channels.is_empty());
        let sample = sample_channel(&walk.channels[0], walk.duration * 0.5).unwrap();
        assert!(sample.len() == 3 || sample.len() == 4, "{sample:?}");
        println!("walk duration={:.2}s channels={} sample0={sample:?}", walk.duration, walk.channels.len());
    }
}
