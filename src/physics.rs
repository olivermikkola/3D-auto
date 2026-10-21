//! Rigid-body boxes. Oriented boxes collide via the separating axis test,
//! contacts are the penetrating corners, and a sequential-impulse solver
//! (accumulated, clamped normal + two-axis friction, Baumgarte bias) applies
//! both linear and angular response. Cars roll, crates tumble, ramps work.
//!
//! Bodies with `step > 0` walk up low ledges instead of bumping into them,
//! and `lock_rotation` keeps characters upright.

use crate::engine::Entity;
use crate::math::{Quat, Vec3, v3};
use std::collections::{HashMap, HashSet};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Static,
    Dynamic,
    Kinematic,
}

#[derive(Clone, Debug)]
pub struct Body {
    pub kind: Kind,
    pub half: Vec3,
    pub vel: Vec3,
    pub ang_vel: Vec3,
    pub inv_mass: f32,
    /// Body-space diagonal inverse inertia.
    pub inv_inertia: Vec3,
    pub restitution: f32,
    pub friction: f32,
    pub gravity: f32,
    pub sensor: bool,
    pub grounded: bool,
    /// Ledges up to this height are stepped onto instead of blocking.
    pub step: f32,
    pub lock_rotation: bool,
}

impl Body {
    pub fn new(kind: Kind, half: Vec3) -> Body {
        let mut b = Body {
            kind,
            half,
            vel: Vec3::ZERO,
            ang_vel: Vec3::ZERO,
            inv_mass: 0.0,
            inv_inertia: Vec3::ZERO,
            restitution: 0.0,
            friction: 0.6,
            gravity: 1.0,
            sensor: false,
            grounded: false,
            step: 0.0,
            lock_rotation: false,
        };
        b.set_mass(1.0);
        b
    }

    /// Solid box inertia. Non-dynamic or rotation-locked bodies get none.
    pub fn set_mass(&mut self, m: f32) {
        if self.kind != Kind::Dynamic || m <= 0.0 {
            self.inv_mass = 0.0;
            self.inv_inertia = Vec3::ZERO;
            return;
        }
        self.inv_mass = 1.0 / m;
        let h = self.half;
        let i = |a: f32, b: f32| if self.lock_rotation { 0.0 } else { 3.0 / (m * (a * a + b * b)) };
        self.inv_inertia = v3(i(h.y, h.z), i(h.x, h.z), i(h.x, h.y));
    }

    fn inv_inertia_world(&self, q: Quat, v: Vec3) -> Vec3 {
        if self.inv_inertia == Vec3::ZERO {
            return Vec3::ZERO; // static, kinematic or rotation-locked
        }
        q.rotate(q.conj().rotate(v).mul(self.inv_inertia))
    }
}

/// World-space half extents of an oriented box's bounding box.
pub fn extents(half: Vec3, rot: Quat) -> Vec3 {
    let [a, b, c] = rot.axes();
    let (a, b, c) = (a.abs() * half.x, b.abs() * half.y, c.abs() * half.z);
    a + b + c
}

/// A heightfield: `w` x `d` heights, `step` meters apart, row by row from
/// (x0, z0) toward +x then +z. Each cell is two triangles split along its
/// (x+1, z)-(x, z+1) diagonal, and drawing and collision use that same
/// surface. `id` is its entity, the "b" side of terrain contacts.
pub struct Terrain {
    pub x0: f32,
    pub z0: f32,
    pub step: f32,
    pub w: usize,
    pub d: usize,
    pub heights: Vec<f32>,
    pub id: usize,
    pub top: f32,
    /// How far raised pavements and medians stand above the road beside them.
    pub kerb: f32,
    roads: Vec<RoadSeg>,
    /// Road segments by ROAD_CELL square, as ranges into `road_items`.
    road_cells: Vec<u32>,
    road_items: Vec<u32>,
    road_w: usize,
}

/// A stretch of road laid over the terrain: its centerline from `a` to `b`
/// (heights in y), flat across out to `half` meters each side. The asphalt
/// is `carriage` meters each side; past it, a side that's `raised` (a
/// pavement, a median) stands the terrain's `kerb` higher, out to `half`.
/// Side 0 is the one toward (dz, -dx), (dx, dz) being b - a.
#[derive(Clone, Copy)]
pub struct RoadSeg {
    pub a: Vec3,
    pub b: Vec3,
    pub half: f32,
    pub carriage: f32,
    pub raised: [bool; 2],
    /// Which road it's part of: a road follows its nearest piece, and
    /// different roads that overlap blend.
    pub road: u32,
}

const ROAD_CELL: f32 = 16.0;
/// Past a road's edge the surface eases back to the heightfield over this many meters.
const ROAD_BLEND: f32 = 2.0;

impl Terrain {
    pub fn new(x0: f32, z0: f32, step: f32, w: usize, d: usize, heights: Vec<f32>) -> Terrain {
        let top = heights.iter().copied().fold(f32::MIN, f32::max);
        Terrain {
            x0,
            z0,
            step,
            w,
            d,
            heights,
            id: usize::MAX,
            top,
            kerb: 0.0,
            roads: Vec::new(),
            road_cells: Vec::new(),
            road_items: Vec::new(),
            road_w: 0,
        }
    }

    /// Lay roads over the heightfield: on them the surface is the road's
    /// own, smooth along it and level across, instead of the grid's
    /// triangles; it eases back to the grid just past their edges.
    pub fn with_roads(mut self, roads: Vec<RoadSeg>) -> Terrain {
        let (rw, rd) =
            (((self.w - 1) as f32 * self.step / ROAD_CELL) as usize + 1, ((self.d - 1) as f32 * self.step / ROAD_CELL) as usize + 1);
        let mut lists: Vec<Vec<u32>> = vec![Vec::new(); rw * rd];
        let cell = |v: f32, n: usize| ((v / ROAD_CELL).floor().max(0.0) as usize).min(n - 1);
        for (k, r) in roads.iter().enumerate() {
            let pad = r.half + ROAD_BLEND;
            let (lx, hx) = (r.a.x.min(r.b.x) - pad - self.x0, r.a.x.max(r.b.x) + pad - self.x0);
            let (lz, hz) = (r.a.z.min(r.b.z) - pad - self.z0, r.a.z.max(r.b.z) + pad - self.z0);
            for j in cell(lz, rd)..=cell(hz, rd) {
                for i in cell(lx, rw)..=cell(hx, rw) {
                    lists[j * rw + i].push(k as u32);
                }
            }
            self.top = self.top.max(r.a.y).max(r.b.y);
        }
        self.road_cells = Vec::with_capacity(lists.len() + 1);
        self.road_items.clear();
        for l in &lists {
            self.road_cells.push(self.road_items.len() as u32);
            self.road_items.extend_from_slice(l);
        }
        self.road_cells.push(self.road_items.len() as u32);
        self.roads = roads;
        self.road_w = rw;
        // Where a road runs below the grid (in a sag, or down a trench into
        // a tunnel) the grid under it comes down to meet it, so the ground
        // drawn there doesn't cover the road.
        for j in 0..self.d {
            for i in 0..self.w {
                let (x, z) = (self.x0 + i as f32 * self.step, self.z0 + j as f32 * self.step);
                if let Some((on, rh, _)) = self.road(x, z)
                    && on >= 1.0
                    && rh - 0.15 < self.heights[j * self.w + i]
                {
                    self.heights[j * self.w + i] = rh - 0.15;
                }
            }
        }
        self
    }

    pub fn at(&self, i: usize, j: usize) -> f32 {
        self.heights[j * self.w + i]
    }

    /// How much of (x, z) is road (1 on one, easing to 0 over ROAD_BLEND
    /// past its edge), and the roads' height and normal there. Where roads
    /// overlap, as they do around junctions, they're averaged, nearer
    /// centerlines counting more, so one never steps onto another. On a
    /// raised side it's a kerb higher, unless it's on some road's asphalt
    /// (where one road's pavement meets another road at a junction).
    fn road(&self, x: f32, z: f32) -> Option<(f32, f32, Vec3)> {
        if self.roads.is_empty() {
            return None;
        }
        let (u, v) = ((x - self.x0) / ROAD_CELL, (z - self.z0) / ROAD_CELL);
        if !(u >= 0.0 && v >= 0.0) || u as usize >= self.road_w || (v as usize + 1) * self.road_w >= self.road_cells.len() {
            return None;
        }
        let c = v as usize * self.road_w + u as usize;
        // Per road: its pieces blended, the ones (x, z) is beside by far the
        // most (so inside a bend there's no crease where one piece hands over
        // to the next):
        // (road, weight, weighted height, weighted normal, nearest distance
        // squared, coverage, reach).
        let mut near = [(u32::MAX, 0.0f32, 0.0f32, Vec3::ZERO, f32::MAX, 0.0f32, 0.0f32); 8];
        let mut n = 0;
        let (mut asphalt, mut raised) = (false, false);
        for &k in &self.road_items[self.road_cells[c] as usize..self.road_cells[c + 1] as usize] {
            let r = &self.roads[k as usize];
            let (dx, dz) = (r.b.x - r.a.x, r.b.z - r.a.z);
            let l2 = dx * dx + dz * dz;
            let along = if l2 > 1e-9 { ((x - r.a.x) * dx + (z - r.a.z) * dz) / l2 } else { 0.0 };
            let t = along.clamp(0.0, 1.0);
            let d2 = (x - r.a.x - dx * t).powi(2) + (z - r.a.z - dz * t).powi(2);
            let on = 1.0 - (d2.sqrt() - r.half) / ROAD_BLEND;
            if on <= 0.0 {
                continue;
            }
            let g = if l2 > 1e-9 { (r.b.y - r.a.y) / l2 } else { 0.0 };
            let (h, nrm) = (r.a.y + (r.b.y - r.a.y) * t, v3(-dx * g, 1.0, -dz * g).norm());
            // Beside its own piece a point counts that piece almost alone;
            // a meter past a piece's end, it barely counts, nor toward the
            // edge of a piece across a bend.
            let past_end = (along - t).abs() * l2.sqrt();
            if d2 <= r.carriage * r.carriage {
                asphalt = true;
            } else if past_end < 1e-3 && d2 <= r.half * r.half {
                let side = ((x - r.a.x) * dz - (z - r.a.z) * dx < 0.0) as usize;
                raised |= r.raised[side];
            }
            let w = (1.0 - d2.sqrt() / (r.half + ROAD_BLEND)).powi(2) / (past_end * past_end + 0.01).powi(2);
            let i = match near[..n].iter().position(|p| p.0 == r.road) {
                Some(i) => i,
                None if n < near.len() => {
                    n += 1;
                    near[n - 1].0 = r.road;
                    n - 1
                }
                None => continue,
            };
            let p = &mut near[i];
            p.1 += w;
            p.2 += w * h;
            p.3 += nrm * w;
            p.4 = p.4.min(d2);
            p.5 = p.5.max(on.min(1.0));
            p.6 = r.half + ROAD_BLEND;
        }
        // Then the roads together, nearer centerlines counting more and
        // fading out smoothly toward each one's outer edge, so between two
        // the surface leans from one to the other without a step.
        let (mut cover, mut sw, mut sh, mut sn) = (0.0f32, 0.0f32, 0.0f32, Vec3::ZERO);
        for &(_, pw, ph, pn, d2, on, reach) in &near[..n] {
            let w = (1.0 - d2.sqrt() / reach).powi(2);
            cover = cover.max(on);
            sw += w;
            sh += w * ph / pw;
            sn += pn.norm() * w;
        }
        let kerb = if raised && !asphalt { self.kerb } else { 0.0 };
        (sw > 0.0).then(|| (cover, sh / sw + kerb, sn.norm()))
    }

    /// Height and upward normal at (x, z), roads included; None off the grid.
    pub fn surface(&self, x: f32, z: f32) -> Option<(f32, Vec3)> {
        let (h, n) = self.grid(x, z)?;
        Some(match self.road(x, z) {
            Some((on, rh, rn)) => (h + (rh - h) * on, (n * (1.0 - on) + rn * on).norm()),
            None => (h, n),
        })
    }

    /// The heightfield's own triangles at (x, z), as drawn.
    pub fn grid(&self, x: f32, z: f32) -> Option<(f32, Vec3)> {
        let (u, v) = ((x - self.x0) / self.step, (z - self.z0) / self.step);
        if !(u >= 0.0 && v >= 0.0) {
            return None;
        }
        let (i, j) = (u as usize, v as usize);
        if i + 1 >= self.w || j + 1 >= self.d {
            return None;
        }
        let (fx, fz) = (u - i as f32, v - j as f32);
        let (h00, h10, h01, h11) = (self.at(i, j), self.at(i + 1, j), self.at(i, j + 1), self.at(i + 1, j + 1));
        let (h, dx, dz) = if fx + fz <= 1.0 {
            (h00 + (h10 - h00) * fx + (h01 - h00) * fz, h10 - h00, h01 - h00)
        } else {
            (h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz), h11 - h01, h11 - h10)
        };
        Some((h, v3(-dx / self.step, 1.0, -dz / self.step).norm()))
    }

    /// Where a ray coming from above first meets the surface: distance and
    /// normal. Marches half a cell at a time, then bisects.
    pub fn ray(&self, o: Vec3, dir: Vec3, max: f32) -> Option<(f32, Vec3)> {
        let below = |t: f32| {
            let p = o + dir * t;
            self.surface(p.x, p.z).map(|(h, _)| p.y < h)
        };
        let dt = self.step * 0.5;
        let (mut t0, mut t) = (0.0f32, 0.0f32);
        if below(0.0) == Some(true) {
            return None; // starts underground
        }
        while t < max {
            t = (t + dt).min(max);
            let p = o + dir * t;
            if p.y > self.top && dir.y >= 0.0 {
                return None; // above every hill and climbing
            }
            if below(t) == Some(true) {
                let (mut lo, mut hi) = (t0, t);
                for _ in 0..16 {
                    let mid = (lo + hi) * 0.5;
                    if below(mid) == Some(true) {
                        hi = mid;
                    } else {
                        lo = mid;
                    }
                }
                let p = o + dir * hi;
                return self.surface(p.x, p.z).map(|(_, n)| (hi, n));
            }
            t0 = t;
        }
        None
    }
}

pub struct Contact {
    pub a: u32,
    pub b: u32,
    /// Closing speed along the contact normal when they met (m/s).
    pub speed: f32,
}

/// Accumulated impulses from last step, keyed by (body a, body b, feature).
/// Starting the solver from them ("warm starting") is what lets stacks rest.
pub type WarmCache = HashMap<(usize, usize, u8), (f32, f32, f32)>;

struct Point {
    feature: u8,
    ra: Vec3,
    rb: Vec3,
    depth: f32,
    t1: Vec3,
    t2: Vec3,
    mass_n: f32,
    mass_t1: f32,
    mass_t2: f32,
    bounce: f32,
    pn: f32,
    pt1: f32,
    pt2: f32,
}

struct Manifold {
    a: usize,
    b: usize,
    n: Vec3, // from b to a
    mu: f32,
    points: Vec<Point>,
}

const ITERATIONS: usize = 10;
const SLOP: f32 = 0.01;
const BAUMGARTE: f32 = 0.2;

fn body(ents: &[Option<Entity>], i: usize) -> (&Entity, &Body) {
    let e = ents[i].as_ref().unwrap();
    (e, e.body.as_ref().unwrap())
}

/// Broad phase. Static bodies sit in a uniform grid over XZ that persists
/// between steps and is rebuilt only when one is added, removed or moved.
/// Dynamic and kinematic bodies, and anything huge (the ground), are checked
/// against everyone. Candidates come back in ascending entity order, the
/// order a full scan visits them, so the solver sees the same sequence.
#[derive(Default)]
pub struct Broad {
    cells: HashMap<(i32, i32), Vec<usize>>,
    big: Vec<usize>,
    /// Each static's AABB, and the pose it had when the grid was built.
    boxes: Vec<Option<(Vec3, Vec3)>>,
    poses: Vec<Option<[f32; 10]>>,
    statics: usize,
    pub rebuilds: u64,
    /// As of the last step: the moving bodies, and how many slots there were.
    movers: Vec<usize>,
    len: usize,
}

impl Broad {
    const CELL: f32 = 16.0;
    /// Bodies spanning more than this many cells skip the grid.
    const BIG: i32 = 6;

    fn range(c: Vec3, h: Vec3) -> (i32, i32, i32, i32) {
        let f = |v: f32| (v / Self::CELL).floor() as i32;
        (f(c.x - h.x), f(c.x + h.x), f(c.z - h.z), f(c.z + h.z))
    }

    fn pose(p: Vec3, r: Quat, h: Vec3) -> [f32; 10] {
        [p.x, p.y, p.z, r.x, r.y, r.z, r.w, h.x, h.y, h.z]
    }

    fn rebuild(&mut self, ents: &[Option<Entity>]) {
        self.cells.clear();
        self.big.clear();
        self.boxes = vec![None; ents.len()];
        self.poses = vec![None; ents.len()];
        self.statics = 0;
        self.rebuilds += 1;
        for (i, e) in ents.iter().enumerate() {
            let Some(e) = e else { continue };
            let Some(b) = &e.body else { continue };
            if b.kind != Kind::Static {
                continue;
            }
            let (c, h) = (e.pos, extents(b.half, e.rot));
            self.boxes[i] = Some((c, h));
            self.poses[i] = Some(Self::pose(e.pos, e.rot, b.half));
            self.statics += 1;
            let (x0, x1, z0, z1) = Self::range(c, h);
            if x1 - x0 > Self::BIG || z1 - z0 > Self::BIG {
                self.big.push(i);
                continue;
            }
            for x in x0..=x1 {
                for z in z0..=z1 {
                    self.cells.entry((x, z)).or_default().push(i);
                }
            }
        }
    }

    /// Entities near the box: statics from its cells, big ones and `movers`, sorted.
    fn near(&self, (c, h): (Vec3, Vec3), movers: &[usize], out: &mut Vec<usize>) {
        out.clear();
        out.extend_from_slice(&self.big);
        out.extend_from_slice(movers);
        let (x0, x1, z0, z1) = Self::range(c, h);
        for x in x0..=x1 {
            for z in z0..=z1 {
                if let Some(v) = self.cells.get(&(x, z)) {
                    out.extend_from_slice(v);
                }
            }
        }
        out.sort_unstable();
        out.dedup();
    }
}

pub fn step(
    ents: &mut [Option<Entity>],
    dt: f32,
    gravity: f32,
    warm: &mut WarmCache,
    broad: &mut Broad,
    terrain: Option<&Terrain>,
) -> Vec<Contact> {
    // 1. Forces. Also notice whether any static body changed since the grid was built.
    let mut dynamic = Vec::new();
    let mut movers = Vec::new();
    let (mut statics, mut stale) = (0, false);
    for (i, e) in ents.iter_mut().enumerate() {
        let Some(e) = e else { continue };
        let Some(b) = &mut e.body else { continue };
        if b.kind == Kind::Static {
            statics += 1;
            stale = stale || broad.poses.get(i).copied().flatten() != Some(Broad::pose(e.pos, e.rot, b.half));
            continue;
        }
        movers.push(i);
        if b.kind == Kind::Dynamic {
            b.vel.y += gravity * b.gravity * dt;
            b.ang_vel = b.ang_vel * (1.0 / (1.0 + 0.3 * dt));
            if b.lock_rotation {
                b.ang_vel = Vec3::ZERO;
            }
            b.grounded = false;
            dynamic.push(i);
        }
    }
    if stale || statics != broad.statics {
        broad.rebuild(ents);
    }
    broad.movers.clone_from(&movers);
    broad.len = ents.len();

    // 2. Narrow phase. Moving bodies' AABBs are computed fresh; statics' come from the grid.
    let aabb = |e: &Entity| (e.pos, extents(e.body.as_ref().unwrap().half, e.rot));
    let mut moving: HashMap<usize, (Vec3, Vec3)> = HashMap::with_capacity(movers.len());
    for &i in &movers {
        moving.insert(i, aabb(ents[i].as_ref().unwrap()));
    }
    let bounds = |j: usize| moving.get(&j).copied().or_else(|| broad.boxes[j]).unwrap();
    let mut manifolds = Vec::new();
    let mut touching = Vec::new();
    let mut seen = HashSet::new();
    let mut near = Vec::new();
    for &i in &dynamic {
        let bi = moving[&i];
        broad.near(bi, &movers, &mut near);
        for &j in &near {
            if i == j {
                continue;
            }
            let ((ca, ha), (cb, hb)) = (bi, bounds(j));
            let (d, h) = ((ca - cb).abs(), ha + hb);
            if d.x >= h.x || d.y >= h.y || d.z >= h.z {
                continue;
            }
            let b_dynamic = body(ents, j).1.kind == Kind::Dynamic;
            if b_dynamic && j < i || !seen.insert((i.min(j), i.max(j))) {
                continue;
            }
            let (ea, ba) = body(ents, i);
            let (eb, bb) = body(ents, j);
            let Some((n, pts)) = collide(ea.pos, ea.rot, ba.half, eb.pos, eb.rot, bb.half) else { continue };
            if ba.sensor || bb.sensor {
                touching.push((i, j, 0.0));
                continue;
            }
            // Step-up: a low ledge met side-on lifts the body instead of walling it.
            // Narrow vertical posts and poles (e.g. lamp posts, traffic signs) must not act
            // as step ramps for vehicles; require the obstacle to have sufficient horizontal footprint.
            let b_is_pole = hb.x < 0.25 && hb.z < 0.25 && hb.y > 1.5;
            if !b_dynamic && !b_is_pole && ba.step > 0.0 && n.y.abs() < 0.5 {
                // The ledge's height where the body is: a tilted slab's top
                // face there (a bridge deck piece), not its bounding box's
                // top, which is its highest corner metres away.
                let up = eb.rot.rotate(Vec3::UP);
                let mut top = cb.y + hb.y;
                if up.y > 0.9 {
                    let t = eb.pos + up * bb.half.y;
                    top = top.min(t.y - (up.x * (ca.x - t.x) + up.z * (ca.z - t.z)) / up.y);
                }
                let rise = top - (ca.y - ha.y);
                if rise > -0.2 && rise <= ba.step && ca.y > top {
                    let e = ents[i].as_mut().unwrap();
                    e.pos.y += rise.max(0.0) + 0.01;
                    let b = e.body.as_mut().unwrap();
                    b.vel.y = b.vel.y.max(0.0);
                    b.grounded = true;
                    touching.push((i, j, 0.0));
                    continue;
                }
            }
            let mu = (ba.friction * bb.friction).sqrt();
            let e_rest = ba.restitution.max(bb.restitution);
            let mut m = Manifold { a: i, b: j, n, mu, points: Vec::new() };
            let (t1, t2) = tangents(n);
            let mut closing: f32 = 0.0;
            for (feature, p, depth) in pts {
                let (ra, rb) = (p - ea.pos, p - eb.pos);
                let k = |dir: Vec3| {
                    let ia = ba.inv_mass + ba.inv_inertia_world(ea.rot, ra.cross(dir)).cross(ra).dot(dir);
                    let ib = bb.inv_mass + bb.inv_inertia_world(eb.rot, rb.cross(dir)).cross(rb).dot(dir);
                    1.0 / (ia + ib).max(1e-9)
                };
                let vn = rel_vel(ba, bb, ra, rb).dot(n);
                closing = closing.max(-vn);
                let bounce = if vn < -1.0 { -e_rest * vn } else { 0.0 };
                let (pn, pt1, pt2) = warm.get(&(i, j, feature)).copied().unwrap_or_default();
                m.points.push(Point { feature, ra, rb, depth, t1, t2, mass_n: k(n), mass_t1: k(t1), mass_t2: k(t2), bounce, pn, pt1, pt2 });
            }
            touching.push((i, j, closing));
            if n.y > 0.7 {
                ents[i].as_mut().unwrap().body.as_mut().unwrap().grounded = true;
            } else if n.y < -0.7 && b_dynamic {
                ents[j].as_mut().unwrap().body.as_mut().unwrap().grounded = true;
            }
            manifolds.push(m);
        }
    }

    // 2b. Terrain: each corner of a moving box that's below the surface
    // pushes off it along the surface's normal there, one contact each.
    if let Some(t) = terrain
        && ents.get(t.id).is_some_and(|e| e.is_some())
    {
        let mut grounded = Vec::new();
        for &i in &dynamic {
            let (ea, ba) = body(ents, i);
            let (eb, bb) = body(ents, t.id);
            if ba.sensor || ea.pos.y - ba.half.len() > t.top {
                continue;
            }
            let mut closing: f32 = 0.0;
            let mut hit = false;
            for (k, p) in corners(ea.pos, &ea.rot.axes(), ba.half).into_iter().enumerate() {
                let Some((h, n)) = t.surface(p.x, p.z) else { continue };
                if p.y >= h {
                    continue;
                }
                let feature = 24 + k as u8;
                let (ra, rb) = (p - ea.pos, p - eb.pos);
                let kk = |dir: Vec3| {
                    let ia = ba.inv_mass + ba.inv_inertia_world(ea.rot, ra.cross(dir)).cross(ra).dot(dir);
                    1.0 / ia.max(1e-9)
                };
                let vn = rel_vel(ba, bb, ra, rb).dot(n);
                closing = closing.max(-vn);
                let bounce = if vn < -1.0 { -ba.restitution * vn } else { 0.0 };
                let (pn, pt1, pt2) = warm.get(&(i, t.id, feature)).copied().unwrap_or_default();
                let (t1, t2) = tangents(n);
                let depth = (h - p.y) * n.y;
                let point = Point { feature, ra, rb, depth, t1, t2, mass_n: kk(n), mass_t1: kk(t1), mass_t2: kk(t2), bounce, pn, pt1, pt2 };
                manifolds.push(Manifold { a: i, b: t.id, n, mu: (ba.friction * bb.friction).sqrt(), points: vec![point] });
                hit = true;
                if n.y > 0.7 {
                    grounded.push(i);
                }
            }
            if hit {
                touching.push((i, t.id, closing));
            }
        }
        for i in grounded {
            ents[i].as_mut().unwrap().body.as_mut().unwrap().grounded = true;
        }
    }

    // 3. Sequential impulses, starting from last step's.
    for m in &manifolds {
        warm_start(ents, m);
    }
    for _ in 0..ITERATIONS {
        for m in &mut manifolds {
            solve(ents, m, dt);
        }
    }

    warm.clear();
    for m in &manifolds {
        for p in &m.points {
            warm.insert((m.a, m.b, p.feature), (p.pn, p.pt1, p.pt2));
        }
    }

    // 4. Integrate.
    for e in ents.iter_mut().flatten() {
        let Some(b) = &e.body else { continue };
        match b.kind {
            Kind::Static => {}
            _ => {
                e.pos += b.vel * dt;
                if b.ang_vel != Vec3::ZERO {
                    e.rot = e.rot.integrate(b.ang_vel, dt);
                }
            }
        }
    }

    touching.into_iter().map(|(a, b, speed)| Contact { a: a.min(b) as u32, b: a.max(b) as u32, speed }).collect()
}

fn rel_vel(a: &Body, b: &Body, ra: Vec3, rb: Vec3) -> Vec3 {
    (a.vel + a.ang_vel.cross(ra)) - (b.vel + b.ang_vel.cross(rb))
}

fn tangents(n: Vec3) -> (Vec3, Vec3) {
    let t1 = if n.x.abs() > 0.57 { v3(n.y, -n.x, 0.0) } else { v3(0.0, n.z, -n.y) }.norm();
    (t1, n.cross(t1))
}

/// Both bodies of a manifold, and a function applying an impulse at a contact.
fn bodies<'a>(
    ents: &'a mut [Option<Entity>],
    m: &Manifold,
) -> (&'a mut Body, &'a mut Body, impl Fn(&mut Body, &mut Body, Vec3, Vec3, Vec3) + use<>) {
    let (ea, eb) = pair_mut(ents, m.a, m.b);
    let (ea, eb) = (ea.as_mut().unwrap(), eb.as_mut().unwrap());
    let (qa, qb) = (ea.rot, eb.rot);
    let (a, b) = (ea.body.as_mut().unwrap(), eb.body.as_mut().unwrap());
    let b_moves = b.kind == Kind::Dynamic;
    let apply = move |a: &mut Body, b: &mut Body, ra: Vec3, rb: Vec3, imp: Vec3| {
        a.vel += imp * a.inv_mass;
        a.ang_vel += a.inv_inertia_world(qa, ra.cross(imp));
        if b_moves {
            b.vel -= imp * b.inv_mass;
            b.ang_vel -= b.inv_inertia_world(qb, rb.cross(imp));
        }
    };
    (a, b, apply)
}

fn warm_start(ents: &mut [Option<Entity>], m: &Manifold) {
    let (a, b, apply) = bodies(ents, m);
    for p in &m.points {
        apply(a, b, p.ra, p.rb, m.n * p.pn + p.t1 * p.pt1 + p.t2 * p.pt2);
    }
}

fn solve(ents: &mut [Option<Entity>], m: &mut Manifold, dt: f32) {
    let (a, b, apply) = bodies(ents, m);
    for p in &mut m.points {
        // Normal: push apart, with a bias that removes penetration.
        let vn = rel_vel(a, b, p.ra, p.rb).dot(m.n);
        let bias = (BAUMGARTE / dt * (p.depth - SLOP).max(0.0)).max(p.bounce);
        let old = p.pn;
        p.pn = (old + (bias - vn) * p.mass_n).max(0.0);
        apply(a, b, p.ra, p.rb, m.n * (p.pn - old));

        // Friction, bounded by the normal impulse (box approximation of the cone).
        let lim = m.mu * p.pn;
        for (t, acc, mass) in [(p.t1, &mut p.pt1, p.mass_t1), (p.t2, &mut p.pt2, p.mass_t2)] {
            let vt = rel_vel(a, b, p.ra, p.rb).dot(t);
            let old = *acc;
            *acc = (old - vt * mass).clamp(-lim, lim);
            apply(a, b, p.ra, p.rb, t * (*acc - old));
        }
    }
}

/// (feature id, world point, penetration depth). Feature ids are stable
/// across steps (which corner of which box) so impulses can be warm-started.
pub type ContactPoint = (u8, Vec3, f32);

/// Separating axis test for two oriented boxes. Returns the contact normal
/// (pointing from b to a) and contact points with their depths.
pub fn collide(ca: Vec3, qa: Quat, ha: Vec3, cb: Vec3, qb: Quat, hb: Vec3) -> Option<(Vec3, Vec<ContactPoint>)> {
    let (aa, ab) = (qa.axes(), qb.axes());
    let d = ca - cb;
    let radius = |ax: &[Vec3; 3], h: Vec3, l: Vec3| ax[0].dot(l).abs() * h.x + ax[1].dot(l).abs() * h.y + ax[2].dot(l).abs() * h.z;
    let mut best: Option<(f32, Vec3)> = None;
    let mut test = |l: Vec3, is_edge: bool| -> bool {
        let len = l.len();
        if len < 1e-4 {
            return true; // parallel edges: covered by face axes
        }
        let l = l * (1.0 / len);
        let overlap = radius(&aa, ha, l) + radius(&ab, hb, l) - d.dot(l).abs();
        if overlap < 0.0 {
            return false;
        }
        // Prefer face axes; edge axes must be clearly better to win.
        let score = if is_edge { overlap * 1.05 + 0.01 } else { overlap };
        if best.is_none_or(|(s, _)| score < s) {
            best = Some((score, if d.dot(l) < 0.0 { -l } else { l }));
        }
        true
    };
    for l in aa.iter().chain(ab.iter()) {
        if !test(*l, false) {
            return None;
        }
    }
    for x in &aa {
        for y in &ab {
            if !test(x.cross(*y), true) {
                return None;
            }
        }
    }
    let (_, n) = best?;

    // Contacts: corners of each box that are inside the other.
    let mut pts = Vec::new();
    let top_b = cb.dot(n) + radius(&ab, hb, n);
    let bottom_a = ca.dot(n) - radius(&aa, ha, n);
    for (k, p) in corners(ca, &aa, ha).into_iter().enumerate() {
        if inside(p, cb, &ab, hb) {
            pts.push((k as u8, p, top_b - p.dot(n)));
        }
    }
    for (k, p) in corners(cb, &ab, hb).into_iter().enumerate() {
        if inside(p, ca, &aa, ha) {
            pts.push((8 + k as u8, p, p.dot(n) - bottom_a));
        }
    }
    if pts.is_empty() {
        // Edge on edge: one contact between the two deepest features.
        let pa = support(ca, &aa, ha, -n);
        let pb = support(cb, &ab, hb, n);
        pts.push((16, (pa + pb) * 0.5, (pb - pa).dot(n).max(0.0)));
    }
    if pts.len() > 8 {
        pts.sort_by(|x, y| y.2.total_cmp(&x.2));
        pts.truncate(8);
    }
    Some((n, pts))
}

fn corners(c: Vec3, ax: &[Vec3; 3], h: Vec3) -> [Vec3; 8] {
    let mut out = [Vec3::ZERO; 8];
    for (i, o) in out.iter_mut().enumerate() {
        let s = |bit: usize| if i >> bit & 1 == 1 { 1.0 } else { -1.0 };
        *o = c + ax[0] * (h.x * s(0)) + ax[1] * (h.y * s(1)) + ax[2] * (h.z * s(2));
    }
    out
}

fn inside(p: Vec3, c: Vec3, ax: &[Vec3; 3], h: Vec3) -> bool {
    let d = p - c;
    let tol = 1e-3;
    d.dot(ax[0]).abs() <= h.x + tol && d.dot(ax[1]).abs() <= h.y + tol && d.dot(ax[2]).abs() <= h.z + tol
}

/// Corner of the box farthest along `dir`.
fn support(c: Vec3, ax: &[Vec3; 3], h: Vec3, dir: Vec3) -> Vec3 {
    let s = |a: Vec3, e: f32| a * (e * a.dot(dir).signum());
    c + s(ax[0], h.x) + s(ax[1], h.y) + s(ax[2], h.z)
}

fn pair_mut<T>(s: &mut [T], i: usize, j: usize) -> (&mut T, &mut T) {
    assert!(i != j);
    if i < j {
        let (l, r) = s.split_at_mut(j);
        (&mut l[i], &mut r[0])
    } else {
        let (l, r) = s.split_at_mut(i);
        (&mut r[0], &mut l[j])
    }
}

pub struct RayHit {
    pub id: u32,
    pub dist: f32,
    pub point: Vec3,
    pub normal: Vec3,
}

/// Slab test in each box's local frame. `dir` must be normalized.
pub fn raycast(ents: &[Option<Entity>], o: Vec3, dir: Vec3, max: f32, ignore: Option<u32>) -> Option<RayHit> {
    let mut best = None;
    for i in 0..ents.len() {
        ray_test(ents, i, o, dir, max, ignore, &mut best);
    }
    best
}

/// The same ray, testing only what's near it: the statics in the grid cells
/// it crosses (nearest first, stopping past the nearest hit), big statics,
/// the bodies that were moving at the last step, slots added since, and
/// `touched` (statics moved since). Before the first step, or with too much
/// changed, it tests everything.
pub fn raycast_near(
    ents: &[Option<Entity>],
    broad: &Broad,
    touched: &[u32],
    o: Vec3,
    dir: Vec3,
    max: f32,
    ignore: Option<u32>,
) -> Option<RayHit> {
    let since = broad.len.min(ents.len());
    if broad.len == 0 || touched.len() > 256 || ents.len() - since > 256 {
        return raycast(ents, o, dir, max, ignore);
    }
    let mut best = None;
    for &i in broad.big.iter().chain(&broad.movers) {
        ray_test(ents, i, o, dir, max, ignore, &mut best);
    }
    for i in since..ents.len() {
        ray_test(ents, i, o, dir, max, ignore, &mut best);
    }
    for &i in touched {
        ray_test(ents, i as usize, o, dir, max, ignore, &mut best);
    }
    // Walk the cells under the ray in x, z (a 2D DDA).
    let c = Broad::CELL;
    let (mut cx, mut cz) = ((o.x / c).floor() as i32, (o.z / c).floor() as i32);
    let (sx, sz) = (if dir.x > 0.0 { 1 } else { -1 }, if dir.z > 0.0 { 1 } else { -1 });
    let first = |p: f32, d: f32, cell: i32| {
        if d.abs() < 1e-9 { f32::INFINITY } else { ((cell + (d > 0.0) as i32) as f32 * c - p) / d }
    };
    let every = |d: f32| if d.abs() < 1e-9 { f32::INFINITY } else { c / d.abs() };
    let (mut tx, mut tz, dtx, dtz) = (first(o.x, dir.x, cx), first(o.z, dir.z, cz), every(dir.x), every(dir.z));
    loop {
        if let Some(v) = broad.cells.get(&(cx, cz)) {
            for &i in v {
                ray_test(ents, i, o, dir, max, ignore, &mut best);
            }
        }
        // A static hit is in a cell it covers: nothing in a cell entered
        // after the nearest hit can be nearer.
        let reach = best.as_ref().map_or(max, |h: &RayHit| h.dist);
        let t_next = tx.min(tz);
        if !t_next.is_finite() || t_next > reach {
            break;
        }
        if tx < tz {
            tx += dtx;
            cx += sx;
        } else {
            tz += dtz;
            cz += sz;
        }
    }
    best
}

fn ray_test(ents: &[Option<Entity>], i: usize, o: Vec3, dir: Vec3, max: f32, ignore: Option<u32>, best: &mut Option<RayHit>) {
    let Some(Some(e)) = ents.get(i) else { return };
    let Some(b) = &e.body else { return };
    if b.sensor || Some(i as u32) == ignore {
        return;
    }
    // Bounding-sphere reject before the exact test; rejects nearly everything.
    let oc = e.pos - o;
    let (r, t) = (b.half.len(), oc.dot(dir));
    let reach = best.as_ref().map_or(max, |h| h.dist);
    if t + r < 0.0 || t - r > reach || oc.dot(oc) - t * t > r * r {
        return;
    }
    let inv = e.rot.conj();
    let (lo, ld) = (inv.rotate(o - e.pos), inv.rotate(dir));
    let (mut t0, mut t1, mut axis_hit) = (0.0f32, max, usize::MAX);
    let mut ok = true;
    for ax in 0..3 {
        let (od, dd, hh) = (lo.get(ax), ld.get(ax), b.half.get(ax));
        if dd.abs() < 1e-8 {
            if od.abs() > hh {
                ok = false;
                break;
            }
            continue;
        }
        let (mut ta, mut tb) = ((-hh - od) / dd, (hh - od) / dd);
        if ta > tb {
            std::mem::swap(&mut ta, &mut tb);
        }
        if ta > t0 {
            t0 = ta;
            axis_hit = ax;
        }
        t1 = t1.min(tb);
        if t0 > t1 {
            ok = false;
            break;
        }
    }
    if !ok || axis_hit == usize::MAX || best.as_ref().is_some_and(|h| h.dist <= t0) {
        return; // miss, or ray starts inside the box
    }
    let mut n = Vec3::ZERO;
    n.set(axis_hit, -ld.get(axis_hit).signum());
    *best = Some(RayHit { id: i as u32, dist: t0, point: o + dir * t0, normal: e.rot.rotate(n) });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::Entity;

    fn ent(pos: Vec3, kind: Kind, half: Vec3) -> Option<Entity> {
        let mut e = Entity::new(pos);
        e.body = Some(Body::new(kind, half));
        Some(e)
    }

    fn ground() -> Option<Entity> {
        ent(v3(0., -0.5, 0.), Kind::Static, v3(50., 0.5, 50.))
    }

    fn run(w: &mut [Option<Entity>], seconds: f32) {
        let (mut warm, mut broad) = (WarmCache::new(), Broad::default());
        for _ in 0..(seconds * 60.0) as usize {
            step(w, 1.0 / 60.0, -20.0, &mut warm, &mut broad, None);
        }
    }

    fn get(w: &[Option<Entity>], i: usize) -> &Entity {
        w[i].as_ref().unwrap()
    }

    /// A plane rising `slope` meters per meter toward +x, 40 x 40 m, as a
    /// terrain whose entity is slot `id`.
    fn ramp_terrain(slope: f32, id: usize) -> Terrain {
        let (w, d, step) = (21, 21, 2.0);
        let mut hs = Vec::new();
        for _j in 0..d {
            for i in 0..w {
                hs.push(5.0 + (i as f32 * step - 20.0) * slope);
            }
        }
        let mut t = Terrain::new(-20.0, -20.0, step, w, d, hs);
        t.id = id;
        t
    }

    fn holder() -> Option<Entity> {
        ent(v3(0., -10_000., 0.), Kind::Static, Vec3::ZERO)
    }

    #[test]
    fn terrain_surface_is_the_drawn_triangles() {
        // Grid points exactly, planes in between, and nothing off the edge.
        let t = ramp_terrain(0.25, 0);
        let (h, n) = t.surface(3.0, -7.3).unwrap();
        assert!((h - (5.0 + 3.0 * 0.25)).abs() < 1e-4, "{h}");
        assert!((n - v3(-0.25, 1.0, 0.0).norm()).len() < 1e-4, "{n:?}");
        assert!(t.surface(-21.0, 0.0).is_none() && t.surface(0.0, 20.5).is_none());
        // A bump: the four triangles around one raised point.
        let mut b = Terrain::new(0.0, 0.0, 1.0, 3, 3, vec![0., 0., 0., 0., 2., 0., 0., 0., 0.]);
        b.id = 0;
        assert!((b.surface(1.0, 1.0).unwrap().0 - 2.0).abs() < 1e-5);
        assert!((b.surface(0.75, 0.75).unwrap().0 - 1.0).abs() < 1e-5, "lower triangle: halfway along both");
        assert!((b.surface(1.25, 1.25).unwrap().0 - 1.0).abs() < 1e-5);
    }

    #[test]
    fn roads_lay_their_own_smooth_surface_over_the_terrain() {
        // Lumpy ground on a 10 m grid, graded roughly to a road climbing 5%
        // along x in 10 m pieces, 6 m each side; a second road leaving its
        // middle at a slant, a little steeper.
        let (w, d, step) = (31, 21, 10.0);
        let main = |x: f32| 3.0 + x * 0.05;
        let hs = (0..w * d)
            .map(|k| main((k % w) as f32 * step) + ((k % w) as f32 * 1.3).sin() * 0.5 + ((k / w) as f32 * 0.7).cos() * 0.3)
            .collect();
        let mut roads: Vec<RoadSeg> = (0..20)
            .map(|k| {
                let (x0, x1) = (50.0 + k as f32 * 10.0, 60.0 + k as f32 * 10.0);
                RoadSeg { a: v3(x0, main(x0), 100.0), b: v3(x1, main(x1), 100.0), half: 6.0, carriage: 6.0, raised: [false; 2], road: 0 }
            })
            .collect();
        roads.push(RoadSeg {
            a: v3(150.0, main(150.0), 100.0),
            b: v3(200.0, main(150.0) + 4.0, 130.0),
            half: 6.0,
            carriage: 6.0,
            raised: [false; 2],
            road: 1,
        });
        let t = Terrain::new(0.0, 0.0, step, w, d, hs).with_roads(roads);
        for x in [61.0, 87.5, 113.3] {
            for z in [94.5, 100.0, 105.5] {
                let (h, n) = t.surface(x, z).unwrap();
                assert!((h - main(x)).abs() < 1e-3, "on the road at ({x}, {z}): {h} not {}", main(x));
                assert!((n - v3(-0.05, 1.0, 0.0).norm()).len() < 1e-3, "{n:?}");
            }
        }
        assert_eq!(t.surface(100.0, 109.0), t.grid(100.0, 109.0), "past the blend it's the grid again");
        for x in [60.0, 100.0, 140.0] {
            assert!(t.grid(x, 100.0).unwrap().0 <= main(x) - 0.149, "the grid under the road comes down to it at x {x}");
        }
        let h = t.surface(100.0, 107.0).unwrap().0;
        assert!(h > main(100.0).min(t.grid(100.0, 107.0).unwrap().0) - 1e-3 && h < main(100.0).max(t.grid(100.0, 107.0).unwrap().0) + 1e-3);
        // Walking a fine lattice around the fork, on the roads the surface
        // never steps: neighbours 10 cm apart differ by little more than the
        // steepest slope there allows, even where the two roads overlap.
        let on_road = |x: f32, z: f32| t.road(x, z).is_some_and(|r| r.0 >= 1.0);
        let mut worst: f32 = 0.0;
        for j in 0..400 {
            for i in 0..1200 {
                let (x, z) = (80.0 + i as f32 * 0.1, 90.0 + j as f32 * 0.1);
                let h = t.surface(x, z).unwrap().0;
                for (x2, z2) in [(x + 0.1, z), (x, z + 0.1)] {
                    if on_road(x, z) && on_road(x2, z2) {
                        worst = worst.max((t.surface(x2, z2).unwrap().0 - h).abs());
                    }
                }
            }
        }
        assert!(worst < 0.03, "a step of {worst} m in 10 cm");
    }

    #[test]
    fn pavements_stand_a_kerb_above_the_road() {
        // Flat ground at 1 m; a road along x at z = 100, 4 m of asphalt
        // each side and a pavement to 7 m on its side 0 (toward -z) only;
        // a side street running off it toward -z, no pavements.
        let mut t = Terrain::new(0.0, 0.0, 10.0, 31, 21, vec![1.0; 31 * 21]);
        t.kerb = 0.12;
        let main = RoadSeg { a: v3(20.0, 2.0, 100.0), b: v3(280.0, 2.0, 100.0), half: 7.0, carriage: 4.0, raised: [true, false], road: 0 };
        let side = RoadSeg { a: v3(150.0, 2.0, 100.0), b: v3(150.0, 2.0, 40.0), half: 4.0, carriage: 4.0, raised: [false; 2], road: 1 };
        let t = t.with_roads(vec![main, side]);
        let h = |x: f32, z: f32| t.surface(x, z).unwrap().0;
        assert!((h(100.0, 100.0) - 2.0).abs() < 1e-4 && (h(100.0, 103.5) - 2.0).abs() < 1e-4, "the asphalt is level");
        assert!((h(100.0, 95.0) - 2.12).abs() < 1e-4, "the pavement is a kerb up: {}", h(100.0, 95.0));
        assert!((h(100.0, 105.0) - 2.0).abs() < 1e-4, "no pavement on side 1: {}", h(100.0, 105.0));
        assert!((h(150.0, 95.0) - 2.0).abs() < 1e-3, "where the side street crosses it, no kerb: {}", h(150.0, 95.0));
    }

    #[test]
    fn rays_meet_the_terrain() {
        let t = ramp_terrain(0.25, 0);
        // Straight down from 30 m over x = 4: the ground is at 6 m.
        let (d, n) = t.ray(v3(4., 30., 0.), v3(0., -1., 0.), 100.).unwrap();
        assert!((d - 24.0).abs() < 0.01, "{d}");
        assert!(n.x < 0.0 && n.y > 0.9);
        // Level, toward the rising side from x = -10 at 6 m: meets it at x = 4.
        let (d, _) = t.ray(v3(-10., 6., 0.), v3(1., 0., 0.), 100.).unwrap();
        assert!((d - 14.0).abs() < 0.01, "{d}");
        // Away from it, or starting underground: nothing.
        assert!(t.ray(v3(-10., 6., 0.), v3(-1., 0., 0.), 100.).is_none());
        assert!(t.ray(v3(10., 0., 0.), v3(1., 0., 0.), 100.).is_none());
    }

    #[test]
    fn boxes_rest_on_gentle_slopes_and_slide_off_steep_ones() {
        for (slope, slides) in [(0.0, false), (0.2, false), (1.2, true)] {
            let mut w = vec![holder(), ent(v3(0., 12., 0.), Kind::Dynamic, v3(1., 0.5, 1.))];
            w[1].as_mut().unwrap().body.as_mut().unwrap().friction = 0.6;
            let t = ramp_terrain(slope, 0);
            let (mut warm, mut broad) = (WarmCache::new(), Broad::default());
            for _ in 0..240 {
                step(&mut w, 1.0 / 60.0, -20.0, &mut warm, &mut broad, Some(&t));
            }
            let e = get(&w, 1);
            let b = e.body.as_ref().unwrap();
            if slides {
                assert!(e.pos.x < -5.0 || b.vel.x < -2.0, "slope {slope}: still at x {} going {}", e.pos.x, b.vel.x);
            } else {
                assert!(e.pos.x.abs() < 1.5 && b.vel.len() < 0.05, "slope {slope}: drifted to {:?} at {:?}", e.pos, b.vel);
                let ground = t.surface(e.pos.x, e.pos.z).unwrap().0;
                // Resting on the surface, not sunk into it or floating.
                let most = ground + 0.5 / (1.0 + slope * slope).sqrt() + slope + 0.1;
                assert!(e.pos.y > ground && e.pos.y < most, "slope {slope}: y {} ground {ground}", e.pos.y);
                assert!(b.grounded, "slope {slope}: not grounded");
            }
        }
    }

    #[test]
    fn ray_through_the_grid_matches_testing_everything() {
        // Statics scattered over a few hundred meters, a moving box, and one
        // static spawned and one moved after the step: the grid walk finds
        // the same nearest hit as the brute-force test for rays every way.
        let mut w = vec![ground()];
        let mut seed = 7u32;
        let mut rnd = || {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            (seed >> 8) as f32 / (1u32 << 24) as f32
        };
        for _ in 0..400 {
            let p = v3(rnd() * 300. - 150., rnd() * 6., rnd() * 300. - 150.);
            let half = v3(0.5 + rnd() * 8., 0.5 + rnd() * 4., 0.5 + rnd() * 8.);
            let mut e = ent(p, Kind::Static, half);
            e.as_mut().unwrap().rot = Quat::axis_angle(Vec3::UP, rnd() * 6.);
            w.push(e);
        }
        w.push(ent(v3(3., 1., 3.), Kind::Dynamic, v3(1., 1., 1.)));
        let (mut warm, mut broad) = (WarmCache::new(), Broad::default());
        step(&mut w, 1.0 / 60.0, -20.0, &mut warm, &mut broad, None);
        w.push(ent(v3(-20., 1., 0.), Kind::Static, v3(1., 3., 1.)));
        w[5].as_mut().unwrap().pos = v3(0., 1., -30.);
        let touched = [5u32];
        let mut checked = 0;
        for k in 0..300 {
            let a = k as f32 * 0.37;
            let o = v3(rnd() * 200. - 100., 0.5 + rnd() * 5., rnd() * 200. - 100.);
            let dir = v3(a.cos(), (rnd() - 0.6) * 0.3, a.sin()).norm();
            let all = raycast(&w, o, dir, 250., None);
            let near = raycast_near(&w, &broad, &touched, o, dir, 250., None);
            assert_eq!(all.as_ref().map(|h| h.id), near.as_ref().map(|h| h.id), "ray {k}");
            checked += all.is_some() as usize;
        }
        assert!(checked > 200, "only {checked} rays hit anything");
    }

    #[test]
    fn broad_phase_notices_statics_moving() {
        // A crate resting on a platform falls when the platform is moved away,
        // and the grid is only rebuilt when a static actually changes.
        let platform = ent(v3(40., 3.0, 0.), Kind::Static, v3(2., 0.5, 2.));
        let mut w = vec![ground(), platform, ent(v3(40., 4.0, 0.), Kind::Dynamic, v3(0.5, 0.5, 0.5))];
        let (mut warm, mut broad) = (WarmCache::new(), Broad::default());
        for _ in 0..120 {
            step(&mut w, 1.0 / 60.0, -20.0, &mut warm, &mut broad, None);
        }
        assert!((get(&w, 2).pos.y - 4.0).abs() < 0.05, "crate rests on the platform");
        assert_eq!(broad.rebuilds, 1, "nothing static changed, so one build");
        w[1].as_mut().unwrap().pos.x = 80.0;
        for _ in 0..60 {
            step(&mut w, 1.0 / 60.0, -20.0, &mut warm, &mut broad, None);
        }
        assert_eq!(broad.rebuilds, 2, "moving the platform rebuilt the grid");
        assert!(get(&w, 2).pos.y < 1.0, "and the crate fell to the ground (y = {})", get(&w, 2).pos.y);
    }

    #[test]
    fn box_settles_on_ground() {
        let mut w = vec![ground(), ent(v3(0., 5., 0.), Kind::Dynamic, v3(0.5, 0.5, 0.5))];
        run(&mut w, 4.0);
        let e = get(&w, 1);
        assert!((e.pos.y - 0.5).abs() < 0.05, "y = {}", e.pos.y);
        assert!(e.body.as_ref().unwrap().grounded);
    }

    #[test]
    fn tilted_box_falls_flat() {
        let mut w = vec![ground(), ent(v3(0., 3., 0.), Kind::Dynamic, v3(1.0, 0.5, 0.5))];
        w[1].as_mut().unwrap().rot = Quat::euler(0.4, 0.0, 0.6);
        run(&mut w, 6.0);
        let e = get(&w, 1);
        // Resting on a face: one local axis is vertical, and it isn't spinning.
        let up = e.rot.axes().iter().map(|a| a.y.abs()).fold(0.0, f32::max);
        assert!(up > 0.99, "not flat: {:?}", e.rot.axes());
        assert!(e.body.as_ref().unwrap().ang_vel.len() < 0.05);
        assert!(e.pos.y < 1.05);
    }

    #[test]
    fn stack_is_stable() {
        let mut w = vec![ground()];
        for k in 0..5 {
            w.push(ent(v3(0., 0.5 + k as f32 * 1.0, 0.), Kind::Dynamic, v3(0.5, 0.5, 0.5)));
        }
        run(&mut w, 8.0);
        let top = get(&w, 5).pos;
        assert!(top.x.abs() < 0.1 && top.z.abs() < 0.1 && (top.y - 4.5).abs() < 0.1, "stack drifted: {top:?}");
    }

    #[test]
    fn box_slides_down_ramp() {
        let mut ramp = ent(v3(0., 1.0, 0.), Kind::Static, v3(2., 0.25, 6.)).unwrap();
        ramp.rot = Quat::euler(0.0, -0.35, 0.0); // rises toward +Z
        let mut w = vec![ground(), Some(ramp), ent(v3(0., 3.5, 2.5), Kind::Dynamic, v3(0.4, 0.4, 0.4))];
        w[2].as_mut().unwrap().body.as_mut().unwrap().friction = 0.0;
        run(&mut w, 3.0);
        assert!(get(&w, 2).pos.z < -2.0, "should slide down toward -Z: {:?}", get(&w, 2).pos);
    }

    #[test]
    fn off_center_hit_spins() {
        let mut w = vec![ent(v3(0., 0., 0.), Kind::Dynamic, v3(0.5, 0.5, 2.0)), ent(v3(-3., 0., 1.5), Kind::Dynamic, v3(0.5, 0.5, 0.5))];
        for e in w.iter_mut().flatten() {
            e.body.as_mut().unwrap().gravity = 0.0;
        }
        w[1].as_mut().unwrap().body.as_mut().unwrap().vel = v3(10., 0., 0.);
        run(&mut w, 0.5);
        assert!(get(&w, 0).body.as_ref().unwrap().ang_vel.y.abs() > 0.5, "a hit near the end should spin it");
    }

    #[test]
    fn steps_onto_curb() {
        let mk = |step_h| {
            let mut w = vec![
                ground(),
                ent(v3(5., 0.1, 0.), Kind::Static, v3(2., 0.1, 5.)),
                ent(v3(0., 0.9, 0.), Kind::Dynamic, v3(0.35, 0.9, 0.35)),
            ];
            let b = w[2].as_mut().unwrap().body.as_mut().unwrap();
            b.step = step_h;
            b.lock_rotation = true;
            b.set_mass(1.0);
            let (mut warm, mut broad) = (WarmCache::new(), Broad::default());
            for _ in 0..90 {
                w[2].as_mut().unwrap().body.as_mut().unwrap().vel.x = 4.0;
                step(&mut w, 1.0 / 60.0, -20.0, &mut warm, &mut broad, None);
            }
            get(&w, 2).pos
        };
        let p = mk(0.0);
        assert!(p.x < 3.0, "without step-up the curb blocks: x = {}", p.x);
        let p = mk(0.4);
        assert!(p.x > 4.0 && (p.y - 1.1).abs() < 0.06, "stepped up: {p:?}");
    }

    #[test]
    fn walkers_step_over_a_seam_between_tilted_slabs() {
        // Two 10 m deck pieces up a 6 % slope, the second 8 cm proud of the
        // first where they meet (pieces of a bridge at a bend). The step is
        // the slab's top there, not its bounding box's (its far corner).
        let rot = Quat::euler(0.0, -0.06, 0.0);
        let fwd = rot.rotate(v3(0., 0., 1.));
        let mut w =
            vec![ent(v3(0., 0., 0.), Kind::Static, v3(3., 0.5, 5.)), ent(fwd * 10.0 + v3(0., 0.08, 0.), Kind::Static, v3(3., 0.5, 5.))];
        for e in w.iter_mut() {
            e.as_mut().unwrap().rot = rot;
        }
        let start = v3(0., 0.0, -3.0);
        let top = start.y + 0.5 / rot.rotate(Vec3::UP).y + (start.z * fwd.y / fwd.z);
        w.push(ent(v3(0., top + 0.95, -3.0), Kind::Dynamic, v3(0.35, 0.9, 0.35)));
        let b = w[2].as_mut().unwrap().body.as_mut().unwrap();
        b.step = 0.45;
        b.lock_rotation = true;
        b.set_mass(70.0);
        b.friction = 0.0;
        let (mut warm, mut broad) = (WarmCache::new(), Broad::default());
        for _ in 0..600 {
            w[2].as_mut().unwrap().body.as_mut().unwrap().vel.z = 1.3;
            step(&mut w, 1.0 / 60.0, -20.0, &mut warm, &mut broad, None);
        }
        let p = get(&w, 2).pos;
        assert!(p.z > 8.0, "walked on over the seam: z = {}", p.z);
    }

    #[test]
    fn narrow_poles_do_not_step_up_vehicles() {
        let mut w = vec![
            ground(),
            // A narrow static pole (like a lamp post): center=(5.0, 5.0, 0.0), half = (0.15, 5.0, 0.15)
            ent(v3(5., 5.0, 0.), Kind::Static, v3(0.15, 5.0, 0.15)),
            // A heavy vehicle approaching the pole: center=(0.0, 1.6, 0.0), half = (1.3, 1.6, 6.1)
            ent(v3(0., 1.6, 0.), Kind::Dynamic, v3(1.3, 1.6, 6.1)),
        ];
        let b = w[2].as_mut().unwrap().body.as_mut().unwrap();
        b.step = 0.55;
        b.lock_rotation = true;
        b.set_mass(11500.0);
        let (mut warm, mut broad) = (WarmCache::new(), Broad::default());
        for _ in 0..90 {
            w[2].as_mut().unwrap().body.as_mut().unwrap().vel.x = 4.0;
            step(&mut w, 1.0 / 60.0, -20.0, &mut warm, &mut broad, None);
        }
        let p = get(&w, 2).pos;
        assert!(p.x < 4.0, "narrow pole colliders must block horizontal travel, not act as ramps: x = {}", p.x);
        assert!(p.y < 2.5, "narrow pole colliders must not launch vehicle vertically (y = {})", p.y);
    }

    #[test]
    fn ray_hits_nearest_and_respects_rotation() {
        let mut w = vec![ent(v3(10., 0., 0.), Kind::Static, Vec3::ONE), ent(v3(5., 0., 0.), Kind::Static, Vec3::ONE)];
        let h = raycast(&w, Vec3::ZERO, v3(1., 0., 0.), 100.0, None).unwrap();
        assert_eq!(h.id, 1);
        assert!((h.dist - 4.0).abs() < 1e-5);
        assert!((h.normal - v3(-1., 0., 0.)).len() < 1e-5);
        assert!(raycast(&w, Vec3::ZERO, v3(0., 1., 0.), 100.0, None).is_none());
        // Rotated 45 degrees, the near corner is sqrt(2) from the center.
        w[1].as_mut().unwrap().rot = Quat::axis_angle(Vec3::UP, std::f32::consts::FRAC_PI_4);
        let h = raycast(&w, Vec3::ZERO, v3(1., 0., 0.), 100.0, None).unwrap();
        assert!((h.dist - (5.0 - 2f32.sqrt())).abs() < 1e-4, "{}", h.dist);
    }
}
