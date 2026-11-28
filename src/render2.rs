//! Offscreen renderer for the Engine 2.0 postcard comparison.
//! The screenshot path keeps graphics and presentation separate from input.

use crate::engine::{Engine, Entity};
use crate::humans::{Humans, Mip};
use crate::math::{Mat4, Vec3};
use crate::mesh::{ObjSurface, Vertex};
use bytemuck::{Pod, Zeroable, bytes_of, cast_slice};
use std::collections::HashMap;
use std::path::Path;
use std::time::Duration;
use wgpu::util::DeviceExt;
use wgpu::*;

const COLOR: TextureFormat = TextureFormat::Rgba8Unorm;
const DEPTH: TextureFormat = TextureFormat::Depth32Float;
/// The sun's depth: 16 bits is plenty (1.2 cm steps over the near
/// cascade's 800 m) and halves the memory traffic of drawing and copying it,
/// which on an integrated GPU is most of what shadows cost.
const SHADOW_DEPTH: TextureFormat = TextureFormat::Depth16Unorm;
/// Sun depth layers: what the world samples (near, far), and the cached
/// still part of the near cascade that is copied into layer 0 each frame.
const NEAR_LAYER: u32 = 0;
const STATIC_LAYER: u32 = 2;
/// Entities that are always on the move: drawn into the near sun depth every
/// frame, never cached.
const MOVERS: [&str; 6] = ["walker", "traffic", "tram", "cop", "coplight", "mission"];
/// Anything else still for this many frames (2 s) joins the cached part.
const STILL_FRAMES: u32 = 120;
/// The shadows' sun moves in steps of 0.1 degree (this cosine).
const SUN_STEP_COS: f32 = 0.999_998_5;

/// A cheap fingerprint of what an entity casts: mesh, its revision and pose.
fn pose_key(e: &crate::engine::Entity, mesh: usize, rev: u32) -> u64 {
    let mut h = 0xcbf2_9ce4_8422_2325u64 ^ mesh as u64 ^ (u64::from(rev) << 40);
    for f in [e.pos.x, e.pos.y, e.pos.z, e.scale.x, e.scale.y, e.scale.z, e.rot.x, e.rot.y, e.rot.z, e.rot.w] {
        h = (h ^ u64::from(f.to_bits())).wrapping_mul(0x0100_0000_01b3);
    }
    h ^ (u64::from(e.shadow) | u64::from(e.visible) << 1 | u64::from(e.color[3] >= 1.0) << 2 | u64::from(e.layer) << 3)
}

const WORLD: [VertexAttribute; 3] = vertex_attr_array![0 => Float32x3, 1 => Uint8x4, 2 => Unorm8x4];
const OBJ_SURFACE: [VertexAttribute; 2] = vertex_attr_array![3 => Float32x2, 4 => Uint32];
const HUD: [VertexAttribute; 2] = vertex_attr_array![0 => Float32x2, 1 => Float32x4];

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Scene {
    view_projection: [f32; 16],
    eye: [f32; 4],
    fog: [f32; 4],
    sky: [f32; 4],
    sun: [f32; 4],
    sun_color: [f32; 4],
    ambient: [f32; 4],
    bounce: [f32; 4],
    light_projection: [f32; 16],
    camera_forward: [f32; 4],
    camera_right: [f32; 4],
    camera_up: [f32; 4],
    sky_top: [f32; 4],
    material_ground: [f32; 4],
    /// x: 1 for the HDR look (linear light, haze, tone-mapped after).
    post: [f32; 4],
    /// The far shadow cascade: the whole visible city at a coarser texel.
    light_far: [f32; 16],
    /// x, y: depth range in metres of the near and far cascades; z, w: their texel size in metres.
    cascades: [f32; 4],
    /// The lamp grid (`Lamps`): x, z of its corner, cell size in metres, and
    /// 1 when any lamp is lit (0 by day: the shader skips the lamps).
    lamp_grid: [f32; 4],
    /// x: how wet the streets are, y: how hard it rains (0..1), z: seconds
    /// (for falling rain and ripples), w: cloud cover (0..1).
    weather: [f32; 4],
}

/// Lamps and headlights near the camera (engine `light`s), at most
/// `LAMP_MAX`, and a grid of `LAMP_GRID` x `LAMP_GRID` cells on the ground
/// round the camera, each listing up to `LAMP_SLOTS` lights that reach it.
/// A pixel reads only its own cell's lights.
const LAMP_MAX: usize = 128;
const LAMP_GRID: usize = 32;
const LAMP_CELL: f32 = 8.0;
const LAMP_SLOTS: usize = 8;
/// A light is listed in the cells within this many of its radii: its pool is
/// one radius across, its glints on water and wet streets reach further.
const LAMP_REACH: f32 = 2.0;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Lamps {
    /// Per light three rows: position and radius; colour times intensity
    /// (linear in the HDR look); direction and cos(half cone), -1 for a point light.
    lights: [[f32; 4]; LAMP_MAX * 3],
    /// Per cell `LAMP_SLOTS` light indices, a byte each (255 = none), two
    /// cells to a row.
    cells: [[u32; 4]; LAMP_GRID * LAMP_GRID * LAMP_SLOTS / 16],
}

/// Fill the lamp grid for this frame. The grid sits mostly ahead of the
/// camera (the lights behind it light nothing in view) and snaps to whole
/// cells so it does not swim as the camera moves. Returns the scene's
/// `lamp_grid` row and how many lights went in.
fn lamp_grid(eng: &Engine, env: &crate::engine::Env, eye: Vec3, forward: Vec3, hdr: bool, out: &mut Lamps) -> ([f32; 4], usize) {
    let span = LAMP_GRID as f32 * LAMP_CELL;
    let flat = Vec3 { x: forward.x, y: 0.0, z: forward.z };
    let ahead = if flat.len() > 1e-3 { flat.norm() * (span * 0.25) } else { Vec3::ZERO };
    let centre = eye + ahead;
    let x0 = ((centre.x - span / 2.0) / LAMP_CELL).floor() * LAMP_CELL;
    let z0 = ((centre.z - span / 2.0) / LAMP_CELL).floor() * LAMP_CELL;
    out.cells = [[u32::MAX; 4]; LAMP_GRID * LAMP_GRID * LAMP_SLOTS / 16];
    if env.glow <= 0.01 {
        return ([x0, z0, LAMP_CELL, 0.0], 0);
    }
    let mut near: Vec<(f32, Vec3, Vec3, &crate::engine::Light)> = eng
        .lights
        .iter()
        .flatten()
        .filter(|l| l.intensity > 0.0 && eng.light_layer(l) == Some(eng.view_layer))
        .filter_map(|l| eng.light_world(l).map(|(p, d)| (p, d, l)))
        .filter(|(p, _, l)| {
            let reach = l.radius * LAMP_REACH;
            p.x + reach >= x0 && p.x - reach <= x0 + span && p.z + reach >= z0 && p.z - reach <= z0 + span
        })
        .map(|(p, d, l)| ((p - eye).len() - l.radius, p, d, l))
        .collect();
    near.sort_by(|a, b| a.0.total_cmp(&b.0));
    near.truncate(LAMP_MAX);
    let mut used = [0u8; LAMP_GRID * LAMP_GRID];
    let decode = |c: f32| if hdr { c.max(0.0).powf(2.2) } else { c };
    for (k, (_, p, d, l)) in near.iter().enumerate() {
        let strength = l.intensity * env.glow;
        out.lights[k * 3] = [p.x, p.y, p.z, l.radius];
        out.lights[k * 3 + 1] = [decode(l.color[0]) * strength, decode(l.color[1]) * strength, decode(l.color[2]) * strength, 0.0];
        out.lights[k * 3 + 2] = [d.x, d.y, d.z, l.cone];
        // Nearest lights first, so a full cell keeps the ones that matter most.
        let reach = l.radius * LAMP_REACH;
        let cell = |v: f32, o: f32| ((v - o) / LAMP_CELL).floor().clamp(-1.0, LAMP_GRID as f32) as i32;
        let (i0, i1) = (cell(p.x - reach, x0).max(0), cell(p.x + reach, x0).min(LAMP_GRID as i32 - 1));
        let (j0, j1) = (cell(p.z - reach, z0).max(0), cell(p.z + reach, z0).min(LAMP_GRID as i32 - 1));
        for j in j0..=j1 {
            for i in i0..=i1 {
                // Only the cells the light's reach actually touches.
                let cx = x0 + (i as f32 + 0.5) * LAMP_CELL;
                let cz = z0 + (j as f32 + 0.5) * LAMP_CELL;
                let dx = ((cx - p.x).abs() - LAMP_CELL / 2.0).max(0.0);
                let dz = ((cz - p.z).abs() - LAMP_CELL / 2.0).max(0.0);
                if dx * dx + dz * dz > reach * reach {
                    continue;
                }
                let c = j as usize * LAMP_GRID + i as usize;
                let slot = used[c] as usize;
                if slot >= LAMP_SLOTS {
                    continue;
                }
                used[c] += 1;
                let byte = c * LAMP_SLOTS + slot;
                let word = &mut out.cells[byte / 16][(byte / 4) % 4];
                let shift = (byte % 4) * 8;
                *word = (*word & !(0xff << shift)) | ((k as u32) << shift);
            }
        }
    }
    ([x0, z0, LAMP_CELL, if near.is_empty() { 0.0 } else { 1.0 }], near.len())
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Object {
    model: [f32; 16],
    tint: [f32; 4],
    inv_scale_sq: [f32; 4],
    material_flags: [u32; 4],
}

fn walked(e: &Entity) -> f32 {
    let forward = e.rot.rotate(Vec3 { x: 0.0, y: 0.0, z: 1.0 });
    e.pos.x * forward.x + e.pos.z * forward.z
}

impl Object {
    fn new(e: &Entity, humans: Option<&Humans>) -> Self {
        let inv_sq = |s: f32| 1.0 / (s * s).max(1e-6);
        // x: 1 a building, 2 a car with its lights on (low byte); bit 8 a
        // car braking, bits 16-31 its front wheels' angle (radians x 10000
        // + 32768); y: a walker (limbs
        // swing); z: how far along its facing it has come, in metres, so the
        // stride follows the ground, not a clock (for anything else: how far
        // it has driven, which rolls car wheels).
        let walker = e.tag == "walker";
        let kind = if e.tag == "building" {
            1
        } else if e.tag == "traffic" {
            2
        } else {
            0
        };
        let distance = if walker { walked(e) } else { e.driven };
        // w: which of the atlas's number plates a car shows: from where it
        // is parked, or (for a car that drives) its paint and mesh.
        let mix = |a: u32| (a ^ (a >> 16)).wrapping_mul(0x045d_9f3b);
        // (Only cars: w is the person for skinned meshes.)
        let plate = match e.tag.as_str() {
            "parked" => mix(mix(e.pos.x.to_bits() ^ mix(e.pos.z.to_bits()))) >> 8,
            "traffic" => mix(mix(e.color[0].to_bits() ^ mix(e.color[2].to_bits() ^ mix(e.mesh.unwrap_or(0) as u32)))) >> 8,
            _ => 0,
        };
        let steer = ((e.steer.clamp(-0.7, 0.7) * 10000.0).round() as i32 + 32768) as u32;
        let car = (e.braking as u32) << 8 | steer << 16;
        let mut flags = [kind | car, walker as u32, distance.to_bits(), plate];
        if let Some((h, &person)) = humans.and_then(|h| Some((h, h.meshes.get(&e.mesh?)?))) {
            // A skinned person: z is instead the phase of its walk cycle
            // (low 16 bits, 0..1) and how far it stands still (high 16
            // bits); w which person (+1) and the pose table's shape.
            let phase = (h.phase(person, walked(e) / e.scale.y.max(0.1)) * 65535.0).round() as u32;
            let still = ((1.0 - e.gait).clamp(0.0, 1.0) * 65535.0).round() as u32;
            flags[2] = phase.min(65535) | still << 16;
            flags[3] = (person + 1) | h.frames << 8 | h.bones << 16;
        }
        Self {
            model: Mat4::trs_q(e.pos, e.rot, e.scale).0,
            tint: e.color,
            inv_scale_sq: [inv_sq(e.scale.x), inv_sq(e.scale.y), inv_sq(e.scale.z), e.glow],
            material_flags: flags,
        }
    }
}

/// The people's walk poses and texture atlas on the GPU (stand-ins of one
/// matrix and one pixel when the game has none).
struct HumanGpu {
    rev: u64,
    poses: Buffer,
    atlas: TextureView,
    sampler: Sampler,
}

impl HumanGpu {
    fn new(device: &Device, queue: &Queue, humans: Option<&Humans>) -> Self {
        let blank = [[0.0f32; 4]; 3];
        let rows: &[[f32; 4]] = humans.map_or(&blank[..], |h| &h.poses[..]);
        let poses = device.create_buffer(&BufferDescriptor {
            label: Some("human poses"),
            size: (rows.len() * 16) as u64,
            usage: BufferUsages::STORAGE | BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        queue.write_buffer(&poses, 0, bytemuck::cast_slice(rows));
        let pixel = [(1, 1, vec![255u8; 4])];
        let mips = humans.map_or(&pixel[..], |h| &h.atlas[..]);
        // sRGB bytes read as they are: the shader's lin() converts, as for vertex colours.
        let atlas = atlas_texture(device, queue, "human atlas", mips);
        let sampler = device.create_sampler(&SamplerDescriptor {
            label: Some("human atlas"),
            mag_filter: FilterMode::Linear,
            min_filter: FilterMode::Linear,
            mipmap_filter: MipmapFilterMode::Linear,
            anisotropy_clamp: 4,
            ..Default::default()
        });
        Self { rev: humans.map_or(0, |h| h.rev), poses, atlas, sampler }
    }
}

/// An RGBA8 texture with its mips, colour read as stored (see HumanGpu).
fn atlas_texture(device: &Device, queue: &Queue, label: &str, mips: &[Mip]) -> TextureView {
    let texture = device.create_texture(&TextureDescriptor {
        label: Some(label),
        size: Extent3d { width: mips[0].0, height: mips[0].1, depth_or_array_layers: 1 },
        mip_level_count: mips.len() as u32,
        sample_count: 1,
        dimension: TextureDimension::D2,
        format: TextureFormat::Rgba8Unorm,
        usage: TextureUsages::TEXTURE_BINDING | TextureUsages::COPY_DST,
        view_formats: &[],
    });
    for (level, (w, h, bytes)) in mips.iter().enumerate() {
        queue.write_texture(
            TexelCopyTextureInfo { texture: &texture, mip_level: level as u32, origin: Origin3d::ZERO, aspect: TextureAspect::All },
            bytes,
            TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(w * 4), rows_per_image: Some(*h) },
            Extent3d { width: *w, height: *h, depth_or_array_layers: 1 },
        );
    }
    texture.create_view(&TextureViewDescriptor::default())
}

/// Texels a side of the baked leaf mask (`leaf_texture`).
const LEAF_RES: u32 = 256;

/// `noise_hash` in render2.wgsl, in the same f32 steps.
fn noise_hash(x: f32, y: f32) -> f32 {
    let fract = |v: f32| v - v.floor();
    let (mut a, mut b, mut c) = (fract(x * 0.1031), fract(y * 0.1031), fract(x * 0.1031));
    let d = a * (b + 33.33) + b * (c + 33.33) + c * (a + 33.33);
    (a, b, c) = (a + d, b + d, c + d);
    fract((a + b) * c)
}

/// The leaf card's cut-out (`leaf_mask` as it was in render2.wgsl: a
/// jittered grid of rotated ellipses inside a ragged disc), worked out once
/// here instead of for every leaf pixel in every pass: red is covered,
/// green the leaf's own brightness from 0.7 (0) to 1.3 (255). It was the
/// biggest cost of the frame, mostly in the sun's shadow map.
// 6.2832, not TAU: the shader's numbers, so the leaves keep their shapes.
#[allow(clippy::approx_constant)]
fn leaf_texture(device: &Device, queue: &Queue) -> TextureView {
    let n = LEAF_RES as usize;
    let mut px = vec![0u8; n * n * 4];
    for row in 0..n {
        for col in 0..n {
            let (u, v) = ((col as f32 + 0.5) / n as f32, (row as f32 + 0.5) / n as f32);
            let ragged = 0.47 - 0.07 * noise_hash((u * 9.0).floor() + 17.0, (v * 9.0).floor() + 17.0);
            if ((u - 0.5).powi(2) + (v - 0.5).powi(2)).sqrt() > ragged {
                continue;
            }
            let (px_u, px_v) = (u * 7.0, v * 7.0);
            let (cu, cv) = (px_u.floor(), px_v.floor());
            let mut best = None;
            for x in -1..=1 {
                for y in -1..=1 {
                    let (gx, gy) = (cu + x as f32, cv + y as f32);
                    let h1 = noise_hash(gx, gy);
                    let h2 = noise_hash(gx + 31.7, gy + 31.7);
                    let (ex, ey) = (gx + 0.5 + (h1 - 0.5) * 0.8, gy + 0.5 + (h2 - 0.5) * 0.8);
                    let a = noise_hash(gx + 71.3, gy + 71.3) * 6.2832;
                    let (dx, dy) = (px_u - ex, px_v - ey);
                    let (rx, ry) = (dx * a.cos() + dy * a.sin(), -dx * a.sin() + dy * a.cos());
                    if (rx / 0.46).powi(2) + (ry / 0.24).powi(2) < 1.0 {
                        best = Some(h2);
                    }
                }
            }
            if let Some(h2) = best {
                let at = (row * n + col) * 4;
                px[at] = 255;
                px[at + 1] = (h2 * 255.0).round() as u8;
                px[at + 3] = 255;
            }
        }
    }
    atlas_texture(device, queue, "leaf mask", &[(LEAF_RES, LEAF_RES, px)])
}

/// The cars' texture atlas on the GPU (one white pixel when the game has none).
struct CarGpu {
    rev: u64,
    atlas: TextureView,
}

impl CarGpu {
    fn new(device: &Device, queue: &Queue, atlas: Option<&(u64, Vec<Mip>)>) -> Self {
        let pixel = [(1, 1, vec![255u8; 4])];
        let mips = atlas.map_or(&pixel[..], |(_, m)| &m[..]);
        Self { rev: atlas.map_or(0, |(rev, _)| *rev), atlas: atlas_texture(device, queue, "atlas", mips) }
    }
}

/// One square of sun depth: its side and depth range in metres, and how far
/// ahead of the camera its centre sits (as a fraction of the side).
#[derive(Clone, Copy)]
struct Cascade {
    size: f32,
    depth: f32,
    ahead: f32,
    /// The square moves in steps this big (metres); 0 means one texel.
    step: f32,
}

impl Cascade {
    fn texel(self) -> f32 {
        self.size / crate::render::SHADOW_RES as f32
    }
}

/// 150 m at 4096 texels: 3.7 cm a texel round the player. It moves in steps
/// of 8 m (a whole number of texels), so what stands still in it can be
/// drawn once and kept (`State::near_static`).
const NEAR_CASCADE: Cascade = Cascade { size: 150.0, depth: 800.0, ahead: 0.3, step: 8.0 };
/// 1400 m round the camera at 34 cm a texel, moving in 200 m steps so it can
/// be drawn once and reused while the camera stays near.
const FAR_CASCADE: Cascade = Cascade { size: 1400.0, depth: 2400.0, ahead: 0.0, step: 200.0 };

/// The sun's view of one cascade, snapped to whole texels so edges don't crawl
/// as the camera moves.
fn cascade(eng: &crate::engine::Engine, c: Cascade, sun: Vec3) -> Mat4 {
    let cam = &eng.camera;
    let mut forward = cam.target - cam.eye;
    forward.y = 0.0;
    let mut focus = cam.eye + forward.norm() * (c.size * c.ahead);
    focus.y = 0.0;
    let toward = sun.norm();
    let up = if toward.y.abs() > 0.99 { Vec3 { x: 0.0, y: 0.0, z: 1.0 } } else { Vec3::UP };
    let r = (-toward).cross(up).norm();
    let u = r.cross(-toward);
    // The centre on a grid in the sun's frame (all three axes), built from
    // the grid alone so the matrix is bit-for-bit the same while the camera
    // stays in one cell: edges don't crawl, and a cached cascade stays valid.
    let texel = if c.step > 0.0 { (c.step / c.texel()).round().max(1.0) * c.texel() } else { c.texel() };
    let grid = |a: f32| (a / texel).floor() * texel;
    let focus = r * grid(focus.dot(r)) + u * grid(focus.dot(u)) + toward * grid(focus.dot(toward));
    let view = Mat4::look_at(focus + sun * (c.depth * 0.5), focus, up);
    let h = c.size * 0.5;
    Mat4::ortho(-h, h, -h, h, 0.0, c.depth) * view
}

fn extent((width, height): (u32, u32)) -> Extent3d {
    Extent3d { width, height, depth_or_array_layers: 1 }
}

fn texture(device: &Device, label: &str, size: Extent3d, format: TextureFormat, usage: TextureUsages) -> Texture {
    device.create_texture(&TextureDescriptor {
        label: Some(label),
        size,
        mip_level_count: 1,
        sample_count: 1,
        dimension: TextureDimension::D2,
        format,
        usage,
        view_formats: &[],
    })
}

fn buffer(device: &Device, label: &str, contents: &[u8], usage: BufferUsages) -> Buffer {
    device.create_buffer_init(&util::BufferInitDescriptor { label: Some(label), contents, usage })
}

struct ImagePipeline<'a> {
    vertex: &'a str,
    fragment: &'a str,
    inputs: &'a [VertexBufferLayout<'a>],
    layout: Option<&'a PipelineLayout>,
    depth_write: Option<bool>,
    blend: Option<BlendState>,
    format: TextureFormat,
}

impl ImagePipeline<'_> {
    fn create(self, device: &Device, shader: &ShaderModule) -> RenderPipeline {
        device.create_render_pipeline(&RenderPipelineDescriptor {
            label: Some(self.vertex),
            layout: self.layout,
            vertex: VertexState {
                module: shader,
                entry_point: Some(self.vertex),
                compilation_options: PipelineCompilationOptions::default(),
                buffers: self.inputs,
            },
            fragment: Some(FragmentState {
                module: shader,
                entry_point: Some(self.fragment),
                compilation_options: PipelineCompilationOptions::default(),
                targets: &[Some(ColorTargetState { format: self.format, blend: self.blend, write_mask: ColorWrites::ALL })],
            }),
            primitive: PrimitiveState::default(),
            depth_stencil: self.depth_write.map(|write| DepthStencilState {
                format: DEPTH,
                depth_write_enabled: Some(write),
                depth_compare: Some(CompareFunction::LessEqual),
                stencil: StencilState::default(),
                bias: DepthBiasState::default(),
            }),
            multisample: MultisampleState::default(),
            multiview_mask: None,
            cache: None,
        })
    }
}

struct DrawMesh {
    vertices: Buffer,
    surface: Option<Buffer>,
    indices: Buffer,
    count: u32,
}

#[derive(Clone, Copy, Default, PartialEq, Eq)]
pub enum Upscale {
    #[default]
    Bilinear,
    Easu,
    EasuRcas,
}

impl std::str::FromStr for Upscale {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "bilinear" => Ok(Self::Bilinear),
            "easu" => Ok(Self::Easu),
            "easu-rcas" => Ok(Self::EasuRcas),
            _ => Err("--upscale expects bilinear, easu or easu-rcas".into()),
        }
    }
}

impl Upscale {
    fn name(self) -> &'static str {
        match self {
            Self::Bilinear => "bilinear",
            Self::Easu => "easu",
            Self::EasuRcas => "easu-rcas",
        }
    }
}

/// What the renderer is set up for. Changing any of it means a new renderer.
#[derive(Clone)]
pub struct Settings {
    /// The 3D scene's size, and the image's (HUD and final size).
    pub internal: (u32, u32),
    pub output: (u32, u32),
    pub upscale: Upscale,
    pub material_pack: Option<std::path::PathBuf>,
    pub hdr: bool,
}

/// One frame's numbers, for the postcard line and the profiler.
#[derive(Default, Clone, Copy)]
pub struct Stats {
    pub draws: usize,
    pub in_view: usize,
    pub textured_meshes: usize,
}

struct Gpu {
    device: Device,
    queue: Queue,
    info: AdapterInfo,
    queries: bool,
}

struct CachedMesh {
    rev: u32,
    mesh: DrawMesh,
    bounds: (Vec3, f32),
    /// Its sun depth needs the texture coordinates: leaves and skinned
    /// people are cut out in the fragment stage, limbs swing in the vertex
    /// stage. Everything else (windows, buildings, cars...) takes the plain
    /// depth pipeline, which has no fragment stage at all: far cheaper.
    shadow_uv: bool,
}

/// Whether a mesh's sun depth needs its texture coordinates (`CachedMesh::shadow_uv`).
fn shadow_needs_uv(surfaces: &[crate::mesh::ObjSurface]) -> bool {
    const LEAF: u32 = 5;
    const SKINNED: u32 = 0x8000_0000;
    surfaces.iter().any(|s| s.role == LEAF || s.role & SKINNED != 0 || (7..=12).contains(&s.role))
}

/// Everything built from the device, the settings and one engine: pipelines,
/// render targets, materials. Rebuilt when the engine is (a reload).
struct State {
    shader: ShaderModule,
    sampler: Sampler,
    /// The output image drawn onto a window's surface, per surface format.
    present: Option<(TextureFormat, RenderPipeline, BindGroup)>,
    spatial_shader: Option<ShaderModule>,
    world_group_layout: BindGroupLayout,
    material_group: BindGroup,
    material_ground: [f32; 4],
    shadow_texture: Texture,
    shadow_layers: [TextureView; 3],
    shadow_group: BindGroup,
    shadow: RenderPipeline,
    shadow_uv: RenderPipeline,
    shadow_far: RenderPipeline,
    shadow_uv_far: RenderPipeline,
    sky: RenderPipeline,
    opaque: RenderPipeline,
    alpha: RenderPipeline,
    opaque_uv: RenderPipeline,
    alpha_uv: RenderPipeline,
    scene_view: TextureView,
    depth_view: TextureView,
    tonemapped: Option<TextureView>,
    occlusion: Option<(TextureView, RenderPipeline, BindGroup, BindGroup)>,
    /// The tone map pass: pipeline, its images, the scene's depth, the scene constants.
    tone_map: Option<(RenderPipeline, BindGroup, BindGroup, BindGroup)>,
    blit: Option<(RenderPipeline, BindGroup)>,
    hud: RenderPipeline,
    output_texture: Texture,
    output_view: TextureView,
    easu_intermediate: Option<TextureView>,
    scene_uniform: Buffer,
    /// Per-object constants, one aligned slot each; grows as needed.
    objects: Buffer,
    object_slots: usize,
    /// What the far cascade was last drawn from; unchanged means reuse it.
    far_drawn: Option<u64>,
    /// What the cached still part of the near cascade (STATIC_LAYER) holds,
    /// and the camera position its draw distances were judged from.
    near_static: Option<u64>,
    static_eye: Vec3,
    /// The sun direction the shadows were last drawn for (`SUN_STEP_COS`).
    shadow_sun: Option<Vec3>,
    /// By entity slot: its last `pose_key` and how many frames since it changed.
    motion: Vec<(u64, u32)>,
    /// How many frames redrew the cached near layer (for the FLY bench).
    still_redraws: u64,
    world_group: BindGroup,
    humans: HumanGpu,
    cars: CarGpu,
    /// The prop atlas (shop signs, tram livery); the same kind of texture.
    props: CarGpu,
    /// The leaf cards' cut-out, baked once (`leaf_texture`).
    leaves: TextureView,
    /// This frame's lamp grid (`Lamps`).
    lamps: Buffer,
    timestamps: Option<QuerySet>,
    /// Which pass boundaries this frame stamped (`STAMPS`): AO and the tone
    /// map are optional passes.
    stamped: [bool; STAMPS as usize],
}

/// One entity to draw this frame: (mesh, entity, in view, within its draw
/// distances, a far-cascade caster, a cached near caster, its slot).
type Draw<'a> = (usize, &'a crate::engine::Entity, bool, bool, bool, bool, usize);

/// GPU timestamps a frame: 0 start, 1 end, then the ends of the near sun
/// shadows, the world, AO and the tone map, for `gpu_stages`.
const STAMPS: u32 = 6;
const STAGE_NAMES: [&str; 5] = ["shadows", "world", "ao", "tonemap", "output"];

/// The wgpu renderer: device, pipelines and uploaded meshes kept from frame
/// to frame. `postcard` renders one frame of it to a file.
pub struct Renderer2 {
    gpu: Gpu,
    settings: Settings,
    epoch: u64,
    state: State,
    meshes: HashMap<usize, CachedMesh>,
}

const OBJECT_SIZE: u64 = size_of::<Object>() as u64;

impl Renderer2 {
    /// A renderer on the best adapter, compatible with `surface` if given.
    pub fn new(eng: &Engine, settings: Settings, instance: &Instance, surface: Option<&Surface<'_>>) -> Result<Self, String> {
        let s = &settings;
        if s.upscale != Upscale::Bilinear && (s.internal == s.output || s.internal.0 > s.output.0 || s.internal.1 > s.output.1) {
            return Err("--upscale easu and easu-rcas require a smaller internal scene".into());
        }
        let adapter = pollster::block_on(instance.request_adapter(&RequestAdapterOptions {
            power_preference: PowerPreference::HighPerformance,
            compatible_surface: surface,
            ..Default::default()
        }))
        .map_err(|e| e.to_string())?;
        let info = adapter.get_info();
        let queries = adapter.features().contains(Features::TIMESTAMP_QUERY);
        let limits = Limits::default().using_resolution(adapter.limits());
        for side in [s.internal.0, s.internal.1, s.output.0, s.output.1] {
            if !(1..=limits.max_texture_dimension_2d).contains(&side) {
                return Err(format!("image side {side} outside device limits 1..={}", limits.max_texture_dimension_2d));
            }
        }
        let (device, queue) = pollster::block_on(adapter.request_device(&DeviceDescriptor {
            required_features: if queries { Features::TIMESTAMP_QUERY } else { Features::empty() },
            required_limits: limits,
            ..Default::default()
        }))
        .map_err(|e| e.to_string())?;
        let gpu = Gpu { device, queue, info, queries };
        let state = State::new(&gpu, &settings, eng)?;
        Ok(Self { gpu, settings, epoch: eng.epoch, state, meshes: HashMap::new() })
    }

    pub fn device(&self) -> &Device {
        &self.gpu.device
    }

    pub fn adapter_info(&self) -> &AdapterInfo {
        &self.gpu.info
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    /// New sizes (the window changed): targets follow, meshes stay.
    pub fn resize(&mut self, eng: &Engine, internal: (u32, u32), output: (u32, u32)) -> Result<(), String> {
        self.settings.internal = internal;
        self.settings.output = output;
        self.state = State::new(&self.gpu, &self.settings, eng)?;
        Ok(())
    }

    /// Draw the frame's output image onto a window's surface texture.
    pub fn present_onto(&mut self, encoder: &mut CommandEncoder, target: &TextureView, format: TextureFormat) {
        let st = &mut self.state;
        if st.present.as_ref().map(|p| p.0) != Some(format) {
            let (pipeline, group) =
                full_screen(&self.gpu.device, &st.shader, &st.sampler, "blit_fragment", &st.output_view, format, "output onto the window");
            st.present = Some((format, pipeline, group));
        }
        let (_, pipeline, group) = st.present.as_ref().expect("present pipeline");
        let mut pass = encoder.begin_render_pass(&RenderPassDescriptor {
            label: Some("onto the window"),
            color_attachments: &[Some(attachment(target, LoadOp::Clear(Color::BLACK)))],
            ..Default::default()
        });
        pass.set_pipeline(pipeline);
        pass.set_bind_group(0, group, &[]);
        pass.draw(0..3, 0..1);
    }

    /// How many frames so far redrew the cached still part of the near sun depth.
    pub fn still_redraws(&self) -> u64 {
        self.state.still_redraws
    }

    /// Submit a frame and wait for its GPU time, in total and by stage
    /// (`STAGE_NAMES`; a stage whose pass didn't run is 0).
    pub fn gpu_stages(&self, mut encoder: CommandEncoder) -> Result<Option<(f64, [f64; 5])>, String> {
        let Some(queries) = &self.state.timestamps else {
            self.submit(encoder);
            return Ok(None);
        };
        let device = &self.gpu.device;
        let bytes = 8 * STAMPS as u64;
        let resolve = device.create_buffer(&BufferDescriptor {
            label: Some("timestamp resolve"),
            size: bytes,
            usage: BufferUsages::QUERY_RESOLVE | BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        let read = device.create_buffer(&BufferDescriptor {
            label: Some("timestamp read"),
            size: bytes,
            usage: BufferUsages::COPY_DST | BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.resolve_query_set(queries, 0..STAMPS, &resolve, 0);
        encoder.copy_buffer_to_buffer(&resolve, 0, &read, 0, bytes);
        let submission = self.gpu.queue.submit([encoder.finish()]);
        let slice = read.slice(..);
        slice.map_async(MapMode::Read, |_| {});
        device
            .poll(PollType::Wait { submission_index: Some(submission), timeout: Some(Duration::from_secs(30)) })
            .map_err(|e| e.to_string())?;
        let data = slice.get_mapped_range();
        let stamp = |i: usize| u64::from_le_bytes(data[i * 8..i * 8 + 8].try_into().unwrap());
        let ms = |a: u64, b: u64| b.saturating_sub(a) as f64 * self.gpu.queue.get_timestamp_period() as f64 / 1e6;
        // Boundaries in frame order: start, shadows, world, AO, tone map, end.
        let order = [0usize, 2, 3, 4, 5, 1];
        let mut stages = [0.0; 5];
        let mut last = stamp(0);
        for (stage, &slot) in order[1..].iter().enumerate() {
            if self.state.stamped[slot] {
                stages[stage] = ms(last, stamp(slot));
                last = stamp(slot);
            }
        }
        Ok(Some((ms(stamp(0), stamp(1)), stages)))
    }

    pub fn submit(&self, encoder: CommandEncoder) {
        self.gpu.queue.submit([encoder.finish()]);
    }

    /// Write the last frame's output image to a PPM file.
    pub fn save_output(&self, path: &Path) -> Result<(), String> {
        let encoder = self.gpu.device.create_command_encoder(&CommandEncoderDescriptor::default());
        save_ppm(&self.gpu.device, &self.gpu.queue, encoder, self.output(), None, path).map(|_| ())
    }

    /// The frame's output image (output size, `COLOR`), with the HUD on it.
    pub fn output(&self) -> &Texture {
        &self.state.output_texture
    }

    /// Encode one frame of `eng` into the output image. Nothing is submitted.
    pub fn encode(&mut self, eng: &Engine) -> Result<(CommandEncoder, Stats), String> {
        if eng.epoch != self.epoch {
            // A reload: a new engine with new meshes and maybe new terrain.
            self.state = State::new(&self.gpu, &self.settings, eng)?;
            self.meshes.clear();
            self.epoch = eng.epoch;
        }
        let (device, queue) = (&self.gpu.device, &self.gpu.queue);
        let st = &mut self.state;
        let car_rev = eng.car_atlas.as_ref().map_or(0, |(rev, _)| *rev);
        let prop_rev = eng.prop_atlas.as_ref().map_or(0, |(rev, _)| *rev);
        if eng.humans.as_ref().map_or(0, |h| h.rev) != st.humans.rev || car_rev != st.cars.rev || prop_rev != st.props.rev {
            st.humans = HumanGpu::new(device, queue, eng.humans.as_ref());
            st.cars = CarGpu::new(device, queue, eng.car_atlas.as_ref());
            st.props = CarGpu::new(device, queue, eng.prop_atlas.as_ref());
            st.world_group = world_group(
                device,
                &st.world_group_layout,
                &st.scene_uniform,
                &st.objects,
                &st.humans,
                &st.cars,
                &st.props,
                &st.leaves,
                &st.lamps,
            );
        }
        let settings = &self.settings;
        let (internal, output) = (settings.internal, settings.output);
        let spatial = settings.upscale != Upscale::Bilinear;
        let camera = &eng.camera;
        let env = if eng.view_layer == 0 { eng.env.clone() } else { eng.env.indoors() };
        let v4 = |p: Vec3| [p.x, p.y, p.z, 0.0];
        let c4 = |p: [f32; 3]| [p[0], p[1], p[2], 1.0];
        let aspect = output.0 as f32 / output.1 as f32;
        let projection = Mat4::perspective(camera.fov, aspect, 0.25, env.fog_end + 50.0);
        let draw_shadows = env.shadows && env.sun.y > 0.05;
        let forward = (camera.target - camera.eye).norm();
        let right = forward.cross(Vec3::UP).norm();
        let spread = (camera.fov * 0.5).tan();
        // The sun's direction for the shadows moves in small steps (its
        // course over a game day is smooth), so the cached sun depth below is
        // redrawn about once a second, not every frame.
        let sun = match st.shadow_sun {
            // (The game's sun needn't be of unit length.)
            Some(held) if held.norm().dot(env.sun.norm()) >= SUN_STEP_COS => held,
            _ => env.sun,
        };
        st.shadow_sun = Some(sun);
        let light_projection = cascade(eng, NEAR_CASCADE, sun);
        let light_far = cascade(eng, FAR_CASCADE, sun);
        let scene = Scene {
            view_projection: (projection * Mat4::look_at(camera.eye, camera.target, Vec3::UP)).0,
            eye: v4(camera.eye),
            fog: [env.fog_start, env.fog_end, env.glow, if draw_shadows { 1.0 } else { 0.0 }],
            sky: c4(env.sky),
            sun: v4(env.sun),
            sun_color: c4(env.sun_color),
            ambient: c4(env.ambient),
            bounce: c4(env.ground),
            light_projection: light_projection.0,
            camera_forward: v4(forward),
            camera_right: v4(right * (spread * aspect)),
            camera_up: v4(right.cross(forward) * spread),
            sky_top: c4(env.sky_top),
            material_ground: st.material_ground,
            // y, z: the projection's near and far planes, for the AO pass.
            post: [if settings.hdr { 1.0 } else { 0.0 }, 0.25, env.fog_end + 50.0, 0.0],
            light_far: light_far.0,
            cascades: [NEAR_CASCADE.depth, FAR_CASCADE.depth, NEAR_CASCADE.texel(), FAR_CASCADE.texel()],
            lamp_grid: [0.0; 4],
            weather: [env.wet, env.rain, (eng.time % 3600.0) as f32, env.cloud],
        };
        let mut scene = scene;
        let mut lamps = Lamps::zeroed();
        let (grid, lit) = lamp_grid(eng, &env, camera.eye, forward, settings.hdr, &mut lamps);
        scene.lamp_grid = grid;
        if lit > 0 {
            queue.write_buffer(&st.lamps, 0, bytes_of(&lamps));
        }
        queue.write_buffer(&st.scene_uniform, 0, bytes_of(&scene));

        // Meshes go up once, and again only when the engine replaces them
        // (by mesh, not by entity: a city has many entities a mesh).
        for (key, mesh) in eng.meshes.iter().enumerate() {
            let rev = eng.mesh_revs.get(key).copied().unwrap_or(0);
            if self.meshes.get(&key).is_some_and(|c| c.rev == rev) {
                continue;
            }
            if mesh.indices.is_empty() {
                self.meshes.remove(&key);
                continue;
            }
            let draw = DrawMesh {
                vertices: buffer(device, "mesh vertices", cast_slice(&mesh.verts), BufferUsages::VERTEX),
                // Texture coordinates go up for every OBJ that has them: the
                // material pack needs them, and leaf cards are cut out with or
                // without it.
                surface: (mesh.obj_surfaces.len() == mesh.verts.len())
                    .then(|| buffer(device, "OBJ texture coordinates", cast_slice(&mesh.obj_surfaces), BufferUsages::VERTEX)),
                indices: buffer(device, "mesh indices", cast_slice(&mesh.indices), BufferUsages::INDEX),
                count: mesh.indices.len() as u32,
            };
            let shadow_uv = draw.surface.is_some() && shadow_needs_uv(&mesh.obj_surfaces);
            self.meshes.insert(key, CachedMesh { rev, mesh: draw, bounds: crate::render::mesh_bounds(mesh), shadow_uv });
        }

        // Cull: each entity's draw distances (near/far LOD), then the camera's
        // view for the colour pass. Casters outside the view still go to the
        // sun's depth, so shadows reaching into view stay. The far shadow
        // cascade (34 cm a texel) takes only what has no far limit (the far
        // buildings, tree cards and coarse ground; buildings on a map without
        // far versions), at every distance; whatever stops being drawn at
        // some distance (full trees, furniture, cars, people) casts in the
        // near cascade only. Each draw: (mesh, entity, in view, within its
        // draw distances, a far-cascade caster).
        let view_projection = Mat4(scene.view_projection);
        let meshes = &self.meshes;
        let plane = eng.mesh_ids.get("plane").copied();

        // Each entity's bounds in the world (None: nothing to draw), once.
        let bounds: Vec<Option<(Vec3, f32)>> = eng
            .ents
            .iter()
            .map(|e| {
                let e = e.as_ref()?;
                let cached = meshes.get(&e.mesh?)?;
                Some(crate::render::world_bounds(cached.bounds.0, cached.bounds.1, e.pos, e.rot, e.scale))
            })
            .collect();
        // What moves: by entity slot, frames since its mesh or pose changed.
        st.motion.resize(eng.ents.len(), (0, 0));
        for (slot, motion) in eng.ents.iter().zip(st.motion.iter_mut()) {
            let Some((e, key)) = slot.as_ref().and_then(|e| Some((e, e.mesh?))) else {
                *motion = (0, 0);
                continue;
            };
            let Some(cached) = meshes.get(&key) else {
                *motion = (0, 0);
                continue;
            };
            let pose = pose_key(e, key, cached.rev);
            *motion = match *motion {
                // Newly seen (spawned, streamed in): still from the start.
                (0, _) => (pose, STILL_FRAMES),
                (was, still) if was == pose => (pose, still.saturating_add(1)),
                _ => (pose, 0),
            };
        }
        // The near cascade's still casters, judged from `eye`: their slots
        // and a fingerprint of the lot with the cascade's square and sun.
        let near_light = light_projection;
        let in_near = |center: Vec3, radius: f32| {
            let m = &near_light.0;
            let px = m[0] * center.x + m[4] * center.y + m[8] * center.z + m[12];
            let py = m[1] * center.x + m[5] * center.y + m[9] * center.z + m[13];
            let reach = 1.0 + radius / (NEAR_CASCADE.size * 0.5);
            px.abs() <= reach && py.abs() <= reach
        };
        let motion = &st.motion;
        let still_casters = |eye: Vec3| {
            let mut h = 0x9e37_79b9_7f4a_7c15u64 ^ u64::from(draw_shadows);
            for f in near_light.0.iter().chain(&[sun.x, sun.y, sun.z]) {
                h = (h ^ u64::from(f.to_bits())).wrapping_mul(0x0100_0000_01b3);
            }
            let mut slots = vec![false; eng.ents.len()];
            for (i, e) in eng.ents.iter().enumerate() {
                let (Some(e), Some((center, radius))) = (e, bounds[i]) else { continue };
                let Some(key) = e.mesh else { continue };
                if !(e.visible && e.shadow && e.layer == eng.view_layer && e.color[3] >= 1.0 && Some(key) != plane)
                    || motion[i].1 < STILL_FRAMES
                    || MOVERS.contains(&e.tag.as_str())
                {
                    continue;
                }
                if !e.drawn_at((center - eye).len()) || !in_near(center, radius) {
                    continue;
                }
                slots[i] = true;
                h = (h ^ i as u64).wrapping_mul(0x0100_0000_01b3) ^ motion[i].0;
            }
            (h, slots)
        };
        let (mut still_key, mut still) = still_casters(st.static_eye);
        let redraw_still = draw_shadows && st.near_static != Some(still_key);
        if redraw_still {
            st.still_redraws += 1;
            // Judge draw distances from here until the next redraw.
            (still_key, still) = still_casters(camera.eye);
            st.static_eye = camera.eye;
        }
        st.near_static = draw_shadows.then_some(still_key);

        // Cull: each entity's draw distances (near/far LOD), then the camera's
        // view for the colour pass. Casters outside the view still go to the
        // sun's depth. The near cascade's still casters are drawn once into
        // their cached layer (and only listed here when that is redrawn);
        // what moves is drawn into the near cascade every frame. Each draw:
        // (mesh, entity, in view, within its draw distances, a far-cascade
        // caster, a cached near caster, its slot).
        let mut draws: Vec<_> = eng
            .ents
            .iter()
            .enumerate()
            .filter_map(|(i, e)| {
                let e = e.as_ref()?;
                let key = e.mesh?;
                let (center, radius) = bounds[i]?;
                if !e.visible || e.layer != eng.view_layer {
                    return None;
                }
                let distance = (center - camera.eye).len();
                let drawn = e.drawn_at(distance);
                let far_caster = e.far <= 0.0 && distance < FAR_CASCADE.size + radius;
                let cached_caster = still[i];
                if !drawn && !far_caster && !(redraw_still && cached_caster) {
                    return None;
                }
                let in_view = drawn && crate::render::sphere_visible(&view_projection, camera.eye, center, radius, env.fog_end);
                Some((key, e, in_view, drawn, far_caster, cached_caster, i))
            })
            .collect();
        draws.sort_by(|(_, a, ..), (_, b, ..)| {
            (a.color[3] < 1.0).cmp(&(b.color[3] < 1.0)).then_with(|| (b.pos - camera.eye).len().total_cmp(&(a.pos - camera.eye).len()))
        });

        let step = object_step(device);
        if draws.len() > st.object_slots {
            st.object_slots = draws.len().next_power_of_two();
            let total = step.checked_mul(st.object_slots as u64).ok_or("too many draw objects")?;
            if total > device.limits().max_buffer_size || total > u64::from(u32::MAX) {
                return Err("object uniform buffer exceeds device limits".into());
            }
            st.objects = device.create_buffer(&BufferDescriptor {
                label: Some("object constants"),
                size: total,
                usage: BufferUsages::UNIFORM | BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            st.world_group = world_group(
                device,
                &st.world_group_layout,
                &st.scene_uniform,
                &st.objects,
                &st.humans,
                &st.cars,
                &st.props,
                &st.leaves,
                &st.lamps,
            );
        }
        if !draws.is_empty() {
            let mut packed = vec![0; step as usize * draws.len()];
            for (index, &(_, entity, ..)) in draws.iter().enumerate() {
                let offset = index * step as usize;
                packed[offset..offset + OBJECT_SIZE as usize].copy_from_slice(bytes_of(&Object::new(entity, eng.humans.as_ref())));
            }
            queue.write_buffer(&st.objects, 0, &packed);
        }

        let mut encoder = device.create_command_encoder(&CommandEncoderDescriptor::default());
        // Pass boundaries for `gpu_stages`: 0 and 2 (near sun shadows), 1 (the
        // end) are always stamped; the world, AO and tone map ends when run.
        st.stamped = [true, true, true, false, false, false];
        st.stamped[3] = st.timestamps.is_some();
        st.stamped[4] = st.timestamps.is_some() && st.occlusion.is_some();
        st.stamped[5] = st.timestamps.is_some() && st.tone_map.is_some() && st.tonemapped.is_some();
        let queries = st.timestamps.clone();
        let stamp = |slot: u32| {
            queries.as_ref().map(|query_set| RenderPassTimestampWrites {
                query_set,
                beginning_of_pass_write_index: None,
                end_of_pass_write_index: Some(slot),
            })
        };
        // Sun depth: a sharp near cascade round the camera, and the whole
        // visible city at a coarser texel so far streets get shadows too.
        // The far cascade sits still (it moves in 200 m steps), so it is drawn
        // again only when what it sees changes: the sun, its square, or any
        // caster's mesh, place or size.
        let far_key = {
            use std::hash::{Hash, Hasher};
            let mut h = std::collections::hash_map::DefaultHasher::new();
            draw_shadows.hash(&mut h);
            for f in scene.light_far.iter().chain(&[sun.x, sun.y, sun.z]) {
                f.to_bits().hash(&mut h);
            }
            for &(key, e, ..) in draws.iter().filter(|d| d.4) {
                (key, meshes[&key].rev, e.shadow, e.color[3] >= 1.0).hash(&mut h);
                for f in [e.pos.x, e.pos.y, e.pos.z, e.scale.x, e.scale.y, e.scale.z, e.rot.x, e.rot.y, e.rot.z, e.rot.w] {
                    f.to_bits().hash(&mut h);
                }
            }
            h.finish()
        };
        let redraw_far = draw_shadows && st.far_drawn != Some(far_key);
        st.far_drawn = draw_shadows.then_some(far_key);
        // One pass of sun depth into `layer` of the draws `keep` picks.
        let casters = |encoder: &mut CommandEncoder,
                       layer: u32,
                       clear: bool,
                       stamps: Option<RenderPassTimestampWrites<'_>>,
                       keep: &dyn Fn(&Draw) -> bool| {
            let mut pass = encoder.begin_render_pass(&RenderPassDescriptor {
                label: Some(["sun shadows, near", "sun shadows, far", "sun shadows, near, still"][layer as usize]),
                depth_stencil_attachment: Some(RenderPassDepthStencilAttachment {
                    view: &st.shadow_layers[layer as usize],
                    depth_ops: Some(Operations { load: if clear { LoadOp::Clear(1.0) } else { LoadOp::Load }, store: StoreOp::Store }),
                    stencil_ops: None,
                }),
                timestamp_writes: stamps,
                ..Default::default()
            });
            if !draw_shadows {
                return;
            }
            let (plain, cut_out) = if layer == 1 { (&st.shadow_far, &st.shadow_uv_far) } else { (&st.shadow, &st.shadow_uv) };
            for with_uv in [false, true] {
                pass.set_pipeline(if with_uv { cut_out } else { plain });
                for (index, draw) in draws.iter().enumerate() {
                    let &(key, entity, ..) = draw;
                    let cached = &meshes[&key];
                    if !(entity.shadow && entity.color[3] >= 1.0 && Some(key) != plane && cached.shadow_uv == with_uv) || !keep(draw) {
                        continue;
                    }
                    if let (true, Some(surface)) = (with_uv, &cached.mesh.surface) {
                        pass.set_vertex_buffer(1, surface.slice(..));
                    }
                    draw_mesh(&mut pass, &st.world_group, (index as u64 * step) as u32, &cached.mesh);
                }
            }
        };
        let begin = |stamped: &mut bool| {
            let first = !*stamped;
            *stamped = true;
            queries.as_ref().filter(|_| first).map(|query_set| RenderPassTimestampWrites {
                query_set,
                beginning_of_pass_write_index: Some(0),
                end_of_pass_write_index: None,
            })
        };
        let mut started = false;
        if redraw_still {
            casters(&mut encoder, STATIC_LAYER, true, begin(&mut started), &|d| d.5);
        }
        if redraw_far {
            // Walkers move every frame: near shadows only, so the far cascade
            // can stay cached (they have draw distances, so aren't far casters
            // anyway).
            casters(&mut encoder, 1, true, begin(&mut started), &|d| d.4 && d.1.tag != "walker");
        }
        if draw_shadows {
            if !started && queries.is_some() {
                // An empty pass to stamp the start, so the copy is timed too.
                casters(&mut encoder, STATIC_LAYER, false, begin(&mut started), &|_| false);
            }
            let side = st.shadow_texture.width();
            let layer = |z| TexelCopyTextureInfo {
                texture: &st.shadow_texture,
                mip_level: 0,
                origin: Origin3d { x: 0, y: 0, z },
                aspect: TextureAspect::All,
            };
            encoder.copy_texture_to_texture(
                layer(STATIC_LAYER),
                layer(NEAR_LAYER),
                Extent3d { width: side, height: side, depth_or_array_layers: 1 },
            );
        }
        // What moves, on top of the copy: drawn this frame, in the square,
        // and not in the cached layer.
        let stamps = queries.as_ref().map(|query_set| RenderPassTimestampWrites {
            query_set,
            beginning_of_pass_write_index: (!started).then_some(0),
            end_of_pass_write_index: Some(2),
        });
        casters(&mut encoder, NEAR_LAYER, !draw_shadows, stamps, &|&(.., drawn, _, cached_caster, slot)| {
            drawn && !cached_caster && bounds[slot].is_some_and(|(c, r)| in_near(c, r))
        });
        {
            let mut pass = encoder.begin_render_pass(&RenderPassDescriptor {
                label: Some("world at internal resolution"),
                color_attachments: &[Some(attachment(&st.scene_view, LoadOp::Clear(Color::BLACK)))],
                depth_stencil_attachment: Some(depth_attachment(&st.depth_view)),
                timestamp_writes: stamp(3),
                ..Default::default()
            });
            pass.set_pipeline(&st.sky);
            pass.set_bind_group(0, &st.world_group, &[0]);
            pass.draw(0..3, 0..1);
            pass.set_pipeline(&st.opaque);
            pass.set_bind_group(1, &st.shadow_group, &[]);
            pass.set_bind_group(2, &st.material_group, &[]);
            let mut current = (true, false);
            for (index, &(key, entity, in_view, ..)) in draws.iter().enumerate() {
                if !in_view {
                    continue;
                }
                let mesh = &meshes[&key].mesh;
                let required = (entity.color[3] >= 1.0, mesh.surface.is_some());
                if required != current {
                    pass.set_pipeline(match required {
                        (true, false) => &st.opaque,
                        (false, false) => &st.alpha,
                        (true, true) => &st.opaque_uv,
                        (false, true) => &st.alpha_uv,
                    });
                    current = required;
                }
                if let Some(surface) = &mesh.surface {
                    pass.set_vertex_buffer(1, surface.slice(..));
                }
                draw_mesh(&mut pass, &st.world_group, (index as u64 * step) as u32, mesh);
            }
        }
        if let Some((target, pipeline, constants, depth)) = &st.occlusion {
            let mut pass = encoder.begin_render_pass(&RenderPassDescriptor {
                label: Some("ambient occlusion"),
                color_attachments: &[Some(attachment(target, LoadOp::Clear(Color::WHITE)))],
                timestamp_writes: stamp(4),
                ..Default::default()
            });
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, constants, &[]);
            pass.set_bind_group(1, depth, &[]);
            pass.draw(0..3, 0..1);
        }
        if let (Some((pipeline, group, depth, constants)), Some(target)) = (&st.tone_map, &st.tonemapped) {
            let mut pass = encoder.begin_render_pass(&RenderPassDescriptor {
                label: Some("tone map"),
                color_attachments: &[Some(attachment(target, LoadOp::Clear(Color::BLACK)))],
                timestamp_writes: stamp(5),
                ..Default::default()
            });
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, group, &[]);
            pass.set_bind_group(1, depth, &[]);
            pass.set_bind_group(2, constants, &[]);
            pass.draw(0..3, 0..1);
        }
        let presented = st.tonemapped.as_ref().unwrap_or(&st.scene_view);
        if let Some(shader) = &st.spatial_shader {
            if let Some(view) = &st.easu_intermediate {
                compute_spatial(device, &mut encoder, shader, "easu_pass", presented, view, output);
                compute_spatial(device, &mut encoder, shader, "rcas_pass", view, &st.output_view, output);
            } else {
                compute_spatial(device, &mut encoder, shader, "easu_pass", presented, &st.output_view, output);
            }
        }
        let hud = (!eng.hud.is_empty()).then(|| {
            let data: Vec<_> = eng
                .hud
                .as_chunks::<6>()
                .0
                .iter()
                .flat_map(|v| [v[0] / output.0 as f32 * 2.0 - 1.0, 1.0 - v[1] / output.1 as f32 * 2.0, v[2], v[3], v[4], v[5]])
                .collect();
            (buffer(device, "HUD vertices", cast_slice(&data), BufferUsages::VERTEX), data.len() as u32 / 6)
        });
        {
            let load = if spatial { LoadOp::Load } else { LoadOp::Clear(Color::BLACK) };
            let mut pass = encoder.begin_render_pass(&RenderPassDescriptor {
                label: Some("scene and HUD at output resolution"),
                color_attachments: &[Some(attachment(&st.output_view, load))],
                timestamp_writes: st.timestamps.as_ref().map(|query_set| RenderPassTimestampWrites {
                    query_set,
                    beginning_of_pass_write_index: None,
                    end_of_pass_write_index: Some(1),
                }),
                ..Default::default()
            });
            if let Some((pipeline, group)) = &st.blit {
                pass.set_pipeline(pipeline);
                pass.set_bind_group(0, group, &[]);
                pass.draw(0..3, 0..1);
            }
            if let Some((vertices, count)) = &hud {
                pass.set_pipeline(&st.hud);
                pass.set_vertex_buffer(0, vertices.slice(..));
                pass.draw(0..*count, 0..1);
            }
        }
        let _ = internal;
        let stats = Stats {
            draws: draws.iter().filter(|d| d.3).count(),
            in_view: draws.iter().filter(|d| d.2).count(),
            textured_meshes: meshes.values().filter(|c| c.mesh.surface.is_some()).count(),
        };
        Ok((encoder, stats))
    }
}

fn object_step(device: &Device) -> u64 {
    let align = device.limits().min_uniform_buffer_offset_alignment as u64;
    OBJECT_SIZE.div_ceil(align) * align
}

#[allow(clippy::too_many_arguments)]
fn world_group(
    device: &Device,
    layout: &BindGroupLayout,
    scene: &Buffer,
    objects: &Buffer,
    humans: &HumanGpu,
    cars: &CarGpu,
    props: &CarGpu,
    leaves: &TextureView,
    lamps: &Buffer,
) -> BindGroup {
    device.create_bind_group(&BindGroupDescriptor {
        label: Some("scene and objects"),
        layout,
        entries: &[
            BindGroupEntry { binding: 0, resource: scene.as_entire_binding() },
            BindGroupEntry {
                binding: 1,
                resource: BindingResource::Buffer(BufferBinding { buffer: objects, offset: 0, size: BufferSize::new(OBJECT_SIZE) }),
            },
            BindGroupEntry { binding: 2, resource: humans.poses.as_entire_binding() },
            BindGroupEntry { binding: 3, resource: BindingResource::TextureView(&humans.atlas) },
            BindGroupEntry { binding: 4, resource: BindingResource::Sampler(&humans.sampler) },
            BindGroupEntry { binding: 5, resource: BindingResource::TextureView(&cars.atlas) },
            BindGroupEntry { binding: 6, resource: BindingResource::TextureView(&props.atlas) },
            BindGroupEntry { binding: 7, resource: BindingResource::TextureView(leaves) },
            BindGroupEntry { binding: 8, resource: lamps.as_entire_binding() },
        ],
    })
}

impl State {
    fn new(gpu: &Gpu, settings: &Settings, eng: &Engine) -> Result<Self, String> {
        let device = &gpu.device;
        let (internal, output, hdr) = (settings.internal, settings.output, settings.hdr);
        let spatial = settings.upscale != Upscale::Bilinear;
        // The HDR look draws the scene in linear light into a float target, and a
        // tone-mapping pass brings it to the screen before any upscaling.
        let scene_format = if hdr { TextureFormat::Rgba16Float } else { COLOR };
        let (material_layout, material_group, material_ground) =
            crate::postcard_materials::bind(device, &gpu.queue, eng, settings.material_pack.as_deref())?;
        let shader = device.create_shader_module(include_wgsl!("render2.wgsl"));
        let scene_view = texture(
            device,
            "scene colour",
            extent(internal),
            scene_format,
            TextureUsages::RENDER_ATTACHMENT | TextureUsages::TEXTURE_BINDING,
        )
        .create_view(&TextureViewDescriptor::default());
        let tonemapped = hdr.then(|| {
            texture(
                device,
                "tone-mapped colour",
                extent(internal),
                COLOR,
                TextureUsages::RENDER_ATTACHMENT | TextureUsages::TEXTURE_BINDING,
            )
            .create_view(&TextureViewDescriptor::default())
        });
        let depth_view =
            texture(device, "scene depth", extent(internal), DEPTH, TextureUsages::RENDER_ATTACHMENT | TextureUsages::TEXTURE_BINDING)
                .create_view(&TextureViewDescriptor::default());
        let mut output_usage = TextureUsages::RENDER_ATTACHMENT | TextureUsages::COPY_SRC | TextureUsages::TEXTURE_BINDING;
        if spatial {
            output_usage |= TextureUsages::STORAGE_BINDING;
        }
        let output_texture = texture(device, "output colour", extent(output), COLOR, output_usage);
        let output_view = output_texture.create_view(&TextureViewDescriptor::default());
        let shadow_side = crate::render::SHADOW_RES.min(device.limits().max_texture_dimension_2d);
        let shadow_texture = texture(
            device,
            "sun depth cascades",
            Extent3d { width: shadow_side, height: shadow_side, depth_or_array_layers: 3 },
            SHADOW_DEPTH,
            TextureUsages::RENDER_ATTACHMENT | TextureUsages::TEXTURE_BINDING | TextureUsages::COPY_SRC | TextureUsages::COPY_DST,
        );
        let shadow_view =
            shadow_texture.create_view(&TextureViewDescriptor { dimension: Some(TextureViewDimension::D2Array), ..Default::default() });
        let shadow_layers = [0, 1, 2].map(|layer| {
            shadow_texture.create_view(&TextureViewDescriptor {
                dimension: Some(TextureViewDimension::D2),
                base_array_layer: layer,
                array_layer_count: Some(1),
                ..Default::default()
            })
        });

        let scene_uniform = device.create_buffer(&BufferDescriptor {
            label: Some("scene constants"),
            size: size_of::<Scene>() as u64,
            usage: BufferUsages::UNIFORM | BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let object_slots = 256;
        let objects = device.create_buffer(&BufferDescriptor {
            label: Some("object constants"),
            size: object_step(device) * object_slots as u64,
            usage: BufferUsages::UNIFORM | BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let uniform_layout = |binding, min_size, dynamic| BindGroupLayoutEntry {
            binding,
            visibility: ShaderStages::VERTEX_FRAGMENT,
            ty: BindingType::Buffer {
                ty: BufferBindingType::Uniform,
                has_dynamic_offset: dynamic,
                min_binding_size: BufferSize::new(min_size),
            },
            count: None,
        };
        let world_group_layout = device.create_bind_group_layout(&BindGroupLayoutDescriptor {
            label: Some("world uniform layout"),
            entries: &[
                uniform_layout(0, size_of::<Scene>() as u64, false),
                uniform_layout(1, OBJECT_SIZE, true),
                BindGroupLayoutEntry {
                    binding: 2,
                    visibility: ShaderStages::VERTEX,
                    ty: BindingType::Buffer {
                        ty: BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 3,
                    visibility: ShaderStages::FRAGMENT,
                    ty: BindingType::Texture {
                        sample_type: TextureSampleType::Float { filterable: true },
                        view_dimension: TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 4,
                    visibility: ShaderStages::FRAGMENT,
                    ty: BindingType::Sampler(SamplerBindingType::Filtering),
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 5,
                    // The vertex stage reads its size (number plates).
                    visibility: ShaderStages::VERTEX_FRAGMENT,
                    ty: BindingType::Texture {
                        sample_type: TextureSampleType::Float { filterable: true },
                        view_dimension: TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 6,
                    visibility: ShaderStages::FRAGMENT,
                    ty: BindingType::Texture {
                        sample_type: TextureSampleType::Float { filterable: true },
                        view_dimension: TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 7,
                    visibility: ShaderStages::FRAGMENT,
                    ty: BindingType::Texture {
                        sample_type: TextureSampleType::Float { filterable: true },
                        view_dimension: TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                uniform_layout(8, size_of::<Lamps>() as u64, false),
            ],
        });
        let humans = HumanGpu::new(device, &gpu.queue, eng.humans.as_ref());
        let cars = CarGpu::new(device, &gpu.queue, eng.car_atlas.as_ref());
        let props = CarGpu::new(device, &gpu.queue, eng.prop_atlas.as_ref());
        let leaves = leaf_texture(device, &gpu.queue);
        let lamps = device.create_buffer(&BufferDescriptor {
            label: Some("lamps"),
            size: size_of::<Lamps>() as u64,
            usage: BufferUsages::UNIFORM | BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let world_group = world_group(device, &world_group_layout, &scene_uniform, &objects, &humans, &cars, &props, &leaves, &lamps);
        let scene_layout = device.create_pipeline_layout(&PipelineLayoutDescriptor {
            label: Some("world layout"),
            bind_group_layouts: &[Some(&world_group_layout)],
            immediate_size: 0,
        });
        let world_inputs =
            [VertexBufferLayout { array_stride: size_of::<Vertex>() as u64, step_mode: VertexStepMode::Vertex, attributes: &WORLD }];
        let world_uv_inputs = [
            world_inputs[0].clone(),
            VertexBufferLayout {
                array_stride: size_of::<ObjSurface>() as u64,
                step_mode: VertexStepMode::Vertex,
                attributes: &OBJ_SURFACE,
            },
        ];
        let shadow_group_layout = device.create_bind_group_layout(&BindGroupLayoutDescriptor {
            label: Some("sun depth layout"),
            entries: &[
                BindGroupLayoutEntry {
                    binding: 0,
                    visibility: ShaderStages::FRAGMENT,
                    ty: BindingType::Texture {
                        sample_type: TextureSampleType::Depth,
                        view_dimension: TextureViewDimension::D2Array,
                        multisampled: false,
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 1,
                    visibility: ShaderStages::FRAGMENT,
                    ty: BindingType::Sampler(SamplerBindingType::Comparison),
                    count: None,
                },
            ],
        });
        // Linear filtering makes each compare a 2x2 blend: smooth shadow edges.
        let shadow_sampler = device.create_sampler(&SamplerDescriptor {
            compare: Some(CompareFunction::LessEqual),
            mag_filter: FilterMode::Linear,
            min_filter: FilterMode::Linear,
            ..Default::default()
        });
        let shadow_group = device.create_bind_group(&BindGroupDescriptor {
            label: Some("sun depth for lighting"),
            layout: &shadow_group_layout,
            entries: &[
                BindGroupEntry { binding: 0, resource: BindingResource::TextureView(&shadow_view) },
                BindGroupEntry { binding: 1, resource: BindingResource::Sampler(&shadow_sampler) },
            ],
        });
        let world_layout = device.create_pipeline_layout(&PipelineLayoutDescriptor {
            label: Some("world with sun depth and materials"),
            bind_group_layouts: &[Some(&world_group_layout), Some(&shadow_group_layout), Some(&material_layout)],
            immediate_size: 0,
        });
        let depth_pipeline = |label, entry, inputs: &[VertexBufferLayout<'_>], fragment: Option<&str>| {
            device.create_render_pipeline(&RenderPipelineDescriptor {
                label: Some(label),
                layout: Some(&scene_layout),
                vertex: VertexState {
                    module: &shader,
                    entry_point: Some(entry),
                    compilation_options: PipelineCompilationOptions::default(),
                    buffers: inputs,
                },
                primitive: PrimitiveState::default(),
                depth_stencil: Some(DepthStencilState {
                    format: SHADOW_DEPTH,
                    depth_write_enabled: Some(true),
                    depth_compare: Some(CompareFunction::LessEqual),
                    stencil: StencilState::default(),
                    bias: DepthBiasState::default(),
                }),
                multisample: MultisampleState::default(),
                fragment: fragment.map(|entry| FragmentState {
                    module: &shader,
                    entry_point: Some(entry),
                    compilation_options: PipelineCompilationOptions::default(),
                    targets: &[],
                }),
                multiview_mask: None,
                cache: None,
            })
        };
        let shadow = depth_pipeline("sun depth pipeline", "shadow_vertex", &world_inputs, None);
        // Meshes with texture coordinates draw into the sun's depth through a
        // fragment stage, so leaf cards cast leaf-shaped (dappled) shadows.
        let shadow_uv =
            depth_pipeline("sun depth pipeline with leaf cut-outs", "shadow_uv_vertex", &world_uv_inputs, Some("shadow_leaf_fragment"));
        let shadow_far = depth_pipeline("far sun depth pipeline", "shadow_far_vertex", &world_inputs, None);
        let shadow_uv_far =
            depth_pipeline("far sun depth with leaf cut-outs", "shadow_uv_far_vertex", &world_uv_inputs, Some("shadow_leaf_fragment"));
        let sky = ImagePipeline {
            vertex: "sky_vertex",
            fragment: "sky_fragment",
            inputs: &[],
            layout: Some(&scene_layout),
            depth_write: Some(false),
            blend: None,
            format: scene_format,
        }
        .create(device, &shader);
        let world_pipeline = |opaque, has_uv| {
            ImagePipeline {
                vertex: if has_uv { "world_uv_vertex" } else { "world_vertex" },
                fragment: "world_fragment",
                inputs: if has_uv { &world_uv_inputs } else { &world_inputs },
                layout: Some(&world_layout),
                depth_write: Some(opaque),
                // Colour blends; alpha keeps what is under it: the opaque
                // surfaces' mirror weight for the reflections (tone map).
                blend: (!opaque).then_some(BlendState {
                    color: BlendState::ALPHA_BLENDING.color,
                    alpha: BlendComponent { src_factor: BlendFactor::Zero, dst_factor: BlendFactor::One, operation: BlendOperation::Add },
                }),
                format: scene_format,
            }
            .create(device, &shader)
        };
        let sampler = device.create_sampler(&SamplerDescriptor {
            mag_filter: FilterMode::Linear,
            min_filter: FilterMode::Linear,
            ..Default::default()
        });
        // HDR look: ambient occlusion from the scene's depth, then the tone map
        // (which applies it) into an 8-bit image for the blit or upscaler.
        let occlusion = hdr.then(|| {
            let target = texture(
                device,
                "ambient occlusion",
                extent(internal),
                TextureFormat::R8Unorm,
                TextureUsages::RENDER_ATTACHMENT | TextureUsages::TEXTURE_BINDING,
            )
            .create_view(&TextureViewDescriptor::default());
            let pipeline = ImagePipeline {
                vertex: "blit_vertex",
                fragment: "ao_fragment",
                inputs: &[],
                layout: None,
                depth_write: None,
                blend: None,
                format: TextureFormat::R8Unorm,
            }
            .create(device, &shader);
            let constants = device.create_bind_group(&BindGroupDescriptor {
                label: Some("AO scene constants"),
                layout: &pipeline.get_bind_group_layout(0),
                entries: &[BindGroupEntry { binding: 0, resource: scene_uniform.as_entire_binding() }],
            });
            let depth = device.create_bind_group(&BindGroupDescriptor {
                label: Some("AO scene depth"),
                layout: &pipeline.get_bind_group_layout(1),
                entries: &[BindGroupEntry { binding: 2, resource: BindingResource::TextureView(&depth_view) }],
            });
            (target, pipeline, constants, depth)
        });
        let tone_map = occlusion.as_ref().map(|(ao, ..)| {
            let pipeline = ImagePipeline {
                vertex: "blit_vertex",
                fragment: "tonemap_fragment",
                inputs: &[],
                layout: None,
                depth_write: None,
                blend: None,
                format: COLOR,
            }
            .create(device, &shader);
            let group = device.create_bind_group(&BindGroupDescriptor {
                label: Some("HDR scene and AO to tone map"),
                layout: &pipeline.get_bind_group_layout(0),
                entries: &[
                    BindGroupEntry { binding: 0, resource: BindingResource::TextureView(&scene_view) },
                    BindGroupEntry { binding: 1, resource: BindingResource::Sampler(&sampler) },
                    BindGroupEntry { binding: 2, resource: BindingResource::TextureView(ao) },
                ],
            });
            // Reflections and rain read the scene's depth and constants.
            let depth = device.create_bind_group(&BindGroupDescriptor {
                label: Some("tone map scene depth"),
                layout: &pipeline.get_bind_group_layout(1),
                entries: &[BindGroupEntry { binding: 2, resource: BindingResource::TextureView(&depth_view) }],
            });
            let constants = device.create_bind_group(&BindGroupDescriptor {
                label: Some("tone map scene constants"),
                layout: &pipeline.get_bind_group_layout(2),
                entries: &[BindGroupEntry { binding: 0, resource: scene_uniform.as_entire_binding() }],
            });
            (pipeline, group, depth, constants)
        });
        let blit = (!spatial).then(|| {
            let presented = tonemapped.as_ref().unwrap_or(&scene_view);
            full_screen(device, &shader, &sampler, "blit_fragment", presented, COLOR, "scene colour for presentation")
        });
        let hud = ImagePipeline {
            vertex: "hud_vertex",
            fragment: "hud_fragment",
            inputs: &[VertexBufferLayout { array_stride: 24, step_mode: VertexStepMode::Vertex, attributes: &HUD }],
            layout: None,
            depth_write: None,
            blend: Some(BlendState::ALPHA_BLENDING),
            format: COLOR,
        }
        .create(device, &shader);
        let easu_intermediate = (settings.upscale == Upscale::EasuRcas).then(|| {
            texture(device, "EASU colour", extent(output), COLOR, TextureUsages::STORAGE_BINDING | TextureUsages::TEXTURE_BINDING)
                .create_view(&TextureViewDescriptor::default())
        });
        let timestamps = gpu.queries.then(|| {
            device.create_query_set(&QuerySetDescriptor {
                label: Some("scene and presentation boundaries"),
                ty: QueryType::Timestamp,
                count: STAMPS,
            })
        });
        Ok(Self {
            present: None,
            sampler,
            spatial_shader: spatial.then(|| device.create_shader_module(include_wgsl!("spatial.wgsl"))),
            opaque: world_pipeline(true, false),
            alpha: world_pipeline(false, false),
            opaque_uv: world_pipeline(true, true),
            alpha_uv: world_pipeline(false, true),
            shader,
            world_group_layout,
            material_group,
            material_ground,
            shadow_texture,
            shadow_layers,
            shadow_group,
            shadow,
            shadow_uv,
            shadow_far,
            shadow_uv_far,
            sky,
            scene_view,
            depth_view,
            tonemapped,
            occlusion,
            tone_map,
            blit,
            hud,
            output_texture,
            output_view,
            easu_intermediate,
            scene_uniform,
            objects,
            object_slots,
            far_drawn: None,
            near_static: None,
            static_eye: Vec3::ZERO,
            shadow_sun: None,
            motion: Vec::new(),
            still_redraws: 0,
            world_group,
            humans,
            cars,
            props,
            leaves,
            lamps,
            timestamps,
            stamped: [false; STAMPS as usize],
        })
    }
}

/// A full-screen pass from `source` through `fragment` into `format`.
fn full_screen(
    device: &Device,
    shader: &ShaderModule,
    sampler: &Sampler,
    fragment: &str,
    source: &TextureView,
    format: TextureFormat,
    label: &str,
) -> (RenderPipeline, BindGroup) {
    let pipeline = ImagePipeline { vertex: "blit_vertex", fragment, inputs: &[], layout: None, depth_write: None, blend: None, format }
        .create(device, shader);
    let group = device.create_bind_group(&BindGroupDescriptor {
        label: Some(label),
        layout: &pipeline.get_bind_group_layout(0),
        entries: &[
            BindGroupEntry { binding: 0, resource: BindingResource::TextureView(source) },
            BindGroupEntry { binding: 1, resource: BindingResource::Sampler(sampler) },
        ],
    });
    (pipeline, group)
}

/// A renderer that draws into its own image, with no window (benchmarks).
pub fn offscreen(
    eng: &Engine,
    internal: (u32, u32),
    output: (u32, u32),
    upscale: Upscale,
    material_pack: Option<&Path>,
    hdr: bool,
) -> Result<Renderer2, String> {
    let instance = Instance::new(InstanceDescriptor { backends: Backends::PRIMARY, ..InstanceDescriptor::new_without_display_handle() });
    let settings = Settings { internal, output, upscale, material_pack: material_pack.map(Path::to_path_buf), hdr };
    Renderer2::new(eng, settings, &instance, None)
}

pub fn postcard(
    eng: &Engine,
    internal: (u32, u32),
    output: (u32, u32),
    upscale: Upscale,
    material_pack: Option<&Path>,
    hdr: bool,
    path: &Path,
) -> Result<(), String> {
    let instance = Instance::new(InstanceDescriptor { backends: Backends::PRIMARY, ..InstanceDescriptor::new_without_display_handle() });
    let settings = Settings { internal, output, upscale, material_pack: material_pack.map(Path::to_path_buf), hdr };
    let mut renderer = Renderer2::new(eng, settings, &instance, None)?;
    let (encoder, stats) = renderer.encode(eng)?;
    let gpu_ms = save_ppm(&renderer.gpu.device, &renderer.gpu.queue, encoder, renderer.output(), renderer.state.timestamps.as_ref(), path)?;
    let info = renderer.adapter_info();
    println!(
        "wgpu postcard: {} ({:?}, {:?}); scene {}x{}, output {}x{}, {} draws ({} in view); upscale {}; gpu {}",
        info.name,
        info.backend,
        info.device_type,
        internal.0,
        internal.1,
        output.0,
        output.1,
        stats.draws,
        stats.in_view,
        upscale.name(),
        gpu_ms.map_or_else(|| "unavailable".into(), |ms| format!("{ms:.3} ms (one frame)")),
    );
    // WGPU_BENCH=N: N more frames of the same scene on the same renderer
    // (meshes already up), each timed by the GPU's own timestamps, with a
    // rest between them: what a frame costs the GPU, without heating the
    // machine the way back-to-back frames do.
    if let Some(n) = std::env::var("WGPU_BENCH").ok().and_then(|v| v.parse::<u32>().ok()).filter(|&n| n > 0) {
        let (mut times, mut cpu, mut stages) = (Vec::new(), Vec::new(), Vec::new());
        for _ in 0..n {
            // CPU: culling, the objects' constants and recording the commands.
            let start = std::time::Instant::now();
            let (encoder, _) = renderer.encode(eng)?;
            cpu.push(start.elapsed().as_secs_f64() * 1000.0);
            if let Some((ms, by_stage)) = renderer.gpu_stages(encoder)? {
                times.push(ms);
                stages.push(by_stage);
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        cpu.sort_by(f64::total_cmp);
        times.sort_by(f64::total_cmp);
        if let (Some(&best), Some(&worst)) = (times.first(), times.last()) {
            let at = |q: f64| times[((times.len() - 1) as f64 * q).round() as usize];
            println!(
                "wgpu bench: {} frames, GPU ms median {:.2}, p90 {:.2}, best {:.2}, worst {:.2}; CPU encode ms median {:.2}",
                times.len(),
                at(0.5),
                at(0.9),
                best,
                worst,
                cpu[cpu.len() / 2]
            );
            // Each stage's median on its own (they needn't add up to the total's).
            let medians: Vec<String> = STAGE_NAMES
                .iter()
                .enumerate()
                .map(|(i, name)| {
                    let mut v: Vec<f64> = stages.iter().map(|s: &[f64; 5]| s[i]).collect();
                    v.sort_by(f64::total_cmp);
                    format!("{name} {:.2}", v[v.len() / 2])
                })
                .collect();
            println!("wgpu bench stages (GPU ms medians): {}", medians.join(", "));
        }
    }
    if let Some(pack) = material_pack {
        println!("wgpu material pack: {}", pack.display());
        println!("wgpu OBJ texture coordinates: {} meshes", stats.textured_meshes);
    }
    println!("screenshot: {}", path.display());
    Ok(())
}

fn compute_spatial(
    device: &Device,
    encoder: &mut CommandEncoder,
    shader: &ShaderModule,
    entry: &str,
    source: &TextureView,
    destination: &TextureView,
    (width, height): (u32, u32),
) {
    let pipeline = device.create_compute_pipeline(&ComputePipelineDescriptor {
        label: Some(entry),
        layout: None,
        module: shader,
        entry_point: Some(entry),
        compilation_options: PipelineCompilationOptions::default(),
        cache: None,
    });
    let group = device.create_bind_group(&BindGroupDescriptor {
        label: Some(entry),
        layout: &pipeline.get_bind_group_layout(0),
        entries: &[
            BindGroupEntry { binding: 0, resource: BindingResource::TextureView(source) },
            BindGroupEntry { binding: 1, resource: BindingResource::TextureView(destination) },
        ],
    });
    let mut pass = encoder.begin_compute_pass(&ComputePassDescriptor { label: Some(entry), timestamp_writes: None });
    pass.set_pipeline(&pipeline);
    pass.set_bind_group(0, &group, &[]);
    pass.dispatch_workgroups(width.div_ceil(8), height.div_ceil(8), 1);
}

fn attachment(view: &TextureView, load: LoadOp<Color>) -> RenderPassColorAttachment<'_> {
    RenderPassColorAttachment { view, depth_slice: None, resolve_target: None, ops: Operations { load, store: StoreOp::Store } }
}

fn depth_attachment(view: &TextureView) -> RenderPassDepthStencilAttachment<'_> {
    RenderPassDepthStencilAttachment {
        view,
        depth_ops: Some(Operations { load: LoadOp::Clear(1.0), store: StoreOp::Store }),
        stencil_ops: None,
    }
}

fn draw_mesh(pass: &mut RenderPass<'_>, group: &BindGroup, offset: u32, mesh: &DrawMesh) {
    pass.set_bind_group(0, group, &[offset]);
    pass.set_vertex_buffer(0, mesh.vertices.slice(..));
    pass.set_index_buffer(mesh.indices.slice(..), IndexFormat::Uint32);
    pass.draw_indexed(0..mesh.count, 0, 0..1);
}

fn save_ppm(
    device: &Device,
    queue: &Queue,
    mut encoder: CommandEncoder,
    texture: &Texture,
    queries: Option<&QuerySet>,
    path: &Path,
) -> Result<Option<f64>, String> {
    let size = texture.size();
    let row = (size.width * 4).div_ceil(COPY_BYTES_PER_ROW_ALIGNMENT) * COPY_BYTES_PER_ROW_ALIGNMENT;
    let image_bytes = u64::from(row) * u64::from(size.height);
    let timing_bytes = if queries.is_some() { 16 } else { 0 };
    if image_bytes + timing_bytes > device.limits().max_buffer_size {
        return Err("screenshot exceeds the device's readback buffer limit".into());
    }
    let readback = device.create_buffer(&BufferDescriptor {
        label: Some("screenshot readback"),
        size: image_bytes + timing_bytes,
        usage: BufferUsages::COPY_DST | BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    encoder.copy_texture_to_buffer(
        texture.as_image_copy(),
        TexelCopyBufferInfo {
            buffer: &readback,
            layout: TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(row), rows_per_image: None },
        },
        size,
    );
    if let Some(query_set) = queries {
        let resolve = device.create_buffer(&BufferDescriptor {
            label: Some("timestamp resolve"),
            size: timing_bytes,
            usage: BufferUsages::QUERY_RESOLVE | BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });
        encoder.resolve_query_set(query_set, 0..2, &resolve, 0);
        encoder.copy_buffer_to_buffer(&resolve, 0, &readback, image_bytes, timing_bytes);
    }
    let submission = queue.submit([encoder.finish()]);
    let slice = readback.slice(..);
    let (send, receive) = std::sync::mpsc::channel();
    slice.map_async(MapMode::Read, move |result| {
        let _ = send.send(result);
    });
    device
        .poll(PollType::Wait { submission_index: Some(submission), timeout: Some(Duration::from_secs(30)) })
        .map_err(|e| e.to_string())?;
    receive.recv_timeout(Duration::from_secs(1)).map_err(|e| e.to_string())?.map_err(|e| e.to_string())?;
    let data = slice.get_mapped_range();
    let width = size.width;
    let height = size.height;
    let mut ppm = format!("P6\n{width} {height}\n255\n").into_bytes();
    ppm.reserve(width as usize * height as usize * 3);
    for scanline in data[..image_bytes as usize].chunks_exact(row as usize) {
        for rgba in scanline[..width as usize * 4].as_chunks::<4>().0 {
            ppm.extend_from_slice(&rgba[..3]);
        }
    }
    std::fs::write(path, ppm).map_err(|e| format!("{}: {e}", path.display()))?;
    let gpu_ms = queries.map(|_| {
        let stamps = &data[image_bytes as usize..];
        let start = u64::from_le_bytes(stamps[..8].try_into().unwrap());
        let end = u64::from_le_bytes(stamps[8..].try_into().unwrap());
        end.saturating_sub(start) as f64 * queue.get_timestamp_period() as f64 / 1e6
    });
    drop(data);
    readback.unmap();
    Ok(gpu_ms)
}
