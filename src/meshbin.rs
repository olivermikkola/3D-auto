//! Meshes as compact binary files (`.mesh`), written next to the OBJ they were
//! read from by `auto --pack-meshes DIR`. Reading one is a copy, not a parse:
//! a city's tiles load in a fraction of the time, and on a worker thread.
//!
//! Layout, little-endian: `AMSH`, version (u32), vertex count, index count,
//! surface count (u32 each; surfaces are 0 or one per vertex), then the
//! vertices (20 bytes each, as `mesh::Vertex`), the surfaces (u, v as f32 and
//! the role as u32) and the indices (u32).
use crate::mesh::{Mesh, Vertex};
use std::path::{Path, PathBuf};

const MAGIC: &[u8; 4] = b"AMSH";
const VERSION: u32 = 1;
const VERTEX: usize = 20;
const SURFACE: usize = 12;

/// The binary file beside an OBJ.
pub fn beside(obj: &Path) -> PathBuf {
    obj.with_extension("mesh")
}

#[cfg_attr(not(all(feature = "wgpu-postcard", not(target_arch = "wasm32"))), allow(dead_code))]
pub fn encode(m: &Mesh) -> Vec<u8> {
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    let surfaces = if m.obj_surfaces.len() == m.verts.len() { m.obj_surfaces.as_slice() } else { &[] };
    #[cfg(not(all(feature = "wgpu-postcard", not(target_arch = "wasm32"))))]
    let surfaces: &[[u8; SURFACE]] = &[];
    let mut out = Vec::with_capacity(20 + m.verts.len() * VERTEX + surfaces.len() * SURFACE + m.indices.len() * 4);
    out.extend_from_slice(MAGIC);
    for n in [VERSION, m.verts.len() as u32, m.indices.len() as u32, surfaces.len() as u32] {
        out.extend_from_slice(&n.to_le_bytes());
    }
    for v in &m.verts {
        for f in v.pos {
            out.extend_from_slice(&f.to_le_bytes());
        }
        out.extend_from_slice(&v.normal);
        out.extend_from_slice(&v.color);
    }
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    for s in surfaces {
        out.extend_from_slice(&s.uv[0].to_le_bytes());
        out.extend_from_slice(&s.uv[1].to_le_bytes());
        out.extend_from_slice(&s.role.to_le_bytes());
    }
    for i in &m.indices {
        out.extend_from_slice(&i.to_le_bytes());
    }
    out
}

fn u32_at(b: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([b[at], b[at + 1], b[at + 2], b[at + 3]])
}

fn f32_at(b: &[u8], at: usize) -> f32 {
    f32::from_bits(u32_at(b, at))
}

pub fn decode(b: &[u8]) -> Result<Mesh, String> {
    if b.len() < 20 || &b[0..4] != MAGIC {
        return Err("not a packed mesh".into());
    }
    if u32_at(b, 4) != VERSION {
        return Err(format!("packed mesh version {} (this build reads {VERSION})", u32_at(b, 4)));
    }
    let (nv, ni, ns) = (u32_at(b, 8) as usize, u32_at(b, 12) as usize, u32_at(b, 16) as usize);
    if ns != 0 && ns != nv {
        return Err("packed mesh: surfaces don't match the vertices".into());
    }
    let (vs, ss) = (20, 20 + nv * VERTEX);
    let is = ss + ns * SURFACE;
    if b.len() != is + ni * 4 {
        return Err("packed mesh: wrong length".into());
    }
    let verts = b[vs..ss]
        .chunks_exact(VERTEX)
        .map(|c| Vertex {
            pos: [f32_at(c, 0), f32_at(c, 4), f32_at(c, 8)],
            normal: [c[12], c[13], c[14], c[15]],
            color: [c[16], c[17], c[18], c[19]],
        })
        .collect();
    let indices: Vec<u32> = b[is..].chunks_exact(4).map(|c| u32_at(c, 0)).collect();
    if indices.iter().any(|&i| i as usize >= nv) {
        return Err("packed mesh: index out of range".into());
    }
    #[allow(unused_mut)]
    let mut m = Mesh { verts, indices, ..Default::default() };
    #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
    {
        m.obj_surfaces = b[ss..is]
            .chunks_exact(SURFACE)
            .map(|c| crate::mesh::ObjSurface { uv: [f32_at(c, 0), f32_at(c, 4)], role: u32_at(c, 8) })
            .collect();
    }
    Ok(m)
}

/// Whether a packed copy beside this OBJ is at least as new as the OBJ.
fn fresh(obj: &Path, packed: &Path) -> bool {
    let modified = |p: &Path| std::fs::metadata(p).and_then(|m| m.modified()).ok();
    match (modified(obj), modified(packed)) {
        (Some(o), Some(p)) => p >= o,
        (None, Some(_)) => true,
        _ => false,
    }
}

/// An OBJ, from its packed copy when that is up to date. Safe on any thread.
pub fn load(obj: &Path) -> Result<Mesh, String> {
    let packed = beside(obj);
    if !cfg!(target_arch = "wasm32") && fresh(obj, &packed) {
        let bytes = crate::vfs::read(&packed).map_err(|e| format!("{}: {e}", packed.display()))?;
        return decode(&bytes).map_err(|e| format!("{}: {e}", packed.display()));
    }
    crate::mesh::load_obj(obj)
}

/// `--pack-meshes DIR`: write a packed copy beside every OBJ in DIR that has
/// none or an older one. Returns (packed, skipped as fresh), or the first error.
#[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
pub fn pack_dir(dir: &Path) -> Result<(usize, usize), String> {
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicUsize, Ordering};
    let objs: Vec<PathBuf> = crate::vfs::list(dir, false)
        .into_iter()
        .filter(|n| n.ends_with(".obj"))
        .map(|n| dir.join(n))
        .filter(|p| !fresh(p, &beside(p)))
        .collect();
    let skipped = crate::vfs::list(dir, false).iter().filter(|n| n.ends_with(".obj")).count() - objs.len();
    let next = AtomicUsize::new(0);
    let error = Mutex::new(None);
    let workers = std::thread::available_parallelism().map_or(4, |n| n.get()).min(8);
    std::thread::scope(|s| {
        for _ in 0..workers {
            s.spawn(|| {
                loop {
                    let i = next.fetch_add(1, Ordering::Relaxed);
                    let Some(obj) = objs.get(i) else { break };
                    let result = crate::mesh::load_obj(obj).and_then(|m| {
                        let packed = beside(obj);
                        let tmp = packed.with_extension("mesh.tmp");
                        std::fs::write(&tmp, encode(&m))
                            .and_then(|_| std::fs::rename(&tmp, &packed))
                            .map_err(|e| format!("{}: {e}", packed.display()))
                    });
                    if let Err(e) = result {
                        error.lock().unwrap().get_or_insert(e);
                        break;
                    }
                }
            });
        }
    });
    match error.into_inner().unwrap() {
        Some(e) => Err(e),
        None => Ok((objs.len(), skipped)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::math::v3;

    #[test]
    fn round_trip() {
        let mut m = Mesh::default();
        m.tri(v3(0.0, 0.0, 0.0), v3(1.0, 0.0, 0.0), v3(0.0, 1.0, 2.5), v3(0.2, 0.4, 0.6));
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        {
            m.obj_surfaces = (0..m.verts.len()).map(|i| crate::mesh::ObjSurface { uv: [i as f32, 0.5], role: 7 }).collect();
        }
        let back = decode(&encode(&m)).unwrap();
        assert_eq!(back.indices, m.indices);
        assert_eq!(back.verts.len(), 3);
        for (a, b) in back.verts.iter().zip(&m.verts) {
            assert_eq!((a.pos, a.normal, a.color), (b.pos, b.normal, b.color));
        }
        #[cfg(all(feature = "wgpu-postcard", not(target_arch = "wasm32")))]
        assert_eq!(back.obj_surfaces[2].uv, [2.0, 0.5]);
        assert!(decode(&encode(&m)[..30]).is_err());
    }
}
