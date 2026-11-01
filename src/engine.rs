//! The engine's whole state. Lua owns the game; this owns the facts.

use crate::audio::{Mixer, Samples};
use crate::font;
use crate::math::{Quat, Vec3, v3};
use crate::mesh::{self, Mesh};
use crate::physics::{self, Body, Broad, Contact, Terrain, WarmCache};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

static EPOCH: AtomicU64 = AtomicU64::new(1);

pub const TICK_HZ: f64 = 60.0;
/// Meshes at least this big keep their vertices only on the GPU once drawn.
const GPU_ONLY_VERTS: usize = 4096;
/// The baked trees' chunk, metres square.
const FOREST_CHUNK: f32 = 200.0;

/// One of a map's trees (`Engine::load_forest`).
pub struct Tree {
    pub x: f32,
    pub z: f32,
    pub crown: f32,
    pub street: bool,
    pub hash: f32,
}

/// A map's trees, which of them stand at the current quality, and the
/// trees by 50 m square for `forest_near`.
pub struct Forest {
    pub file: String,
    pub trees: Vec<Tree>,
    pub standing: Vec<bool>,
    cells: HashMap<(i32, i32), Vec<u32>>,
}

impl Forest {
    fn cell(x: f32, z: f32) -> (i32, i32) {
        ((x / 50.0).floor() as i32, (z / 50.0).floor() as i32)
    }
}

/// Sends a mesh to the GPU as soon as it's made: (engine epoch, mesh id,
/// revision, mesh). Set by the windowed game; headless runs have none.
pub type Uploader = Box<dyn FnMut(u64, usize, u32, &Mesh)>;

#[derive(Clone, Debug)]
pub struct Entity {
    pub pos: Vec3,
    pub rot: Quat,
    pub scale: Vec3,
    pub mesh: Option<usize>,
    pub color: [f32; 4],
    pub body: Option<Body>,
    pub tag: String,
    pub visible: bool,
    /// Casts the sun's shadow (not the baked trees: see `set_forest`).
    pub shadow: bool,
    /// Self-illumination that ignores time of day (muzzle flashes, fire, pickups).
    pub glow: f32,
    /// Pose before the last tick, so frames between ticks can be drawn in
    /// between. None until the first tick, and after a teleport.
    pub prev: Option<(Vec3, Quat)>,
}

impl Entity {
    pub fn new(pos: Vec3) -> Entity {
        Entity {
            pos,
            rot: Quat::IDENTITY,
            scale: Vec3::ONE,
            mesh: None,
            color: [1.0; 4],
            body: None,
            tag: String::new(),
            visible: true,
            shadow: true,
            glow: 0.0,
            prev: None,
        }
    }
}

/// A point or spot light. With `follow`, `pos` and `dir` are in that
/// entity's local space and the light rides along (headlights, lamps).
#[derive(Clone, Debug)]
pub struct Light {
    pub pos: Vec3,
    pub dir: Vec3,
    pub color: [f32; 3],
    pub intensity: f32,
    pub radius: f32,
    /// Cosine of the spot half-angle; -1 makes it a point light.
    pub cone: f32,
    pub follow: Option<u32>,
}

pub struct Camera {
    pub eye: Vec3,
    pub target: Vec3,
    pub fov: f32,
}

pub struct Env {
    /// Horizon color; also the fog color.
    pub sky: [f32; 3],
    pub sky_top: [f32; 3],
    pub sun_color: [f32; 3],
    /// Hemisphere ambient: light from above and bounce from below.
    pub ambient: [f32; 3],
    pub ground: [f32; 3],
    /// 0 by day, 1 at night: scales emissive surfaces and all lights.
    pub glow: f32,
    pub shadows: bool,
    /// 0 dry, 1 soaked: flat dark grey surfaces (asphalt, paving) darken
    /// and mirror the sky at low angles.
    pub wet: f32,
    /// 0 bare, 1 snowed over: flat ground goes white (roads less so).
    pub snow: f32,
    pub fog_start: f32,
    pub fog_end: f32,
    pub sun: Vec3,
    pub gravity: f32,
}

pub struct Engine {
    pub root: PathBuf,
    pub ents: Vec<Option<Entity>>,
    pub live: usize,
    pub lights: Vec<Option<Light>>,
    warm: WarmCache,
    broad: Broad,
    /// Statics moved since the last step, which the broad-phase grid doesn't know about yet.
    touched: Vec<u32>,
    /// Live entity ids by tag, ascending (ids only ever grow).
    tagged: HashMap<String, Vec<u32>>,
    /// The ground as a heightfield, if the game gave one, and the entities
    /// drawing it.
    pub terrain: Option<Terrain>,
    terrain_chunks: Vec<u32>,
    /// The entities drawing the baked trees (`set_forest`).
    forest_chunks: Vec<u32>,
    forest_meshes: Vec<String>,
    /// The map's trees, loaded from its file (`load_forest`).
    pub forest: Option<Forest>,
    pub meshes: Vec<Mesh>,
    pub mesh_ids: HashMap<String, usize>,
    /// Bumped when a mesh is replaced so the renderer re-uploads it.
    pub mesh_revs: Vec<u32>,
    /// Big meshes whose vertices now live only on the GPU (see `release_uploaded`).
    pub gpu_only: HashSet<usize>,
    /// When set, big meshes go to the GPU the moment they're made and their
    /// vertices are dropped then, rather than after the first frame: a city
    /// built in one go never holds all of them at once (in the browser,
    /// memory once grown stays grown).
    pub uploader: Option<Uploader>,
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
    /// While set, HUD rects and quads are cut to this rectangle (x0, y0, x1, y1).
    pub hud_clip: Option<[f32; 4]>,
    pub time: f64,
    pub tick: u64,
    pub quit: bool,
    /// A script asked for a fresh start (engine.reload), as F5 does.
    pub reload: bool,
    pub error: Option<String>,
    /// Shared with the audio thread; survives script reloads.
    pub mixer: Arc<Mutex<Mixer>>,
    pub sounds: HashMap<String, Samples>,
    /// Voices that track an entity: (voice, entity).
    pub follow: Vec<(u32, u32)>,
    /// Save data; carried across script reloads like the mixer.
    pub saves: crate::save::Store,
    /// While paused there are no ticks: physics, the clock and game sounds stop.
    pub paused: bool,
    pub fullscreen: bool,
    /// Run with --headless: no window, nobody at the controls.
    pub headless: bool,
    /// Mouse position in window pixels, for clicking on menus.
    pub cursor: (f32, f32),
    /// The first connected gamepad's sticks and triggers.
    pub pad: Option<crate::pad::State>,
}

impl Engine {
    /// Remember every pose before a tick.
    pub fn snapshot(&mut self) {
        for e in self.ents.iter_mut().flatten() {
            e.prev = Some((e.pos, e.rot));
        }
    }

    /// Move everything `t` (0..1) of the way from its pose before the last
    /// tick to its pose now, for drawing a frame that falls between ticks.
    /// Returns what `unblend` puts back.
    pub fn blend(&mut self, t: f32) -> Vec<(usize, [Vec3; 2], [Quat; 2])> {
        let mut saved = Vec::new();
        for (i, e) in self.ents.iter_mut().enumerate() {
            let Some(e) = e else { continue };
            let Some((p, r)) = e.prev else { continue };
            if p == e.pos && r == e.rot {
                continue;
            }
            let (bp, br) = (p + (e.pos - p) * t, r.nlerp(e.rot, t));
            saved.push((i, [e.pos, bp], [e.rot, br]));
            e.pos = bp;
            e.rot = br;
        }
        saved
    }

    /// Back to the ticked poses, except where the frame moved something itself.
    pub fn unblend(&mut self, saved: Vec<(usize, [Vec3; 2], [Quat; 2])>) {
        for (i, [p, bp], [r, br]) in saved {
            if let Some(Some(e)) = self.ents.get_mut(i) {
                if e.pos == bp {
                    e.pos = p;
                }
                if e.rot == br {
                    e.rot = r;
                }
            }
        }
    }

    pub fn new(root: PathBuf, mixer: Arc<Mutex<Mixer>>) -> Engine {
        mixer.lock().unwrap().stop_all();
        let mut e = Engine {
            root,
            ents: Vec::new(),
            live: 0,
            warm: WarmCache::new(),
            broad: Broad::default(),
            touched: Vec::new(),
            tagged: HashMap::new(),
            terrain: None,
            terrain_chunks: Vec::new(),
            forest_chunks: Vec::new(),
            forest_meshes: Vec::new(),
            forest: None,
            meshes: Vec::new(),
            mesh_ids: HashMap::new(),
            mesh_revs: Vec::new(),
            gpu_only: HashSet::new(),
            uploader: None,
            epoch: EPOCH.fetch_add(1, Ordering::Relaxed),
            camera: Camera { eye: v3(0., 10., -20.), target: Vec3::ZERO, fov: 70f32.to_radians() },
            env: Env {
                sky: [0.55, 0.7, 0.85],
                sky_top: [0.32, 0.52, 0.85],
                sun_color: [0.9, 0.84, 0.72],
                ambient: [0.42, 0.45, 0.52],
                ground: [0.12, 0.12, 0.12],
                glow: 0.0,
                shadows: true,
                wet: 0.0,
                snow: 0.0,
                fog_start: 80.0,
                fog_end: 260.0,
                sun: v3(0.4, 0.8, 0.3).norm(),
                gravity: -20.0,
            },
            lights: Vec::new(),
            keys: HashSet::new(),
            mouse_delta: (0.0, 0.0),
            mouse_grab: false,
            screen: (1280.0, 720.0),
            hud: Vec::new(),
            hud_clip: None,
            time: 0.0,
            tick: 0,
            quit: false,
            reload: false,
            error: None,
            mixer,
            sounds: HashMap::new(),
            follow: Vec::new(),
            saves: Default::default(),
            paused: false,
            fullscreen: false,
            headless: false,
            cursor: (0.0, 0.0),
            pad: None,
        };
        for (name, m) in mesh::builtins() {
            e.add_mesh(name, m);
        }
        e
    }

    /// Register (or replace) a named mesh. Returns its id.
    pub fn add_mesh(&mut self, name: &str, m: Mesh) -> usize {
        let id = if let Some(&id) = self.mesh_ids.get(name) {
            self.meshes[id] = m;
            self.mesh_revs[id] += 1;
            self.gpu_only.remove(&id);
            id
        } else {
            self.meshes.push(m);
            self.mesh_revs.push(0);
            self.mesh_ids.insert(name.to_string(), self.meshes.len() - 1);
            self.meshes.len() - 1
        };
        if let Some(up) = self.uploader.as_mut()
            && self.meshes[id].verts.len() >= GPU_ONLY_VERTS
        {
            up(self.epoch, id, self.mesh_revs[id], &self.meshes[id]);
            self.meshes[id] = Mesh::default();
            self.gpu_only.insert(id);
        }
        id
    }

    /// Drop the CPU copy of meshes the renderer has uploaded. Only big ones
    /// go (baked roads, blocks, terrain): they are most of a city's memory and
    /// nothing builds other meshes from them. Replacing one uploads it again.
    pub fn release_uploaded(&mut self, ids: &[usize]) {
        for &id in ids {
            if self.meshes[id].verts.len() >= GPU_ONLY_VERTS {
                self.meshes[id] = Mesh::default();
                self.gpu_only.insert(id);
            }
        }
    }

    pub fn spawn(&mut self, e: Entity) -> u32 {
        let id = self.ents.len() as u32;
        self.tagged.entry(e.tag.clone()).or_default().push(id);
        self.ents.push(Some(e));
        self.live += 1;
        id
    }

    pub fn despawn(&mut self, id: u32) {
        if let Some(slot) = self.ents.get_mut(id as usize)
            && let Some(e) = slot.take()
        {
            self.live -= 1;
            if e.body.as_ref().is_some_and(|b| b.kind == physics::Kind::Static) {
                self.broad.forget(id as usize);
            }
            if let Some(ids) = self.tagged.get_mut(&e.tag)
                && let Ok(k) = ids.binary_search(&id)
            {
                ids.remove(k);
            }
        }
    }

    /// Live entities with this tag, in spawn order.
    pub fn find(&self, tag: &str) -> Vec<u32> {
        self.tagged.get(tag).cloned().unwrap_or_default()
    }

    /// The entity nearest to `p` within `r` (with `tag`, only those: looked
    /// up by tag, not by going through every entity on the map) and how far
    /// it is. On a tie the one spawned first.
    pub fn nearest(&self, p: Vec3, r: f32, tag: Option<&str>, ignore: Option<u32>) -> Option<(u32, f32)> {
        let near = |i: u32| {
            let en = self.get(i)?;
            let d = (en.pos - p).len();
            (Some(i) != ignore && d <= r).then_some((i, d))
        };
        match tag {
            Some(t) => self.tagged.get(t)?.iter().filter_map(|&i| near(i)).min_by(|a, b| a.1.total_cmp(&b.1)),
            None => (0..self.ents.len() as u32).filter_map(near).min_by(|a, b| a.1.total_cmp(&b.1)),
        }
    }

    pub fn get(&self, id: u32) -> Option<&Entity> {
        self.ents.get(id as usize)?.as_ref()
    }

    pub fn get_mut(&mut self, id: u32) -> Option<&mut Entity> {
        self.ents.get_mut(id as usize)?.as_mut()
    }

    /// For moving or turning an entity: notes a static, so rays still find it there.
    pub fn pose_mut(&mut self, id: u32) -> Option<&mut Entity> {
        let en = self.ents.get_mut(id as usize)?.as_mut()?;
        if en.body.as_ref().is_some_and(|b| b.kind == physics::Kind::Static) {
            self.touched.push(id);
        }
        Some(en)
    }

    /// The nearest body or terrain a ray hits; see physics::raycast_near.
    pub fn raycast(&self, o: Vec3, dir: Vec3, max: f32, ignore: Option<u32>) -> Option<physics::RayHit> {
        let hit = physics::raycast_near(&self.ents, &self.broad, &self.touched, o, dir, max, ignore);
        let Some(t) = self.terrain.as_ref().filter(|t| Some(t.id as u32) != ignore) else { return hit };
        let reach = hit.as_ref().map_or(max, |h| h.dist);
        match t.ray(o, dir, reach) {
            Some((dist, normal)) => Some(physics::RayHit { id: t.id as u32, dist, point: o + dir * dist, normal }),
            None => hit,
        }
    }

    /// Replace the ground heightfield (or remove it with None). It's drawn
    /// in chunks of CHUNK cells, the colour blended between its points'
    /// `colors` (one rgb per height, or grass), and collides
    /// through an entity tagged "terrain".
    pub fn set_terrain(&mut self, terrain: Option<Terrain>, colors: Option<Vec<[f32; 3]>>) {
        const CHUNK: usize = 64;
        if let Some(old) = self.terrain.take() {
            self.despawn(old.id as u32);
        }
        for id in std::mem::take(&mut self.terrain_chunks) {
            self.despawn(id);
        }
        let Some(mut t) = terrain else { return };
        let mut holder = Entity::new(v3(0.0, -10_000.0, 0.0));
        holder.tag = "terrain".to_string();
        holder.visible = false;
        holder.body = Some(Body::new(physics::Kind::Static, Vec3::ZERO));
        t.id = self.spawn(holder) as usize;
        let grass = [0.3, 0.42, 0.24];
        let col = |i: usize, j: usize| {
            let c = colors.as_ref().map_or(grass, |c| c[j * t.w + i]);
            v3(c[0], c[1], c[2])
        };
        let point = |i: usize, j: usize| v3(t.x0 + i as f32 * t.step, t.at(i, j), t.z0 + j as f32 * t.step);
        for cj in (0..t.d - 1).step_by(CHUNK) {
            for ci in (0..t.w - 1).step_by(CHUNK) {
                let mut m = Mesh::default();
                for j in cj..(cj + CHUNK).min(t.d - 1) {
                    for i in ci..(ci + CHUNK).min(t.w - 1) {
                        // Wound so the faces point up; the same split as Terrain::surface.
                        let (a, b, c, d) = ((i, j), (i, j + 1), (i + 1, j), (i + 1, j + 1));
                        m.tri_blend(point(a.0, a.1), point(b.0, b.1), point(c.0, c.1), [col(a.0, a.1), col(b.0, b.1), col(c.0, c.1)]);
                        m.tri_blend(point(c.0, c.1), point(b.0, b.1), point(d.0, d.1), [col(c.0, c.1), col(b.0, b.1), col(d.0, d.1)]);
                    }
                }
                let mesh = self.add_mesh(&format!("terrain_{ci}_{cj}"), m);
                let mut chunk = Entity::new(Vec3::ZERO);
                chunk.mesh = Some(mesh);
                chunk.tag = "terrain_mesh".to_string();
                let id = self.spawn(chunk);
                self.terrain_chunks.push(id);
            }
        }
        self.terrain = Some(t);
    }

    /// Load a map's trees: 10 bytes each, x and z (f32, little-endian),
    /// the crown across in metres and 1 for a street's tree (u8 each).
    pub fn load_forest(&mut self, file: &str, bytes: &[u8]) -> Result<usize, String> {
        if !bytes.len().is_multiple_of(10) {
            return Err(format!("{file} is {} bytes, not 10 a tree", bytes.len()));
        }
        let f32_at = |b: &[u8]| f32::from_le_bytes([b[0], b[1], b[2], b[3]]);
        let trees: Vec<Tree> = bytes
            .chunks(10)
            .map(|b| {
                let (x, z) = (f32_at(&b[0..4]), f32_at(&b[4..8]));
                // A hash of the place, 0..1: which trees a lower quality leaves out.
                let h = ((x * 10.0).floor() as i32).wrapping_mul(73_856_093) ^ ((z * 10.0).floor() as i32).wrapping_mul(19_349_663);
                Tree { x, z, crown: b[8] as f32, street: b[9] != 0, hash: h.rem_euclid(1000) as f32 / 1000.0 }
            })
            .collect();
        let mut cells: HashMap<(i32, i32), Vec<u32>> = HashMap::new();
        for (i, t) in trees.iter().enumerate() {
            cells.entry(Forest::cell(t.x, t.z)).or_default().push(i as u32);
        }
        let n = trees.len();
        self.forest = Some(Forest { file: file.to_string(), standing: vec![false; n], trees, cells });
        Ok(n)
    }

    /// Stand the loaded trees: those by a street where their hash is under
    /// `street`, the rest under `park`, and bake them. Returns how many stand.
    pub fn stand_forest(&mut self, street: f32, park: f32) -> usize {
        let Some(f) = self.forest.as_mut() else {
            self.set_forest(&[], FOREST_CHUNK);
            return 0;
        };
        let ground = |x: f32, z: f32| self.terrain.as_ref().and_then(|t| t.surface(x, z)).map_or(0.0, |(h, _)| h);
        let mut baked = Vec::new();
        for (t, on) in f.trees.iter().zip(f.standing.iter_mut()) {
            *on = t.hash < if t.street { street } else { park };
            if *on {
                baked.push([t.x, ground(t.x, t.z), t.z, t.crown]);
            }
        }
        self.set_forest(&baked, FOREST_CHUNK);
        baked.len()
    }

    /// The standing trees within `r` of (x, z): (number, x, z, crown).
    pub fn forest_near(&self, x: f32, z: f32, r: f32) -> Vec<(u32, f32, f32, f32)> {
        let Some(f) = &self.forest else { return Vec::new() };
        let ((i0, j0), (i1, j1)) = (Forest::cell(x - r, z - r), Forest::cell(x + r, z + r));
        let mut out = Vec::new();
        for i in i0..=i1 {
            for j in j0..=j1 {
                for &k in f.cells.get(&(i, j)).map_or(&[][..], |v| v.as_slice()) {
                    let t = &f.trees[k as usize];
                    if f.standing[k as usize] && (t.x - x).powi(2) + (t.z - z).powi(2) < r * r {
                        out.push((k, t.x, t.z, t.crown));
                    }
                }
            }
        }
        out
    }

    /// Replace the baked trees: each (x, ground y, z, crown across) a leafy
    /// tree (mesh::leafy_tree), baked into one mesh per `chunk` metres square
    /// so a city's trees are a few hundred draws, not a hundred thousand.
    /// They are only drawn, cast no sun shadow; whatever should stop a car
    /// is the game's to add.
    /// Returns the chunks made.
    pub fn set_forest(&mut self, trees: &[[f32; 4]], chunk: f32) -> usize {
        for id in std::mem::take(&mut self.forest_chunks) {
            self.despawn(id);
        }
        // Emptied, not left holding a chunk nothing draws any more.
        for name in std::mem::take(&mut self.forest_meshes) {
            self.add_mesh(&name, Mesh::default());
        }
        let mut cells: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
        for (i, t) in trees.iter().enumerate() {
            cells.entry(((t[0] / chunk).floor() as i32, (t[2] / chunk).floor() as i32)).or_default().push(i);
        }
        let mut keys: Vec<_> = cells.keys().copied().collect();
        keys.sort();
        for (ci, cj) in keys {
            let mut m = Mesh::default();
            for &i in &cells[&(ci, cj)] {
                let t = trees[i];
                let seed = (t[0] * 10.0) as i32 as u32 ^ ((t[2] * 10.0) as i32 as u32).rotate_left(16);
                mesh::leafy_tree(&mut m, v3(t[0], t[1], t[2]), t[3], seed);
            }
            let name = format!("forest_{ci}_{cj}");
            let mesh = self.add_mesh(&name, m);
            self.forest_meshes.push(name);
            let mut e = Entity::new(Vec3::ZERO);
            e.mesh = Some(mesh);
            e.tag = "forest".to_string();
            // No sun shadow: a crown's would be a solid black disc on the
            // ground (real leaves let light through), and a city's trees
            // would double the shadow pass. The ground under them is a
            // shaded grass instead (tools/osm_import.py).
            e.shadow = false;
            let id = self.spawn(e);
            self.forest_chunks.push(id);
        }
        self.forest_chunks.len()
    }

    /// World-space position and direction of a light, if its anchor exists.
    pub fn light_world(&self, l: &Light) -> Option<(Vec3, Vec3)> {
        match l.follow {
            None => Some((l.pos, l.dir)),
            Some(id) => self.get(id).map(|e| (e.pos + e.rot.rotate(l.pos), e.rot.rotate(l.dir))),
        }
    }

    /// Pause or resume. Pausing returns the keys that were held, now released,
    /// so scripts can be told they went up (nothing stays "held" through a menu).
    pub fn set_paused(&mut self, on: bool) -> Vec<String> {
        let mut released = Vec::new();
        if on && !self.paused {
            released = self.keys.drain().collect();
            released.sort();
        }
        self.paused = on;
        self.mixer.lock().unwrap().paused = on;
        released
    }

    pub fn step(&mut self, dt: f32) -> Vec<Contact> {
        self.tick += 1;
        self.time += dt as f64;
        let contacts = physics::step(&mut self.ents, dt, self.env.gravity, &mut self.warm, &mut self.broad, self.terrain.as_ref());
        self.touched.clear();
        contacts
    }

    /// Put the listener at the camera and move entity-following voices.
    pub fn update_audio(&mut self) {
        let mut m = self.mixer.lock().unwrap();
        m.listener = self.camera.eye;
        m.listener_right = (self.camera.target - self.camera.eye).cross(Vec3::UP).norm();
        let ents = &self.ents;
        self.follow.retain(|&(voice, ent)| match ents.get(ent as usize).and_then(|e| e.as_ref()) {
            Some(e) if m.playing(voice) => {
                m.set(voice, None, None, Some(e.pos));
                true
            }
            _ => {
                m.stop(voice);
                false
            }
        });
    }

    pub fn hud_rect(&mut self, x: f32, y: f32, w: f32, h: f32, c: [f32; 4]) {
        let (mut x0, mut y0, mut x1, mut y1) = (x, y, x + w, y + h);
        if let Some([cx0, cy0, cx1, cy1]) = self.hud_clip {
            (x0, y0, x1, y1) = (x0.max(cx0), y0.max(cy0), x1.min(cx1), y1.min(cy1));
            if x1 <= x0 || y1 <= y0 {
                return;
            }
        }
        for (px, py) in [(x0, y0), (x1, y0), (x1, y1), (x0, y0), (x1, y1), (x0, y1)] {
            self.hud.extend_from_slice(&[px, py, c[0], c[1], c[2], c[3]]);
        }
    }

    /// A convex quad (corners in order), cut to the clip rectangle if one is set.
    pub fn hud_quad(&mut self, pts: [(f32, f32); 4], c: [f32; 4]) {
        let mut poly: Vec<(f32, f32)> = pts.to_vec();
        if let Some(clip) = self.hud_clip {
            poly = clip_to_rect(poly, clip);
            if poly.len() < 3 {
                return;
            }
        }
        for i in 1..poly.len() - 1 {
            for (px, py) in [poly[0], poly[i], poly[i + 1]] {
                self.hud.extend_from_slice(&[px, py, c[0], c[1], c[2], c[3]]);
            }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nearest_by_tag_skips_others_the_ignored_and_the_gone() {
        let mut e = Engine::new(PathBuf::from("."), Arc::new(Mutex::new(Mixer::default())));
        let at = |tag: &str, x: f32| {
            let mut en = Entity::new(v3(x, 0.0, 0.0));
            en.tag = tag.to_string();
            en
        };
        let ped = e.spawn(at("ped", 1.0));
        let car = e.spawn(at("car", 2.0));
        let car2 = e.spawn(at("car", 3.0));
        assert_eq!(e.nearest(Vec3::ZERO, 10.0, None, None), Some((ped, 1.0)));
        assert_eq!(e.nearest(Vec3::ZERO, 10.0, Some("car"), None), Some((car, 2.0)));
        assert_eq!(e.nearest(Vec3::ZERO, 10.0, Some("car"), Some(car)), Some((car2, 3.0)));
        assert_eq!(e.nearest(Vec3::ZERO, 2.5, Some("car"), Some(car)), None);
        assert_eq!(e.nearest(Vec3::ZERO, 10.0, Some("lamp"), None), None);
        e.despawn(car);
        assert_eq!(e.nearest(Vec3::ZERO, 10.0, Some("car"), None), Some((car2, 3.0)));
    }

    #[test]
    fn a_forest_loads_stands_by_quality_and_answers_whats_near() {
        let mut e = Engine::new(PathBuf::from("."), Arc::new(Mutex::new(Mixer::default())));
        let mut bytes = Vec::new();
        for k in 0..400 {
            let (x, z) = ((k % 20) as f32 * 9.0, (k / 20) as f32 * 9.0);
            bytes.extend_from_slice(&x.to_le_bytes());
            bytes.extend_from_slice(&z.to_le_bytes());
            bytes.extend_from_slice(&[8, (k % 4 == 0) as u8]);
        }
        assert_eq!(e.load_forest("t.bin", &bytes), Ok(400));
        assert!(e.load_forest("t.bin", &bytes[..15]).is_err(), "10 bytes a tree");
        e.load_forest("t.bin", &bytes).unwrap();
        assert_eq!(e.stand_forest(1.0, 1.0), 400);
        let some = e.stand_forest(1.0, 0.3);
        assert!(some > 100 + 60 && some < 100 + 150, "every street tree and about 30 % of the rest: {some}");
        assert_eq!(e.find("forest").len(), 1, "one chunk for a 171 m square");
        let near = e.forest_near(0.0, 0.0, 12.0);
        assert!(near.iter().all(|t| t.1 * t.1 + t.2 * t.2 < 144.0 && e.forest.as_ref().unwrap().standing[t.0 as usize]));
        assert!(near.iter().any(|t| t.0 == 0), "a street tree always stands");
        assert_eq!(e.stand_forest(0.0, 0.0), 0);
        assert!(e.forest_near(0.0, 0.0, 1e6).is_empty() && e.find("forest").is_empty());
    }

    #[test]
    fn find_lists_live_entities_by_tag_in_spawn_order() {
        let mut e = Engine::new(PathBuf::from("."), Arc::new(Mutex::new(Mixer::default())));
        let tagged = |tag: &str| {
            let mut en = Entity::new(Vec3::ZERO);
            en.tag = tag.to_string();
            en
        };
        let ids: Vec<u32> = ["car", "ped", "car", "car"].iter().map(|t| e.spawn(tagged(t))).collect();
        e.despawn(ids[2]);
        e.despawn(ids[2]); // twice is fine
        let last = e.spawn(tagged("car"));
        assert_eq!(e.find("car"), vec![ids[0], ids[3], last]);
        assert_eq!(e.find("ped"), vec![ids[1]]);
        assert!(e.find("cop").is_empty());
    }

    #[test]
    fn pausing_releases_held_keys_once() {
        let mut e = Engine::new(PathBuf::from("."), Arc::new(Mutex::new(Mixer::default())));
        e.keys.extend(["w".to_string(), "mouse1".to_string()]);
        assert_eq!(e.set_paused(true), vec!["mouse1", "w"]);
        assert!(e.paused && e.keys.is_empty() && e.mixer.lock().unwrap().paused);
        e.keys.insert("down".into()); // menu navigation while paused
        assert!(e.set_paused(true).is_empty(), "pausing again releases nothing");
        assert!(e.set_paused(false).is_empty() && !e.paused && !e.mixer.lock().unwrap().paused);
    }

    #[test]
    fn frames_between_ticks_blend_and_put_back() {
        let mut e = Engine::new(PathBuf::from("."), Arc::new(Mutex::new(Mixer::default())));
        let (a, b) = (e.spawn(Entity::new(Vec3::ZERO)), e.spawn(Entity::new(Vec3::ZERO)));
        assert!(e.blend(0.5).is_empty(), "nothing to blend before the first tick");
        e.snapshot();
        e.get_mut(a).unwrap().pos = v3(10.0, 0.0, 0.0);
        e.get_mut(b).unwrap().pos = v3(0.0, 0.0, 4.0);
        let saved = e.blend(0.25);
        assert_eq!(e.get(a).unwrap().pos, v3(2.5, 0.0, 0.0));
        e.get_mut(b).unwrap().pos = v3(7.0, 0.0, 0.0); // the frame moved b itself
        e.unblend(saved);
        assert_eq!(e.get(a).unwrap().pos, v3(10.0, 0.0, 0.0), "back to the ticked pose");
        assert_eq!(e.get(b).unwrap().pos, v3(7.0, 0.0, 0.0), "a move made during the frame stays");
    }
}

/// A convex polygon cut to an axis-aligned rectangle (x0, y0, x1, y1), one
/// edge at a time (Sutherland-Hodgman).
pub fn clip_to_rect(poly: Vec<(f32, f32)>, r: [f32; 4]) -> Vec<(f32, f32)> {
    // Each edge: which axis (0 x, 1 y), the bound, and whether inside is >= it.
    let edges = [(0, r[0], true), (0, r[2], false), (1, r[1], true), (1, r[3], false)];
    let mut out = poly;
    for (axis, bound, ge) in edges {
        if out.is_empty() {
            break;
        }
        let inside = |p: (f32, f32)| {
            let v = if axis == 0 { p.0 } else { p.1 };
            if ge { v >= bound } else { v <= bound }
        };
        let input = std::mem::take(&mut out);
        for i in 0..input.len() {
            let a = input[i];
            let b = input[(i + 1) % input.len()];
            let (ia, ib) = (inside(a), inside(b));
            if ia {
                out.push(a);
            }
            if ia != ib {
                let (va, vb) = if axis == 0 { (a.0, b.0) } else { (a.1, b.1) };
                let t = (bound - va) / (vb - va);
                out.push((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t));
            }
        }
    }
    out
}

#[cfg(test)]
mod clip_tests {
    use super::clip_to_rect;

    fn area(p: &[(f32, f32)]) -> f32 {
        let mut a = 0.0;
        for i in 0..p.len() {
            let (x0, y0) = p[i];
            let (x1, y1) = p[(i + 1) % p.len()];
            a += x0 * y1 - x1 * y0;
        }
        a.abs() / 2.0
    }

    #[test]
    fn inside_is_kept_outside_is_dropped() {
        let sq = vec![(1.0, 1.0), (2.0, 1.0), (2.0, 2.0), (1.0, 2.0)];
        assert_eq!(clip_to_rect(sq.clone(), [0.0, 0.0, 10.0, 10.0]), sq);
        assert!(clip_to_rect(sq, [5.0, 5.0, 10.0, 10.0]).is_empty());
    }

    #[test]
    fn a_diamond_over_a_corner_is_cut() {
        // A diamond round (0, 0) with radius 2, cut to x, y >= 0: a quarter of its area.
        let d = vec![(2.0, 0.0), (0.0, 2.0), (-2.0, 0.0), (0.0, -2.0)];
        let c = clip_to_rect(d, [0.0, 0.0, 10.0, 10.0]);
        assert!((area(&c) - 2.0).abs() < 1e-5, "area {}", area(&c));
    }
}
