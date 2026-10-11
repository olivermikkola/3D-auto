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
        q.rotate(q.conj().rotate(v).mul(self.inv_inertia))
    }
}

/// World-space half extents of an oriented box's bounding box.
pub fn extents(half: Vec3, rot: Quat) -> Vec3 {
    let [a, b, c] = rot.axes();
    let (a, b, c) = (a.abs() * half.x, b.abs() * half.y, c.abs() * half.z);
    a + b + c
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

pub fn step(ents: &mut [Option<Entity>], dt: f32, gravity: f32, warm: &mut WarmCache) -> Vec<Contact> {
    // 1. Forces.
    let mut dynamic = Vec::new();
    let mut solid = Vec::new();
    for (i, e) in ents.iter_mut().enumerate() {
        let Some(e) = e else { continue };
        let Some(b) = &mut e.body else { continue };
        if b.kind == Kind::Dynamic {
            b.vel.y += gravity * b.gravity * dt;
            b.ang_vel = b.ang_vel * (1.0 / (1.0 + 0.3 * dt));
            if b.lock_rotation {
                b.ang_vel = Vec3::ZERO;
            }
            b.grounded = false;
            dynamic.push(i);
        }
        solid.push(i);
    }

    // 2. Narrow phase over a flat AABB cache.
    let aabb = |e: &Entity| (e.pos, extents(e.body.as_ref().unwrap().half, e.rot));
    let boxes: Vec<(Vec3, Vec3)> = solid.iter().map(|&i| aabb(ents[i].as_ref().unwrap())).collect();
    let slot: HashMap<usize, usize> = solid.iter().enumerate().map(|(s, &i)| (i, s)).collect();
    let mut manifolds = Vec::new();
    let mut touching = Vec::new();
    let mut seen = HashSet::new();
    for &i in &dynamic {
        let si = slot[&i];
        for (sj, &j) in solid.iter().enumerate() {
            if i == j {
                continue;
            }
            let ((ca, ha), (cb, hb)) = (boxes[si], boxes[sj]);
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
            if !b_dynamic && ba.step > 0.0 && n.y.abs() < 0.5 {
                let rise = (cb.y + hb.y) - (ca.y - ha.y);
                if rise > 0.0 && rise <= ba.step && ca.y > cb.y + hb.y {
                    let e = ents[i].as_mut().unwrap();
                    e.pos.y += rise + 0.01;
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
    let mut best: Option<RayHit> = None;
    for (i, e) in ents.iter().enumerate() {
        let Some(e) = e else { continue };
        let Some(b) = &e.body else { continue };
        if b.sensor || Some(i as u32) == ignore {
            continue;
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
            continue; // miss, or ray starts inside the box
        }
        let mut n = Vec3::ZERO;
        n.set(axis_hit, -ld.get(axis_hit).signum());
        best = Some(RayHit { id: i as u32, dist: t0, point: o + dir * t0, normal: e.rot.rotate(n) });
    }
    best
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
        let mut warm = WarmCache::new();
        for _ in 0..(seconds * 60.0) as usize {
            step(w, 1.0 / 60.0, -20.0, &mut warm);
        }
    }

    fn get(w: &[Option<Entity>], i: usize) -> &Entity {
        w[i].as_ref().unwrap()
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
            let mut warm = WarmCache::new();
            for _ in 0..90 {
                w[2].as_mut().unwrap().body.as_mut().unwrap().vel.x = 4.0;
                step(&mut w, 1.0 / 60.0, -20.0, &mut warm);
            }
            get(&w, 2).pos
        };
        let p = mk(0.0);
        assert!(p.x < 3.0, "without step-up the curb blocks: x = {}", p.x);
        let p = mk(0.4);
        assert!(p.x > 4.0 && (p.y - 1.1).abs() < 0.06, "stepped up: {p:?}");
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
