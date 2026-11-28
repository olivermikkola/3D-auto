//! Minimal glTF 2.0 static mesh load: positions, normals, triangle indices,
//! and a flat baseColorFactor. Skins and animations are ignored here (Wave C3/C4).
//!
//! Supports `.gltf` (data-URI or sibling `.bin`) and binary `.glb`.

use crate::math::{Vec3, v3};
use crate::mesh::{Mesh, SkinInfluence, Vertex};
use crate::vfs;
use base64::Engine as _;
use serde_json::Value;
use std::path::Path;

pub fn load_gltf(path: &Path) -> Result<Mesh, String> {
    let bytes = vfs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let is_glb = path.extension().and_then(|e| e.to_str()).is_some_and(|e| e.eq_ignore_ascii_case("glb")) || bytes.starts_with(b"glTF");
    if is_glb {
        return parse_glb(&bytes);
    }
    let src = String::from_utf8(bytes).map_err(|e| format!("{}: {e}", path.display()))?;
    let dir = path.parent().unwrap_or(Path::new("."));
    parse_gltf(&src, |uri| read_buffer(dir, uri))
}

/// Binary glTF: 12-byte header, JSON chunk, BIN chunk.
pub fn parse_glb(bytes: &[u8]) -> Result<Mesh, String> {
    if bytes.len() < 12 || &bytes[0..4] != b"glTF" {
        return Err("glb: bad magic".into());
    }
    let version = u32::from_le_bytes(bytes[4..8].try_into().unwrap());
    if version != 2 {
        return Err(format!("glb: unsupported version {version}"));
    }
    let total = u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;
    if total > bytes.len() {
        return Err("glb: length past end of file".into());
    }
    let mut off = 12;
    let mut json = None;
    let mut bin = None;
    while off + 8 <= total {
        let chunk_len = u32::from_le_bytes(bytes[off..off + 4].try_into().unwrap()) as usize;
        let chunk_ty = &bytes[off + 4..off + 8];
        off += 8;
        if off + chunk_len > total {
            return Err("glb: chunk past end".into());
        }
        let data = &bytes[off..off + chunk_len];
        off += chunk_len;
        match chunk_ty {
            b"JSON" => {
                json = Some(std::str::from_utf8(data).map_err(|e| format!("glb json: {e}"))?.to_string());
            }
            b"BIN\0" => bin = Some(data.to_vec()),
            _ => {}
        }
    }
    let json = json.ok_or("glb: no JSON chunk")?;
    parse_gltf_doc(&json, bin.as_deref(), |uri| Err(format!("glb: unexpected external uri '{uri}'")))
}

fn decode_data_uri(uri: &str) -> Option<Result<Vec<u8>, String>> {
    let rest = uri.strip_prefix("data:")?;
    let b64 = match rest.split(',').nth(1) {
        Some(b) => b,
        None => return Some(Err("bad data URI".into())),
    };
    Some(base64::engine::general_purpose::STANDARD.decode(b64.trim()).map_err(|e| format!("gltf base64: {e}")))
}

fn read_buffer(dir: &Path, uri: &str) -> Result<Vec<u8>, String> {
    if let Some(decoded) = decode_data_uri(uri) {
        return decoded;
    }
    vfs::read(&dir.join(uri)).map_err(|e| format!("gltf buffer '{uri}': {e}"))
}

/// Parse a glTF JSON document. `read_uri` loads external buffer bytes (data URIs are decoded here).
pub fn parse_gltf(src: &str, read_uri: impl Fn(&str) -> Result<Vec<u8>, String>) -> Result<Mesh, String> {
    parse_gltf_doc(src, None, read_uri)
}

fn parse_gltf_doc(src: &str, glb_bin: Option<&[u8]>, read_uri: impl Fn(&str) -> Result<Vec<u8>, String>) -> Result<Mesh, String> {
    let root: Value = serde_json::from_str(src).map_err(|e| format!("gltf json: {e}"))?;
    let buffers_json = root.get("buffers").and_then(|v| v.as_array()).ok_or("gltf: no buffers")?;
    let mut buffers = Vec::with_capacity(buffers_json.len());
    for (i, b) in buffers_json.iter().enumerate() {
        if let Some(uri) = b.get("uri").and_then(|u| u.as_str()) {
            buffers.push(match decode_data_uri(uri) {
                Some(decoded) => decoded?,
                None => read_uri(uri)?,
            });
        } else if let Some(bin) = glb_bin {
            let want = b.get("byteLength").and_then(|v| v.as_u64()).unwrap_or(bin.len() as u64) as usize;
            if want > bin.len() {
                return Err(format!("glb: buffer {i} longer than BIN chunk"));
            }
            buffers.push(bin[..want].to_vec());
        } else {
            return Err(format!("gltf: buffer {i} has no uri"));
        }
    }
    let views = root.get("bufferViews").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let accessors = root.get("accessors").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let materials = root.get("materials").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let meshes = root.get("meshes").and_then(|v| v.as_array()).ok_or("gltf: no meshes")?;

    let mut out = Mesh::default();
    for mesh in meshes {
        let prims = mesh.get("primitives").and_then(|v| v.as_array()).ok_or("gltf: mesh has no primitives")?;
        for prim in prims {
            let mode = prim.get("mode").and_then(|m| m.as_u64()).unwrap_or(4);
            if mode != 4 {
                return Err(format!("gltf: only TRIANGLES (mode 4) supported, got {mode}"));
            }
            let attrs = prim.get("attributes").ok_or("gltf: primitive has no attributes")?;
            let pos_i = attrs.get("POSITION").and_then(|v| v.as_u64()).ok_or("gltf: no POSITION")? as usize;
            let positions = read_f32x3(&accessors, &views, &buffers, pos_i)?;
            let normals = match attrs.get("NORMAL").and_then(|v| v.as_u64()) {
                Some(i) => read_f32x3(&accessors, &views, &buffers, i as usize)?,
                None => Vec::new(),
            };
            let joints = match attrs.get("JOINTS_0").and_then(|v| v.as_u64()) {
                Some(i) => Some(read_joints(&accessors, &views, &buffers, i as usize)?),
                None => None,
            };
            let weights = match attrs.get("WEIGHTS_0").and_then(|v| v.as_u64()) {
                Some(i) => Some(read_weights(&accessors, &views, &buffers, i as usize)?),
                None => None,
            };
            if joints.is_some() != weights.is_some() {
                return Err("gltf: JOINTS_0 and WEIGHTS_0 must both be present".into());
            }
            let indices = match prim.get("indices").and_then(|v| v.as_u64()) {
                Some(i) => read_indices(&accessors, &views, &buffers, i as usize)?,
                None => (0..positions.len() as u32).collect(),
            };
            let col = material_color(&materials, prim.get("material").and_then(|v| v.as_u64()).map(|u| u as usize));
            if indices.len() % 3 != 0 {
                return Err("gltf: index count not a multiple of 3".into());
            }
            for tri in indices.chunks(3) {
                let i0 = tri[0] as usize;
                let i1 = tri[1] as usize;
                let i2 = tri[2] as usize;
                let a = *positions.get(i0).ok_or_else(|| format!("gltf: index {i0} out of range"))?;
                let b = *positions.get(i1).ok_or_else(|| format!("gltf: index {i1} out of range"))?;
                let cpt = *positions.get(i2).ok_or_else(|| format!("gltf: index {i2} out of range"))?;
                if normals.len() == positions.len() {
                    let base = out.verts.len() as u32;
                    out.verts.push(Vertex::new(a, normals[i0], col, 0.0));
                    out.verts.push(Vertex::new(b, normals[i1], col, 0.0));
                    out.verts.push(Vertex::new(cpt, normals[i2], col, 0.0));
                    out.indices.extend_from_slice(&[base, base + 1, base + 2]);
                } else {
                    out.tri_e(a, b, cpt, col, 0.0);
                }
                if let (Some(js), Some(ws)) = (&joints, &weights) {
                    for idx in [i0, i1, i2] {
                        out.influences.push(SkinInfluence { joints: js[idx], weights: ws[idx] });
                    }
                }
            }
        }
    }
    if out.tri_count() == 0 {
        return Err("gltf: no triangles".into());
    }
    if !out.influences.is_empty() && out.influences.len() != out.verts.len() {
        return Err("gltf: skin influences not parallel to verts".into());
    }
    Ok(out)
}

fn material_color(materials: &[Value], index: Option<usize>) -> Vec3 {
    let Some(i) = index else { return Vec3::ONE };
    let Some(mat) = materials.get(i) else { return Vec3::ONE };
    let factor = mat.pointer("/pbrMetallicRoughness/baseColorFactor").and_then(|v| v.as_array());
    match factor {
        Some(c) if c.len() >= 3 => {
            v3(c[0].as_f64().unwrap_or(1.0) as f32, c[1].as_f64().unwrap_or(1.0) as f32, c[2].as_f64().unwrap_or(1.0) as f32)
        }
        _ => Vec3::ONE,
    }
}

fn accessor_slice<'a>(
    accessors: &[Value],
    views: &[Value],
    buffers: &'a [Vec<u8>],
    index: usize,
) -> Result<(&'a [u8], usize, usize, usize), String> {
    let acc = accessors.get(index).ok_or_else(|| format!("gltf: missing accessor {index}"))?;
    let count = acc.get("count").and_then(|v| v.as_u64()).ok_or("gltf: accessor count")? as usize;
    let component_type = acc.get("componentType").and_then(|v| v.as_u64()).ok_or("gltf: componentType")? as u32;
    let view_i = acc.get("bufferView").and_then(|v| v.as_u64()).ok_or("gltf: accessor bufferView")? as usize;
    let acc_offset = acc.get("byteOffset").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
    let view = views.get(view_i).ok_or_else(|| format!("gltf: missing bufferView {view_i}"))?;
    let buf_i = view.get("buffer").and_then(|v| v.as_u64()).ok_or("gltf: bufferView buffer")? as usize;
    let view_offset = view.get("byteOffset").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
    let view_len = view.get("byteLength").and_then(|v| v.as_u64()).ok_or("gltf: bufferView byteLength")? as usize;
    let stride = view.get("byteStride").and_then(|v| v.as_u64()).map(|s| s as usize);
    let buf = buffers.get(buf_i).ok_or_else(|| format!("gltf: missing buffer {buf_i}"))?;
    let start = view_offset + acc_offset;
    let end = view_offset + view_len;
    if end > buf.len() || start > end {
        return Err("gltf: bufferView out of range".into());
    }
    Ok((&buf[start..end], count, component_type as usize, stride.unwrap_or(0)))
}

fn read_f32x3(accessors: &[Value], views: &[Value], buffers: &[Vec<u8>], index: usize) -> Result<Vec<Vec3>, String> {
    let acc = accessors.get(index).ok_or_else(|| format!("gltf: missing accessor {index}"))?;
    let ty = acc.get("type").and_then(|v| v.as_str()).unwrap_or("");
    if ty != "VEC3" {
        return Err(format!("gltf: expected VEC3 accessor, got {ty}"));
    }
    let (slice, count, component_type, stride) = accessor_slice(accessors, views, buffers, index)?;
    if component_type != 5126 {
        return Err(format!("gltf: expected FLOAT positions/normals, got {component_type}"));
    }
    let step = if stride == 0 { 12 } else { stride };
    if slice.len() < count.saturating_mul(step).saturating_sub(stride.saturating_sub(12).min(stride)) && count * 12 > slice.len() {
        // Fall through to bounds check per element.
    }
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let off = i * step;
        if off + 12 > slice.len() {
            return Err("gltf: VEC3 data short".into());
        }
        let x = f32::from_le_bytes(slice[off..off + 4].try_into().unwrap());
        let y = f32::from_le_bytes(slice[off + 4..off + 8].try_into().unwrap());
        let z = f32::from_le_bytes(slice[off + 8..off + 12].try_into().unwrap());
        out.push(v3(x, y, z));
    }
    Ok(out)
}

fn read_joints(accessors: &[Value], views: &[Value], buffers: &[Vec<u8>], index: usize) -> Result<Vec<[u16; 4]>, String> {
    let acc = accessors.get(index).ok_or_else(|| format!("gltf: missing accessor {index}"))?;
    let ty = acc.get("type").and_then(|v| v.as_str()).unwrap_or("");
    if ty != "VEC4" {
        return Err(format!("gltf: expected VEC4 joints, got {ty}"));
    }
    let (slice, count, component_type, stride) = accessor_slice(accessors, views, buffers, index)?;
    let (width, read): (usize, fn(&[u8]) -> u16) = match component_type {
        5121 => (1, |b| b[0] as u16),
        5123 => (2, |b| u16::from_le_bytes([b[0], b[1]])),
        o => return Err(format!("gltf: unsupported JOINTS componentType {o}")),
    };
    let step = if stride == 0 { width * 4 } else { stride };
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let off = i * step;
        if off + width * 4 > slice.len() {
            return Err("gltf: joints data short".into());
        }
        let mut j = [0u16; 4];
        for (k, slot) in j.iter_mut().enumerate() {
            let o = off + k * width;
            *slot = read(&slice[o..o + width]);
        }
        out.push(j);
    }
    Ok(out)
}

fn read_weights(accessors: &[Value], views: &[Value], buffers: &[Vec<u8>], index: usize) -> Result<Vec<[f32; 4]>, String> {
    let acc = accessors.get(index).ok_or_else(|| format!("gltf: missing accessor {index}"))?;
    let ty = acc.get("type").and_then(|v| v.as_str()).unwrap_or("");
    if ty != "VEC4" {
        return Err(format!("gltf: expected VEC4 weights, got {ty}"));
    }
    let (slice, count, component_type, stride) = accessor_slice(accessors, views, buffers, index)?;
    if component_type != 5126 {
        return Err(format!("gltf: expected FLOAT weights, got {component_type}"));
    }
    let step = if stride == 0 { 16 } else { stride };
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let off = i * step;
        if off + 16 > slice.len() {
            return Err("gltf: weights data short".into());
        }
        let mut w = [0f32; 4];
        for (k, slot) in w.iter_mut().enumerate() {
            let o = off + k * 4;
            *slot = f32::from_le_bytes(slice[o..o + 4].try_into().unwrap());
        }
        out.push(w);
    }
    Ok(out)
}

fn read_indices(accessors: &[Value], views: &[Value], buffers: &[Vec<u8>], index: usize) -> Result<Vec<u32>, String> {
    let acc = accessors.get(index).ok_or_else(|| format!("gltf: missing accessor {index}"))?;
    let ty = acc.get("type").and_then(|v| v.as_str()).unwrap_or("");
    if ty != "SCALAR" {
        return Err(format!("gltf: expected SCALAR indices, got {ty}"));
    }
    let (slice, count, component_type, stride) = accessor_slice(accessors, views, buffers, index)?;
    let (width, read): (usize, fn(&[u8]) -> u32) = match component_type {
        5121 => (1, |b| b[0] as u32),
        5123 => (2, |b| u16::from_le_bytes([b[0], b[1]]) as u32),
        5125 => (4, |b| u32::from_le_bytes([b[0], b[1], b[2], b[3]])),
        o => return Err(format!("gltf: unsupported index componentType {o}")),
    };
    let step = if stride == 0 { width } else { stride };
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let off = i * step;
        if off + width > slice.len() {
            return Err("gltf: index data short".into());
        }
        out.push(read(&slice[off..off + width]));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A red unit triangle in the XY plane, Y-up, as a single data-URI buffer.
    fn triangle_gltf() -> String {
        // positions: (0,0,0), (1,0,0), (0,1,0); normals: +Z; indices 0,1,2
        let mut bin = Vec::new();
        for v in [[0f32, 0., 0.], [1., 0., 0.], [0., 1., 0.]] {
            bin.extend_from_slice(&v[0].to_le_bytes());
            bin.extend_from_slice(&v[1].to_le_bytes());
            bin.extend_from_slice(&v[2].to_le_bytes());
        }
        for _ in 0..3 {
            bin.extend_from_slice(&0f32.to_le_bytes());
            bin.extend_from_slice(&0f32.to_le_bytes());
            bin.extend_from_slice(&1f32.to_le_bytes());
        }
        bin.extend_from_slice(&0u16.to_le_bytes());
        bin.extend_from_slice(&1u16.to_le_bytes());
        bin.extend_from_slice(&2u16.to_le_bytes());
        let b64 = base64::engine::general_purpose::STANDARD.encode(&bin);
        format!(
            r#"{{
  "asset": {{"version": "2.0"}},
  "buffers": [{{"byteLength": {len}, "uri": "data:application/octet-stream;base64,{b64}"}}],
  "bufferViews": [
    {{"buffer": 0, "byteOffset": 0, "byteLength": 36}},
    {{"buffer": 0, "byteOffset": 36, "byteLength": 36}},
    {{"buffer": 0, "byteOffset": 72, "byteLength": 6}}
  ],
  "accessors": [
    {{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "max": [1,1,0], "min": [0,0,0]}},
    {{"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3"}},
    {{"bufferView": 2, "componentType": 5123, "count": 3, "type": "SCALAR"}}
  ],
  "materials": [{{"pbrMetallicRoughness": {{"baseColorFactor": [0.8, 0.1, 0.1, 1.0]}}}}],
  "meshes": [{{"primitives": [{{"attributes": {{"POSITION": 0, "NORMAL": 1}}, "indices": 2, "material": 0}}]}}]
}}"#,
            len = bin.len()
        )
    }

    #[test]
    fn loads_a_coloured_triangle_from_gltf_json() {
        let mesh = parse_gltf(&triangle_gltf(), |_| Err("no external".into())).unwrap();
        assert_eq!(mesh.tri_count(), 1);
        assert_eq!(mesh.verts.len(), 3);
        let c = mesh.verts[0].color();
        assert!((c.x - 0.8).abs() < 0.02 && c.y < 0.15 && c.z < 0.15, "red-ish: {c:?}");
        let n = mesh.verts[0].normal();
        assert!(n.z > 0.9, "faces +Z: {n:?}");
    }

    #[test]
    fn rejects_non_triangle_mode() {
        let src = r#"{"asset":{"version":"2.0"},"buffers":[{"byteLength":1,"uri":"data:application/octet-stream;base64,AA=="}],
            "bufferViews":[{"buffer":0,"byteLength":1}],"accessors":[],
            "meshes":[{"primitives":[{"attributes":{"POSITION":0},"mode":1}]}]}"#;
        let err = parse_gltf(src, |_| Ok(vec![0])).unwrap_err();
        assert!(err.contains("TRIANGLES"), "{err}");
    }

    #[test]
    fn loads_vuena_hero_bind_pose_with_skin_influences() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tools/cache/characters/vuena-blocky/GLB/blocky_01_hero.glb");
        if !path.exists() {
            eprintln!("skip: no character pack at {} (docs/RENDERER.md)", path.display());
            return;
        }
        let mesh = load_gltf(&path).unwrap();
        assert!(mesh.tri_count() > 1000, "tris={}", mesh.tri_count());
        assert_eq!(mesh.influences.len(), mesh.verts.len());
        let inf = &mesh.influences[0];
        let weight_sum: f32 = inf.weights.iter().sum();
        assert!((weight_sum - 1.0).abs() < 0.05, "weights sum {weight_sum}");
        assert!(inf.joints.iter().any(|&j| j > 0) || inf.weights[0] > 0.5, "has joint influence");
    }

    #[test]
    fn loads_triangle_from_glb_container() {
        let mut bin = Vec::new();
        for v in [[0f32, 0., 0.], [1., 0., 0.], [0., 1., 0.]] {
            for x in v {
                bin.extend_from_slice(&x.to_le_bytes());
            }
        }
        bin.extend_from_slice(&0u16.to_le_bytes());
        bin.extend_from_slice(&1u16.to_le_bytes());
        bin.extend_from_slice(&2u16.to_le_bytes());
        let json = format!(
            r#"{{"asset":{{"version":"2.0"}},"buffers":[{{"byteLength":{}}}],
            "bufferViews":[{{"buffer":0,"byteOffset":0,"byteLength":36}},{{"buffer":0,"byteOffset":36,"byteLength":6}}],
            "accessors":[
              {{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","max":[1,1,0],"min":[0,0,0]}},
              {{"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}}
            ],
            "meshes":[{{"primitives":[{{"attributes":{{"POSITION":0}},"indices":1}}]}}]}}"#,
            bin.len()
        );
        let mut json_bytes = json.into_bytes();
        while json_bytes.len() % 4 != 0 {
            json_bytes.push(b' ');
        }
        while bin.len() % 4 != 0 {
            bin.push(0);
        }
        let total = 12 + 8 + json_bytes.len() + 8 + bin.len();
        let mut glb = Vec::with_capacity(total);
        glb.extend_from_slice(b"glTF");
        glb.extend_from_slice(&2u32.to_le_bytes());
        glb.extend_from_slice(&(total as u32).to_le_bytes());
        glb.extend_from_slice(&(json_bytes.len() as u32).to_le_bytes());
        glb.extend_from_slice(b"JSON");
        glb.extend_from_slice(&json_bytes);
        glb.extend_from_slice(&(bin.len() as u32).to_le_bytes());
        glb.extend_from_slice(b"BIN\0");
        glb.extend_from_slice(&bin);
        let mesh = parse_glb(&glb).unwrap();
        assert_eq!(mesh.tri_count(), 1);
    }
}
