//! Axis-aligned box physics. No rotation dynamics: a body's collision box is
//! its half-extents rotated by the entity's yaw, then re-boxed. Brute-force
//! pair tests, minimum-axis push-out, impulse response with Coulomb friction.
//! Good enough for cars, crates, and people; trivial to reason about.

use crate::engine::Entity;
use crate::math::{Vec3, v3};
use std::collections::HashSet;

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
    pub inv_mass: f32,
    pub restitution: f32,
    pub friction: f32,
    pub gravity: f32,
    pub sensor: bool,
    pub grounded: bool,
    /// Ledges up to this height are stepped onto instead of blocking.
    pub step: f32,
}

impl Body {
    pub fn new(kind: Kind, half: Vec3) -> Body {
        Body {
            kind,
            half,
            vel: Vec3::ZERO,
            inv_mass: if kind == Kind::Dynamic { 1.0 } else { 0.0 },
            restitution: 0.0,
            friction: 0.6,
            gravity: 1.0,
            sensor: false,
            grounded: false,
            step: 0.0,
        }
    }
}

/// World-space half extents of an entity's yawed box.
pub fn extents(half: Vec3, yaw: f32) -> Vec3 {
    let (s, c) = yaw.sin_cos();
    let (s, c) = (s.abs(), c.abs());
    v3(c * half.x + s * half.z, half.y, s * half.x + c * half.z)
}

pub struct Contact {
    pub a: u32,
    pub b: u32,
}

pub fn step(ents: &mut [Option<Entity>], dt: f32, gravity: f32) -> Vec<Contact> {
    let mut dynamic = Vec::new();
    let mut solid = Vec::new();
    for (i, e) in ents.iter_mut().enumerate() {
        let Some(e) = e else { continue };
        let Some(b) = &mut e.body else { continue };
        match b.kind {
            Kind::Dynamic => {
                b.vel.y += gravity * b.gravity * dt;
                e.pos += b.vel * dt;
                b.grounded = false;
                dynamic.push(i);
            }
            Kind::Kinematic => e.pos += b.vel * dt,
            Kind::Static => {}
        }
        solid.push(i);
    }

    // Flat AABB cache: most pairs are rejected without touching the entities.
    let aabb = |e: &Entity| (e.pos, extents(e.body.as_ref().unwrap().half, e.yaw));
    let mut boxes: Vec<(Vec3, Vec3)> = solid.iter().map(|&i| aabb(ents[i].as_ref().unwrap())).collect();
    let slot_of: std::collections::HashMap<usize, usize> = solid.iter().enumerate().map(|(s, &i)| (i, s)).collect();
    let dyn_slots: Vec<usize> = dynamic.iter().map(|i| slot_of[i]).collect();

    let mut seen = HashSet::new();
    let mut contacts = Vec::new();
    for _iter in 0..3 {
        for &si in &dyn_slots {
            for sj in 0..solid.len() {
                let (i, j) = (solid[si], solid[sj]);
                if i == j {
                    continue;
                }
                let ((ca, ha), (cb, hb)) = (boxes[si], boxes[sj]);
                let (d, h) = ((ca - cb).abs(), ha + hb);
                if d.x >= h.x || d.y >= h.y || d.z >= h.z {
                    continue;
                }
                let both_dynamic = ents[j].as_ref().and_then(|e| e.body.as_ref()).is_some_and(|b| b.kind == Kind::Dynamic);
                if both_dynamic && j < i {
                    continue; // pair handled from the other side
                }
                if let Some(hit) = resolve(ents, i, j) {
                    boxes[si] = aabb(ents[i].as_ref().unwrap());
                    boxes[sj] = aabb(ents[j].as_ref().unwrap());
                    let key = (i.min(j), i.max(j));
                    if hit && seen.insert(key) {
                        contacts.push(Contact { a: key.0 as u32, b: key.1 as u32 });
                    }
                }
            }
        }
    }
    contacts
}

/// Resolve one pair. Returns Some(true) if they touch.
fn resolve(ents: &mut [Option<Entity>], i: usize, j: usize) -> Option<bool> {
    let (ea, eb) = pair_mut(ents, i, j);
    let (ea, eb) = (ea.as_mut()?, eb.as_mut()?);
    let ha = extents(ea.body.as_ref()?.half, ea.yaw);
    let hb = extents(eb.body.as_ref()?.half, eb.yaw);
    let d = ea.pos - eb.pos;
    let pen = (ha + hb) - d.abs();
    if pen.x <= 0.0 || pen.y <= 0.0 || pen.z <= 0.0 {
        return Some(false);
    }
    let (a, b) = (ea.body.as_mut()?, eb.body.as_mut()?);
    if a.sensor || b.sensor {
        return Some(true);
    }
    // Minimum penetration axis, normal points from b to a.
    let mut axis = if pen.x < pen.y && pen.x < pen.z {
        0
    } else if pen.y < pen.z {
        1
    } else {
        2
    };
    // Step-up: a low ledge under a's feet lifts it rather than walling it.
    if axis != 1 && b.kind != Kind::Dynamic && d.y > 0.0 && pen.y <= a.step {
        axis = 1;
    }
    let mut n = Vec3::ZERO;
    n.set(axis, if d.get(axis) >= 0.0 { 1.0 } else { -1.0 });
    let depth = pen.get(axis);

    let (ima, imb) = (a.inv_mass, if b.kind == Kind::Dynamic { b.inv_mass } else { 0.0 });
    let total = ima + imb;
    if total <= 0.0 {
        return Some(true);
    }
    ea.pos += n * (depth * ima / total);
    eb.pos -= n * (depth * imb / total);

    let rel = a.vel - b.vel;
    let vn = rel.dot(n);
    if vn < 0.0 {
        let e = a.restitution.max(b.restitution);
        let jn = -(1.0 + e) * vn / total;
        // Coulomb friction on the tangential component.
        let vt = rel - n * vn;
        let vt_len = vt.len();
        let mu = (a.friction * b.friction).sqrt();
        let jt = (vt_len / total).min(mu * jn);
        let tdir = if vt_len > 1e-6 { vt * (1.0 / vt_len) } else { Vec3::ZERO };
        let imp = n * jn - tdir * jt;
        a.vel += imp * ima;
        b.vel -= imp * imb;
    }
    if n.y > 0.7 {
        a.grounded = true;
    } else if n.y < -0.7 {
        b.grounded = true;
    }
    Some(true)
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

/// Slab test against every non-sensor body. `dir` must be normalized.
pub fn raycast(ents: &[Option<Entity>], o: Vec3, dir: Vec3, max: f32, ignore: Option<u32>) -> Option<RayHit> {
    let mut best: Option<RayHit> = None;
    for (i, e) in ents.iter().enumerate() {
        let Some(e) = e else { continue };
        let Some(b) = &e.body else { continue };
        if b.sensor || Some(i as u32) == ignore {
            continue;
        }
        let h = extents(b.half, e.yaw);
        let (mut t0, mut t1, mut axis_hit) = (0.0f32, max, usize::MAX);
        let mut ok = true;
        for ax in 0..3 {
            let (od, dd) = (o.get(ax) - e.pos.get(ax), dir.get(ax));
            let hh = h.get(ax);
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
        n.set(axis_hit, -dir.get(axis_hit).signum());
        best = Some(RayHit { id: i as u32, dist: t0, point: o + dir * t0, normal: n });
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

    #[test]
    fn box_settles_on_ground() {
        let mut w = vec![ent(v3(0., -0.5, 0.), Kind::Static, v3(50., 0.5, 50.)), ent(v3(0., 5., 0.), Kind::Dynamic, v3(0.5, 0.5, 0.5))];
        for _ in 0..240 {
            step(&mut w, 1.0 / 60.0, -20.0);
        }
        let e = w[1].as_ref().unwrap();
        assert!((e.pos.y - 0.5).abs() < 0.05, "y = {}", e.pos.y);
        assert!(e.body.as_ref().unwrap().grounded);
    }

    #[test]
    fn dynamic_boxes_push_apart() {
        let mut w = vec![ent(v3(0., 0., 0.), Kind::Dynamic, Vec3::ONE), ent(v3(1.5, 0., 0.), Kind::Dynamic, Vec3::ONE)];
        for e in w.iter_mut().flatten() {
            e.body.as_mut().unwrap().gravity = 0.0;
        }
        let c = step(&mut w, 1.0 / 60.0, -20.0);
        assert_eq!(c.len(), 1);
        let (a, b) = (w[0].as_ref().unwrap().pos, w[1].as_ref().unwrap().pos);
        assert!(b.x - a.x >= 2.0 - 1e-4);
    }

    #[test]
    fn steps_onto_curb() {
        let mut w = vec![
            ent(v3(0., -0.5, 0.), Kind::Static, v3(50., 0.5, 50.)),
            ent(v3(5., 0.1, 0.), Kind::Static, v3(2., 0.1, 5.)), // 20cm curb
            ent(v3(0., 0.9, 0.), Kind::Dynamic, v3(0.35, 0.9, 0.35)),
        ];
        for _ in 0..90 {
            w[2].as_mut().unwrap().body.as_mut().unwrap().vel.x = 4.0;
            step(&mut w, 1.0 / 60.0, -20.0);
        }
        let p = w[2].as_ref().unwrap().pos;
        assert!(p.x < 3.0, "without step-up the curb blocks: x = {}", p.x);
        w[2] = ent(v3(0., 0.9, 0.), Kind::Dynamic, v3(0.35, 0.9, 0.35));
        w[2].as_mut().unwrap().body.as_mut().unwrap().step = 0.4;
        for _ in 0..90 {
            w[2].as_mut().unwrap().body.as_mut().unwrap().vel.x = 4.0;
            step(&mut w, 1.0 / 60.0, -20.0);
        }
        let p = w[2].as_ref().unwrap().pos;
        assert!(p.x > 4.0 && (p.y - 1.1).abs() < 0.05, "stepped up: {p:?}");
    }

    #[test]
    fn ray_hits_nearest() {
        let w = vec![ent(v3(10., 0., 0.), Kind::Static, Vec3::ONE), ent(v3(5., 0., 0.), Kind::Static, Vec3::ONE)];
        let h = raycast(&w, Vec3::ZERO, v3(1., 0., 0.), 100.0, None).unwrap();
        assert_eq!(h.id, 1);
        assert!((h.dist - 4.0).abs() < 1e-5);
        assert_eq!(h.normal, v3(-1., 0., 0.));
        assert!(raycast(&w, Vec3::ZERO, v3(0., 1., 0.), 100.0, None).is_none());
    }
}
