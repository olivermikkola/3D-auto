//! OpenGL via miniquad. Per frame:
//!   1. shadow pass: sun-space depth, packed into an RGBA8 texture (portable
//!      to any GL2/GLES2 driver), covering a box in front of the camera;
//!   2. sky: a full-screen gradient with sun/moon disc and night stars;
//!   3. lit pass: sun with 3x3 PCF shadows, hemisphere ambient, up to 16
//!      point/spot lights, emissive glow, distance fog (opaque, then sorted alpha);
//!   4. HUD quads.

use crate::engine::Engine;
use crate::math::{Mat4, Vec3, v3};
use crate::mesh::Mesh;
use miniquad::*;

pub const MAX_LIGHTS: usize = 16;
// 4096 texels over 340 m: twice the reach of the old 2048 over 170 m at the
// same sharpness (8 cm a texel). The Beelink's Radeon 890M draws Turku in
// 2-4 ms a frame either way. Browsers keep 2048 (some WebGL caps it).
#[cfg(not(target_arch = "wasm32"))]
const SHADOW_RES: u32 = 4096;
#[cfg(target_arch = "wasm32")]
const SHADOW_RES: u32 = 2048;
const SHADOW_SIZE: f32 = if SHADOW_RES >= 4096 { 340.0 } else { 170.0 }; // meters covered by the shadow map
const SHADOW_DEPTH: f32 = 800.0;

const PRECISION: &str = "#ifdef GL_FRAGMENT_PRECISION_HIGH\nprecision highp float;\n#else\nprecision mediump float;\n#endif\n";

const VS: &str = r#"
attribute vec3 in_pos;
attribute vec4 in_normal; // bytes: 127 is zero, 254 is one
attribute vec4 in_color;  // bytes: rgb, and emissive in a
uniform mat4 mvp;
uniform mat4 model;
uniform vec4 inv_scale2;
varying vec3 v_color;
varying vec3 v_normal;
varying vec3 v_world;
varying float v_emissive;
varying vec3 v_facade; // which facade (0: none), height above the foot (m), bays along the wall
// A facade's window bay (m), as mesh.rs's facade_bay.
float bay_of(float id) { return id < 1.5 ? 3.0 : (id < 2.5 ? 2.7 : (id < 3.5 ? 1.6 : (id < 4.5 ? 3.3 : (id < 5.5 ? 6.0 : 4.0)))); }
void main() {
    v_world = (model * vec4(in_pos, 1.0)).xyz;
    vec3 n = in_normal.xyz / 127.0 - 1.0;
    // A facade's wall is upright: its normal's y byte holds how far along it is.
    float id = in_normal.w;
    float scaled = step(127.5, id);
    id -= 128.0 * scaled;
    float ground_id = id > 63.5 ? id : 0.0; // a ground surface (64 up): no facade, its normal as it is
    if (ground_id > 0.5) id = 0.0;
    if (id > 0.5) n.y = 0.0;
    v_normal = (model * vec4(n * inv_scale2.xyz, 0.0)).xyz;
    v_color = in_color.rgb / 255.0;
    // On a facade the colour's alpha is the height, not a glow.
    float along = in_normal.y / 8.0;
    if (scaled > 0.5) {
        // A unit box stretched by its entity: as many bays as fit the wall.
        vec3 size = inversesqrt(inv_scale2.xyz);
        float len = abs(n.x) > abs(n.z) ? size.z : size.x;
        along = in_normal.y / 255.0 * max(1.0, floor(len / bay_of(id) + 0.5));
    }
    v_facade = id > 0.5 ? vec3(id, in_color.a * 0.5, along) : vec3(ground_id, 0.0, 0.0);
    v_emissive = id > 0.5 ? 0.0 : in_color.a / 255.0;
    gl_Position = mvp * vec4(in_pos, 1.0);
}"#;

const FS: &str = r#"
varying vec3 v_color;
varying vec3 v_normal;
varying vec3 v_world;
varying float v_emissive;
varying vec3 v_facade;
uniform mat4 light_vp;
uniform vec4 tint;
uniform vec4 extra; // x = entity glow, y = how wet the ground is, z = snow cover
uniform vec4 eye;
uniform vec4 fog;
uniform vec4 fog_color;
uniform vec4 sun;
uniform vec4 sun_color;
uniform vec4 ambient;
uniform vec4 ground;
uniform vec4 params; // glow, light count, shadows on, shadow texel
uniform vec4 gmap;  // the ground map: x0, z0, 1 / its width and depth in metres
uniform vec4 gmap2; // its points across and down, on (1) or not
uniform vec4 lpos[16]; // xyz, radius
uniform vec4 lcol[16]; // rgb, intensity
uniform vec4 ldir[16]; // xyz, cos(cone) or -1
uniform sampler2D shadow_map;
uniform sampler2D ground_idx; // each ground point's palette index, in alpha
uniform sampler2D ground_pal; // 256 x 1

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
    // Fade out over the map's outer tenth, so shadows don't end in a line.
    vec2 c = abs(p.xy - 0.5) * 2.0;
    return mix(lit / 9.0, 1.0, smoothstep(0.8, 1.0, max(c.x, c.y)));
}

// (No sin: big arguments lose precision on some GPUs, and the pattern speckles.)
float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// Windows drawn by the pixel on a building's walls: the buildings are boxes
// scaled to size, and windows modelled in them would stretch with them.
// Facades: 1 old town (tall windows in white frames, shops below, a string
// course each floor), 2 flats (wide windows, plain), 3 glass (curtain wall),
// 4 new render (big dark-framed windows, shops below), 5 a big shop (a glass
// front on the ground floor, a sign band over it, plain wall above), 6 works
// (ribbed cladding, a strip of high windows, a roller door every third bay).
// `wall` is the wall's
// colour; `win` comes back 1 in a window that's lit at night, `pane` 1 on
// glass (it mirrors the sky after lighting).
// `along` counts bays from the wall's corner (whole ones fit its length).
vec3 facade(float id, float y, float along, vec3 n, vec3 wall, out float win, out float pane) {
    win = 0.0;
    float fl = floor(y / 3.5);
    float fy = y - fl * 3.5;
    float old = step(id, 1.5);
    float glassy = step(2.5, id) * step(id, 3.5);
    float bay = id < 1.5 ? 3.0 : (id < 2.5 ? 2.7 : (id < 3.5 ? 1.6 : (id < 4.5 ? 3.3 : (id < 5.5 ? 6.0 : 4.0))));
    float col = floor(along);
    float fu = abs(fract(along) - 0.5) * bay;
    // Shops along the street on the old town's and new buildings' ground floor.
    float shop = (old + step(3.5, id)) * (1.0 - step(0.5, fl)); // facades 1 and 4, ground floor
    float hw = mix(id < 1.5 ? 0.55 : (id < 2.5 ? 0.8 : 0.9), bay * 0.38, shop);
    float lo = mix(id < 1.5 ? 1.0 : 1.05, 0.45, shop);
    float hi = mix(id < 1.5 ? 2.85 : 2.55, 3.05, shop);
    float inside = step(fu, hw) * step(lo, fy) * step(fy, hi);
    float frame = step(fu, hw + 0.12) * step(lo - 0.12, fy) * step(fy, hi + 0.1) * (1.0 - inside);
    if (glassy > 0.5) { // all glass but the mullions and floor slabs
        inside = step(fu, bay * 0.5 - 0.06) * step(0.35, fy);
        frame = 1.0 - inside;
    }
    // (The wall's direction rounded: the normal varies a little across a face.)
    // (Seeded by where the window's middle is, so it's the same all across it.)
    vec2 mid = v_world.xz - normalize(vec2(-n.z, n.x)) * (fract(along) - 0.5) * bay;
    float h = hash(floor(mid * 0.5 + 0.25) + vec2(fl * 7.0, 0.0));
    vec3 glass = mix(vec3(0.1, 0.12, 0.15), ambient.rgb * 0.55, 0.25 + 0.35 * h);
    vec3 trim = id < 1.5 ? vec3(0.93, 0.92, 0.88) : (id < 3.5 ? wall * 0.8 : vec3(0.22, 0.22, 0.23));
    // A string course along the old town's floors, and a darker plinth under the shops.
    float course = old * step(fy, 0.22) * step(0.5, fl);
    vec3 c = mix(wall, wall * 0.82, course);
    // The floors' slab edges: a joint between the flats' panels, a band of
    // lighter render on new buildings.
    float flats = step(1.5, id) * step(id, 2.5);
    float slab = step(0.5, fl) * (flats * step(fy, 0.12) + step(3.5, id) * step(id, 4.5) * step(fy, 0.3));
    c = mix(c, flats > 0.5 ? wall * 0.55 : min(wall * 1.25 + 0.08, vec3(1.0)), slab);
    c = mix(c, wall * 0.6, shop * (1.0 - step(0.45, fy)));
    c = mix(c, trim, frame);
    c = mix(c, glass, inside);
    win = inside * step(h, shop > 0.5 ? 0.6 : 0.3);
    pane = inside * (0.3 + 0.25 * h);
    if (id > 4.5 && id < 5.5) { // a big shop
        float front = step(fu, bay * 0.5 - 0.12) * step(0.3, y) * step(y, 3.4);
        float mullion = step(fract(along * 3.0), 0.03) * front;
        front *= 1.0 - mullion;
        float sign = step(3.7, y) * step(y, 4.9);
        c = mix(wall, wall * 0.55, step(y, 0.3));
        c = mix(c, vec3(0.2, 0.21, 0.23), step(3.4, y) * step(y, 3.7) + mullion);
        // The sign band: dark, with a lighter edge, a colour per shop bay.
        vec3 brand = mix(vec3(0.75, 0.16, 0.12), vec3(0.12, 0.3, 0.62), step(0.5, h));
        c = mix(c, mix(vec3(0.16, 0.16, 0.18), brand, step(0.66, h) * step(abs(fract(along) - 0.5), 0.3)), sign);
        c = mix(c, glass, front);
        win = front * step(h, 0.7) + sign * step(0.66, h) * step(abs(fract(along) - 0.5), 0.3) * 0.6;
        pane = front * (0.3 + 0.25 * h);
    } else if (id > 5.5) { // works
        float rib = step(fract(along * 6.0), 0.1);
        float high = step(fu, bay * 0.5 - 0.15) * step(4.4, y) * step(y, 5.2);
        float door = step(abs(mod(col, 3.0) - 1.0), 0.1) * step(fu, 1.7) * step(y, 4.0);
        c = mix(wall, wall * 0.84, rib);
        c = mix(c, mix(vec3(0.34, 0.35, 0.37), vec3(0.28, 0.29, 0.31), step(fract(y * 2.5), 0.12)), door);
        c = mix(c, vec3(0.2, 0.2, 0.21), step(fu, 1.85) * step(y, 4.15) * step(abs(mod(col, 3.0) - 1.0), 0.1) * (1.0 - door));
        c = mix(c, glass, high);
        win = high * step(h, 0.2);
        pane = high * (0.2 + 0.2 * h);
    }
    return c;
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The ground map's colour at world (x, z) p: the four nearest points'
// palette colours, blended (an index can't be).
vec3 pal_at(vec2 t) {
    float k = texture2D(ground_idx, (t + 0.5) / gmap2.xy).a;
    return texture2D(ground_pal, vec2((k * 255.0 + 0.5) / 256.0, 0.5)).rgb;
}
vec3 ground_map(vec2 p) {
    vec2 t = (p - gmap.xy) * gmap.zw * gmap2.xy - 0.5;
    vec2 i = floor(t);
    vec2 f = t - i;
    vec3 a = mix(pal_at(i), pal_at(i + vec2(1.0, 0.0)), f.x);
    vec3 b = mix(pal_at(i + vec2(0.0, 1.0)), pal_at(i + vec2(1.0, 1.0)), f.x);
    return mix(a, b, f.y);
}

// The ground's surface by the pixel (64 worn asphalt, 65 setts), on its
// colour c, at world (x, z) p.
vec3 ground_surface(float id, vec3 c, vec2 p) {
    if (id < 64.5) {
        // Asphalt: blotches of wear at two sizes, the stones in it, and now
        // and then a patch where it's been dug up and laid again.
        float wear = vnoise(p * 0.08) * 0.6 + vnoise(p * 0.45) * 0.4;
        float grit = hash(floor(p * 9.0));
        vec2 cell = floor(p / vec2(7.0, 4.0));
        vec2 in_cell = fract(p / vec2(7.0, 4.0));
        float redone = step(hash(cell + 17.0), 0.05) * step(0.15, in_cell.x) * step(in_cell.x, 0.8) * step(0.2, in_cell.y) * step(in_cell.y, 0.85);
        c *= 0.9 + 0.2 * wear + 0.06 * (grit - 0.5);
        return mix(c, c * 0.8, redone);
    }
    // Setts: rows of 0.16 m stones, every other row half a stone along,
    // each its own shade, in darker joints.
    vec2 q = p / 0.16;
    q.x += 0.5 * mod(floor(q.y), 2.0);
    vec2 f = abs(fract(q) - 0.5);
    float joint = step(0.42, max(f.x, f.y));
    float shade = 0.82 + 0.3 * hash(floor(q));
    return mix(c * shade, c * 0.55, joint);
}

void main() {
    vec3 n = normalize(v_normal);
    vec3 base = v_color * tint.rgb;
    if (v_facade.x > 65.5) {
        // The terrain: its colour from the ground map where there's one.
        vec2 uv = (v_world.xz - gmap.xy) * gmap.zw;
        if (gmap2.z > 0.5 && uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) base = ground_map(v_world.xz) * tint.rgb;
    } else if (v_facade.x > 63.5 && n.y > 0.5) {
        // Far off, the pattern would shimmer: it fades to the plain colour.
        float far = smoothstep(40.0, 140.0, length(v_world - eye.xyz));
        base = mix(ground_surface(v_facade.x, base, v_world.xz), base, far);
    }
    float lit_window = 0.0;
    float pane = 0.0;
    if (v_facade.x > 0.5 && v_facade.x < 63.5 && abs(n.y) < 0.4) {
        // Far off, the pattern would shimmer: it fades to its average.
        float far = smoothstep(110.0, 220.0, length(v_world - eye.xyz));
        vec3 drawn = facade(v_facade.x, v_facade.y, v_facade.z, n, base, lit_window, pane);
        base = mix(drawn, base * 0.8, far);
        lit_window *= 1.0 - far;
        pane *= 1.0 - far;
    }
    float ndl = max(dot(n, sun.xyz), 0.0);
    vec3 light = mix(ground.rgb, ambient.rgb, 0.5 + 0.5 * n.y) + sun_color.rgb * ndl * shadow(ndl);
    vec3 lamps = vec3(0.0);
    for (int i = 0; i < 16; i++) {
        if (float(i) >= params.y) break;
        vec3 l = lpos[i].xyz - v_world;
        float d = length(l);
        l /= max(d, 0.001);
        float att = clamp(1.0 - d / lpos[i].w, 0.0, 1.0);
        // A spot fades from its axis out to the cone's edge, not just at it.
        float c = ldir[i].w;
        float spot = c < -0.5 ? 1.0 : smoothstep(c, c + (1.0 - c) * 0.7, dot(-l, ldir[i].xyz));
        lamps += lcol[i].rgb * (lcol[i].w * att * att * spot * (0.25 + 0.75 * max(dot(n, l), 0.0)));
    }
    // Overlapping pools add up, but toward a ceiling instead of to white.
    // Wet ground: flat, dark, grey surfaces (asphalt, paving) get darker,
    // lamp pools spread brighter on them, and they mirror the sky when
    // seen at a low angle.
    float sat = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
    float lum = dot(base, vec3(0.3, 0.55, 0.15));
    float asphalt = (1.0 - smoothstep(0.06, 0.16, sat)) * (1.0 - smoothstep(0.3, 0.55, lum));
    float wet = extra.y * smoothstep(0.85, 0.97, n.y) * asphalt;
    // Snow lies on what faces up: grass, roofs, pavements; roads only thinly
    // (traffic keeps them dark).
    float snow = extra.z * smoothstep(0.6, 0.85, n.y) * (1.0 - 0.65 * asphalt);
    base = mix(base, vec3(0.9, 0.92, 0.96), snow);
    light += lamps * wet * 0.8;
    light += lamps / (1.0 + 0.4 * lamps);
    float glow = v_emissive * params.x + extra.x;
    // A lit window at night: warm light from inside, not the glass's own colour.
    base = mix(base, vec3(1.0, 0.82, 0.5) * 0.55, lit_window * params.x);
    glow += lit_window * params.x;
    vec3 col = base * light * (1.0 - 0.35 * wet) + base * glow * 1.8;
    // Glass mirrors the sky (the fog's colour is the horizon's: dark at night).
    col = mix(col, fog_color.rgb * 0.75, pane * (1.0 - lit_window * params.x));
    // Glass mirrors the sky (the fog's colour is the horizon's: dark at night).
    col = mix(col, fog_color.rgb * 0.75, pane * (1.0 - lit_window * params.x));
    vec3 to_eye = normalize(eye.xyz - v_world);
    float sheen = pow(1.0 - max(to_eye.y, 0.0), 5.0);
    col = mix(col, fog_color.rgb * 0.8, wet * sheen * 0.7);
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

/// A ground map's texture: points, not blended (an index can't be).
fn ground_tex(format: TextureFormat, width: u32, height: u32) -> TextureParams {
    TextureParams {
        format,
        width,
        height,
        min_filter: FilterMode::Nearest,
        mag_filter: FilterMode::Nearest,
        wrap: TextureWrap::Clamp,
        ..Default::default()
    }
}

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
    gmap: [f32; 4],
    gmap2: [f32; 4],
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
    center: Vec3,
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
    /// The ground map's textures (placeholders until a map has one), and
    /// its uniforms; `ground_rev` is the engine's map they hold.
    ground_idx: TextureId,
    ground_pal: TextureId,
    gmap: [f32; 4],
    gmap2: [f32; 4],
    ground_rev: u32,
    ground_taken: bool,
    meshes: Vec<Option<GpuMesh>>,
    /// Meshes uploaded since the last `take_uploaded`.
    uploaded: Vec<usize>,
    epoch: u64,
    hud_bind: Option<(Bindings, usize)>,
    pub draw_calls: usize,
    /// Triangles drawn last frame, shadow pass included.
    pub triangles: usize,
    pub lights_used: usize,
    /// PROFILE=1: times each frame on the GPU (see `GpuTimer`).
    pub gpu_timer: Option<GpuTimer>,
}

/// PROFILE=1: how long the GPU spends on each frame, from GL timer queries
/// (core since OpenGL 3.3). The CPU-side "draw" time only covers handing
/// the commands over; this is the time the graphics card takes to run them.
/// Three queries take turns, so reading one never stalls on the GPU; a
/// frame whose turn comes while its query is still running isn't timed.
#[derive(Default)]
pub struct GpuTimer {
    queries: [u32; 3],
    running: [bool; 3],
    next: usize,
    timing: bool,
    /// Seconds the GPU took over `frames` timed frames, since the last `take`.
    seconds: f64,
    frames: u32,
}

impl GpuTimer {
    /// None where timer queries don't exist (OpenGL before 3.3, GLES, web).
    pub fn new(gl_version: &str) -> Option<GpuTimer> {
        let ok = !cfg!(target_arch = "wasm32")
            && !gl_version.contains("OpenGL ES")
            && (gl_version.starts_with("3.3") || gl_version.starts_with('4'));
        ok.then(GpuTimer::default)
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn begin(&mut self) {
        use miniquad::gl::*;
        let k = self.next;
        unsafe {
            if self.queries[k] == 0 {
                glGenQueries(1, &mut self.queries[k]);
            }
            if self.running[k] {
                let mut done = 0;
                glGetQueryObjectiv(self.queries[k], GL_QUERY_RESULT_AVAILABLE, &mut done);
                if done == 0 {
                    return;
                }
                let mut ns: u64 = 0;
                glGetQueryObjectui64v(self.queries[k], GL_QUERY_RESULT, &mut ns);
                self.seconds += ns as f64 * 1e-9;
                self.frames += 1;
                self.running[k] = false;
            }
            glBeginQuery(GL_TIME_ELAPSED, self.queries[k]);
        }
        self.timing = true;
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn end(&mut self) {
        if std::mem::take(&mut self.timing) {
            unsafe { miniquad::gl::glEndQuery(miniquad::gl::GL_TIME_ELAPSED) };
            self.running[self.next] = true;
            self.next = (self.next + 1) % self.queries.len();
        }
    }

    #[cfg(target_arch = "wasm32")]
    fn begin(&mut self) {}
    #[cfg(target_arch = "wasm32")]
    fn end(&mut self) {}

    /// The GPU's seconds and frames timed since the last call.
    pub fn take(&mut self) -> (f64, u32) {
        (std::mem::take(&mut self.seconds), std::mem::take(&mut self.frames))
    }
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

fn mesh_bounds(mesh: &crate::mesh::Mesh) -> (Vec3, f32) {
    let Some(first) = mesh.verts.first() else { return (Vec3::ZERO, 0.0) };
    let (mut lo, mut hi) = (first.pos(), first.pos());
    for v in &mesh.verts {
        let p = v.pos();
        lo = v3(lo.x.min(p.x), lo.y.min(p.y), lo.z.min(p.z));
        hi = v3(hi.x.max(p.x), hi.y.max(p.y), hi.z.max(p.z));
    }
    let center = (lo + hi) * 0.5;
    let radius = mesh.verts.iter().map(|v| (v.pos() - center).len()).fold(0.0, f32::max);
    (center, radius)
}

fn world_bounds(center: Vec3, radius: f32, pos: Vec3, rotation: crate::math::Quat, scale: Vec3) -> (Vec3, f32) {
    (pos + rotation.rotate(center.mul(scale)), radius * scale.x.abs().max(scale.y.abs()).max(scale.z.abs()))
}

/// Conservative sphere test against all six OpenGL clip planes. Radius is
/// world-space; unnormalized plane normals avoid six divisions per entity.
fn sphere_visible(vp: &Mat4, eye: Vec3, center: Vec3, radius: f32, fog_end: f32) -> bool {
    if (center - eye).len() - radius > fog_end {
        return false;
    }
    let m = &vp.0;
    for axis in 0..3 {
        for sign in [-1.0, 1.0] {
            let normal = v3(m[3] + sign * m[axis], m[7] + sign * m[4 + axis], m[11] + sign * m[8 + axis]);
            let offset = m[15] + sign * m[12 + axis];
            if normal.dot(center) + offset < -radius * normal.len() - 1e-3 {
                return false;
            }
        }
    }
    true
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
                ("gmap", Float4, 1),
                ("gmap2", Float4, 1),
                ("lpos", Float4, MAX_LIGHTS),
                ("lcol", Float4, MAX_LIGHTS),
                ("ldir", Float4, MAX_LIGHTS),
            ],
            &["shadow_map", "ground_idx", "ground_pal"],
        );
        let attrs = [
            VertexAttribute::new("in_pos", VertexFormat::Float3),
            VertexAttribute::new("in_normal", VertexFormat::Byte4),
            VertexAttribute::new("in_color", VertexFormat::Byte4),
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
        let ground_idx = ctx.new_texture_from_data_and_format(&[0], ground_tex(TextureFormat::Alpha, 1, 1));
        let ground_pal = ctx.new_texture_from_data_and_format(&[0; 4], ground_tex(TextureFormat::RGBA8, 1, 1));
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
            ground_idx,
            ground_pal,
            gmap: [0.0; 4],
            gmap2: [1.0, 1.0, 0.0, 0.0],
            ground_rev: 0,
            ground_taken: false,
            meshes: Vec::new(),
            uploaded: Vec::new(),
            epoch: 0,
            hud_bind: None,
            draw_calls: 0,
            triangles: 0,
            lights_used: 0,
            gpu_timer: None,
        }
    }

    /// Which GPU and driver draw the game: "renderer (vendor), OpenGL version".
    #[cfg(not(target_arch = "wasm32"))]
    pub fn gpu_name(&self) -> String {
        use miniquad::gl::*;
        const GL_RENDERER: u32 = 0x1F01; // missing from miniquad's list
        let get = |name| unsafe {
            let p = glGetString(name);
            if p.is_null() { String::from("?") } else { std::ffi::CStr::from_ptr(p as _).to_string_lossy().into_owned() }
        };
        format!("{} ({}), OpenGL {}", get(GL_RENDERER), get(GL_VENDOR), get(GL_VERSION))
    }

    #[cfg(target_arch = "wasm32")]
    pub fn gpu_name(&self) -> String {
        format!("WebGL, OpenGL {}", self.ctx.info().gl_version_string)
    }

    /// PROFILE=1: start timing frames on the GPU, where the driver can.
    pub fn time_gpu(&mut self) {
        self.gpu_timer = GpuTimer::new(&self.ctx.info().gl_version_string);
    }

    /// A new engine (a reload) means new meshes: drop the old ones' buffers.
    fn reset_if(&mut self, epoch: u64) {
        if epoch != self.epoch {
            for m in self.meshes.drain(..).flatten() {
                self.ctx.delete_buffer(m.bind.vertex_buffers[0]);
                self.ctx.delete_buffer(m.bind.index_buffer);
            }
            self.epoch = epoch;
        }
    }

    /// The engine's ground map onto the GPU when it's a new one (its
    /// points are then the engine's to drop: `take_ground`).
    fn sync_ground(&mut self, eng: &Engine) {
        match &eng.ground_map {
            Some(g) if g.rev != self.ground_rev && !g.idx.is_empty() => {
                self.ctx.delete_texture(self.ground_idx);
                self.ctx.delete_texture(self.ground_pal);
                self.ground_idx =
                    self.ctx.new_texture_from_data_and_format(&g.idx, ground_tex(TextureFormat::Alpha, g.w as u32, g.h as u32));
                let mut pal = vec![0u8; 256 * 4];
                for (k, c) in g.palette.iter().take(256).enumerate() {
                    pal[4 * k..4 * k + 3].copy_from_slice(c);
                    pal[4 * k + 3] = 255;
                }
                self.ground_pal = self.ctx.new_texture_from_data_and_format(&pal, ground_tex(TextureFormat::RGBA8, 256, 1));
                for m in self.meshes.iter_mut().flatten() {
                    m.bind.images = vec![self.shadow_tex, self.ground_idx, self.ground_pal];
                }
                let (wm, hm) = (g.w as f32 * g.step, g.h as f32 * g.step);
                // (the points are at the cells' middles: x0 is the first one's)
                self.gmap = [g.x0 - g.step / 2.0, g.z0 - g.step / 2.0, 1.0 / wm, 1.0 / hm];
                self.gmap2 = [g.w as f32, g.h as f32, 1.0, 0.0];
                self.ground_rev = g.rev;
                self.ground_taken = true;
            }
            None => self.gmap2[2] = 0.0,
            _ => {}
        }
    }

    /// Whether a ground map went to the GPU since the last call: its points
    /// can go from the engine (in the browser they'd be 10 MB held for nothing).
    pub fn take_ground(&mut self) -> bool {
        std::mem::take(&mut self.ground_taken)
    }

    /// Mesh i at revision rev onto the GPU, replacing what was there.
    fn put(&mut self, i: usize, rev: u32, m: &Mesh) {
        if self.meshes.len() <= i {
            self.meshes.resize_with(i + 1, || None);
        }
        if let Some(old) = self.meshes[i].take() {
            self.ctx.delete_buffer(old.bind.vertex_buffers[0]);
            self.ctx.delete_buffer(old.bind.index_buffer);
        }
        if m.indices.is_empty() {
            return;
        }
        let vb = self.ctx.new_buffer(BufferType::VertexBuffer, BufferUsage::Immutable, BufferSource::slice(&m.verts));
        let ib = self.ctx.new_buffer(BufferType::IndexBuffer, BufferUsage::Immutable, BufferSource::slice(&m.indices));
        let (center, radius) = mesh_bounds(m);
        self.meshes[i] = Some(GpuMesh {
            bind: Bindings { vertex_buffers: vec![vb], index_buffer: ib, images: vec![self.shadow_tex, self.ground_idx, self.ground_pal] },
            count: m.indices.len() as i32,
            radius,
            center,
            rev,
        });
    }

    /// A mesh the engine is about to drop its vertices for (Engine::uploader).
    pub fn upload(&mut self, epoch: u64, i: usize, rev: u32, m: &Mesh) {
        self.reset_if(epoch);
        self.put(i, rev, m);
    }

    fn sync(&mut self, eng: &Engine) {
        self.reset_if(eng.epoch);
        self.sync_ground(eng);
        self.meshes.resize_with(self.meshes.len().max(eng.meshes.len()), || None);
        for (i, m) in eng.meshes.iter().enumerate() {
            let rev = eng.mesh_revs[i];
            if self.meshes[i].as_ref().is_some_and(|g| g.rev == rev) || eng.gpu_only.contains(&i) {
                continue;
            }
            self.put(i, rev, m);
            if self.meshes[i].is_some() {
                self.uploaded.push(i);
            }
        }
    }

    /// Meshes uploaded since the last call, whose CPU copies the engine may drop.
    pub fn take_uploaded(&mut self) -> Vec<usize> {
        std::mem::take(&mut self.uploaded)
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
        // The camera keeps 0.4 m off walls, so a 0.25 m near plane clips
        // nothing and buys depth precision for flat details far away.
        let proj = Mat4::perspective(cam.fov, aspect, 0.25, env.fog_end + 50.0);
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
            let (center, r) = world_bounds(g.center, g.radius, e.pos, e.rot, e.scale);
            let to = center - cam.eye;
            let dist = to.len();
            if shadows && e.shadow && e.color[3] >= 1.0 && Some(mi) != plane {
                let d = center - focus;
                if (d.x * d.x + d.z * d.z).sqrt() - r < SHADOW_SIZE * 0.75 {
                    casters.push((e, mi));
                }
            }
            if !sphere_visible(&vp, cam.eye, center, r, env.fog_end) {
                continue;
            }
            if e.color[3] < 1.0 { alpha.push((dist, e, mi)) } else { opaque.push((dist, e, mi)) }
        }
        alpha.sort_by(|a, b| b.0.total_cmp(&a.0));
        self.draw_calls = 0;
        self.triangles = 0;
        if let Some(t) = &mut self.gpu_timer {
            t.begin();
        }

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
                self.triangles += g.count as usize / 3;
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
            extra: [0.0, env.wet, env.snow, 0.0],
            eye: v4(cam.eye, 0.),
            fog: [env.fog_start, env.fog_end, 0.0, 0.0],
            fog_color: c4(env.sky, 1.),
            sun: v4(env.sun, 0.),
            sun_color: c4(env.sun_color, 1.),
            ambient: c4(env.ambient, 1.),
            ground: c4(env.ground, 1.),
            params: [env.glow, 0.0, if shadows { 1.0 } else { 0.0 }, 1.0 / SHADOW_RES as f32],
            gmap: self.gmap,
            gmap2: self.gmap2,
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
                self.triangles += g.count as usize / 3;
            }
        }
        self.draw_hud(eng);
        self.ctx.end_render_pass();
        if let Some(t) = &mut self.gpu_timer {
            t.end();
        }
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
    fn bounds_center_tracks_world_coordinate_terrain_and_rotated_scale() {
        let mut mesh = crate::mesh::Mesh::default();
        mesh.verts = vec![
            crate::mesh::Vertex::new(v3(100., 0., 200.), Vec3::UP, Vec3::ONE, 0.),
            crate::mesh::Vertex::new(v3(120., 10., 220.), Vec3::UP, Vec3::ONE, 0.),
        ];
        let (center, radius) = mesh_bounds(&mesh);
        assert_eq!(center, v3(110., 5., 210.));
        assert!((radius - v3(10., 5., 10.).len()).abs() < 1e-4);
        let rotation = crate::math::Quat::axis_angle(Vec3::UP, std::f32::consts::FRAC_PI_2);
        let (world, scaled) = world_bounds(center, radius, v3(7., 2., 3.), rotation, v3(-2., 3., 1.));
        assert!((world - (v3(7., 2., 3.) + rotation.rotate(center.mul(v3(-2., 3., 1.))))).len() < 1e-4);
        assert!((scaled - radius * 3.).abs() < 1e-4);
    }

    #[test]
    fn view_rejects_spheres_outside_each_clip_plane() {
        let vp = Mat4::perspective(std::f32::consts::FRAC_PI_2, 1.0, 1.0, 100.0);
        assert!(sphere_visible(&vp, Vec3::ZERO, v3(0., 0., -10.), 0.5, 200.));
        for center in [v3(-20., 0., -10.), v3(20., 0., -10.), v3(0., -20., -10.), v3(0., 20., -10.), v3(0., 0., 2.), v3(0., 0., -110.)] {
            assert!(!sphere_visible(&vp, Vec3::ZERO, center, 0.5, 200.), "outside: {center:?}");
        }
        assert!(sphere_visible(&vp, Vec3::ZERO, v3(10.2, 0., -10.), 0.5, 200.), "intersecting side plane must remain");
        assert!(sphere_visible(&vp, Vec3::ZERO, Vec3::ZERO, 2., 200.), "sphere enclosing camera must remain");
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
