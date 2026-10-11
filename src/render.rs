//! OpenGL via miniquad. One pipeline for lit, fogged, flat-shaded meshes
//! (opaque pass, then a sorted alpha pass), one for the 2D HUD.

use crate::engine::Engine;
use crate::math::{Mat4, Vec3};
use miniquad::*;

const VS: &str = r#"#version 100
attribute vec3 in_pos;
attribute vec3 in_normal;
attribute vec3 in_color;
uniform mat4 mvp;
uniform mat4 model;
uniform vec4 inv_scale2;
varying lowp vec3 v_color;
varying highp vec3 v_normal;
varying highp vec3 v_world;
void main() {
    v_world = (model * vec4(in_pos, 1.0)).xyz;
    v_normal = (model * vec4(in_normal * inv_scale2.xyz, 0.0)).xyz;
    v_color = in_color;
    gl_Position = mvp * vec4(in_pos, 1.0);
}"#;

const FS: &str = r#"#version 100
precision mediump float;
varying lowp vec3 v_color;
varying highp vec3 v_normal;
varying highp vec3 v_world;
uniform vec4 tint;
uniform vec4 eye;
uniform vec4 fog;
uniform vec4 fog_color;
uniform vec4 sun;
void main() {
    vec3 n = normalize(v_normal);
    float diff = max(dot(n, sun.xyz), 0.0);
    float hemi = 0.5 + 0.5 * n.y;
    vec3 base = v_color * tint.rgb;
    vec3 light = vec3(0.30, 0.33, 0.40) * hemi + vec3(1.0, 0.93, 0.80) * diff * 0.9 + 0.12;
    vec3 col = base * light;
    float d = length(v_world - eye.xyz);
    float f = clamp((d - fog.x) / (fog.y - fog.x), 0.0, 1.0);
    gl_FragColor = vec4(mix(col, fog_color.rgb, f * f), tint.a);
}"#;

const HUD_VS: &str = r#"#version 100
attribute vec2 in_pos;
attribute vec4 in_color;
uniform vec4 screen;
varying lowp vec4 v_color;
void main() {
    gl_Position = vec4(in_pos.x / screen.x * 2.0 - 1.0, 1.0 - in_pos.y / screen.y * 2.0, 0.0, 1.0);
    v_color = in_color;
}"#;

const HUD_FS: &str = r#"#version 100
varying lowp vec4 v_color;
void main() { gl_FragColor = v_color; }"#;

#[repr(C)]
struct Uniforms {
    mvp: [f32; 16],
    model: [f32; 16],
    inv_scale2: [f32; 4],
    tint: [f32; 4],
    eye: [f32; 4],
    fog: [f32; 4],
    fog_color: [f32; 4],
    sun: [f32; 4],
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
    hud: Pipeline,
    meshes: Vec<Option<GpuMesh>>,
    epoch: u64,
    hud_bind: Option<(Bindings, usize)>,
    pub draw_calls: usize,
}

fn blend() -> Option<BlendState> {
    Some(BlendState::new(Equation::Add, BlendFactor::Value(BlendValue::SourceAlpha), BlendFactor::OneMinusValue(BlendValue::SourceAlpha)))
}

impl Renderer {
    pub fn new() -> Renderer {
        let mut ctx = window::new_rendering_backend();
        let u = |n: &str, t| UniformDesc::new(n, t);
        let shader = ctx
            .new_shader(
                ShaderSource::Glsl { vertex: VS, fragment: FS },
                ShaderMeta {
                    images: vec![],
                    uniforms: UniformBlockLayout {
                        uniforms: vec![
                            u("mvp", UniformType::Mat4),
                            u("model", UniformType::Mat4),
                            u("inv_scale2", UniformType::Float4),
                            u("tint", UniformType::Float4),
                            u("eye", UniformType::Float4),
                            u("fog", UniformType::Float4),
                            u("fog_color", UniformType::Float4),
                            u("sun", UniformType::Float4),
                        ],
                    },
                },
            )
            .expect("3d shader");
        let attrs = [
            VertexAttribute::new("in_pos", VertexFormat::Float3),
            VertexAttribute::new("in_normal", VertexFormat::Float3),
            VertexAttribute::new("in_color", VertexFormat::Float3),
        ];
        let base =
            PipelineParams { depth_test: Comparison::LessOrEqual, depth_write: true, cull_face: CullFace::Back, ..Default::default() };
        let opaque = ctx.new_pipeline(&[BufferLayout::default()], &attrs, shader, base);
        let alpha = ctx.new_pipeline(
            &[BufferLayout::default()],
            &attrs,
            shader,
            PipelineParams { depth_write: false, color_blend: blend(), ..base },
        );

        let hud_shader = ctx
            .new_shader(
                ShaderSource::Glsl { vertex: HUD_VS, fragment: HUD_FS },
                ShaderMeta { images: vec![], uniforms: UniformBlockLayout { uniforms: vec![u("screen", UniformType::Float4)] } },
            )
            .expect("hud shader");
        let hud = ctx.new_pipeline(
            &[BufferLayout::default()],
            &[VertexAttribute::new("in_pos", VertexFormat::Float2), VertexAttribute::new("in_color", VertexFormat::Float4)],
            hud_shader,
            PipelineParams { color_blend: blend(), ..Default::default() },
        );
        Renderer { ctx, opaque, alpha, hud, meshes: Vec::new(), epoch: 0, hud_bind: None, draw_calls: 0 }
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
                bind: Bindings { vertex_buffers: vec![vb], index_buffer: ib, images: vec![] },
                count: m.indices.len() as i32,
                radius,
                rev,
            });
        }
    }

    pub fn draw(&mut self, eng: &Engine) {
        self.sync(eng);
        let (w, h) = eng.screen;
        let cam = &eng.camera;
        let proj = Mat4::perspective(cam.fov, w / h.max(1.0), 0.1, eng.env.fog_end + 50.0);
        let view = Mat4::look_at(cam.eye, cam.target, Vec3::UP);
        let vp = proj * view;
        let fwd = (cam.target - cam.eye).norm();
        let sky = eng.env.sky;

        // Cull, then split into opaque and back-to-front alpha lists.
        let mut opaque = Vec::new();
        let mut alpha = Vec::new();
        for e in eng.ents.iter().flatten() {
            let (Some(mi), true) = (e.mesh, e.visible) else { continue };
            let Some(Some(g)) = self.meshes.get(mi) else { continue };
            let r = g.radius * e.scale.x.abs().max(e.scale.y.abs()).max(e.scale.z.abs());
            let to = e.pos - cam.eye;
            let dist = to.len();
            if dist - r > eng.env.fog_end || to.dot(fwd) < -r {
                continue;
            }
            if e.color[3] < 1.0 { alpha.push((dist, e, mi)) } else { opaque.push((dist, e, mi)) }
        }
        alpha.sort_by(|a, b| b.0.total_cmp(&a.0));

        self.ctx.begin_default_pass(PassAction::Clear { color: Some((sky[0], sky[1], sky[2], 1.0)), depth: Some(1.0), stencil: None });
        self.draw_calls = 0;
        let mut uni = Uniforms {
            mvp: [0.0; 16],
            model: [0.0; 16],
            inv_scale2: [1.0; 4],
            tint: [1.0; 4],
            eye: [cam.eye.x, cam.eye.y, cam.eye.z, 0.0],
            fog: [eng.env.fog_start, eng.env.fog_end, 0.0, 0.0],
            fog_color: [sky[0], sky[1], sky[2], 1.0],
            sun: [eng.env.sun.x, eng.env.sun.y, eng.env.sun.z, 0.0],
        };
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
