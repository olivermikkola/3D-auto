//! The engine's whole state. Lua owns the game; this owns the facts.

use crate::font;
use crate::math::{Vec3, v3};
use crate::mesh::{self, Mesh};
use crate::physics::{self, Body, Contact};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

static EPOCH: AtomicU64 = AtomicU64::new(1);

pub const TICK_HZ: f64 = 60.0;

#[derive(Clone, Debug)]
pub struct Entity {
    pub pos: Vec3,
    pub yaw: f32,
    pub scale: Vec3,
    pub mesh: Option<usize>,
    pub color: [f32; 4],
    pub body: Option<Body>,
    pub tag: String,
    pub visible: bool,
}

impl Entity {
    pub fn new(pos: Vec3) -> Entity {
        Entity { pos, yaw: 0.0, scale: Vec3::ONE, mesh: None, color: [1.0; 4], body: None, tag: String::new(), visible: true }
    }
}

pub struct Camera {
    pub eye: Vec3,
    pub target: Vec3,
    pub fov: f32,
}

pub struct Env {
    pub sky: [f32; 3],
    pub fog_start: f32,
    pub fog_end: f32,
    pub sun: Vec3,
    pub gravity: f32,
}

pub struct Engine {
    pub root: PathBuf,
    pub ents: Vec<Option<Entity>>,
    pub live: usize,
    pub meshes: Vec<Mesh>,
    pub mesh_ids: HashMap<String, usize>,
    /// Bumped when a mesh is replaced so the renderer re-uploads it.
    pub mesh_revs: Vec<u32>,
    /// Unique per Engine instance; a new epoch tells the renderer to drop GPU state.
    pub epoch: u64,
    pub camera: Camera,
    pub env: Env,
    pub keys: HashSet<String>,
    pub mouse_delta: (f32, f32),
    pub mouse_grab: bool,
    pub screen: (f32, f32),
    /// HUD triangles for this frame: x, y, r, g, b, a per vertex, in pixels.
    pub hud: Vec<f32>,
    pub time: f64,
    pub tick: u64,
    pub quit: bool,
    pub error: Option<String>,
}

impl Engine {
    pub fn new(root: PathBuf) -> Engine {
        let mut e = Engine {
            root,
            ents: Vec::new(),
            live: 0,
            meshes: Vec::new(),
            mesh_ids: HashMap::new(),
            mesh_revs: Vec::new(),
            epoch: EPOCH.fetch_add(1, Ordering::Relaxed),
            camera: Camera { eye: v3(0., 10., -20.), target: Vec3::ZERO, fov: 70f32.to_radians() },
            env: Env { sky: [0.55, 0.7, 0.85], fog_start: 80.0, fog_end: 260.0, sun: v3(0.4, 0.8, 0.3).norm(), gravity: -20.0 },
            keys: HashSet::new(),
            mouse_delta: (0.0, 0.0),
            mouse_grab: false,
            screen: (1280.0, 720.0),
            hud: Vec::new(),
            time: 0.0,
            tick: 0,
            quit: false,
            error: None,
        };
        for (name, m) in mesh::builtins() {
            e.add_mesh(name, m);
        }
        e
    }

    /// Register (or replace) a named mesh. Returns its id.
    pub fn add_mesh(&mut self, name: &str, m: Mesh) -> usize {
        if let Some(&id) = self.mesh_ids.get(name) {
            self.meshes[id] = m;
            self.mesh_revs[id] += 1;
            return id;
        }
        self.meshes.push(m);
        self.mesh_revs.push(0);
        self.mesh_ids.insert(name.to_string(), self.meshes.len() - 1);
        self.meshes.len() - 1
    }

    pub fn spawn(&mut self, e: Entity) -> u32 {
        self.ents.push(Some(e));
        self.live += 1;
        (self.ents.len() - 1) as u32
    }

    pub fn despawn(&mut self, id: u32) {
        if let Some(slot) = self.ents.get_mut(id as usize)
            && slot.take().is_some()
        {
            self.live -= 1;
        }
    }

    pub fn get(&self, id: u32) -> Option<&Entity> {
        self.ents.get(id as usize)?.as_ref()
    }

    pub fn get_mut(&mut self, id: u32) -> Option<&mut Entity> {
        self.ents.get_mut(id as usize)?.as_mut()
    }

    pub fn step(&mut self, dt: f32) -> Vec<Contact> {
        self.tick += 1;
        self.time += dt as f64;
        physics::step(&mut self.ents, dt, self.env.gravity)
    }

    pub fn hud_rect(&mut self, x: f32, y: f32, w: f32, h: f32, c: [f32; 4]) {
        for (px, py) in [(x, y), (x + w, y), (x + w, y + h), (x, y), (x + w, y + h), (x, y + h)] {
            self.hud.extend_from_slice(&[px, py, c[0], c[1], c[2], c[3]]);
        }
    }

    /// Bitmap text. `size` is the pixel height of a glyph cell (7 font pixels).
    pub fn hud_text(&mut self, s: &str, x: f32, y: f32, size: f32, c: [f32; 4]) {
        let px = size / 7.0;
        let (mut cx, mut cy) = (x, y);
        for ch in s.chars() {
            if ch == '\n' {
                cx = x;
                cy += size * 1.4;
                continue;
            }
            let mut pix = Vec::new();
            font::glyph(ch, |gx, gy| pix.push((gx, gy)));
            for (gx, gy) in pix {
                self.hud_rect(cx + gx as f32 * px, cy + gy as f32 * px, px, px, c);
            }
            cx += font::ADVANCE * px;
        }
    }

    pub fn text_width(s: &str, size: f32) -> f32 {
        let longest = s.lines().map(|l| l.chars().count()).max().unwrap_or(0);
        longest as f32 * font::ADVANCE * size / 7.0
    }
}
