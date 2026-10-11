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

/// Column-major: m[col*4 + row].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Mat4(pub [f32; 16]);

impl Mat4 {
    /// translate * rotY(yaw) * scale
    pub fn trs(t: Vec3, yaw: f32, s: Vec3) -> Mat4 {
        let (sn, c) = yaw.sin_cos();
        Mat4([c * s.x, 0., -sn * s.x, 0., 0., s.y, 0., 0., sn * s.z, 0., c * s.z, 0., t.x, t.y, t.z, 1.])
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
}
