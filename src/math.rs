//! Just enough linear algebra. Column-major 4x4 matrices, right-handed, Y up.

use std::ops::{Add, AddAssign, Mul, Neg, Sub, SubAssign};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

pub const fn v3(x: f32, y: f32, z: f32) -> Vec3 {
    Vec3 { x, y, z }
}

impl Vec3 {
    pub const ZERO: Vec3 = v3(0.0, 0.0, 0.0);
    pub const ONE: Vec3 = v3(1.0, 1.0, 1.0);
    pub const UP: Vec3 = v3(0.0, 1.0, 0.0);

    pub fn dot(self, o: Vec3) -> f32 {
        self.x * o.x + self.y * o.y + self.z * o.z
    }
    pub fn cross(self, o: Vec3) -> Vec3 {
        v3(self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x)
    }
    pub fn len(self) -> f32 {
        self.dot(self).sqrt()
    }
    pub fn norm(self) -> Vec3 {
        let l = self.len();
        if l > 1e-8 { self * (1.0 / l) } else { Vec3::ZERO }
    }
    pub fn mul(self, o: Vec3) -> Vec3 {
        v3(self.x * o.x, self.y * o.y, self.z * o.z)
    }
    pub fn abs(self) -> Vec3 {
        v3(self.x.abs(), self.y.abs(), self.z.abs())
    }
    pub fn get(self, axis: usize) -> f32 {
        [self.x, self.y, self.z][axis]
    }
    pub fn set(&mut self, axis: usize, v: f32) {
        match axis {
            0 => self.x = v,
            1 => self.y = v,
            _ => self.z = v,
        }
    }
    /// Rotate around +Y by `yaw` radians. Forward at yaw is (sin yaw, 0, cos yaw).
    pub fn rot_y(self, yaw: f32) -> Vec3 {
        let (s, c) = yaw.sin_cos();
        v3(c * self.x + s * self.z, self.y, -s * self.x + c * self.z)
    }
}

impl Add for Vec3 {
    type Output = Vec3;
    fn add(self, o: Vec3) -> Vec3 {
        v3(self.x + o.x, self.y + o.y, self.z + o.z)
    }
}
impl Sub for Vec3 {
    type Output = Vec3;
    fn sub(self, o: Vec3) -> Vec3 {
        v3(self.x - o.x, self.y - o.y, self.z - o.z)
    }
}
impl Mul<f32> for Vec3 {
    type Output = Vec3;
    fn mul(self, s: f32) -> Vec3 {
        v3(self.x * s, self.y * s, self.z * s)
    }
}
impl Neg for Vec3 {
    type Output = Vec3;
    fn neg(self) -> Vec3 {
        v3(-self.x, -self.y, -self.z)
    }
}
impl AddAssign for Vec3 {
    fn add_assign(&mut self, o: Vec3) {
        *self = *self + o;
    }
}
impl SubAssign for Vec3 {
    fn sub_assign(&mut self, o: Vec3) {
        *self = *self - o;
    }
}

/// Unit quaternion for orientation. (x, y, z) is the vector part.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Quat {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub w: f32,
}

impl Quat {
    pub const IDENTITY: Quat = Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

    pub fn axis_angle(axis: Vec3, angle: f32) -> Quat {
        let a = axis.norm();
        let (s, c) = (angle * 0.5).sin_cos();
        Quat { x: a.x * s, y: a.y * s, z: a.z * s, w: c }
    }

    /// Yaw about +Y, then pitch about local +X, then roll about local +Z.
    pub fn euler(yaw: f32, pitch: f32, roll: f32) -> Quat {
        Quat::axis_angle(Vec3::UP, yaw) * Quat::axis_angle(v3(1., 0., 0.), pitch) * Quat::axis_angle(v3(0., 0., 1.), roll)
    }

    pub fn conj(self) -> Quat {
        Quat { x: -self.x, y: -self.y, z: -self.z, w: self.w }
    }

    pub fn norm(self) -> Quat {
        let l = (self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w).sqrt();
        if l < 1e-8 {
            return Quat::IDENTITY;
        }
        Quat { x: self.x / l, y: self.y / l, z: self.z / l, w: self.w / l }
    }

    pub fn rotate(self, v: Vec3) -> Vec3 {
        let u = v3(self.x, self.y, self.z);
        let t = u.cross(v) * 2.0;
        v + t * self.w + u.cross(t)
    }

    /// Local axes in world space: (right-handed x, y, z).
    /// (The columns of the rotation matrix, computed directly.)
    pub fn axes(self) -> [Vec3; 3] {
        let Quat { x, y, z, w } = self;
        let (xx, yy, zz) = (x * x, y * y, z * z);
        let (xy, xz, yz, wx, wy, wz) = (x * y, x * z, y * z, w * x, w * y, w * z);
        [
            v3(1. - 2. * (yy + zz), 2. * (xy + wz), 2. * (xz - wy)),
            v3(2. * (xy - wz), 1. - 2. * (xx + zz), 2. * (yz + wx)),
            v3(2. * (xz + wy), 2. * (yz - wx), 1. - 2. * (xx + yy)),
        ]
    }

    /// Advance by angular velocity `w` (world space, rad/s) over `dt`.
    pub fn integrate(self, w: Vec3, dt: f32) -> Quat {
        let dq = Quat { x: w.x, y: w.y, z: w.z, w: 0.0 } * self;
        let h = 0.5 * dt;
        Quat { x: self.x + dq.x * h, y: self.y + dq.y * h, z: self.z + dq.z * h, w: self.w + dq.w * h }.norm()
    }

    /// Heading: the angle of the local +Z axis projected onto the ground.
    pub fn yaw(self) -> f32 {
        let f = self.rotate(v3(0., 0., 1.));
        f.x.atan2(f.z)
    }
}

impl Mul for Quat {
    type Output = Quat;
    fn mul(self, o: Quat) -> Quat {
        Quat {
            w: self.w * o.w - self.x * o.x - self.y * o.y - self.z * o.z,
            x: self.w * o.x + self.x * o.w + self.y * o.z - self.z * o.y,
            y: self.w * o.y - self.x * o.z + self.y * o.w + self.z * o.x,
            z: self.w * o.z + self.x * o.y - self.y * o.x + self.z * o.w,
        }
    }
}

/// Column-major: m[col*4 + row].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Mat4(pub [f32; 16]);

impl Mat4 {
    /// translate * rotY(yaw) * scale
    #[cfg(test)]
    pub fn trs(t: Vec3, yaw: f32, s: Vec3) -> Mat4 {
        let (sn, c) = yaw.sin_cos();
        Mat4([c * s.x, 0., -sn * s.x, 0., 0., s.y, 0., 0., sn * s.z, 0., c * s.z, 0., t.x, t.y, t.z, 1.])
    }

    /// translate * rotate(q) * scale
    pub fn trs_q(t: Vec3, q: Quat, s: Vec3) -> Mat4 {
        let [ax, ay, az] = q.axes();
        let (ax, ay, az) = (ax * s.x, ay * s.y, az * s.z);
        Mat4([ax.x, ax.y, ax.z, 0., ay.x, ay.y, ay.z, 0., az.x, az.y, az.z, 0., t.x, t.y, t.z, 1.])
    }

    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) -> Mat4 {
        let f = 1.0 / (fovy * 0.5).tan();
        let nf = 1.0 / (near - far);
        Mat4([f / aspect, 0., 0., 0., 0., f, 0., 0., 0., 0., (far + near) * nf, -1., 0., 0., 2. * far * near * nf, 0.])
    }

    pub fn look_at(eye: Vec3, target: Vec3, up: Vec3) -> Mat4 {
        let f = (target - eye).norm();
        let mut s = f.cross(up).norm();
        if s.len() < 1e-6 {
            s = v3(1., 0., 0.);
        }
        let u = s.cross(f);
        Mat4([s.x, u.x, -f.x, 0., s.y, u.y, -f.y, 0., s.z, u.z, -f.z, 0., -s.dot(eye), -u.dot(eye), f.dot(eye), 1.])
    }
}

impl Mul for Mat4 {
    type Output = Mat4;
    fn mul(self, o: Mat4) -> Mat4 {
        let (a, b) = (&self.0, &o.0);
        let mut r = [0.0; 16];
        for c in 0..4 {
            for row in 0..4 {
                r[c * 4 + row] = (0..4).map(|k| a[k * 4 + row] * b[c * 4 + k]).sum();
            }
        }
        Mat4(r)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rot_y_matches_matrix() {
        let p = v3(1.0, 2.0, 3.0);
        let yaw = 0.7;
        let m = Mat4::trs(Vec3::ZERO, yaw, Vec3::ONE).0;
        let mx = v3(m[0] * p.x + m[4] * p.y + m[8] * p.z, m[1] * p.x + m[5] * p.y + m[9] * p.z, m[2] * p.x + m[6] * p.y + m[10] * p.z);
        assert!((mx - p.rot_y(yaw)).len() < 1e-5);
        // yaw 90deg turns +Z forward into +X
        assert!((v3(0., 0., 1.).rot_y(std::f32::consts::FRAC_PI_2) - v3(1., 0., 0.)).len() < 1e-5);
    }

    #[test]
    fn quat_matches_yaw_conventions() {
        let yaw = 0.7;
        let q = Quat::axis_angle(Vec3::UP, yaw);
        let p = v3(1.0, 2.0, 3.0);
        assert!((q.rotate(p) - p.rot_y(yaw)).len() < 1e-5);
        assert!((q.yaw() - yaw).abs() < 1e-5);
        assert_eq!(
            Mat4::trs_q(v3(1., 2., 3.), q, v3(2., 3., 4.)).0.map(|x| (x * 1e4).round()),
            Mat4::trs(v3(1., 2., 3.), yaw, v3(2., 3., 4.)).0.map(|x| (x * 1e4).round())
        );
        // Pitching up tilts the nose (+Z) upward, and keeps the heading.
        let r = Quat::euler(yaw, -0.3, 0.0);
        assert!(r.rotate(v3(0., 0., 1.)).y > 0.2);
        assert!((r.yaw() - yaw).abs() < 1e-5);
        // The direct matrix form agrees with rotating the basis vectors.
        let q = Quat::euler(0.3, -0.7, 1.1);
        let ax = q.axes();
        for (a, b) in ax.iter().zip([v3(1., 0., 0.), Vec3::UP, v3(0., 0., 1.)]) {
            assert!((*a - q.rotate(b)).len() < 1e-5);
        }
        // Spinning at 1 rad/s about Y for 1s turns the heading by 1 rad.
        let mut q = Quat::IDENTITY;
        for _ in 0..1000 {
            q = q.integrate(Vec3::UP, 0.001);
        }
        assert!((q.yaw() - 1.0).abs() < 1e-3);
    }
}
