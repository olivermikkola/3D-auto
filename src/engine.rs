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
    pub meshes: Vec<Mesh>,
    pub mesh_ids: HashMap<String, usize>,
    /// Bumped when a mesh is replaced so the renderer re-uploads it.
    pub mesh_revs: Vec<u32>,
    /// Big meshes whose vertices now live only on the GPU (see `release_uploaded`).
    pub gpu_only: HashSet<usize>,
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
            meshes: Vec::new(),
            mesh_ids: HashMap::new(),
            mesh_revs: Vec::new(),
            gpu_only: HashSet::new(),
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
        if let Some(&id) = self.mesh_ids.get(name) {
            self.meshes[id] = m;
            self.mesh_revs[id] += 1;
            self.gpu_only.remove(&id);
            return id;
        }
        self.meshes.push(m);
        self.mesh_revs.push(0);
        self.mesh_ids.insert(name.to_string(), self.meshes.len() - 1);
        self.meshes.len() - 1
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
    /// in chunks of CHUNK cells, each cell colored by the average of its
    /// corners' `colors` (one rgb per height, or grass), and collides
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
        let col = |i: usize, j: usize| colors.as_ref().map_or(grass, |c| c[j * t.w + i]);
        let point = |i: usize, j: usize| v3(t.x0 + i as f32 * t.step, t.at(i, j), t.z0 + j as f32 * t.step);
        let avg = |cs: [[f32; 3]; 3]| {
            let c = |k: usize| (cs[0][k] + cs[1][k] + cs[2][k]) / 3.0;
            v3(c(0), c(1), c(2))
        };
        for cj in (0..t.d - 1).step_by(CHUNK) {
            for ci in (0..t.w - 1).step_by(CHUNK) {
                let mut m = Mesh::default();
                for j in cj..(cj + CHUNK).min(t.d - 1) {
                    for i in ci..(ci + CHUNK).min(t.w - 1) {
                        // Wound so the faces point up; the same split as Terrain::surface.
                        let (a, b, c, d) = ((i, j), (i, j + 1), (i + 1, j), (i + 1, j + 1));
                        m.tri(point(a.0, a.1), point(b.0, b.1), point(c.0, c.1), avg([col(a.0, a.1), col(b.0, b.1), col(c.0, c.1)]));
                        m.tri(point(c.0, c.1), point(b.0, b.1), point(d.0, d.1), avg([col(c.0, c.1), col(b.0, b.1), col(d.0, d.1)]));
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

#[cfg(test)]
mod tests {
    use super::*;

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
