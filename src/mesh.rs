//! CPU-side meshes: flat-shaded triangles with per-vertex color.
//! Built-in unit primitives, Wavefront OBJ (+MTL Kd colors), and baking
//! several parts into one mesh so a prefab is a single draw call.

use crate::math::{Quat, Vec3, v3};
use std::collections::HashMap;
use std::path::Path;

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct Vertex {
    pub pos: [f32; 3],
    pub normal: [f32; 3],
    pub color: [f32; 3],
    /// 0 = lit normally, 1 = glows at night (headlights, windows, bulbs).
    pub emissive: f32,
}

#[derive(Clone, Debug, Default)]
pub struct Mesh {
    pub verts: Vec<Vertex>,
    pub indices: Vec<u32>,
}

impl Mesh {
    pub fn tri(&mut self, a: Vec3, b: Vec3, c: Vec3, col: Vec3) {
        self.tri_e(a, b, c, col, 0.0);
    }

    pub fn tri_e(&mut self, a: Vec3, b: Vec3, c: Vec3, col: Vec3, emissive: f32) {
        let n = (b - a).cross(c - a).norm();
        let base = self.verts.len() as u32;
        for p in [a, b, c] {
            self.verts.push(Vertex { pos: [p.x, p.y, p.z], normal: [n.x, n.y, n.z], color: [col.x, col.y, col.z], emissive });
        }
        self.indices.extend_from_slice(&[base, base + 1, base + 2]);
    }

    /// Counter-clockwise quad (seen from the front).
    pub fn quad(&mut self, a: Vec3, b: Vec3, c: Vec3, d: Vec3, col: Vec3) {
        self.tri(a, b, c, col);
        self.tri(a, c, d, col);
    }

    /// Point the mesh's Y axis along `axis` ("x" or "z"); e.g. a cylinder becomes a wheel.
    pub fn reorient(&mut self, axis: &str) -> Result<(), String> {
        let f: fn([f32; 3]) -> [f32; 3] = match axis {
            "y" => return Ok(()),
            "x" => |[x, y, z]| [y, -x, z], // rotate -90deg about Z
            "z" => |[x, y, z]| [x, -z, y], // rotate +90deg about X
            o => return Err(format!("bad axis '{o}'")),
        };
        for v in &mut self.verts {
            v.pos = f(v.pos);
            v.normal = f(v.normal);
        }
        Ok(())
    }

    pub fn tri_count(&self) -> usize {
        self.indices.len() / 3
    }

    /// Append `src` scaled, turned (yaw, then pitch about its own +X, then
    /// roll about its +Z, as Quat::euler orders them), moved by `offset`,
    /// and tinted by `col`.
    pub fn append_tilted(&mut self, src: &Mesh, offset: Vec3, (yaw, pitch, roll): (f32, f32, f32), scale: Vec3, col: Vec3, emissive: f32) {
        let base = self.verts.len() as u32;
        let inv = v3(1.0 / scale.x, 1.0 / scale.y, 1.0 / scale.z);
        let tilt =
            (pitch != 0.0 || roll != 0.0).then(|| Quat::axis_angle(v3(1.0, 0.0, 0.0), pitch) * Quat::axis_angle(v3(0.0, 0.0, 1.0), roll));
        let turn = |v: Vec3| tilt.map_or(v, |q| q.rotate(v)).rot_y(yaw);
        for v in &src.verts {
            let p = turn(v3(v.pos[0], v.pos[1], v.pos[2]).mul(scale)) + offset;
            let n = turn(v3(v.normal[0], v.normal[1], v.normal[2]).mul(inv)).norm();
            self.verts.push(Vertex {
                pos: [p.x, p.y, p.z],
                normal: [n.x, n.y, n.z],
                color: [v.color[0] * col.x, v.color[1] * col.y, v.color[2] * col.z],
                emissive: v.emissive.max(emissive),
            });
        }
        self.indices.extend(src.indices.iter().map(|i| i + base));
    }
}

/// Unit cube centered on the origin.
pub fn cube() -> Mesh {
    let mut m = Mesh::default();
    let h = 0.5;
    let p = |x: f32, y: f32, z: f32| v3(x * h, y * h, z * h);
    let w = Vec3::ONE;
    m.quad(p(-1., -1., 1.), p(1., -1., 1.), p(1., 1., 1.), p(-1., 1., 1.), w); // +z
    m.quad(p(1., -1., -1.), p(-1., -1., -1.), p(-1., 1., -1.), p(1., 1., -1.), w); // -z
    m.quad(p(1., -1., 1.), p(1., -1., -1.), p(1., 1., -1.), p(1., 1., 1.), w); // +x
    m.quad(p(-1., -1., -1.), p(-1., -1., 1.), p(-1., 1., 1.), p(-1., 1., -1.), w); // -x
    m.quad(p(-1., 1., 1.), p(1., 1., 1.), p(1., 1., -1.), p(-1., 1., -1.), w); // +y
    m.quad(p(-1., -1., -1.), p(1., -1., -1.), p(1., -1., 1.), p(-1., -1., 1.), w); // -y
    m
}

/// Unit ramp: full height at +z, zero height at -z.
pub fn wedge() -> Mesh {
    let mut m = Mesh::default();
    let w = Vec3::ONE;
    let (a, b) = (v3(-0.5, -0.5, -0.5), v3(0.5, -0.5, -0.5));
    let (c, d) = (v3(0.5, -0.5, 0.5), v3(-0.5, -0.5, 0.5));
    let (e, f) = (v3(0.5, 0.5, 0.5), v3(-0.5, 0.5, 0.5));
    m.quad(a, b, c, d, w); // bottom
    m.quad(d, c, e, f, w); // back wall +z
    m.quad(a, f, e, b, w); // slope
    m.tri(a, d, f, w); // -x side
    m.tri(b, e, c, w); // +x side
    m
}

/// Unit cylinder along Y (diameter 1, height 1).
pub fn cylinder(sides: usize) -> Mesh {
    let mut m = Mesh::default();
    let w = Vec3::ONE;
    let pt = |i: usize, y: f32| {
        let a = i as f32 / sides as f32 * std::f32::consts::TAU;
        v3(a.cos() * 0.5, y, -a.sin() * 0.5)
    };
    for i in 0..sides {
        let (a0, a1) = (pt(i, -0.5), pt(i + 1, -0.5));
        let (b0, b1) = (pt(i, 0.5), pt(i + 1, 0.5));
        m.quad(a0, a1, b1, b0, w);
        m.tri(v3(0., 0.5, 0.), b0, b1, w);
        m.tri(v3(0., -0.5, 0.), a1, a0, w);
    }
    m
}

/// Low-poly UV sphere, diameter 1.
pub fn sphere(rings: usize, segs: usize) -> Mesh {
    let mut m = Mesh::default();
    let pt = |r: usize, s: usize| {
        let th = r as f32 / rings as f32 * std::f32::consts::PI;
        let ph = s as f32 / segs as f32 * std::f32::consts::TAU;
        v3(th.sin() * ph.cos() * 0.5, th.cos() * 0.5, -th.sin() * ph.sin() * 0.5)
    };
    for r in 0..rings {
        for s in 0..segs {
            let (a, b, c, d) = (pt(r, s), pt(r + 1, s), pt(r + 1, s + 1), pt(r, s + 1));
            if r != 0 {
                m.tri(a, b, d, Vec3::ONE);
            }
            if r != rings - 1 {
                m.tri(b, c, d, Vec3::ONE);
            }
        }
    }
    m
}

/// Unit quad in XZ facing +Y.
pub fn plane() -> Mesh {
    let mut m = Mesh::default();
    m.quad(v3(-0.5, 0., 0.5), v3(0.5, 0., 0.5), v3(0.5, 0., -0.5), v3(-0.5, 0., -0.5), Vec3::ONE);
    m
}

pub const BUILTIN_NAMES: [&str; 5] = ["cube", "wedge", "cylinder", "sphere", "plane"];

pub fn builtins_contains(name: &str) -> bool {
    BUILTIN_NAMES.contains(&name)
}

pub fn builtins() -> Vec<(&'static str, Mesh)> {
    vec![("cube", cube()), ("wedge", wedge()), ("cylinder", cylinder(10)), ("sphere", sphere(6, 10)), ("plane", plane())]
}

/// Minimal Wavefront OBJ: v, f (any polygon, fan-triangulated, v/vt/vn and negative
/// indices), mtllib + usemtl for flat Kd colors. Normals are recomputed flat.
pub fn load_obj(path: &Path) -> Result<Mesh, String> {
    let src = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let dir = path.parent().unwrap_or(Path::new("."));
    let mut pos: Vec<Vec3> = Vec::new();
    let mut mats: HashMap<String, (Vec3, f32)> = HashMap::new();
    let (mut col, mut glow) = (Vec3::ONE, 0.0);
    let mut m = Mesh::default();
    let num = |s: Option<&str>| s.and_then(|s| s.parse::<f32>().ok()).unwrap_or(0.0);
    for (ln, line) in src.lines().enumerate() {
        let mut it = line.split_whitespace();
        match it.next() {
            Some("v") => pos.push(v3(num(it.next()), num(it.next()), num(it.next()))),
            Some("mtllib") => {
                if let Some(f) = it.next()
                    && let Ok(txt) = std::fs::read_to_string(dir.join(f))
                {
                    parse_mtl(&txt, &mut mats);
                }
            }
            Some("usemtl") => (col, glow) = it.next().and_then(|n| mats.get(n).copied()).unwrap_or((Vec3::ONE, 0.0)),
            Some("f") => {
                let idx: Result<Vec<Vec3>, String> = it
                    .map(|tok| {
                        let i: i64 = tok.split('/').next().unwrap_or("").parse().map_err(|_| format!("line {}: bad face", ln + 1))?;
                        let i = if i < 0 { pos.len() as i64 + i } else { i - 1 };
                        pos.get(i as usize).copied().ok_or(format!("line {}: index out of range", ln + 1))
                    })
                    .collect();
                let p = idx?;
                for k in 1..p.len().saturating_sub(1) {
                    m.tri_e(p[0], p[k], p[k + 1], col, glow);
                }
            }
            _ => {}
        }
    }
    Ok(m)
}

/// Kd is the color; Ke (emission) marks the material as glowing at night.
fn parse_mtl(txt: &str, out: &mut HashMap<String, (Vec3, f32)>) {
    let mut cur = String::new();
    for line in txt.lines() {
        let mut it = line.split_whitespace();
        let key = it.next();
        let c: Vec<f32> = it.filter_map(|s| s.parse().ok()).collect();
        match key {
            Some("newmtl") => {
                cur = line.split_whitespace().nth(1).unwrap_or("").to_string();
                out.insert(cur.clone(), (Vec3::ONE, 0.0));
            }
            Some("Kd") if c.len() >= 3 => out.entry(cur.clone()).or_insert((Vec3::ONE, 0.0)).0 = v3(c[0], c[1], c[2]),
            Some("Ke") if c.len() >= 3 => out.entry(cur.clone()).or_insert((Vec3::ONE, 0.0)).1 = c[0].max(c[1]).max(c[2]).min(1.0),
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every face normal of a closed convex primitive must point away from its center.
    fn outward(m: &Mesh) {
        for t in m.indices.chunks(3) {
            let v = &m.verts[t[0] as usize];
            let p = v3(v.pos[0], v.pos[1], v.pos[2]);
            let n = v3(v.normal[0], v.normal[1], v.normal[2]);
            assert!(p.dot(n) > 0.0, "inward face at {p:?} n={n:?}");
        }
    }

    #[test]
    fn mtl_colors_and_emission() {
        let mut m = HashMap::new();
        parse_mtl("newmtl lamp\nKd 1 0.9 0.5\nKe 1 1 1\nnewmtl body\nKd 0.2 0.2 0.2\n", &mut m);
        assert_eq!(m["lamp"], (v3(1.0, 0.9, 0.5), 1.0));
        assert_eq!(m["body"], (v3(0.2, 0.2, 0.2), 0.0));
    }

    #[test]
    fn primitives_face_outward() {
        outward(&cube());
        outward(&cylinder(8));
        outward(&wedge_centered());
        outward(&sphere(6, 10));
    }

    // The origin lies on the wedge's slope; shift so the convexity test applies.
    fn wedge_centered() -> Mesh {
        let mut w = Mesh::default();
        w.append_tilted(&wedge(), v3(0.0, 0.25, -0.25), (0.0, 0.0, 0.0), Vec3::ONE, Vec3::ONE, 0.0);
        w
    }

    #[test]
    fn tilted_parts_climb_where_they_point() {
        // A 10 m plank turned to face +X and pitched up 0.2 rad: its far end
        // is 10 sin(0.2) higher than its near end, and it's still outward-facing.
        let mut m = Mesh::default();
        m.append_tilted(&cube(), Vec3::ZERO, (std::f32::consts::FRAC_PI_2, -0.2, 0.0), v3(1.0, 0.1, 10.0), Vec3::ONE, 0.0);
        let (lo, hi) = m.verts.iter().fold((v3(9., 9., 9.), v3(-9., -9., -9.)), |(lo, hi), v| {
            let p = v3(v.pos[0], v.pos[1], v.pos[2]);
            (if p.x < lo.x { p } else { lo }, if p.x > hi.x { p } else { hi })
        });
        assert!(hi.x > 4.8 && lo.x < -4.8, "{lo:?} {hi:?}");
        assert!((hi.y - lo.y - 10.0 * 0.2f32.sin()).abs() < 0.15, "rise {}", hi.y - lo.y);
        outward(&m);
    }
}
