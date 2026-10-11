//! OpenGL via miniquad. Per frame:
//!   1. shadow pass: sun-space depth, packed into an RGBA8 texture (portable
//!      to any GL2/GLES2 driver), covering a box in front of the camera;
//!   2. sky: a full-screen gradient with sun/moon disc and night stars;
//!   3. lit pass: sun with 3x3 PCF shadows, hemisphere ambient, up to 16
//!      point/spot lights, emissive glow, distance fog (opaque, then sorted alpha);
//!   4. HUD quads.

use crate::engine::Engine;
use crate::math::{Mat4, Vec3, v3};
use miniquad::*;

pub const MAX_LIGHTS: usize = 16;
const SHADOW_RES: u32 = 2048;
const SHADOW_SIZE: f32 = 170.0; // meters covered by the shadow map
const SHADOW_DEPTH: f32 = 420.0;

const PRECISION: &str = "#ifdef GL_FRAGMENT_PRECISION_HIGH\nprecision highp float;\n#else\nprecision mediump float;\n#endif\n";

const VS: &str = r#"
attribute vec3 in_pos;
attribute vec3 in_normal;
attribute vec3 in_color;
attribute float in_emissive;
uniform mat4 mvp;
uniform mat4 model;
uniform vec4 inv_scale2;
varying vec3 v_color;
varying vec3 v_normal;
varying vec3 v_world;
varying float v_emissive;
void main() {
    v_world = (model * vec4(in_pos, 1.0)).xyz;
    v_normal = (model * vec4(in_normal * inv_scale2.xyz, 0.0)).xyz;
    v_color = in_color;
    v_emissive = in_emissive;
    gl_Position = mvp * vec4(in_pos, 1.0);
}"#;

const FS: &str = r#"
varying vec3 v_color;
varying vec3 v_normal;
varying vec3 v_world;
varying float v_emissive;
uniform mat4 light_vp;
uniform vec4 tint;
uniform vec4 extra; // x = entity glow
uniform vec4 eye;
uniform vec4 fog;
uniform vec4 fog_color;
uniform vec4 sun;
uniform vec4 sun_color;
uniform vec4 ambient;
uniform vec4 ground;
uniform vec4 params; // glow, light count, shadows on, shadow texel
uniform vec4 lpos[16]; // xyz, radius
uniform vec4 lcol[16]; // rgb, intensity
uniform vec4 ldir[16]; // xyz, cos(cone) or -1
uniform sampler2D shadow_map;

float unpack(vec4 c) { return dot(c, vec4(1.0, 1.0 / 255.0, 1.0 / 65025.0, 1.0 / 16581375.0)); }

float shadow(float ndl) {
    if (params.z < 0.5 || ndl <= 0.0) return 1.0;
    vec3 p = (light_vp * vec4(v_world, 1.0)).xyz * 0.5 + 0.5;
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) return 1.0;
    float bias = 0.0005 + 0.002 * (1.0 - ndl);
    float lit = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            lit += step(p.z - bias, unpack(texture2D(shadow_map, p.xy + vec2(float(x), float(y)) * params.w)));
        }
    }
    return lit / 9.0;
}

void main() {
    vec3 n = normalize(v_normal);
    vec3 base = v_color * tint.rgb;
    float ndl = max(dot(n, sun.xyz), 0.0);
    vec3 light = mix(ground.rgb, ambient.rgb, 0.5 + 0.5 * n.y) + sun_color.rgb * ndl * shadow(ndl);
    for (int i = 0; i < 16; i++) {
        if (float(i) >= params.y) break;
        vec3 l = lpos[i].xyz - v_world;
        float d = length(l);
        l /= max(d, 0.001);
        float att = clamp(1.0 - d / lpos[i].w, 0.0, 1.0);
        float spot = ldir[i].w < -0.5 ? 1.0 : smoothstep(ldir[i].w, ldir[i].w + 0.08, dot(-l, ldir[i].xyz));
        light += lcol[i].rgb * (lcol[i].w * att * att * spot * (0.25 + 0.75 * max(dot(n, l), 0.0)));
    }
    float glow = v_emissive * params.x + extra.x;
    vec3 col = base * light + base * glow * 1.8;
    float d = length(v_world - eye.xyz);
    float f = clamp((d - fog.x) / (fog.y - fog.x), 0.0, 1.0);
    f = f * f * (1.0 - 0.7 * glow);
    gl_FragColor = vec4(mix(col, fog_color.rgb, f), tint.a);
}"#;

const SHADOW_VS: &str = r#"
attribute vec3 in_pos;
uniform mat4 mvp;
void main() { gl_Position = mvp * vec4(in_pos, 1.0); }"#;

const SHADOW_FS: &str = r#"
void main() {
    vec4 e = fract(gl_FragCoord.z * vec4(1.0, 255.0, 65025.0, 16581375.0));
    gl_FragColor = e - e.yzww * vec4(1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0, 0.0);
}"#;

const SKY_VS: &str = r#"
attribute vec2 in_pos;
varying vec2 v_ndc;
void main() { v_ndc = in_pos; gl_Position = vec4(in_pos, 1.0, 1.0); }"#;

const SKY_FS: &str = r#"
varying vec2 v_ndc;
uniform vec4 cam_fwd;
uniform vec4 cam_right; // scaled by tan(fov/2) * aspect
uniform vec4 cam_up;    // scaled by tan(fov/2)
uniform vec4 horizon;
uniform vec4 top;
uniform vec4 sun;
uniform vec4 sun_color; // a = glow
void main() {
    vec3 dir = normalize(cam_fwd.xyz + cam_right.xyz * v_ndc.x + cam_up.xyz * v_ndc.y);
    float h = clamp(dir.y, 0.0, 1.0);
    vec3 col = mix(horizon.rgb, top.rgb, pow(h, 0.55));
    float s = max(dot(dir, sun.xyz), 0.0);
    float disc = smoothstep(0.9993, 0.9997, s);
    col += sun_color.rgb * (disc * 3.0 + pow(s, 48.0) * 0.4) * step(0.0, sun.y);
    vec3 cell = floor(dir * 260.0);
    float star = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
    col += vec3(step(0.9975, star) * sun_color.a * h * 0.9);
    gl_FragColor = vec4(col, 1.0);
}"#;

const HUD_VS: &str = r#"
attribute vec2 in_pos;
attribute vec4 in_color;
uniform vec4 screen;
varying vec4 v_color;
void main() {
    gl_Position = vec4(in_pos.x / screen.x * 2.0 - 1.0, 1.0 - in_pos.y / screen.y * 2.0, 0.0, 1.0);
    v_color = in_color;
}"#;

const HUD_FS: &str = r#"
varying vec4 v_color;
void main() { gl_FragColor = v_color; }"#;

#[repr(C)]
struct Uniforms {
    mvp: [f32; 16],
    model: [f32; 16],
    light_vp: [f32; 16],
    inv_scale2: [f32; 4],
    tint: [f32; 4],
    extra: [f32; 4],
    eye: [f32; 4],
    fog: [f32; 4],
    fog_color: [f32; 4],
    sun: [f32; 4],
    sun_color: [f32; 4],
    ambient: [f32; 4],
    ground: [f32; 4],
    params: [f32; 4],
    lpos: [[f32; 4]; MAX_LIGHTS],
    lcol: [[f32; 4]; MAX_LIGHTS],
    ldir: [[f32; 4]; MAX_LIGHTS],
}

#[repr(C)]
struct SkyUniforms {
    cam_fwd: [f32; 4],
    cam_right: [f32; 4],
    cam_up: [f32; 4],
    horizon: [f32; 4],
    top: [f32; 4],
    sun: [f32; 4],
    sun_color: [f32; 4],
}

struct GpuMesh {
    bind: Bindings,
    count: i32,
    radius: f32,
    rev: u32,
}

pub struct Renderer {
    ctx: Box<dyn RenderingBackend>,
    opaque: Pipeline,
    alpha: Pipeline,
    shadow: Pipeline,
    sky: Pipeline,
    hud: Pipeline,
    shadow_pass: RenderPass,
    shadow_tex: TextureId,
    sky_bind: Bindings,
    meshes: Vec<Option<GpuMesh>>,
    epoch: u64,
    hud_bind: Option<(Bindings, usize)>,
    pub draw_calls: usize,
    pub lights_used: usize,
}

fn blend() -> Option<BlendState> {
    Some(BlendState::new(Equation::Add, BlendFactor::Value(BlendValue::SourceAlpha), BlendFactor::OneMinusValue(BlendValue::SourceAlpha)))
}

fn shader(ctx: &mut Box<dyn RenderingBackend>, vs: &str, fs: &str, uniforms: &[(&str, UniformType, usize)], images: &[&str]) -> ShaderId {
    let vertex = format!("#version 100\n{vs}");
    let fragment = format!("#version 100\n{PRECISION}{fs}");
    let meta = ShaderMeta {
        images: images.iter().map(|s| s.to_string()).collect(),
        uniforms: UniformBlockLayout { uniforms: uniforms.iter().map(|(n, t, c)| UniformDesc::new(n, *t).array(*c)).collect() },
    };
    ctx.new_shader(ShaderSource::Glsl { vertex: &vertex, fragment: &fragment }, meta).unwrap_or_else(|e| panic!("shader: {e:?}"))
}

fn v4(v: Vec3, w: f32) -> [f32; 4] {
    [v.x, v.y, v.z, w]
}

fn c4(c: [f32; 3], w: f32) -> [f32; 4] {
    [c[0], c[1], c[2], w]
}

impl Renderer {
    pub fn new() -> Renderer {
        let mut ctx = window::new_rendering_backend();
        use UniformType::*;
        let main = shader(
            &mut ctx,
            VS,
            FS,
            &[
                ("mvp", Mat4, 1),
                ("model", Mat4, 1),
                ("light_vp", Mat4, 1),
                ("inv_scale2", Float4, 1),
                ("tint", Float4, 1),
                ("extra", Float4, 1),
                ("eye", Float4, 1),
                ("fog", Float4, 1),
                ("fog_color", Float4, 1),
                ("sun", Float4, 1),
                ("sun_color", Float4, 1),
                ("ambient", Float4, 1),
                ("ground", Float4, 1),
                ("params", Float4, 1),
                ("lpos", Float4, MAX_LIGHTS),
                ("lcol", Float4, MAX_LIGHTS),
                ("ldir", Float4, MAX_LIGHTS),
            ],
            &["shadow_map"],
        );
        let attrs = [
            VertexAttribute::new("in_pos", VertexFormat::Float3),
            VertexAttribute::new("in_normal", VertexFormat::Float3),
            VertexAttribute::new("in_color", VertexFormat::Float3),
            VertexAttribute::new("in_emissive", VertexFormat::Float1),
        ];
        let base =
            PipelineParams { depth_test: Comparison::LessOrEqual, depth_write: true, cull_face: CullFace::Back, ..Default::default() };
        let opaque = ctx.new_pipeline(&[BufferLayout::default()], &attrs, main, base);
        let alpha =
            ctx.new_pipeline(&[BufferLayout::default()], &attrs, main, PipelineParams { depth_write: false, color_blend: blend(), ..base });

        // Shadow casters render back faces: cheap, and keeps acne off lit faces.
        let shadow_sh = shader(&mut ctx, SHADOW_VS, SHADOW_FS, &[("mvp", Mat4, 1)], &[]);
        let shadow = ctx.new_pipeline(&[BufferLayout::default()], &attrs, shadow_sh, PipelineParams { cull_face: CullFace::Front, ..base });
        let tex = |format, filter| TextureParams {
            format,
            width: SHADOW_RES,
            height: SHADOW_RES,
            min_filter: filter,
            mag_filter: filter,
            wrap: TextureWrap::Clamp,
            ..Default::default()
        };
        let shadow_tex = ctx.new_render_texture(tex(TextureFormat::RGBA8, FilterMode::Nearest));
        let shadow_depth = ctx.new_render_texture(tex(TextureFormat::Depth, FilterMode::Nearest));
        let shadow_pass = ctx.new_render_pass(shadow_tex, Some(shadow_depth));

        let sky_sh = shader(
            &mut ctx,
            SKY_VS,
            SKY_FS,
            &[
                ("cam_fwd", Float4, 1),
                ("cam_right", Float4, 1),
                ("cam_up", Float4, 1),
                ("horizon", Float4, 1),
                ("top", Float4, 1),
                ("sun", Float4, 1),
                ("sun_color", Float4, 1),
            ],
            &[],
        );
        let sky = ctx.new_pipeline(
            &[BufferLayout::default()],
            &[VertexAttribute::new("in_pos", VertexFormat::Float2)],
            sky_sh,
            PipelineParams::default(),
        );
        let tri: [f32; 6] = [-1., -1., 3., -1., -1., 3.];
        let sky_bind = Bindings {
            vertex_buffers: vec![ctx.new_buffer(BufferType::VertexBuffer, BufferUsage::Immutable, BufferSource::slice(&tri))],
            index_buffer: ctx.new_buffer(BufferType::IndexBuffer, BufferUsage::Immutable, BufferSource::slice(&[0u16, 1, 2])),
            images: vec![],
        };

        let hud_sh = shader(&mut ctx, HUD_VS, HUD_FS, &[("screen", Float4, 1)], &[]);
        let hud = ctx.new_pipeline(
            &[BufferLayout::default()],
            &[VertexAttribute::new("in_pos", VertexFormat::Float2), VertexAttribute::new("in_color", VertexFormat::Float4)],
            hud_sh,
            PipelineParams { color_blend: blend(), ..Default::default() },
        );
        Renderer {
            ctx,
            opaque,
            alpha,
            shadow,
            sky,
            hud,
            shadow_pass,
            shadow_tex,
            sky_bind,
            meshes: Vec::new(),
            epoch: 0,
            hud_bind: None,
            draw_calls: 0,
            lights_used: 0,
        }
    }

    fn sync(&mut self, eng: &Engine) {
        if eng.epoch != self.epoch {
            for m in self.meshes.drain(..).flatten() {
                self.ctx.delete_buffer(m.bind.vertex_buffers[0]);
                self.ctx.delete_buffer(m.bind.index_buffer);
            }
            self.epoch = eng.epoch;
        }
        self.meshes.resize_with(eng.meshes.len(), || None);
        for (i, m) in eng.meshes.iter().enumerate() {
            let rev = eng.mesh_revs[i];
            if self.meshes[i].as_ref().is_some_and(|g| g.rev == rev) {
                continue;
            }
            if let Some(old) = self.meshes[i].take() {
                self.ctx.delete_buffer(old.bind.vertex_buffers[0]);
                self.ctx.delete_buffer(old.bind.index_buffer);
            }
            if m.indices.is_empty() {
                continue;
            }
            let vb = self.ctx.new_buffer(BufferType::VertexBuffer, BufferUsage::Immutable, BufferSource::slice(&m.verts));
            let ib = self.ctx.new_buffer(BufferType::IndexBuffer, BufferUsage::Immutable, BufferSource::slice(&m.indices));
            let radius = m.verts.iter().map(|v| (v.pos[0].powi(2) + v.pos[1].powi(2) + v.pos[2].powi(2)).sqrt()).fold(0.0, f32::max);
            self.meshes[i] = Some(GpuMesh {
                bind: Bindings { vertex_buffers: vec![vb], index_buffer: ib, images: vec![self.shadow_tex] },
                count: m.indices.len() as i32,
                radius,
                rev,
            });
        }
    }

    /// Orthographic sun view covering a box in front of the camera, snapped
    /// to whole shadow texels so edges don't shimmer as the camera moves.
    fn shadow_matrix(eng: &Engine) -> (Mat4, Vec3) {
        let cam = &eng.camera;
        let sun = eng.env.sun;
        let mut fwd = cam.target - cam.eye;
        fwd.y = 0.0;
        let mut focus = cam.eye + fwd.norm() * (SHADOW_SIZE * 0.3);
        focus.y = 0.0;
        let up = if sun.y.abs() > 0.99 { v3(0., 0., 1.) } else { Vec3::UP };
        let r = (-sun).cross(up).norm();
        let u = r.cross(-sun);
        let texel = SHADOW_SIZE / SHADOW_RES as f32;
        let snap = |a: f32| (a / texel).floor() * texel - a;
        focus += r * snap(focus.dot(r)) + u * snap(focus.dot(u));
        let view = Mat4::look_at(focus + sun * (SHADOW_DEPTH * 0.5), focus, up);
        let h = SHADOW_SIZE * 0.5;
        (Mat4::ortho(-h, h, -h, h, 0.0, SHADOW_DEPTH) * view, focus)
    }

    pub fn draw(&mut self, eng: &Engine) {
        self.sync(eng);
        let (w, h) = eng.screen;
        let env = &eng.env;
        let cam = &eng.camera;
        let aspect = w / h.max(1.0);
        let proj = Mat4::perspective(cam.fov, aspect, 0.1, env.fog_end + 50.0);
        let view = Mat4::look_at(cam.eye, cam.target, Vec3::UP);
        let vp = proj * view;
        let fwd = (cam.target - cam.eye).norm();
        let plane = eng.mesh_ids.get("plane").copied();

        // Cull, then split into opaque and back-to-front alpha lists.
        let mut opaque = Vec::new();
        let mut alpha = Vec::new();
        let mut casters = Vec::new();
        let (light_vp, focus) = Self::shadow_matrix(eng);
        let shadows = env.shadows && env.sun.y > 0.05;
        for e in eng.ents.iter().flatten() {
            let (Some(mi), true) = (e.mesh, e.visible) else { continue };
            let Some(Some(g)) = self.meshes.get(mi) else { continue };
            let r = g.radius * e.scale.x.abs().max(e.scale.y.abs()).max(e.scale.z.abs());
            let to = e.pos - cam.eye;
            let dist = to.len();
            if shadows && e.color[3] >= 1.0 && Some(mi) != plane {
                let d = e.pos - focus;
                if (d.x * d.x + d.z * d.z).sqrt() - r < SHADOW_SIZE * 0.75 {
                    casters.push((e, mi));
                }
            }
            if dist - r > env.fog_end || to.dot(fwd) < -r {
                continue;
            }
            if e.color[3] < 1.0 { alpha.push((dist, e, mi)) } else { opaque.push((dist, e, mi)) }
        }
        alpha.sort_by(|a, b| b.0.total_cmp(&a.0));
        self.draw_calls = 0;

        // 1. Shadow map.
        if shadows {
            self.ctx
                .begin_pass(Some(self.shadow_pass), PassAction::Clear { color: Some((1., 1., 1., 1.)), depth: Some(1.0), stencil: None });
            self.ctx.apply_pipeline(&self.shadow);
            for (e, mi) in &casters {
                let g = self.meshes[*mi].as_ref().unwrap();
                let mvp = light_vp * Mat4::trs_q(e.pos, e.rot, e.scale);
                self.ctx.apply_bindings(&g.bind);
                self.ctx.apply_uniforms(UniformsSource::table(&mvp.0));
                self.ctx.draw(0, g.count, 1);
                self.draw_calls += 1;
            }
            self.ctx.end_render_pass();
        }

        // 2. Sky.
        self.ctx.begin_default_pass(PassAction::Clear {
            color: Some((env.sky[0], env.sky[1], env.sky[2], 1.0)),
            depth: Some(1.0),
            stencil: None,
        });
        let t = (cam.fov * 0.5).tan();
        let right = fwd.cross(Vec3::UP).norm();
        let up = right.cross(fwd);
        let sky = SkyUniforms {
            cam_fwd: v4(fwd, 0.),
            cam_right: v4(right * (t * aspect), 0.),
            cam_up: v4(up * t, 0.),
            horizon: c4(env.sky, 1.),
            top: c4(env.sky_top, 1.),
            sun: v4(env.sun, 0.),
            sun_color: c4(env.sun_color, env.glow),
        };
        self.ctx.apply_pipeline(&self.sky);
        self.ctx.apply_bindings(&self.sky_bind);
        self.ctx.apply_uniforms(UniformsSource::table(&sky));
        self.ctx.draw(0, 3, 1);

        // 3. The world, lit by the nearest lights.
        let mut uni = Uniforms {
            mvp: [0.0; 16],
            model: [0.0; 16],
            light_vp: light_vp.0,
            inv_scale2: [1.0; 4],
            tint: [1.0; 4],
            extra: [0.0; 4],
            eye: v4(cam.eye, 0.),
            fog: [env.fog_start, env.fog_end, 0.0, 0.0],
            fog_color: c4(env.sky, 1.),
            sun: v4(env.sun, 0.),
            sun_color: c4(env.sun_color, 1.),
            ambient: c4(env.ambient, 1.),
            ground: c4(env.ground, 1.),
            params: [env.glow, 0.0, if shadows { 1.0 } else { 0.0 }, 1.0 / SHADOW_RES as f32],
            lpos: [[0.0; 4]; MAX_LIGHTS],
            lcol: [[0.0; 4]; MAX_LIGHTS],
            ldir: [[0.0; 4]; MAX_LIGHTS],
        };
        self.lights_used = 0;
        if env.glow > 0.01 {
            let mut near: Vec<(f32, Vec3, Vec3, &crate::engine::Light)> = eng
                .lights
                .iter()
                .flatten()
                .filter(|l| l.intensity > 0.0)
                .filter_map(|l| eng.light_world(l).map(|(p, d)| ((p - cam.eye).len() - l.radius, p, d, l)))
                .filter(|(score, ..)| *score < env.fog_end)
                .collect();
            near.sort_by(|a, b| a.0.total_cmp(&b.0));
            for (k, (_, p, d, l)) in near.iter().take(MAX_LIGHTS).enumerate() {
                uni.lpos[k] = v4(*p, l.radius);
                uni.lcol[k] = c4(l.color, l.intensity * env.glow);
                uni.ldir[k] = v4(*d, l.cone);
                self.lights_used += 1;
            }
            uni.params[1] = self.lights_used as f32;
        }
        for (pipe, list) in [(&self.opaque, &opaque), (&self.alpha, &alpha)] {
            if list.is_empty() {
                continue;
            }
            self.ctx.apply_pipeline(pipe);
            for (_, e, mi) in list.iter() {
                let g = self.meshes[*mi].as_ref().unwrap();
                let model = Mat4::trs_q(e.pos, e.rot, e.scale);
                uni.mvp = (vp * model).0;
                uni.model = model.0;
                let s = e.scale;
                uni.inv_scale2 = [1.0 / (s.x * s.x), 1.0 / (s.y * s.y), 1.0 / (s.z * s.z), 0.0];
                uni.tint = e.color;
                uni.extra[0] = e.glow;
                self.ctx.apply_bindings(&g.bind);
                self.ctx.apply_uniforms(UniformsSource::table(&uni));
                self.ctx.draw(0, g.count, 1);
                self.draw_calls += 1;
            }
        }
        self.draw_hud(eng);
        self.ctx.end_render_pass();
    }

    fn draw_hud(&mut self, eng: &Engine) {
        let verts = eng.hud.len() / 6;
        if verts == 0 {
            return;
        }
        if self.hud_bind.as_ref().is_none_or(|(_, cap)| *cap < verts) {
            if let Some((b, _)) = self.hud_bind.take() {
                self.ctx.delete_buffer(b.vertex_buffers[0]);
                self.ctx.delete_buffer(b.index_buffer);
            }
            let cap = verts.next_power_of_two().max(4096);
            let vb = self.ctx.new_buffer(BufferType::VertexBuffer, BufferUsage::Stream, BufferSource::empty::<f32>(cap * 6));
            let idx: Vec<u32> = (0..cap as u32).collect();
            let ib = self.ctx.new_buffer(BufferType::IndexBuffer, BufferUsage::Immutable, BufferSource::slice(&idx));
            self.hud_bind = Some((Bindings { vertex_buffers: vec![vb], index_buffer: ib, images: vec![] }, cap));
        }
        let (bind, _) = self.hud_bind.as_ref().unwrap();
        self.ctx.buffer_update(bind.vertex_buffers[0], BufferSource::slice(&eng.hud));
        self.ctx.apply_pipeline(&self.hud);
        self.ctx.apply_bindings(bind);
        let screen = [eng.screen.0, eng.screen.1, 0.0, 0.0];
        self.ctx.apply_uniforms(UniformsSource::table(&screen));
        self.ctx.draw(0, verts as i32, 1);
    }

    pub fn commit(&mut self) {
        self.ctx.commit_frame();
    }

    /// Read the back buffer and write a binary PPM.
    pub fn screenshot(&mut self, path: &str, w: i32, h: i32) -> std::io::Result<()> {
        let mut px = vec![0u8; (w * h * 4) as usize];
        unsafe {
            miniquad::gl::glReadPixels(0, 0, w, h, miniquad::gl::GL_RGBA, miniquad::gl::GL_UNSIGNED_BYTE, px.as_mut_ptr() as *mut _);
        }
        let mut out = format!("P6\n{w} {h}\n255\n").into_bytes();
        for y in (0..h).rev() {
            for x in 0..w {
                let i = ((y * w + x) * 4) as usize;
                out.extend_from_slice(&px[i..i + 3]);
            }
        }
        std::fs::write(path, out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio::Mixer;
    use std::sync::{Arc, Mutex};

    fn engine() -> Engine {
        let mut e = Engine::new(std::path::PathBuf::from("."), Arc::new(Mutex::new(Mixer::default())));
        e.camera.eye = v3(13.37, 8.0, -42.1);
        e.camera.target = v3(20.0, 2.0, 0.0);
        e
    }

    fn clip(m: &Mat4, p: Vec3) -> Vec3 {
        let m = m.0;
        v3(
            m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
            m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
            m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14],
        )
    }

    #[test]
    fn shadow_box_covers_the_view_and_is_stable() {
        let mut e = engine();
        let (m, focus) = Renderer::shadow_matrix(&e);
        let c = clip(&m, focus);
        assert!(c.x.abs() < 1e-3 && c.y.abs() < 1e-3 && c.z.abs() < 1.0, "focus at the center: {c:?}");
        // The focus is ahead of the camera, so the camera's ground point is inside too.
        let below = clip(&m, v3(e.camera.eye.x, 0.0, e.camera.eye.z));
        assert!(below.x.abs() < 1.0 && below.y.abs() < 1.0);
        // A 40-meter tower top near the focus is still in front of the near plane.
        assert!(clip(&m, focus + v3(0.0, 40.0, 0.0)).z > -1.0);
        // Sub-texel camera motion must not move the shadow map (no shimmer).
        // One texel is 2/SHADOW_RES ~ 1e-3 in clip space; allow only float noise.
        e.camera.eye.x += 0.001;
        e.camera.target.x += 0.001;
        let (m2, _) = Renderer::shadow_matrix(&e);
        assert!(m.0.iter().zip(m2.0).all(|(a, b)| (a - b).abs() < 1e-4), "{:?} vs {:?}", m.0, m2.0);
    }

    #[test]
    fn straight_down_sun_does_not_degenerate() {
        let mut e = engine();
        e.env.sun = Vec3::UP;
        let (m, focus) = Renderer::shadow_matrix(&e);
        assert!(m.0.iter().all(|x| x.is_finite()));
        assert!(clip(&m, focus).x.abs() < 1e-3);
    }
}
