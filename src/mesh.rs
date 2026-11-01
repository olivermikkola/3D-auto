//! CPU-side meshes: flat-shaded triangles with per-vertex color.
//! Built-in unit primitives, Wavefront OBJ (+MTL Kd colors), and baking
//! several parts into one mesh so a prefab is a single draw call.

use crate::math::{Quat, Vec3, v3};
use std::collections::HashMap;
use std::path::Path;

/// 20 bytes: a city is millions of triangles, so normal and colour are bytes.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct Vertex {
    pub pos: [f32; 3],
    /// Unit normal, each axis -1..1 stored as 0..254 (127 is zero); w is
    /// the facade the shader draws windows of on a wall (0: none; see
    /// `set_facade`). A facade's wall is upright, so its y is free and holds
    /// how far along the wall the vertex is, in window bays.
    pub normal: [u8; 4],
    /// Color 0..255. Alpha is emissive: 0 = lit normally, 255 = glows at
    /// night (headlights, windows, bulbs). On a facade it is instead the
    /// height above the building's foot, in half metres.
    pub color: [u8; 4],
}

fn unorm(x: f32) -> u8 {
    (x.clamp(0.0, 1.0) * 255.0).round() as u8
}

fn snorm(x: f32) -> u8 {
    ((x.clamp(-1.0, 1.0) * 127.0).round() as i32 + 127) as u8
}

impl Vertex {
    pub fn new(p: Vec3, n: Vec3, col: Vec3, emissive: f32) -> Vertex {
        Vertex {
            pos: [p.x, p.y, p.z],
            normal: [snorm(n.x), snorm(n.y), snorm(n.z), 0],
            color: [unorm(col.x), unorm(col.y), unorm(col.z), unorm(emissive)],
        }
    }

    pub fn pos(&self) -> Vec3 {
        v3(self.pos[0], self.pos[1], self.pos[2])
    }

    pub fn normal(&self) -> Vec3 {
        let f = |b: u8| (b as f32 - 127.0) / 127.0;
        let y = if self.on_facade() { 0.0 } else { f(self.normal[1]) };
        v3(f(self.normal[0]), y, f(self.normal[2]))
    }

    pub fn color(&self) -> Vec3 {
        v3(self.color[0] as f32 / 255.0, self.color[1] as f32 / 255.0, self.color[2] as f32 / 255.0)
    }

    pub fn emissive(&self) -> f32 {
        if self.on_facade() { 0.0 } else { self.color[3] as f32 / 255.0 }
    }

    fn on_facade(&self) -> bool {
        self.normal[3] > 0 && self.ground() == 0
    }

    /// The ground surface the shader draws on this vertex (0: none; else
    /// GROUND_ASPHALT or GROUND_SETTS).
    pub fn ground(&self) -> u8 {
        let b = self.normal[3];
        if b >= GROUND_ASPHALT && b & FACADE_SCALED == 0 { b } else { 0 }
    }

    pub fn set_ground(&mut self, id: u8) {
        self.normal[3] = id;
    }

    /// The facade on this wall (0: none, else as `set_facade` takes it),
    /// its height above the foot (m) and the byte for how far along it is.
    pub fn facade(&self) -> (u8, f32, u8) {
        if !self.on_facade() {
            return (0, 0.0, 0);
        }
        (self.normal[3], self.color[3] as f32 * FACADE_STEP, self.normal[1])
    }

    /// Mark as facade `id` at `height` m above the building's foot and
    /// `along` the wall: in eighths of a bay, or with FACADE_SCALED set in
    /// `id` (a unit mesh its entity stretches), in 255ths of the wall, the
    /// shader working out the bays from the entity's scale.
    pub fn set_facade(&mut self, id: u8, height: f32, along: u8) {
        self.normal[3] = id;
        self.normal[1] = along;
        self.color[3] = (height / FACADE_STEP).round().clamp(0.0, 255.0) as u8;
    }
}

/// A facade's height above the foot is kept in half metres (up to 127 m).
pub const FACADE_STEP: f32 = 0.5;
/// Set in a facade id: the mesh is a unit one its entity scales to size.
pub const FACADE_SCALED: u8 = 0x80;
/// Ground surfaces, in the same byte as a facade but from 64 up: worn
/// asphalt, and setts (paving stones) on the paths that have them.
pub const GROUND_ASPHALT: u8 = 64;
pub const GROUND_SETTS: u8 = 65;
/// The width of a facade's window bays, by facade id (render.rs's `bay`).
pub fn facade_bay(id: u8) -> f32 {
    match id & !FACADE_SCALED {
        1 => 3.0,
        2 => 2.7,
        3 => 1.6,
        5 => 6.0,
        6 => 4.0,
        _ => 3.3,
    }
}

/// Lettering from the bitmap font (`font.rs`) as a mesh: each column's run
/// of lit pixels is one box from `cube`, `depth` deep. The text is centred on
/// x, stands on y = 0 and reads from +z; a letter is `height` tall.
pub fn text(cube: &Mesh, s: &str, height: f32, depth: f32) -> Mesh {
    let px = height / 7.0;
    let n = s.chars().count() as f32;
    let x0 = -(n * crate::font::ADVANCE - 1.0) * px / 2.0;
    let mut out = Mesh::default();
    for (i, ch) in s.chars().enumerate() {
        let mut cols = [0u8; 5];
        crate::font::glyph(ch, |x, y| cols[x as usize] |= 1 << y);
        for (x, col) in cols.iter().enumerate() {
            let mut y = 0;
            while y < 7 {
                if col >> y & 1 == 0 {
                    y += 1;
                    continue;
                }
                let top = y;
                while y < 7 && col >> y & 1 == 1 {
                    y += 1;
                }
                let run = (y - top) as f32;
                let cx = x0 + (i as f32 * crate::font::ADVANCE + x as f32 + 0.5) * px;
                let cy = (7.0 - top as f32 - run / 2.0) * px;
                out.append_tilted(cube, v3(cx, cy, 0.0), (0.0, 0.0, 0.0), v3(px, run * px, depth), Vec3::ONE, 0.0);
            }
        }
    }
    out
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

    /// A triangle with a colour at each corner, blended across it.
    pub fn tri_blend(&mut self, a: Vec3, b: Vec3, c: Vec3, cols: [Vec3; 3]) {
        let n = (b - a).cross(c - a).norm();
        let base = self.verts.len() as u32;
        for (p, col) in [a, b, c].into_iter().zip(cols) {
            self.verts.push(Vertex::new(p, n, col, 0.0));
        }
        self.indices.extend_from_slice(&[base, base + 1, base + 2]);
    }

    pub fn tri_e(&mut self, a: Vec3, b: Vec3, c: Vec3, col: Vec3, emissive: f32) {
        let n = (b - a).cross(c - a).norm();
        let base = self.verts.len() as u32;
        for p in [a, b, c] {
            self.verts.push(Vertex::new(p, n, col, emissive));
        }
        self.indices.extend_from_slice(&[base, base + 1, base + 2]);
    }

    /// Counter-clockwise quad (seen from the front). Flat, so its two
    /// triangles share four vertices.
    pub fn quad(&mut self, a: Vec3, b: Vec3, c: Vec3, d: Vec3, col: Vec3) {
        let n = (b - a).cross(c - a).norm();
        let base = self.verts.len() as u32;
        for p in [a, b, c, d] {
            self.verts.push(Vertex::new(p, n, col, 0.0));
        }
        self.indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
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
            let (p, n) = (f(v.pos), v.normal());
            let n = f([n.x, n.y, n.z]);
            let (facade, ground) = (v.facade(), v.ground());
            *v = Vertex::new(v3(p[0], p[1], p[2]), v3(n[0], n[1], n[2]), v.color(), v.emissive());
            if facade.0 > 0 {
                v.set_facade(facade.0, facade.1, facade.2);
            } else if ground > 0 {
                v.set_ground(ground);
            }
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
            let p = turn(v.pos().mul(scale)) + offset;
            let n = turn(v.normal().mul(inv)).norm();
            let mut out = Vertex::new(p, n, v.color().mul(col), v.emissive().max(emissive));
            let (id, h, along) = v.facade();
            if id > 0 {
                out.set_facade(id, h * scale.y, along);
            } else if v.ground() > 0 {
                out.set_ground(v.ground());
            }
            self.verts.push(out);
        }
        self.indices.extend(src.indices.iter().map(|i| i + base));
    }

    /// Mark every vertex from `from` on as ground surface `id` (the shader
    /// draws it only where it faces up).
    pub fn mark_ground(&mut self, from: usize, id: u8) {
        for v in &mut self.verts[from..] {
            v.set_ground(id);
        }
    }

    /// Mark the upright walls among the vertices from `from` on as facade
    /// `id`: heights from the lowest vertex (the walls' foot), and along each
    /// wall in whole bays, as many as fit its length, so windows sit evenly
    /// from corner to corner. `scaled`: a unit mesh its entity stretches.
    pub fn mark_facade(&mut self, from: usize, id: u8, scaled: bool) {
        let foot = self.verts[from..].iter().map(|v| v.pos[1]).fold(f32::INFINITY, f32::min);
        // The walls: runs of vertices facing the same way (a box's face, an
        // outline's side: each is a quad of its own). (Not by plane: on a long
        // wall the normal's rounding put its two ends in different planes.)
        let mut walls: Vec<Vec<usize>> = Vec::new();
        for i in from..self.verts.len() {
            let v = &self.verts[i];
            if v.normal().y.abs() > 0.3 {
                continue;
            }
            match walls.last_mut() {
                Some(w)
                    if *w.last().unwrap() == i - 1
                        && self.verts[i - 1].normal[0] == v.normal[0]
                        && self.verts[i - 1].normal[2] == v.normal[2] =>
                {
                    w.push(i)
                }
                _ => walls.push(vec![i]),
            }
        }
        let bay = facade_bay(id);
        for idx in &walls {
            let n = self.verts[idx[0]].normal();
            let (tx, tz) = (-n.z, n.x);
            let at = |v: &Vertex| v.pos[0] * tx + v.pos[2] * tz;
            let lo = idx.iter().map(|&i| at(&self.verts[i])).fold(f32::INFINITY, f32::min);
            let hi = idx.iter().map(|&i| at(&self.verts[i])).fold(f32::NEG_INFINITY, f32::max);
            let len = (hi - lo).max(1e-3);
            let bays = (len / bay).round().clamp(1.0, 31.0);
            for &i in idx {
                let t = (at(&self.verts[i]) - lo) / len;
                let h = self.verts[i].pos[1] - foot;
                let (fid, along) = if scaled { (id | FACADE_SCALED, t * 255.0) } else { (id, t * bays * 8.0) };
                self.verts[i].set_facade(fid, h, along.round() as u8);
            }
        }
    }
}

/// A road (or pavement, river, track bed) as one strip: its top surface
/// `width` wide along `pts` (x, y, z: the middle line at surface height),
/// mitred at each bend so pieces meet without a seam, and a skirt `depth`
/// deep down each side so its edge never shows a gap above the ground. No
/// ends and no underside: nobody sees them. Two top and four skirt vertices
/// a point, where a box per piece and a cylinder per bend took ~120.
pub fn ribbon(pts: &[Vec3], width: f32, depth: f32, col: Vec3) -> Mesh {
    ribbon_sloped(pts, &|_| width, &|_| depth, 0.0, col)
}

/// A ribbon `width(i)` wide at point i, whose skirts go down `drop(i)` and
/// out `slope` metres for every metre down: an embankment's sides (0:
/// straight down).
pub fn ribbon_sloped(pts: &[Vec3], width: &dyn Fn(usize) -> f32, drop: &dyn Fn(usize) -> f32, slope: f32, col: Vec3) -> Mesh {
    let mut m = Mesh::default();
    let n = pts.len();
    if n < 2 {
        return m;
    }
    let up = v3(0.0, 1.0, 0.0);
    let flat = |v: Vec3| v3(v.x, 0.0, v.z).norm();
    for i in 0..n {
        let half = width(i) / 2.0;
        let (prev, next) = (pts[i.saturating_sub(1)], pts[(i + 1).min(n - 1)]);
        // The bend's mitre: the average of the two pieces' directions,
        // stretched so the edges stay `half` from both (but not past 3x).
        let d0 = flat(pts[i.max(1)] - pts[i.max(1) - 1]);
        let d1 = flat(pts[(i + 1).min(n - 1)] - pts[(i + 1).min(n - 1) - 1]);
        let along = flat(d0 + d1);
        let right = along.cross(up);
        let stretch = (1.0 / along.dot(d1).max(1.0 / 3.0)).min(3.0);
        let side = right * (half * stretch);
        let top = right.cross(next - prev).norm();
        let p = pts[i];
        let depth = drop(i);
        let down = v3(0.0, depth, 0.0);
        let out = right * (slope * depth * stretch);
        let (rn, ln) = ((right + up * slope).norm(), (up * slope - right).norm());
        for (q, nrm) in
            [(p - side, top), (p + side, top), (p + side, rn), (p + side + out - down, rn), (p - side, ln), (p - side - out - down, ln)]
        {
            m.verts.push(Vertex::new(q, nrm, col, 0.0));
        }
    }
    for i in 0..n as u32 - 1 {
        let (a, b) = (6 * i, 6 * (i + 1));
        // Top (left, right, right', left'); right skirt; left skirt.
        m.indices.extend_from_slice(&[a, a + 1, b + 1, a, b + 1, b]);
        m.indices.extend_from_slice(&[a + 2, a + 3, b + 3, a + 2, b + 3, b + 2]);
        m.indices.extend_from_slice(&[a + 4, b + 4, b + 5, a + 4, b + 5, a + 5]);
    }
    m
}

/// A footprint pushed up into a solid: walls round `outline` (x, z points,
/// either way round, not closed) from `bottom` to `top`, and a flat roof cut
/// into triangles by ear clipping. No floor unless `floor` (for a building
/// up on a deck, seen from the road under it). Faces point out, flat shaded.
pub fn prism(outline: &[(f32, f32)], bottom: f32, top: f32, col: Vec3, floor: bool) -> Mesh {
    let mut m = Mesh::default();
    let mut pts: Vec<(f32, f32)> = Vec::with_capacity(outline.len());
    for &p in outline {
        if pts.last().is_none_or(|q: &(f32, f32)| (q.0 - p.0).abs() + (q.1 - p.1).abs() > 1e-4) {
            pts.push(p);
        }
    }
    while pts.len() > 1 && (pts[0].0 - pts[pts.len() - 1].0).abs() + (pts[0].1 - pts[pts.len() - 1].1).abs() <= 1e-4 {
        pts.pop();
    }
    if pts.len() < 3 {
        return m;
    }
    // The faces' winding (see cube's +y) wants the outline clockwise seen
    // from above, which in x, z is a negative shoelace area.
    let twice_area = |p: &[(f32, f32)]| -> f32 {
        (0..p.len())
            .map(|i| {
                let (a, b) = (p[i], p[(i + 1) % p.len()]);
                a.0 * b.1 - b.0 * a.1
            })
            .sum()
    };
    if twice_area(&pts) > 0.0 {
        pts.reverse();
    }
    let at = |p: (f32, f32), y: f32| v3(p.0, y, p.1);
    for i in 0..pts.len() {
        let (a, b) = (pts[i], pts[(i + 1) % pts.len()]);
        m.quad(at(a, bottom), at(b, bottom), at(b, top), at(a, top), col);
    }
    for [a, b, c] in ear_clip(&pts) {
        m.tri(at(pts[a], top), at(pts[b], top), at(pts[c], top), col);
        if floor {
            m.tri(at(pts[c], bottom), at(pts[b], bottom), at(pts[a], bottom), col);
        }
    }
    m
}

/// Triangles (as indices into `pts`) covering a simple polygon that runs
/// clockwise in x, z (negative shoelace area). A polygon that defeats it
/// (self-crossing) gets a fan from its first point for what's left.
fn ear_clip(pts: &[(f32, f32)]) -> Vec<[usize; 3]> {
    let cross = |o: (f32, f32), a: (f32, f32), b: (f32, f32)| (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0);
    let mut idx: Vec<usize> = (0..pts.len()).collect();
    let mut out = Vec::with_capacity(pts.len().saturating_sub(2));
    while idx.len() > 3 {
        let n = idx.len();
        let ear = (0..n).find(|&i| {
            let (a, b, c) = (pts[idx[(i + n - 1) % n]], pts[idx[i]], pts[idx[(i + 1) % n]]);
            // Convex at b (clockwise turn), and no other corner inside abc.
            cross(a, b, c) < 0.0
                && idx.iter().all(|&k| {
                    let p = pts[k];
                    p == a || p == b || p == c || !(cross(a, b, p) <= 0.0 && cross(b, c, p) <= 0.0 && cross(c, a, p) <= 0.0)
                })
        });
        let Some(i) = ear else { break };
        out.push([idx[(i + n - 1) % n], idx[i], idx[(i + 1) % n]]);
        idx.remove(i);
    }
    for k in 1..idx.len().saturating_sub(1) {
        out.push([idx[0], idx[k], idx[k + 1]]);
    }
    out
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

/// A leafy tree (a linden, a maple, a birch) standing at `base`, its crown
/// `crown` metres across, added to `m`: a trunk and one lumpy crown, darker
/// underneath, its shape and green varied by `seed`. 26 vertices: a city's
/// hundred thousand trees bake into a few chunk meshes (Engine::set_forest).
pub fn leafy_tree(m: &mut Mesh, base: Vec3, crown: f32, seed: u32) {
    const SIDES: usize = 7;
    // A hash's next number, 0..1.
    let mut s = seed.wrapping_mul(0x9E37_79B9) ^ 0x85EB_CA6B;
    let mut rnd = || {
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        (s % 10_000) as f32 / 10_000.0
    };
    let r = crown / 2.0;
    let height = 0.9 * crown + 3.0;
    let ry = r * (0.8 + 0.2 * rnd());
    let mid = base + v3(0.0, height - ry, 0.0);
    let leaf = v3(0.2 + 0.08 * rnd(), 0.36 + 0.12 * rnd(), 0.13 + 0.07 * rnd());
    let bark = v3(0.3, 0.23, 0.17);
    let push = |m: &mut Mesh, p: Vec3, n: Vec3, c: Vec3| {
        m.verts.push(Vertex::new(p, n, c, 0.0));
        m.verts.len() as u32 - 1
    };
    // Each triangle wound to face away from `centre`.
    let tri = |m: &mut Mesh, a: u32, b: u32, c: u32, centre: Vec3| {
        let (pa, pb, pc) = (m.verts[a as usize].pos(), m.verts[b as usize].pos(), m.verts[c as usize].pos());
        let out = (pb - pa).cross(pc - pa).dot((pa + pb + pc) * (1.0 / 3.0) - centre) > 0.0;
        m.indices.extend_from_slice(&if out { [a, b, c] } else { [a, c, b] });
    };
    // The trunk, five sides, up into the crown.
    let tr = 0.1 + 0.025 * crown;
    let axis = base + v3(0.0, (height - ry) / 2.0, 0.0);
    let ring = |k: usize, y: f32| {
        let a = k as f32 / 5.0 * std::f32::consts::TAU;
        (v3(a.cos() * tr, y, a.sin() * tr), v3(a.cos(), 0.0, a.sin()))
    };
    let first = m.verts.len() as u32;
    for k in 0..5 {
        let ((p0, n), (p1, _)) = (ring(k, 0.0), ring(k, height - ry));
        push(m, base + p0, n, bark);
        push(m, base + p1, n, bark);
    }
    for k in 0..5u32 {
        let (a, b, c, d) = (first + 2 * k, first + 2 * k + 1, first + 2 * ((k + 1) % 5), first + 2 * ((k + 1) % 5) + 1);
        tri(m, a, c, b, axis);
        tri(m, b, c, d, axis);
    }
    // The crown: a point below, two rings, a point on top; every vertex
    // pushed in or out a little so no two trees are alike.
    let spin = rnd() * std::f32::consts::TAU;
    let shade = |f: f32| leaf * f;
    let vert = |m: &mut Mesh, p: Vec3, f: f32| {
        let n = v3((p.x - mid.x) / r, (p.y - mid.y) / ry, (p.z - mid.z) / r).norm();
        push(m, p, n, shade(f))
    };
    let bottom = vert(m, mid + v3(0.0, -ry * 0.85, 0.0), 0.75);
    let mut rings = [[0u32; SIDES]; 2];
    for (ring, (y, rad, f, twist)) in rings.iter_mut().zip([(-0.3, 0.95, 0.9, 0.0), (0.4, 0.8, 1.05, 0.5)]) {
        for (k, slot) in ring.iter_mut().enumerate() {
            let a = spin + (k as f32 + twist) / SIDES as f32 * std::f32::consts::TAU;
            let w = r * rad * (0.82 + 0.3 * rnd());
            let p = mid + v3(a.cos() * w, ry * (y + 0.12 * (rnd() - 0.5)), a.sin() * w);
            *slot = vert(m, p, f);
        }
    }
    let top = vert(m, mid + v3(r * 0.15 * (rnd() - 0.5), ry, r * 0.15 * (rnd() - 0.5)), 1.15);
    for k in 0..SIDES {
        let k1 = (k + 1) % SIDES;
        let ([l0, l1], [u0, u1]) = ([rings[0][k], rings[0][k1]], [rings[1][k], rings[1][k1]]);
        tri(m, bottom, l0, l1, mid);
        tri(m, l0, l1, u0, mid);
        tri(m, l1, u1, u0, mid);
        tri(m, u0, u1, top, mid);
    }
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
/// A road's round end, cheap: like `cylinder`, but with no floor, a fan for
/// a top and sides sharing a ring of vertices (smooth): 31 vertices where
/// `cylinder` has 100.
pub fn disc(sides: u32) -> Mesh {
    let mut m = Mesh::default();
    let (w, up) = (Vec3::ONE, v3(0., 1., 0.));
    let ring = |i: u32| {
        let a = i as f32 / sides as f32 * std::f32::consts::TAU;
        v3(a.cos() * 0.5, 0.0, -a.sin() * 0.5)
    };
    m.verts.push(Vertex::new(v3(0., 0.5, 0.), up, w, 0.0));
    for i in 0..sides {
        m.verts.push(Vertex::new(ring(i) + v3(0., 0.5, 0.), up, w, 0.0));
    }
    for i in 0..sides {
        m.indices.extend_from_slice(&[0, 1 + i, 1 + (i + 1) % sides]);
    }
    let base = m.verts.len() as u32;
    for i in 0..sides {
        let out = ring(i) * 2.0;
        m.verts.push(Vertex::new(ring(i) + v3(0., 0.5, 0.), out, w, 0.0));
        m.verts.push(Vertex::new(ring(i) - v3(0., 0.5, 0.), out, w, 0.0));
    }
    for i in 0..sides {
        let (a, b) = (base + 2 * i, base + 2 * ((i + 1) % sides));
        m.indices.extend_from_slice(&[a, a + 1, b + 1, a, b + 1, b]);
    }
    m
}

pub fn plane() -> Mesh {
    let mut m = Mesh::default();
    m.quad(v3(-0.5, 0., 0.5), v3(0.5, 0., 0.5), v3(0.5, 0., -0.5), v3(-0.5, 0., -0.5), Vec3::ONE);
    m
}

pub const BUILTIN_NAMES: [&str; 6] = ["cube", "wedge", "cylinder", "sphere", "plane", "disc"];

pub fn builtins_contains(name: &str) -> bool {
    BUILTIN_NAMES.contains(&name)
}

pub fn builtins() -> Vec<(&'static str, Mesh)> {
    vec![
        ("cube", cube()),
        ("wedge", wedge()),
        ("cylinder", cylinder(10)),
        ("sphere", sphere(6, 10)),
        ("plane", plane()),
        ("disc", disc(10)),
    ]
}

/// Minimal Wavefront OBJ: v, f (any polygon, fan-triangulated, v/vt/vn and negative
/// indices), mtllib + usemtl for flat Kd colors. Normals are recomputed flat.
pub fn load_obj(path: &Path) -> Result<Mesh, String> {
    let src = crate::vfs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
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
                    && let Ok(txt) = crate::vfs::read_to_string(&dir.join(f))
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

    #[test]
    fn text_is_a_box_per_run_of_lit_pixels_centred_on_x() {
        // "I": a full-height middle column and the serifs' four single pixels.
        let m = text(&cube(), "I", 0.7, 0.05);
        let (lo, hi) = m.verts.iter().fold((f32::INFINITY, f32::NEG_INFINITY), |(a, b), v| (a.min(v.pos[1]), b.max(v.pos[1])));
        assert!(lo.abs() < 1e-4 && (hi - 0.7).abs() < 1e-4, "stands on 0, 0.7 tall: {lo}..{hi}");
        let xs: f32 = m.verts.iter().map(|v| v.pos[0]).sum::<f32>() / m.verts.len() as f32;
        assert!(xs.abs() < 0.05, "centred: mean x {xs}");
        // "AB" is twice "A"'s advance wide, less the trailing gap.
        let w = |s: &str| {
            let m = text(&cube(), s, 0.7, 0.05);
            let (a, b) = m.verts.iter().fold((f32::INFINITY, f32::NEG_INFINITY), |(a, b), v| (a.min(v.pos[0]), b.max(v.pos[0])));
            b - a
        };
        assert!((w("AB") - 1.1).abs() < 1e-3, "two letters 11 pixels of 0.1 m: {}", w("AB"));
        assert!(text(&cube(), " ", 0.7, 0.05).verts.is_empty());
        assert!(!text(&cube(), "Ä", 0.7, 0.05).verts.is_empty());
    }

    #[test]
    fn a_leafy_tree_stands_on_its_base_its_crown_as_wide_as_asked_facing_out() {
        let mut m = Mesh::default();
        leafy_tree(&mut m, v3(10.0, 2.0, -5.0), 10.0, 7);
        assert_eq!(m.verts.len(), 26, "small: a hundred thousand of them bake into chunks");
        let lo = m.verts.iter().map(|v| v.pos[1]).fold(f32::INFINITY, f32::min);
        let (hi, wide) = m.verts.iter().fold((f32::NEG_INFINITY, 0f32), |(h, w), v| {
            (h.max(v.pos[1]), w.max(((v.pos[0] - 10.0).powi(2) + (v.pos[2] + 5.0).powi(2)).sqrt()))
        });
        assert!((lo - 2.0).abs() < 1e-4, "on the ground: {lo}");
        assert!(hi > 2.0 + 10.0 && hi < 2.0 + 13.0, "about 12 m tall: {}", hi - 2.0);
        assert!(wide > 4.0 && wide < 6.0, "crown about 10 m across: {}", 2.0 * wide);
        // Every face of the crown faces away from the crown's middle (it's
        // drawn with back faces culled), and the trunk's from its axis.
        let mid = m.verts[10..].iter().fold(Vec3::ZERO, |a, v| a + v.pos()) * (1.0 / 16.0);
        for t in m.indices.chunks(3) {
            let [a, b, c] = [t[0], t[1], t[2]].map(|i| m.verts[i as usize].pos());
            let n = (b - a).cross(c - a);
            let centre = (a + b + c) * (1.0 / 3.0);
            let from = if t[0] < 10 { v3(10.0, centre.y, -5.0) } else { mid };
            assert!(n.dot(centre - from) > 0.0, "a face turned in at {centre:?}");
        }
    }

    #[test]
    fn a_facade_counts_heights_from_its_foot_and_survives_copying() {
        let mut m = Mesh::default();
        m.append_tilted(&cube(), v3(0.0, 5.0, 0.0), (0.0, 0.0, 0.0), v3(4.0, 10.0, 4.0), Vec3::ONE, 0.0);
        m.mark_facade(0, 2, false);
        for v in &m.verts {
            let (id, h, along) = v.facade();
            if v.normal().y.abs() > 0.5 {
                assert_eq!(id, 0, "roof and floor aren't walls");
                continue;
            }
            assert_eq!(id, 2);
            assert!((h - v.pos[1]).abs() < 0.26, "height {h} at y {}", v.pos[1]); // foot at y 0
            assert_eq!(v.emissive(), 0.0, "a facade's alpha is its height, not a glow");
            // A 4 m wall holds one 2.7 m bay: its ends are 0 and 1 bay along.
            assert!(along == 0 || along == 8, "along {along}");
            assert_eq!(v.normal().y, 0.0);
        }
        // Copied into another mesh, raised and stretched twice as tall.
        let mut big = Mesh::default();
        big.append_tilted(&m, v3(0.0, 3.0, 0.0), (0.5, 0.0, 0.0), v3(1.0, 2.0, 1.0), Vec3::ONE, 0.0);
        let top = big.verts.iter().map(|v| v.facade().1).fold(0.0, f32::max);
        assert!((top - 20.0).abs() < 0.26, "top {top}");
        assert!(big.verts.iter().all(|v| v.facade().0 == 2 || v.normal().y.abs() > 0.5));
        assert!(big.verts.iter().filter(|v| v.facade().0 == 2).all(|v| v.facade().2 == 0 || v.facade().2 == 8));

        // A long wall far from the origin, slightly off the axes (its
        // normal's rounding put its ends in different planes once): 40 bays.
        let mut long = Mesh::default();
        long.append_tilted(
            &prism(&[(0.0, 0.0), (120.0, 1.3), (120.0, 11.3), (0.0, 10.0)], 0.0, 12.0, Vec3::ONE, false),
            v3(-300.0, 0.0, 250.0),
            (0.0, 0.0, 0.0),
            Vec3::ONE,
            Vec3::ONE,
            0.0,
        );
        long.mark_facade(0, 1, false);
        let along: Vec<u8> = long.verts.iter().filter(|v| v.facade().0 == 1 && v.normal().z.abs() > 0.9).map(|v| v.facade().2).collect();
        assert!(along.contains(&0) && along.contains(&248), "a 120 m wall from 0 to 31 bays (the most): {along:?}");

        // A unit box its entity scales: along the wall in 255ths.
        let mut unit = Mesh::default();
        unit.append_tilted(&cube(), Vec3::ZERO, (0.0, 0.0, 0.0), Vec3::ONE, Vec3::ONE, 0.0);
        unit.mark_facade(0, 1, true);
        let walls: Vec<_> = unit.verts.iter().filter(|v| v.facade().0 > 0).collect();
        assert_eq!(walls.len(), 16);
        assert!(walls.iter().all(|v| v.facade().0 == 1 | FACADE_SCALED && (v.facade().2 == 0 || v.facade().2 == 255)));
    }

    #[test]
    fn prism_of_an_l_has_walls_out_and_a_roof_up() {
        // An L, given counter-clockwise (positive area): it gets turned round.
        let l = [(0.0, 0.0), (10.0, 0.0), (10.0, 4.0), (4.0, 4.0), (4.0, 10.0), (0.0, 10.0)];
        let m = prism(&l, 0.0, 6.0, Vec3::ONE, false);
        let roof: Vec<_> = m.indices.chunks(3).filter(|t| m.verts[t[0] as usize].normal().y > 0.9).collect();
        assert_eq!(roof.len(), 4, "an L's roof is 4 triangles");
        let area: f32 = roof
            .iter()
            .map(|t| {
                let (a, b, c) = (m.verts[t[0] as usize].pos(), m.verts[t[1] as usize].pos(), m.verts[t[2] as usize].pos());
                (b - a).cross(c - a).len() / 2.0
            })
            .sum();
        assert!((area - 64.0).abs() < 1e-3, "roof covers the L: {area}");
        // Each wall faces away from the L's inside: a point just outside
        // its middle, along its normal, isn't in the L.
        let inside = |x: f32, z: f32| (0.0..10.0).contains(&x) && (0.0..10.0).contains(&z) && (x < 4.0 || z < 4.0);
        for t in m.indices.chunks(3) {
            let v = &m.verts[t[0] as usize];
            let n = v.normal();
            if n.y.abs() < 0.1 {
                let c = (m.verts[t[0] as usize].pos() + m.verts[t[1] as usize].pos() + m.verts[t[2] as usize].pos()) * (1.0 / 3.0);
                assert!(!inside(c.x + n.x * 0.1, c.z + n.z * 0.1), "wall at {c:?} faces in");
                assert!(inside(c.x - n.x * 0.1, c.z - n.z * 0.1), "wall at {c:?} has the L behind it");
            }
        }
    }

    #[test]
    fn a_sloped_ribbons_skirts_go_out_as_they_go_down() {
        // Along +x at height 5, 3 wide, sides 2 m down and out 1.5 m a metre.
        let pts = [v3(0.0, 5.0, 0.0), v3(10.0, 5.0, 0.0)];
        let m = ribbon_sloped(&pts, &|_| 3.0, &|_| 2.0, 1.5, Vec3::ONE);
        let low: Vec<Vec3> = m.verts.iter().map(|v| v.pos()).filter(|p| p.y < 3.5).collect();
        assert_eq!(low.len(), 4);
        for p in low {
            assert!((p.y - 3.0).abs() < 1e-4 && (p.z.abs() - (1.5 + 3.0)).abs() < 1e-4, "{p:?}");
        }
        // Without a slope it's the plain ribbon.
        let (a, b) = (ribbon(&pts, 3.0, 0.3, Vec3::ONE), ribbon_sloped(&pts, &|_| 3.0, &|_| 0.3, 0.0, Vec3::ONE));
        assert!(a.verts.iter().zip(&b.verts).all(|(p, q)| (p.pos() - q.pos()).len() < 1e-6));
    }

    #[test]
    fn a_ribbons_width_can_change_along_it() {
        // Along +x, 2 wide at the start and 6 at the end (a quay behind its wall).
        let pts = [v3(0.0, 1.0, 0.0), v3(10.0, 1.0, 0.0)];
        let m = ribbon_sloped(&pts, &|i| [2.0, 6.0][i], &|_| 0.3, 0.0, Vec3::ONE);
        let top: Vec<Vec3> = m.verts.iter().map(|v| v.pos()).filter(|p| p.y > 0.9).collect();
        let half = |x: f32| top.iter().filter(|p| (p.x - x).abs() < 1e-4).map(|p| p.z.abs()).fold(0.0f32, f32::max);
        assert!((half(0.0) - 1.0).abs() < 1e-4 && (half(10.0) - 3.0).abs() < 1e-4, "{top:?}");
    }

    #[test]
    fn prism_skips_repeated_and_closing_points() {
        let sq = [(0.0, 0.0), (0.0, 0.0), (5.0, 0.0), (5.0, 5.0), (0.0, 5.0), (0.0, 0.0)];
        assert_eq!(prism(&sq, 0.0, 3.0, Vec3::ONE, false).tri_count(), 4 * 2 + 2);
        assert_eq!(prism(&[(0.0, 0.0), (1.0, 0.0)], 0.0, 1.0, Vec3::ONE, false).tri_count(), 0);
        // With a floor: the roof's two triangles again underneath.
        let f = prism(&sq, 0.0, 3.0, Vec3::ONE, true);
        assert_eq!(f.tri_count(), 4 * 2 + 2 + 2);
        let down = f.indices.chunks(3).filter(|t| f.verts[t[0] as usize].normal().y < -0.9).count();
        assert_eq!(down, 2, "the floor faces down");
    }

    /// Every face normal of a closed convex primitive must point away from its center.
    fn outward(m: &Mesh) {
        for t in m.indices.chunks(3) {
            let v = &m.verts[t[0] as usize];
            let (p, n) = (v.pos(), v.normal());
            assert!(p.dot(n) > 0.0, "inward face at {p:?} n={n:?}");
        }
    }

    #[test]
    fn packed_vertices_round_trip() {
        assert_eq!(size_of::<Vertex>(), 20);
        let n = v3(0.6, -0.8, 0.0);
        let v = Vertex::new(v3(1.5, -2.0, 3.25), n, v3(0.2, 0.55, 1.0), 0.6);
        assert_eq!(v.pos(), v3(1.5, -2.0, 3.25));
        assert!((v.normal() - n).len() < 0.01, "{:?}", v.normal());
        assert!((v.color() - v3(0.2, 0.55, 1.0)).len() < 0.005, "{:?}", v.color());
        assert!((v.emissive() - 0.6).abs() < 0.005);
        // Out of range clamps rather than wrapping round.
        let w = Vertex::new(Vec3::ZERO, v3(0.0, 1.0, 0.0), v3(1.4, -0.2, 0.5), 2.0);
        assert_eq!((w.color[0], w.color[1], w.color[3]), (255, 0, 255));
    }

    #[test]
    fn quads_share_their_corners() {
        let c = cube();
        assert_eq!((c.verts.len(), c.tri_count()), (24, 12));
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

    #[test]
    fn ground_keeps_its_normal_and_survives_copying() {
        let mut m = Mesh::default();
        m.append_tilted(&cube(), v3(0.0, 0.0, 0.0), (0.0, 0.0, 0.0), v3(4.0, 0.2, 4.0), Vec3::ONE, 0.0);
        m.mark_ground(0, GROUND_SETTS);
        let mut copy = Mesh::default();
        copy.append_tilted(&m, v3(1.0, 0.0, 0.0), (0.7, 0.0, 0.0), Vec3::ONE, Vec3::ONE, 0.0);
        assert!(copy.verts.iter().all(|v| v.ground() == GROUND_SETTS && v.facade().0 == 0));
        assert!(copy.verts.iter().any(|v| v.normal().y > 0.9), "the top still faces up");
    }
}
