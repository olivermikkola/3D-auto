struct Scene {
    view_projection: mat4x4f,
    eye: vec4f,
    fog: vec4f,
    sky: vec4f,
    sun: vec4f,
    sun_color: vec4f,
    ambient: vec4f,
    bounce: vec4f,
    light_projection: mat4x4f,
    camera_forward: vec4f,
    camera_right: vec4f,
    camera_up: vec4f,
    sky_top: vec4f,
    material_ground: vec4f,
    post: vec4f,
    light_far: mat4x4f,
    cascades: vec4f,
    // The lamp grid: x, z of its corner, cell size (m), 1 when any lamp is lit.
    lamp_grid: vec4f,
    // x: how wet the streets are, y: how hard it rains, z: seconds, w: cloud cover.
    weather: vec4f,
}

// Lamps and headlights near the camera (render2.rs `Lamps`): per light
// position + radius, colour, direction + cos(half cone) (-1: all round);
// per grid cell 8 light indices, a byte each (255: none), two cells a row.
struct Lamps {
    lights: array<vec4f, 384>,
    cells: array<vec4u, 512>,
}

struct Object {
    model: mat4x4f,
    tint: vec4f,
    inv_scale_sq: vec4f,
    material_flags: vec4u,
}

@group(0) @binding(0) var<uniform> scene: Scene;
@group(0) @binding(1) var<uniform> object: Object;
@group(0) @binding(2) var<storage, read> human_poses: array<vec4f>;
@group(0) @binding(3) var human_atlas: texture_2d<f32>;
@group(0) @binding(4) var human_sampler: sampler;
@group(0) @binding(5) var car_atlas: texture_2d<f32>;
@group(0) @binding(6) var prop_atlas: texture_2d<f32>;
@group(0) @binding(7) var leaf_texture: texture_2d<f32>;
@group(0) @binding(8) var<uniform> lamps: Lamps;
@group(1) @binding(0) var sun_depth: texture_depth_2d_array;
@group(1) @binding(1) var sun_sampler: sampler_comparison;
@group(2) @binding(0) var material_albedo: texture_2d_array<f32>;
@group(2) @binding(1) var material_surface: texture_2d_array<f32>;
@group(2) @binding(2) var terrain_classes: texture_2d<u32>;
@group(2) @binding(3) var material_sampler: sampler;

struct WorldVertex {
    @builtin(position) clip: vec4f,
    @location(0) world: vec3f,
    @location(1) normal: vec3f,
    @location(2) color: vec4f,
    @location(3) emissive: f32,
    @location(4) @interpolate(flat) surface: u32,
    @location(5) uv_m: vec2f,
    @location(6) @interpolate(flat) obj_role: u32,
}

fn webgpu_clip(gl: vec4f) -> vec4f {
    return vec4f(gl.xy, 0.5 * (gl.z + gl.w), gl.w);
}

// Turn p about the x axis through (y, z) = pivot.
fn swing_x(p: vec3f, pivot: vec2f, angle: f32) -> vec3f {
    let y = p.y - pivot.x;
    let z = p.z - pivot.y;
    let c = cos(angle);
    let s = sin(angle);
    return vec3f(p.x, pivot.x + y * c - z * s, pivot.y + y * s + z * c);
}

// Walkers (tag "walker") swing their legs about the hip and arms about the
// shoulder, in step with the distance walked (a 1.4 m stride). Shins (roles
// 11, 12) also bend at the knee as their leg comes through.
// Roles: 7/8 left/right thigh, 9/10 left/right arm, 11/12 left/right shin.
fn walk_pose(pos: vec3f, role: u32) -> vec3f {
    if object.material_flags.y == 0u || role < 7u || role > 12u { return pos; }
    let phase = bitcast<f32>(object.material_flags.z) * 6.2831853 / 1.4;
    let left = role == 7u || role == 9u || role == 11u;
    if role == 9u || role == 10u {
        // Arms swing against the leg on their side.
        return swing_x(pos, vec2f(1.40, 0.0), -0.35 * sin(phase + select(3.14159265, 0.0, left)));
    }
    let leg_phase = phase + select(3.14159265, 0.0, left);
    var p = pos;
    if role >= 11u {
        p = swing_x(p, vec2f(0.48, 0.0), 0.65 * max(0.0, cos(leg_phase)));
    }
    return swing_x(p, vec2f(0.90, 0.0), 0.42 * sin(leg_phase));
}

// A skinned person's vertex (mesh.rs SKINNED): bit 31, three 5-bit bones
// and two 8-bit weights (the third is the rest). The object says which
// person (w & 255, +1), the pose table's frames and bones, and (z) where
// in the walk cycle it is and how still it stands; the pose is blended
// between the two nearest baked frames, then toward the standing pose.
const SKINNED = 0x80000000u;

fn is_skinned(role: u32) -> bool {
    return (role & SKINNED) != 0u && (object.material_flags.w & 255u) != 0u;
}

fn skin_rows(role: u32) -> array<vec4f, 3> {
    let info = object.material_flags.w;
    let person = (info & 255u) - 1u;
    let frames = (info >> 8u) & 255u;
    let bones = info >> 16u;
    let packed = object.material_flags.z;
    let phase = f32(packed & 65535u) / 65536.0 * f32(frames);
    let still = f32(packed >> 16u) / 65535.0;
    let f0 = u32(floor(phase)) % frames;
    let f1 = (f0 + 1u) % frames;
    let t = phase - floor(phase);
    // Each person has `frames` walk poses, then a standing one.
    let first = person * (frames + 1u);
    let a = (first + f0) * bones;
    let b = (first + f1) * bones;
    let stand = (first + frames) * bones;
    let joints = vec3u(role & 31u, (role >> 5u) & 31u, (role >> 10u) & 31u);
    let w0 = f32((role >> 15u) & 255u) / 255.0;
    let w1 = f32((role >> 23u) & 255u) / 255.0;
    let weights = vec3f(w0, w1, max(0.0, 1.0 - w0 - w1));
    var rows = array<vec4f, 3>(vec4f(0.0), vec4f(0.0), vec4f(0.0));
    for (var k = 0u; k < 3u; k++) {
        if weights[k] <= 0.0 { continue; }
        for (var r = 0u; r < 3u; r++) {
            let walking = mix(human_poses[(a + joints[k]) * 3u + r], human_poses[(b + joints[k]) * 3u + r], t);
            let row = mix(walking, human_poses[(stand + joints[k]) * 3u + r], still);
            rows[r] += weights[k] * row;
        }
    }
    return rows;
}

fn skin_point(rows: array<vec4f, 3>, p: vec3f) -> vec3f {
    let h = vec4f(p, 1.0);
    return vec3f(dot(rows[0], h), dot(rows[1], h), dot(rows[2], h));
}

// Where a vertex is drawn this frame: skinned people walk, the old figures swing limbs.
fn posed(pos: vec3f, role: u32) -> vec3f {
    if is_skinned(role) { return skin_point(skin_rows(role), pos); }
    return walk_pose(pos, role);
}

// Cars (mesh.rs CAR_ROLE, WHEEL): a wheel's vertices carry its hub, along
// the car (+z) and up, in cm; it rolls forward by the distance the car has
// driven (object z) over its radius (the hub's height).
const CAR_ROLE = 13u;
// A prop (mesh.rs PROP_ROLE: shop signs, tram livery): its colour from the
// prop atlas at its OBJ texture coordinate.
const PROP_ROLE = 14u;
const WHEEL = 0x40000000u;
// A number plate (mesh.rs PLATE): its atlas rows move down by a step (bits
// 5-15, pixels) times this car's pick (object w) below a count (bits 16-23).
const PLATE = 0x20000000u;

// The object's kind (object x, low byte: 1 a building, 2 a car that drives);
// for cars bit 8 is braking and bits 16-31 the front wheels' angle.
fn object_kind() -> u32 { return object.material_flags.x & 255u; }
fn braking() -> bool { return (object.material_flags.x & 256u) != 0u; }
fn steer_angle() -> f32 { return (f32(object.material_flags.x >> 16u) - 32768.0) / 10000.0; }
// Where a front wheel turns: about the upright through its middle, this far
// out from the car's centre line (cars.py: half the width less 0.14 m, ±4 cm).
const WHEEL_TRACK = 0.78;

// Turn p about the upright through (x, z) = pivot, the way a yaw turns
// (+z toward +x).
fn swing_y(p: vec3f, pivot: vec2f, angle: f32) -> vec3f {
    let x = p.x - pivot.x;
    let z = p.z - pivot.y;
    let c = cos(angle);
    let s = sin(angle);
    return vec3f(pivot.x + x * c + z * s, p.y, pivot.y - x * s + z * c);
}

fn is_car(role: u32) -> bool {
    return (role & SKINNED) == 0u && (role & 31u) == CAR_ROLE;
}

fn world_parameters(raw: vec3f, packed_normal: vec4u, color: vec4f, uv_in: vec2f, role: u32) -> WorldVertex {
    var pos = walk_pose(raw, role);
    var uv = uv_in;
    if is_car(role) && (role & PLATE) != 0u {
        let pick = object.material_flags.w % max((role >> 16u) & 255u, 1u);
        uv.y -= f32(pick * ((role >> 5u) & 2047u)) / f32(textureDimensions(car_atlas).y);
    }
    var normal = vec3f(packed_normal.xyz) / 127.0 - 1.0;
    if is_skinned(role) {
        let rows = skin_rows(role);
        pos = skin_point(rows, raw);
        normal = vec3f(dot(rows[0].xyz, normal), dot(rows[1].xyz, normal), dot(rows[2].xyz, normal));
    } else if is_car(role) && (role & WHEEL) != 0u {
        let hub = vec2f(f32((role >> 16u) & 255u), f32((role >> 5u) & 2047u) - 1024.0) / 100.0;
        let angle = bitcast<f32>(object.material_flags.z) / max(hub.x, 0.1);
        pos = swing_x(pos, hub, angle);
        normal = swing_x(normal, vec2f(0.0), angle);
        // Front wheels (ahead of the middle) turn with the steering.
        if hub.y > 0.0 {
            let turn = steer_angle();
            pos = swing_y(pos, vec2f(sign(raw.x) * WHEEL_TRACK, hub.y), turn);
            normal = swing_y(normal, vec2f(0.0), turn);
        }
    }
    let world = object.model * vec4f(pos, 1.0);
    // Engine matrices use OpenGL's -w to w depth. WebGPU clips from 0 to w.
    let clip = webgpu_clip(scene.view_projection * world);
    let facade = packed_normal.w & 127u;
    let is_facade = facade > 0u && facade < 64u;
    if is_facade { normal.y = 0.0; }
    let world_normal = object.model * vec4f(normal * object.inv_scale_sq.xyz, 0.0);
    return WorldVertex(
        clip, world.xyz, world_normal.xyz,
        vec4f(color.rgb * object.tint.rgb, object.tint.a),
        select(color.a, 0.0, is_facade),
        facade,
        vec2f(uv.x, -uv.y),
        role,
    );
}

@vertex
fn world_vertex(@location(0) pos: vec3f, @location(1) packed_normal: vec4u, @location(2) color: vec4f) -> WorldVertex {
    return world_parameters(pos, packed_normal, color, vec2f(0.0), 0u);
}

@vertex
fn world_uv_vertex(
    @location(0) pos: vec3f, @location(1) packed_normal: vec4u, @location(2) color: vec4f,
    @location(3) uv: vec2f, @location(4) role: u32,
) -> WorldVertex {
    return world_parameters(pos, packed_normal, color, uv, role);
}

@vertex
fn shadow_vertex(@location(0) pos: vec3f) -> @builtin(position) vec4f {
    return webgpu_clip(scene.light_projection * object.model * vec4f(pos, 1.0));
}

struct ShadowUv {
    @builtin(position) clip: vec4f,
    @location(0) uv: vec2f,
    @location(1) @interpolate(flat) role: u32,
}

@vertex
fn shadow_uv_vertex(@location(0) pos: vec3f, @location(3) uv: vec2f, @location(4) role: u32) -> ShadowUv {
    return ShadowUv(webgpu_clip(scene.light_projection * object.model * vec4f(posed(pos, role), 1.0)), uv, role);
}

@vertex
fn shadow_far_vertex(@location(0) pos: vec3f) -> @builtin(position) vec4f {
    return webgpu_clip(scene.light_far * object.model * vec4f(pos, 1.0));
}

@vertex
fn shadow_uv_far_vertex(@location(0) pos: vec3f, @location(3) uv: vec2f, @location(4) role: u32) -> ShadowUv {
    return ShadowUv(webgpu_clip(scene.light_far * object.model * vec4f(posed(pos, role), 1.0)), uv, role);
}

const LEAF_ROLE = 5u;
const GLASS_ROLE = 6u;

// The HDR look (scene.post.x = 1): stronger sun against the sky light, haze
// that thickens with distance and glows toward the sun, and a tone map after.
fn hdr() -> bool { return scene.post.x > 0.5; }
// Colours in this renderer are display values. The HDR look lights in linear
// light: decode them first (the tone map encodes back at the end).
fn lin(c: vec3f) -> vec3f { return select(c, pow(max(c, vec3f(0.0)), vec3f(2.2)), hdr()); }
fn sun_strength() -> f32 { return select(1.0, 2.6, hdr()); }
fn sky_strength() -> f32 { return select(1.0, 1.25, hdr()); }

fn sky_color(ray: vec3f) -> vec3f {
    let h = clamp(ray.y, 0.0, 1.0);
    var color = lin(mix(scene.sky.rgb, scene.sky_top.rgb, pow(h, 0.55)));
    let sun = max(dot(ray, scene.sun.xyz), 0.0);
    if hdr() {
        // A paler, brighter horizon and a wide glow round the sun.
        color = mix(color, vec3f(0.62, 0.68, 0.74), pow(1.0 - h, 6.0) * 0.35 * (1.0 - scene.fog.z)) * sky_strength() * 1.15;
        color += scene.sun_color.rgb * (pow(sun, 8.0) * 0.6 + pow(sun, 64.0) * 1.5) * step(0.0, scene.sun.y);
    }
    return color;
}

// Distance haze (aerial perspective). Without HDR, the old linear fog.
fn aerial(lit: vec3f, world: vec3f, distance: f32, glow: f32) -> vec3f {
    let fog = clamp((distance - scene.fog.x) / max(scene.fog.y - scene.fog.x, 1e-4), 0.0, 1.0);
    if !hdr() {
        return mix(lit, scene.sky.rgb, fog * fog * (1.0 - 0.7 * glow));
    }
    let ray = (world - scene.eye.xyz) / max(distance, 1e-4);
    let toward_sun = pow(max(dot(ray, scene.sun.xyz), 0.0), 6.0);
    let haze_color = mix(sky_color(vec3f(ray.x, 0.04, ray.z)) * 0.95, scene.sun_color.rgb * sun_strength() * 0.5, toward_sun * 0.5);
    let haze = 1.0 - exp(-max(distance - 30.0, 0.0) * 0.00034);
    let far = max(haze, fog * fog);
    return mix(lit, haze_color, far * (1.0 - 0.7 * glow));
}

// Leaves cut out of a leaf card (OBJ material role "leaf_"): a jittered grid
// of rotated ellipses inside a soft disc, baked into a texture at start-up
// (`leaf_texture` in render2.rs). x: covered (0 or 1); y: the leaf's own
// brightness, so neighbouring leaves differ.
fn leaf_mask(uv: vec2f) -> vec2f {
    let size = vec2i(textureDimensions(leaf_texture));
    let texel = clamp(vec2i(floor(uv * vec2f(size))), vec2i(0), size - 1);
    let m = textureLoad(leaf_texture, texel, 0);
    return vec2f(step(0.5, m.r), 0.7 + 0.6 * m.g);
}

// A person's colour from the atlas (rows stored top first; OBJ v is up).
fn human_texel(uv: vec2f) -> vec4f {
    return textureSampleLevel(human_atlas, human_sampler, vec2f(uv.x, 1.0 - uv.y), 0.0);
}

@fragment
fn shadow_leaf_fragment(input: ShadowUv) {
    if input.role == LEAF_ROLE && leaf_mask(input.uv).x < 0.5 {
        discard;
    }
    if (input.role & SKINNED) != 0u && human_texel(input.uv).a < 0.5 {
        discard;
    }
}

// Sun visibility from one cascade: 4x4 hardware-filtered compares (a soft
// ~5 texel edge), biased by a few texels so lit faces don't self-shadow.
// Returns -1 when the point is outside the cascade.
fn cascade_light(world: vec3f, ndl: f32, layer: i32) -> vec2f {
    var m = scene.light_far;
    if layer == 0 { m = scene.light_projection; }
    let clip = m * vec4f(world, 1.0);
    let uv = clip.xy * vec2f(0.5, -0.5) + 0.5;
    let depth = 0.5 * (clip.z + 1.0);
    let edge = max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0;
    if edge > 0.98 || depth > 1.0 { return vec2f(-1.0, 1.0); }
    let range = select(scene.cascades.y, scene.cascades.x, layer == 0);
    let texel_m = select(scene.cascades.w, scene.cascades.z, layer == 0);
    let bias = (texel_m * (1.5 + 4.0 * (1.0 - ndl)) + 0.02) / range;
    let texel = 1.0 / vec2f(textureDimensions(sun_depth));
    var light = 0.0;
    for (var x = 0; x < 4; x++) {
        for (var y = 0; y < 4; y++) {
            let o = (vec2f(f32(x), f32(y)) - 1.5) * texel;
            light += textureSampleCompareLevel(sun_depth, sun_sampler, uv + o, layer, depth - bias);
        }
    }
    return vec2f(light / 16.0, edge);
}

fn far_shadow(world: vec3f, ndl: f32) -> f32 {
    let far = cascade_light(world, ndl, 1);
    let far_light = select(far.x, 1.0, far.x < 0.0);
    // Fade the far cascade out at its border rather than cut it.
    return mix(far_light, 1.0, smoothstep(0.85, 0.98, far.y));
}

fn shadow(world: vec3f, ndl: f32) -> f32 {
    if scene.fog.w < 0.5 || ndl <= 0.0 { return 1.0; }
    let near = cascade_light(world, ndl, 0);
    if near.x < 0.0 { return far_shadow(world, ndl); }
    // Well inside the near square the far cascade isn't needed at all.
    let fade = smoothstep(0.75, 0.95, near.y);
    if fade <= 0.0 { return near.x; }
    return mix(near.x, far_shadow(world, ndl), fade);
}

const LAMP_GRID = 32;
const LAMP_SLOTS = 8u;

struct LampLight {
    // Light falling on the surface (multiply by its colour).
    diffuse: vec3f,
    // The lamps themselves mirrored in it (add as is).
    glint: vec3f,
}

// The lamps that reach this point (its cell of the lamp grid). `gloss` 0..1:
// how sharply the surface mirrors them; `streak` 0..1: how far a mirrored lamp
// stretches toward the viewer, as on rippled water or a wet street.
fn lamp_light(p: vec3f, n: vec3f, to_eye: vec3f, gloss: f32, streak: f32) -> LampLight {
    var out = LampLight(vec3f(0.0), vec3f(0.0));
    if scene.lamp_grid.w < 0.5 { return out; }
    let cell = vec2i(floor((p.xz - scene.lamp_grid.xy) / scene.lamp_grid.z));
    if any(cell < vec2i(0)) || any(cell >= vec2i(LAMP_GRID)) { return out; }
    let c = u32(cell.y * LAMP_GRID + cell.x);
    let row = lamps.cells[c / 2u];
    let words = select(row.xy, row.zw, (c & 1u) == 1u);
    let r = reflect(-to_eye, n);
    let right = normalize(scene.camera_right.xyz);
    for (var k = 0u; k < LAMP_SLOTS; k++) {
        let index = (words[k / 4u] >> ((k % 4u) * 8u)) & 255u;
        if index == 255u { break; }
        let at = lamps.lights[index * 3u];
        let color = lamps.lights[index * 3u + 1u].rgb;
        let aim = lamps.lights[index * 3u + 2u];
        let to_light = at.xyz - p;
        let d = length(to_light);
        let l = to_light / max(d, 1e-3);
        // A spot fades from its axis out to the cone's edge, not just at it.
        let spot = select(smoothstep(aim.w, aim.w + (1.0 - aim.w) * 0.7, dot(-l, aim.xyz)), 1.0, aim.w < -0.5);
        let fall = clamp(1.0 - d / at.w, 0.0, 1.0);
        out.diffuse += color * (fall * fall * spot * (0.25 + 0.75 * max(dot(n, l), 0.0)));
        if gloss > 0.0 {
            // How far the mirrored direction misses the lamp, across the
            // screen and along it; a streak is a lobe stretched up the screen.
            let e = l - r;
            let across = dot(e, right);
            let along = max(dot(e, e) - across * across, 0.0);
            let width = mix(0.30, 0.025, gloss);
            let height = width * (1.0 + 6.0 * streak);
            let lobe = exp(-across * across / (width * width) - along / (height * height));
            let reach = clamp(1.0 - d / (at.w * 2.0), 0.0, 1.0);
            out.glint += color * (lobe * reach * gloss * max(spot, 0.15) * (0.4 + 2.6 * gloss) * (1.0 - 0.75 * streak));
        }
    }
    return out;
}

// Rooms behind a window (interior mapping): the view ray carries on into a
// box room 4 m wide, 3 m a floor and 5 m deep, laid out along the wall, and
// shows its back wall, side walls, floor or ceiling. At night some rooms are
// lit, each its own colour. Returns the room's light (linear).
fn room_behind(p: vec3f, facing: vec3f, to_eye: vec3f) -> vec3f {
    let t = normalize(vec3f(-facing.z, 0.0, facing.x) + vec3f(1e-5, 0.0, 0.0));
    let v = -to_eye;
    let size = vec3f(4.0, 3.0, 5.0);
    let local = vec2f(dot(p, t), p.y + 0.4);
    let dir = vec3f(dot(v, t), v.y, max(dot(v, -facing), 0.05));
    let cell = floor(local / size.xy);
    let lo = cell * size.xy;
    // Distance along the ray to each wall the ray is heading for.
    let side = select(lo.x - local.x, lo.x + size.x - local.x, dir.x > 0.0) / select(dir.x, 1e-4, abs(dir.x) < 1e-4);
    let floor_or_ceiling = select(lo.y - local.y, lo.y + size.y - local.y, dir.y > 0.0) / select(dir.y, 1e-4, abs(dir.y) < 1e-4);
    let back = size.z / dir.z;
    let hit = min(min(abs(side), abs(floor_or_ceiling)), back);
    // Room surfaces: back wall pale, side walls a little darker, floor darker
    // still (wood), ceiling bright where a lamp hangs.
    var albedo = 0.55;
    if hit == abs(floor_or_ceiling) { albedo = select(0.30, 0.75, dir.y > 0.0); }
    else if hit == abs(side) { albedo = 0.42; }
    let depth = 1.0 / (1.0 + hit * 0.28);
    let wall_id = round(dot(p, facing) * 2.0);
    let id = noise_hash(cell * vec2f(1.7, 3.1) + vec2f(wall_id * 0.37, wall_id * 0.11));
    let shade = noise_hash(cell + vec2f(wall_id, 11.0));
    let day = (scene.ambient.rgb * 0.5 + scene.sun_color.rgb * max(scene.sun.y, 0.0) * 0.25) * sky_strength();
    // By day a room is much darker than the street: you see little inside.
    var light = day * albedo * depth * 0.3;
    // At night under a third of the rooms are lit: most warm, a few cool.
    let lit = step(id, 0.28) * scene.fog.z;
    let warm = mix(vec3f(1.0, 0.62, 0.30), vec3f(1.0, 0.80, 0.55), shade);
    let tone = select(warm, vec3f(0.55, 0.65, 1.0), shade > 0.88);
    light += tone * albedo * (0.5 + 0.8 * depth) * lit * 1.4;
    return light;
}

// Rain on standing water: drops land at random in a half-metre grid (two
// offset grids), each a ring that spreads and fades; fewer drops in a drizzle.
// Returns the surface normal with the rings on it.
fn rain_rings(xz: vec2f, t: f32, n: vec3f, rain: f32) -> vec3f {
    var g = vec2f(0.0);
    for (var layer = 0; layer < 2; layer++) {
        let q = xz * 4.5 + f32(layer) * 0.37;
        let cell = floor(q);
        let seed = noise_hash(cell + f32(layer) * 13.1);
        let centre = cell + 0.25 + 0.5 * vec2f(noise_hash(cell + 3.7), noise_hash(cell + 9.1));
        let phase = fract(t * 1.3 + seed * 7.0);
        let d = q - centre;
        let dist = length(d);
        let r = phase * 0.45;
        let wave = sin((dist - r) * 30.0) * (1.0 - smoothstep(0.0, 0.08, abs(dist - r))) * (1.0 - phase) * (1.0 - phase);
        g += d / max(dist, 1e-3) * wave * step(seed, rain);
    }
    return normalize(n + vec3f(g.x, 0.0, g.y) * 0.18);
}

// Light bounced up from the ground. In the HDR look the sunlit street
// (warm brick and stone) lights walls and undersides in shade, scaled by how
// strong and high the sun is; otherwise the scene's fixed ground colour.
fn bounce_light() -> vec3f {
    if !hdr() { return scene.bounce.rgb; }
    let street = vec3f(0.30, 0.22, 0.16); // linear albedo of old brick paving
    let sun = scene.sun_color.rgb * sun_strength() * max(scene.sun.y, 0.0) * scene.fog.w;
    return scene.bounce.rgb + street * sun * 0.55;
}

fn noise_hash(p: vec2f) -> f32 {
    var q = fract(p.xyx * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn value_noise(p: vec2f) -> f32 {
    let cell = floor(p);
    let sub = fract(p);
    let t = sub * sub * (3.0 - 2.0 * sub);
    let a = mix(noise_hash(cell), noise_hash(cell + vec2f(1, 0)), t.x);
    let b = mix(noise_hash(cell + vec2f(0, 1)), noise_hash(cell + vec2f(1, 1)), t.x);
    return mix(a, b, t.y);
}

fn water_normal(p: vec2f, distance: f32) -> vec3f {
    let fine = p * 0.8;
    let coarse = p * 0.21;
    let gradient = vec2f(
        value_noise(fine + vec2f(0.4, 0.0)) - value_noise(fine - vec2f(0.4, 0.0)),
        value_noise(fine + vec2f(0.0, 0.4)) - value_noise(fine - vec2f(0.0, 0.4)),
    ) * 0.09 + vec2f(
        value_noise(coarse + vec2f(1.5, 7.0)) - value_noise(coarse + vec2f(-1.5, 7.0)),
        value_noise(coarse + vec2f(7.0, 1.5)) - value_noise(coarse + vec2f(7.0, -1.5)),
    ) * 0.07;
    let ripple = -gradient * (1.0 - smoothstep(60.0, 220.0, distance));
    return normalize(vec3f(ripple.x, 1.0, ripple.y));
}

// Array order, metre repeat size and linear luminance come from the
// material pack's manifest (docs/RENDERER.md). The luminance ratios retain
// the map palette.
const REPEAT_M = array(1.0, 1.8, 1.2, 2.5, 2.5, 2.5, 4.0, 1.5);
const MEAN_Y = array(1.00000, 0.05226, 0.16467, 0.12940, 0.06401, 0.19707, 0.19719, 0.19851);

// Ground steeper than this (normal's y) is a quay wall, in brick. The wall's
// triangles lean when terrain.bin's quay offsets move the land points onto
// the true quay line (up to ~2 m off the 1 m grid), so 0.35 left many of
// them paved; real slopes in the city (ramps, grass banks) stay far flatter.
const WALL_NY = 0.6;

fn material_layer(input: WorldVertex, n: vec3f) -> u32 {
    if scene.material_ground.w < 0.5 {
        return 0u;
    }
    if object_kind() == 1u {
        if input.obj_role == 3u {
            return 0u;
        }
        let inferred = input.obj_role == 0u || input.obj_role == 4u;
        if input.obj_role == 1u || (inferred && abs(n.y) <= 0.27) {
            return select(4u, 5u, input.color.g > input.color.r * 0.8);
        }
        if input.obj_role == 2u || (inferred && n.y > 0.27) {
            return select(7u, 6u, input.color.r > input.color.b * 1.25);
        }
    }
    if input.surface != 66u {
        return 0u;
    }
    if n.y < WALL_NY {
        return 4u; // a steep ground face: the brick of a quay wall
    }
    return ground_layer(street(input.world.xz).kind);
}

fn ground_layer(kind: u32) -> u32 {
    switch kind {
        case 2u: { return 1u; }   // brick carriageway
        case 4u, 11u, 12u: { return 2u; } // footway and quay; under a building's edge, footway too
        case 0u, 9u: { return 3u; }  // other paving and bridge decks
        default: { return 0u; }
    }
}

fn class_at(cell: vec2i) -> u32 {
    if any(cell < vec2i(0)) || any(cell >= vec2i(textureDimensions(terrain_classes))) { return 255u; }
    return textureLoad(terrain_classes, cell, 0).r;
}

// Kerbs stand between raised ground (footways, squares, quays, planting: 1)
// and the carriageway (asphalt, brick road, bike lane, tram: 0). Bridges,
// water and the rest have none (-1).
fn raised(kind: u32) -> f32 {
    switch kind {
        case 0u, 4u, 5u, 6u, 7u, 11u: { return 1.0; }
        case 1u, 2u, 3u, 10u: { return 0.0; }
        default: { return -1.0; }
    }
}

struct Street {
    kind: u32,
    // Metres from the kerb line, positive on the raised side; 99 = no kerb near.
    kerb: f32,
    // Unit direction (x, z) from the road up onto the kerb.
    up_kerb: vec2f,
}

// Each 1 m point of the class grid carries its signed distance to the
// nearest kerb (measured from the BGT shapes at build time). Blending the four
// round a pixel gives straight kerbs between the points; the paving switches
// on the same line.
fn street(xz: vec2f) -> Street {
    let p = (xz - scene.material_ground.xy) * scene.material_ground.z;
    let base = vec2i(floor(p));
    let t = p - floor(p);
    let nearest = class_at(vec2i(round(p)));
    var d: array<f32, 4>;
    var kinds: array<u32, 4>;
    let offsets = array(vec2i(0, 0), vec2i(1, 0), vec2i(0, 1), vec2i(1, 1));
    for (var i = 0; i < 4; i++) {
        let cell = base + offsets[i];
        if any(cell < vec2i(0)) || any(cell >= vec2i(textureDimensions(terrain_classes))) {
            return Street(nearest, 99.0, vec2f(0.0));
        }
        let texel = textureLoad(terrain_classes, cell, 0);
        if texel.g == 0u { return Street(nearest, 99.0, vec2f(0.0)); }
        d[i] = (f32(texel.g) - 128.0) * 0.02;
        kinds[i] = texel.r;
    }
    let kerb = mix(mix(d[0], d[1], t.x), mix(d[2], d[3], t.x), t.y);
    let grad = vec2f(mix(d[1] - d[0], d[3] - d[2], t.y), mix(d[2] - d[0], d[3] - d[1], t.x)) * scene.material_ground.z;
    let g = length(grad);
    if g < 1e-3 { return Street(nearest, 99.0, vec2f(0.0)); }
    // Paving from the nearest point on this side of the line.
    let side = kerb > 0.0;
    var kind = nearest;
    var best = 9.0;
    for (var i = 0; i < 4; i++) {
        let dist = length(t - vec2f(offsets[i]));
        if (d[i] > 0.0) == side && raised(kinds[i]) >= 0.0 && dist < best { best = dist; kind = kinds[i]; }
    }
    return Street(kind, kerb, grad / g);
}

// Old paving is never one colour: broad stains, tyre-darkened bands, patches.
fn grime(xz: vec2f, distance: f32) -> f32 {
    let broad = value_noise(xz * 0.18) * 0.6 + value_noise(xz * 0.53 + 17.0) * 0.4;
    let fine = value_noise(xz * 2.3 + 5.0);
    let stains = smoothstep(0.5, 0.85, broad) * 0.22;
    let speckle = (fine - 0.5) * 0.10 * (1.0 - smoothstep(20.0, 60.0, distance));
    return 1.0 - stains + speckle;
}

fn projected(p: vec3f, tangent: vec3f, bitangent: vec3f, repeat_m: f32) -> vec2f {
    return vec2f(dot(p, tangent), -dot(p, bitangent)) / repeat_m;
}

// A car's surface from its atlas texel (the car atlas, docs/RENDERER.md). Alpha says
// what it is: 255 paint (the entity's tint, under a clear coat), 224-247
// glass, 192-223 a lamp lens (lit at night on cars that drive: object x 2),
// 128-191 metal (chrome, alloy), below that unpainted with gloss alpha/127.
// A car atlas texel's surface class (its alpha: paint, glass, lamp, metal,
// matte) from the nearest texel of the mip level being sampled. Filtered,
// two classes' codes blend into a third: lamp next to matte reads as metal,
// paint next to lamp as untinted glass, a bright rim round every lamp,
// grille and plate.
fn car_class(uv: vec2f, dx: vec2f, dy: vec2f) -> f32 {
    let size = vec2f(textureDimensions(car_atlas));
    let footprint = max(length(dx * size), length(dy * size));
    let level = clamp(i32(round(log2(max(footprint, 1.0)))), 0, i32(textureNumLevels(car_atlas)) - 1);
    let dims = vec2i(textureDimensions(car_atlas, level));
    let at = clamp(vec2i(floor(uv * vec2f(dims))), vec2i(0), dims - 1);
    return textureLoad(car_atlas, at, level).a;
}

fn car_shade(input: WorldVertex, n: vec3f, texel: vec4f) -> vec4f {
    let a = texel.a * 255.0;
    let distance = length(input.world - scene.eye.xyz);
    let to_eye = (scene.eye.xyz - input.world) / max(distance, 1e-4);
    var base = lin(texel.rgb);
    var gloss = clamp(a / 127.0, 0.0, 1.0);
    var f0 = 0.04;
    var metal = 0.0;
    var lamp = 0.0;
    if a > 247.5 {
        base *= lin(object.tint.rgb);
        gloss = 1.0;
    } else if a > 223.5 {
        gloss = 1.0;
        f0 = 0.05;
    } else if a > 191.5 {
        gloss = 0.9;
        lamp = 1.0;
    } else if a > 127.5 {
        gloss = 0.8;
        metal = 1.0;
    }
    let ndl = max(dot(n, scene.sun.xyz), 0.0);
    let visibility = shadow(input.world, ndl);
    let lighting = mix(bounce_light(), scene.ambient.rgb, 0.5 + 0.5 * n.y) * sky_strength()
        + scene.sun_color.rgb * ndl * visibility * sun_strength();
    let r = reflect(-to_eye, n);
    let cosine = clamp(dot(to_eye, n), 0.0, 1.0);
    let fresnel = f0 + (1.0 - f0) * pow(1.0 - cosine, 5.0);
    // What a car mirrors: the sky above the horizon, the street below; less
    // of either in the shade of buildings.
    let env = select(sky_color(r), lin(vec3f(0.30, 0.27, 0.24)) * sky_strength(), r.y < 0.0) * (0.55 + 0.45 * visibility);
    let shine = gloss * gloss;
    let mirror = mix(vec3f(fresnel), base * (0.7 + 0.3 * fresnel), metal) * shine;
    var lit = base * (1.0 - 0.85 * metal) * lighting * (1.0 - mirror) + env * mirror;
    let power = mix(12.0, 700.0, shine);
    let highlight = pow(max(dot(r, scene.sun.xyz), 0.0), power) * (power + 8.0) / 40.0;
    lit += scene.sun_color.rgb * sun_strength() * highlight * visibility * mix(vec3f(max(fresnel, 0.04)), base, metal) * gloss;
    let lamps_near = lamp_light(input.world, n, to_eye, shine, 0.0);
    lit += base * (1.0 - 0.85 * metal) * lamps_near.diffuse * (1.0 - mirror) + lamps_near.glint * mix(vec3f(max(fresnel, 0.04)), base, metal);
    let night = lamp * f32(object_kind() == 2u) * scene.fog.z;
    lit += base * 6.0 * night;
    // Brake lights: the red lenses at the back (facing away from the car's
    // +z), by day too.
    let back = -normalize((object.model * vec4f(0.0, 0.0, 1.0, 0.0)).xyz);
    let red = base.r > 2.0 * base.g && base.r > 2.0 * base.b;
    let brake = lamp * f32(braking() && red && dot(n, back) > 0.35);
    lit += base * 14.0 * brake;
    return vec4f(aerial(lit, input.world, distance, night), input.color.a);
}

@fragment
fn world_fragment(input: WorldVertex) -> @location(0) vec4f {
    let dx = dpdx(input.world);
    let dy = dpdy(input.world);
    let uv_m_dx = dpdx(input.uv_m);
    let uv_m_dy = dpdy(input.uv_m);
    let n = input.normal * inverseSqrt(max(dot(input.normal, input.normal), 1e-8));
    if input.obj_role == LEAF_ROLE {
        // uv_m is the OBJ coordinate with v flipped; undo that for the card.
        let leaf = leaf_mask(vec2f(input.uv_m.x, -input.uv_m.y));
        if leaf.x < 0.5 { discard; }
        let distance = length(input.world - scene.eye.xyz);
        let to_eye = (scene.eye.xyz - input.world) / max(distance, 1e-4);
        // A card seen edge-on is a hard line of leaves: drop it, as foliage does.
        let edge_on = abs(dot(n, to_eye));
        if edge_on < 0.22 * leaf.y - 0.05 + 0.08 { discard; }
        let facing = select(n, -n, dot(n, to_eye) < 0.0);
        // Leaves let light through: wrap the sun round, never fully dark.
        let ndl = dot(facing, scene.sun.xyz);
        let sun = clamp(ndl * 0.5 + 0.5, 0.0, 1.0) * 0.85;
        let visibility = shadow(input.world, 0.6);
        let lighting = mix(scene.bounce.rgb, scene.ambient.rgb, 0.5 + 0.5 * facing.y) * 0.9 * sky_strength()
            + scene.sun_color.rgb * sun * visibility * sun_strength();
        let lamp = lamp_light(input.world, facing, to_eye, 0.0, 0.0);
        let lit = lin(input.color.rgb * leaf.y) * (lighting + lamp.diffuse * 0.8);
        return vec4f(aerial(lit, input.world, distance, 0.0), 1.0);
    }
    if input.obj_role == GLASS_ROLE && hdr() {
        // Window glass: the sky reflected (Fresnel), a dark room behind, the sun's glint.
        let distance = length(input.world - scene.eye.xyz);
        let to_eye = (scene.eye.xyz - input.world) / max(distance, 1e-4);
        let facing = select(n, -n, dot(n, to_eye) < 0.0);
        let r = reflect(-to_eye, facing);
        let cosine = clamp(dot(to_eye, facing), 0.0, 1.0);
        let fresnel = 0.06 + 0.94 * pow(1.0 - cosine, 5.0);
        // Below the horizon the glass mirrors the street: darker, warmer.
        let mirrored = select(sky_color(r), lin(vec3f(0.30, 0.27, 0.24)) * sky_strength(), r.y < 0.0);
        let visibility = shadow(input.world, 0.5);
        // Pale warm glass is a street lamp's lantern (furniture.py), lit at night.
        let pane = lin(input.color.rgb);
        if dot(pane, vec3f(0.3333)) > 0.12 {
            let lantern = pane * (0.6 * sky_strength() + vec3f(9.0, 6.4, 3.4) * scene.fog.z);
            return vec4f(aerial(mix(lantern, mirrored, fresnel * (1.0 - scene.fog.z)), input.world, distance, scene.fog.z), 1.0);
        }
        let room = room_behind(input.world, facing, to_eye);
        let lamp = lamp_light(input.world, facing, to_eye, 1.0, 0.0);
        var lit = mix(room, mirrored * 0.75, clamp(0.08 + fresnel, 0.0, 1.0)) + lamp.glint * fresnel;
        lit += scene.sun_color.rgb * sun_strength() * pow(max(dot(r, scene.sun.xyz), 0.0), 400.0) * visibility * 4.0;
        return vec4f(aerial(lit, input.world, distance, 0.0), 1.0);
    }
    if is_car(input.obj_role) {
        // uv_m is the OBJ coordinate with v flipped: the atlas row from the top.
        let uv = vec2f(input.uv_m.x, 1.0 + input.uv_m.y);
        let texel = textureSampleGrad(car_atlas, human_sampler, uv, uv_m_dx, uv_m_dy);
        return car_shade(input, n, vec4f(texel.rgb, car_class(uv, uv_m_dx, uv_m_dy)));
    }
    var shade_normal = n;
    var color = lin(input.color.rgb);
    var sign_glow = 0.0;
    if (input.obj_role & SKINNED) != 0u {
        // uv_m is the OBJ coordinate with v flipped: the atlas row from the top.
        let texel = textureSampleGrad(human_atlas, human_sampler, vec2f(input.uv_m.x, 1.0 + input.uv_m.y), uv_m_dx, uv_m_dy);
        if texel.a < 0.5 { discard; }
        color = lin(texel.rgb) * color;
    } else if input.obj_role == PROP_ROLE {
        // The texel is the colour; the material's Kd (the GL window's colour) is not applied.
        let texel = textureSampleGrad(prop_atlas, human_sampler, vec2f(input.uv_m.x, 1.0 + input.uv_m.y), uv_m_dx, uv_m_dy);
        if texel.a < 0.5 { discard; }
        color = lin(texel.rgb);
        // Shop signs are lit at night.
        sign_glow = 0.9 * scene.fog.z;
    }
    var roughness = 1.0;
    let layer = material_layer(input, n);
    if layer > 0u {
        let ground = input.surface == 66u && n.y >= WALL_NY;
        if input.surface == 66u && !ground {
            // Quay walls: old dark brick, whatever the ground class above.
            color = lin(vec3f(0.34, 0.21, 0.16));
        }
        let up = select(vec3f(0, 1, 0), vec3f(0, 0, -1), abs(n.y) > 0.97 || ground);
        var tangent = normalize(cross(up, n));
        var bitangent = cross(n, tangent);
        // Terrain uses a fixed XZ basis so texture phase is continuous across cells.
        let u_axis = select(tangent, vec3f(1, 0, 0), ground);
        let v_axis = select(bitangent, vec3f(0, 0, -1), ground);
        let scale = REPEAT_M[layer];
        var uv = projected(input.world, u_axis, v_axis, scale);
        var uv_dx = projected(dx, u_axis, v_axis, scale);
        var uv_dy = projected(dy, u_axis, v_axis, scale);
        if input.obj_role > 0u && !ground {
            let det = uv_m_dx.x * uv_m_dy.y - uv_m_dx.y * uv_m_dy.x;
            if abs(det) > 1e-10 {
                tangent = normalize((dx * uv_m_dy.y - dy * uv_m_dx.y) / det);
                bitangent = normalize((dx * uv_m_dy.x - dy * uv_m_dx.x) / det);
                uv = input.uv_m / scale;
                uv_dx = uv_m_dx / scale;
                uv_dy = uv_m_dy / scale;
            }
        }
        let diffuse = textureSampleGrad(material_albedo, material_sampler, uv, i32(layer), uv_dx, uv_dy).rgb;
        let encoded = textureSampleGrad(material_surface, material_sampler, uv, i32(layer), uv_dx, uv_dy);
        // The image origin is top left. +Y tangent space points up the image.
        let normal = (encoded.rgb * 255.0 - vec3f(128.0, 128.0, 127.0)) / 128.0;
        shade_normal = normalize(n * max(normal.z, 0.2) + 0.62 * (tangent * normal.x + bitangent * normal.y));
        let detail = clamp(dot(diffuse, vec3f(0.2126, 0.7152, 0.0722)) / MEAN_Y[layer], 0.38, 2.0);
        color *= mix(1.0, detail, 0.72);
        roughness = encoded.a;
    }
    if input.surface == 66u && n.y >= WALL_NY && scene.material_ground.w > 0.5 {
        let distance = length(input.world - scene.eye.xyz);
        color *= grime(input.world.xz, distance);
        let st = street(input.world.xz);
        let k = st.kerb;
        // Pixel footprint, so thin lines fade instead of shimmering far off.
        let px = max(length(dx), length(dy));
        if k > -0.6 && k < 0.4 && px < 0.25 {
            let fade = 1.0 - smoothstep(0.06, 0.25, px);
            let granite = lin(vec3f(0.60, 0.59, 0.56)) * (0.9 + 0.2 * value_noise(input.world.xz * 6.0));
            let aa = max(px, 0.01);
            // Kerb top: 15 cm of granite, a darker joint every metre.
            let top = smoothstep(-aa, aa, k) * (1.0 - smoothstep(0.15 - aa, 0.15 + aa, k));
            let joint = 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.03, abs(fract(dot(input.world.xz, vec2f(-st.up_kerb.y, st.up_kerb.x))) - 0.5) - 0.47));
            // Its face, seen from the road: a sliver lit by the sun from that side.
            let face = smoothstep(-0.07 - aa, -0.07 + aa, k) * (1.0 - smoothstep(-aa, aa, k));
            // The gutter: a band of dirt and old water along the foot of the kerb.
            let gutter = (1.0 - smoothstep(-0.07, -0.45, k)) * (1.0 - face) * select(1.0, 0.0, k > 0.0);
            color = mix(color, granite * joint, top * fade);
            color *= 1.0 - 0.35 * gutter * fade;
            let face_n = normalize(vec3f(-st.up_kerb.x, 0.25, -st.up_kerb.y));
            shade_normal = normalize(mix(shade_normal, face_n, face * fade));
            color = mix(color, granite * 0.85, face * fade);
            roughness = mix(roughness, 0.8, max(top, gutter) * fade);
        }
    }
    // Wet streets (after Lagarde's wet surfaces, simplified): water darkens
    // the porous paving and smooths it, gathers in low spots and the gutters
    // as puddles that mirror (the sky here, the street in the tone map's
    // reflections), and the rain rings the puddles.
    var mirror = 0.0;
    var wet_streak = 0.0;
    let wet = scene.weather.x;
    if wet > 0.0 && input.surface == 66u && n.y >= WALL_NY {
        let xz = input.world.xz;
        let kerb = street(xz).kerb;
        let gutter = select(0.0, 1.0 - smoothstep(0.0, 0.6, -kerb), kerb < 0.0 && kerb > -0.6);
        let field = value_noise(xz * 0.21) * 0.6 + value_noise(xz * 0.83 + 7.0) * 0.4 + 0.35 * gutter;
        let puddle = smoothstep(0.58, 0.70, field) * smoothstep(0.35, 1.0, wet);
        let soak = wet * (1.0 - puddle);
        color *= mix(1.0, 0.5, wet) * mix(1.0, 0.8, puddle);
        roughness = mix(mix(roughness, 0.2, soak), 0.03, puddle);
        var level = n;
        if puddle > 0.0 && scene.weather.y > 0.0 { level = rain_rings(xz, scene.weather.z, n, scene.weather.y); }
        shade_normal = normalize(mix(shade_normal, level, max(puddle, 0.6 * wet)));
        let to_eye = (scene.eye.xyz - input.world) / max(length(scene.eye.xyz - input.world), 1e-4);
        let fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(to_eye, shade_normal), 0.0, 1.0), 5.0);
        mirror = clamp(fresnel * (1.0 - roughness) * mix(0.7 * wet, 0.9, puddle), 0.0, 0.85);
        wet_streak = wet;
    }
    let sun = max(dot(shade_normal, scene.sun.xyz), 0.0);
    let visibility = shadow(input.world, max(dot(n, scene.sun.xyz), 0.0));
    let lighting = mix(bounce_light(), scene.ambient.rgb, 0.5 + 0.5 * n.y) * sky_strength()
        + scene.sun_color.rgb * sun * visibility * sun_strength();
    let glow = input.emissive * scene.fog.z + object.inv_scale_sq.w;
    let distance = length(input.world - scene.eye.xyz);
    let to_viewer = (scene.eye.xyz - input.world) / max(distance, 1e-4);
    let gloss = max(select(0.0, (1.0 - roughness) * 0.35, layer > 0u), (1.0 - roughness) * wet_streak);
    let lamp = lamp_light(input.world, shade_normal, to_viewer, gloss, wet_streak);
    var lit = color * (lighting + 1.8 * glow + lamp.diffuse + sign_glow) + lamp.glint;
    if mirror > 0.0 {
        // The sky in the wet; where the reflections find the street, they replace it.
        // At night that sky is dark, so a puddle also keeps some of the lamp-lit street round it.
        let seen = sky_color(reflect(-to_viewer, shade_normal)) + lamp.diffuse * 0.15 + scene.ambient.rgb * 0.08;
        lit = mix(lit, seen, mirror);
    }
    if layer > 0u && sun > 0.0 {
        let eye = (scene.eye.xyz - input.world) / max(distance, 1e-4);
        let specular = max(dot(reflect(-scene.sun.xyz, shade_normal), eye), 0.0);
        let glint = pow(specular, mix(65.0, 8.0, roughness)) * (1.0 - roughness);
        lit += scene.sun_color.rgb * glint * sun * visibility * 0.16 * sun_strength();
    }
    if input.surface >= 67u && n.y >= 0.5 {
        var normal = water_normal(input.world.xz, distance);
        if scene.weather.y > 0.0 { normal = rain_rings(input.world.xz, scene.weather.z, normal, scene.weather.y); }
        let to_eye = (scene.eye.xyz - input.world) / max(distance, 1e-4);
        let fresnel = 0.03 + 0.97 * pow(1.0 - clamp(dot(to_eye, normal), 0.0, 1.0), 5.0);
        let sky_seen = select(scene.sky.rgb * 0.85, sky_color(reflect(-to_eye, normal)) * 0.9, hdr());
        // Canal water is murky green-brown; the sky shows mostly at grazing angles.
        lit = mix(lin(vec3f(0.10, 0.13, 0.11)) * sky_strength(), sky_seen, min(fresnel, 0.6));
        // The canal mirrors the quays and facades where the reflections find them.
        mirror = min(fresnel, 0.6) * 0.95;
        let glint = pow(clamp(dot(reflect(-to_eye, normal), scene.sun.xyz), 0.0, 1.0), 150.0);
        lit += scene.sun_color.rgb * glint * visibility * 0.7 * sun_strength();
        // The quays' lamps glint off the ripples, in streaks toward you.
        let on_water = lamp_light(input.world, normal, to_eye, 1.0, 1.0);
        lit += on_water.glint * 0.8 + on_water.diffuse * lin(vec3f(0.10, 0.13, 0.11)) * 0.5;
    }
    // Alpha below 1 marks a mirror for the tone map's reflections (1 - weight).
    return vec4f(aerial(lit, input.world, distance, glow), select(input.color.a, 1.0 - mirror, mirror > 0.0));
}

@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var linear_sampler: sampler;
@group(0) @binding(2) var ambient_occlusion: texture_2d<f32>;
@group(1) @binding(2) var scene_depth: texture_depth_2d;

struct BlitVertex {
    @builtin(position) clip: vec4f,
    @location(0) uv: vec2f,
}

@vertex
fn blit_vertex(@builtin(vertex_index) index: u32) -> BlitVertex {
    let uv = array(vec2f(0, 0), vec2f(2, 0), vec2f(0, 2))[index];
    return BlitVertex(vec4f(uv * vec2f(2, -2) + vec2f(-1, 1), 0, 1), uv);
}

@vertex
fn sky_vertex(@builtin(vertex_index) index: u32) -> BlitVertex {
    let uv = array(vec2f(0, 0), vec2f(2, 0), vec2f(0, 2))[index];
    let ndc = uv * vec2f(2, -2) + vec2f(-1, 1);
    return BlitVertex(vec4f(ndc, 1.0, 1.0), ndc);
}

@fragment
fn sky_fragment(input: BlitVertex) -> @location(0) vec4f {
    let ray = normalize(scene.camera_forward.xyz + input.uv.x * scene.camera_right.xyz + input.uv.y * scene.camera_up.xyz);
    let h = clamp(ray.y, 0.0, 1.0);
    var color = sky_color(ray);
    let sun = max(dot(ray, scene.sun.xyz), 0.0);
    let disc = smoothstep(0.9993, 0.9997, sun);
    color += scene.sun_color.rgb * (disc * 3.0 + pow(sun, 48.0) * 0.4) * step(0.0, scene.sun.y);
    let star = fract(sin(dot(floor(ray * 260.0), vec3f(12.9898, 78.233, 37.719))) * 43758.5453);
    color += vec3f(step(0.9975, star) * scene.fog.z * h * 0.9 * (1.0 - scene.weather.w));
    return vec4f(color, 1.0);
}

@fragment
fn blit_fragment(input: BlitVertex) -> @location(0) vec4f {
    return textureSample(source, linear_sampler, input.uv);
}

// ---- ambient occlusion (HDR look) -----------------------------------------
// World position from the scene's depth: GL-style projection, stored as
// WebGPU depth 0.5 * (z + w) / w. scene.post.yz: near and far planes.
fn depth_distance(d: f32) -> f32 {
    let n = scene.post.y;
    let f = scene.post.z;
    let z = 2.0 * d - 1.0;
    return 2.0 * n * f / (f + n - z * (f - n));
}

fn world_at(uv: vec2f, d: f32) -> vec3f {
    let ndc = vec2f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    let ray = scene.camera_forward.xyz + ndc.x * scene.camera_right.xyz + ndc.y * scene.camera_up.xyz;
    return scene.eye.xyz + ray * depth_distance(d);
}

fn depth_at(pixel: vec2i) -> f32 {
    let size = vec2i(textureDimensions(scene_depth));
    return textureLoad(scene_depth, clamp(pixel, vec2i(0), size - 1), 0);
}

@fragment
fn ao_fragment(input: BlitVertex) -> @location(0) vec4f {
    let size = vec2f(textureDimensions(scene_depth));
    let pixel = vec2i(input.clip.xy);
    let d = depth_at(pixel);
    if d >= 0.99999 { return vec4f(1.0); }
    let uv = (vec2f(pixel) + 0.5) / size;
    let p = world_at(uv, d);
    // Normal from the neighbour on each axis whose depth is closer (no
    // smearing across silhouettes).
    let px = world_at(uv + vec2f(1.0, 0.0) / size, depth_at(pixel + vec2i(1, 0)));
    let nx = world_at(uv - vec2f(1.0, 0.0) / size, depth_at(pixel - vec2i(1, 0)));
    let py = world_at(uv + vec2f(0.0, 1.0) / size, depth_at(pixel + vec2i(0, 1)));
    let ny = world_at(uv - vec2f(0.0, 1.0) / size, depth_at(pixel - vec2i(0, 1)));
    let dx = select(p - nx, px - p, length(px - p) < length(p - nx));
    let dy = select(p - ny, py - p, length(py - p) < length(p - ny));
    var n = normalize(cross(dy, dx));
    if dot(n, scene.eye.xyz - p) < 0.0 { n = -n; }
    let distance = length(p - scene.eye.xyz);
    let radius = clamp(0.06 * distance, 0.8, 4.0);
    // Interleaved gradient noise rotates the kernel per pixel.
    let noise = fract(52.9829189 * fract(dot(vec2f(pixel), vec2f(0.06711056, 0.00583715))));
    let tangent = normalize(cross(n, select(vec3f(0, 1, 0), vec3f(1, 0, 0), abs(n.y) > 0.9)));
    let bitangent = cross(n, tangent);
    var occlusion = 0.0;
    let forward = scene.camera_forward.xyz;
    for (var i = 0u; i < 12u; i++) {
        let k = f32(i);
        let a = (k + noise) * 2.39996;               // golden angle spiral
        let r = sqrt((k + 0.5) / 12.0);
        let lift = sqrt(1.0 - r * r);
        let scale = mix(0.15, 1.0, (k + 0.5) / 12.0);
        let dir = tangent * (cos(a) * r) + bitangent * (sin(a) * r) + n * lift;
        let s = p + dir * radius * scale;
        let clip = scene.view_projection * vec4f(s, 1.0);
        if clip.w <= 0.0 { continue; }
        let suv = vec2f(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
        if any(suv < vec2f(0.0)) || any(suv > vec2f(1.0)) { continue; }
        let scene_d = depth_distance(depth_at(vec2i(suv * size)));
        let sample_d = dot(s - scene.eye.xyz, forward);
        let range = smoothstep(0.0, 1.0, radius / max(abs(sample_d - scene_d), 1e-3));
        occlusion += select(0.0, range, scene_d < sample_d - 0.03);
    }
    let ao = 1.0 - occlusion / 12.0;
    return vec4f(pow(ao, 2.2));
}

// ---- reflections and rain (HDR look, in the tone map pass) ---------------
// The tone map pass reads the scene constants through its own binding (the
// first group holds its images).
@group(2) @binding(0) var<uniform> view: Scene;

fn view_distance(d: f32) -> f32 {
    let n = view.post.y;
    let f = view.post.z;
    return 2.0 * n * f / (f + n - (2.0 * d - 1.0) * (f - n));
}

fn view_ray(uv: vec2f) -> vec3f {
    let ndc = vec2f(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    return view.camera_forward.xyz + ndc.x * view.camera_right.xyz + ndc.y * view.camera_up.xyz;
}

// Screen-space reflection for a flat mirror (canal water, wet streets): the
// view ray bounced straight up, marched through the scene's depth in growing
// steps (out to ~200 m), refined where it passes behind a surface. Returns
// the colour found and how sure (0: nothing found, keep the sky).
fn reflection(uv: vec2f, pixel: vec2i) -> vec4f {
    let size = vec2f(textureDimensions(scene_depth));
    let d = textureLoad(scene_depth, pixel, 0);
    if d >= 0.99999 { return vec4f(0.0); }
    let p = view.eye.xyz + view_ray(uv) * view_distance(d);
    let v = normalize(p - view.eye.xyz);
    // Ripples wobble the mirror a little.
    let wobble = vec3f(value_noise(p.xz * 1.3) - 0.5, 0.0, value_noise(p.xz * 1.3 + 9.0) - 0.5) * 0.04;
    let r = normalize(reflect(v, vec3f(0.0, 1.0, 0.0)) + wobble);
    let forward = view.camera_forward.xyz;
    var t = 0.3 + 0.01 * length(p - view.eye.xyz);
    var last = 0.0;
    for (var i = 0; i < 32; i++) {
        let s = p + r * t;
        let clip = view.view_projection * vec4f(s, 1.0);
        if clip.w <= 0.0 { break; }
        let suv = vec2f(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
        if any(suv < vec2f(0.0)) || any(suv > vec2f(1.0)) { break; }
        let scene_d = textureLoad(scene_depth, vec2i(suv * size), 0);
        let behind = dot(s - view.eye.xyz, forward) - view_distance(scene_d);
        if behind > 0.0 && scene_d < 0.99999 {
            if behind > 0.6 + t * 0.12 { break; } // passed behind something thick: hidden
            // Halve back toward the surface for a sharp contact.
            var lo = last;
            var hi = t;
            for (var k = 0; k < 5; k++) {
                let mid = 0.5 * (lo + hi);
                let m = p + r * mid;
                let mc = view.view_projection * vec4f(m, 1.0);
                let muv = vec2f(mc.x / mc.w * 0.5 + 0.5, 0.5 - mc.y / mc.w * 0.5);
                let md = view_distance(textureLoad(scene_depth, vec2i(clamp(muv, vec2f(0.0), vec2f(0.9999)) * size), 0));
                if dot(m - view.eye.xyz, forward) > md { hi = mid; } else { lo = mid; }
            }
            let hc = view.view_projection * vec4f(p + r * hi, 1.0);
            let huv = clamp(vec2f(hc.x / hc.w * 0.5 + 0.5, 0.5 - hc.y / hc.w * 0.5), vec2f(0.0), vec2f(1.0));
            let edge = min(min(huv.x, 1.0 - huv.x), min(huv.y, 1.0 - huv.y));
            let fade = smoothstep(0.0, 0.08, edge) * (1.0 - smoothstep(120.0, 200.0, hi));
            return vec4f(textureSampleLevel(source, linear_sampler, huv, 0.0).rgb, fade);
        }
        last = t;
        t = t * 1.18 + 0.15;
    }
    return vec4f(0.0);
}

// Falling rain: streaks on four cylinders round the camera (1.2 to 13 m out,
// after Lagarde's camera-attached rain layers), hidden behind nearer
// surfaces, leaning in the wind. Returns how much streak covers this pixel.
fn rain_streaks(uv: vec2f, scene_z: f32) -> f32 {
    let rain = view.weather.y;
    if rain <= 0.0 { return 0.0; }
    let ray = view_ray(uv);
    let across = max(length(ray.xz), 1e-3);
    var sum = 0.0;
    for (var k = 0; k < 4; k++) {
        let radius = 1.2 * pow(2.2, f32(k));
        let z = radius / across;
        if z > scene_z { continue; }
        let at = view.eye.xyz + ray * z;
        let around = atan2(ray.x, ray.z) * radius + at.y * 0.12;
        let u = around / (0.012 * radius);
        let column = floor(u);
        let seed = noise_hash(vec2f(column, f32(k) * 17.0));
        if seed > rain { continue; }
        let period = 2.0 + 3.0 * noise_hash(vec2f(column + 5.0, f32(k)));
        let fall = (at.y + view.weather.z * (7.0 + 3.0 * seed) + seed * 37.0) / period;
        let length_frac = (0.25 + 0.12 * f32(k)) / period;
        let drop = fract(fall);
        let streak = smoothstep(0.0, 0.03, drop) * (1.0 - smoothstep(length_frac, length_frac + 0.03, drop));
        let width = 1.0 - smoothstep(0.04, 0.14, abs(fract(u) - 0.5));
        sum += streak * width / (1.0 + 0.6 * f32(k));
    }
    return sum;
}

// Filmic tone map (ACES fit, Narkowicz) with a little exposure and saturation,
// and a faint vignette. Input is linear light; output goes to an 8-bit target
// read as display values, like the rest of this renderer.
@fragment
fn tonemap_fragment(input: BlitVertex) -> @location(0) vec4f {
    let here = textureSample(source, linear_sampler, input.uv);
    var c = here.rgb;
    let size = vec2f(textureDimensions(scene_depth));
    let pixel = vec2i(input.uv * size);
    let weight = 1.0 - here.a;
    if weight > 0.01 {
        let found = reflection(input.uv, pixel);
        c = mix(c, found.rgb, weight * found.a);
    }
    c *= 0.92;
    // Ambient occlusion, softened over a 3x3 neighbourhood.
    let ao_size = vec2i(textureDimensions(ambient_occlusion));
    let ao_pixel = vec2i(input.uv * vec2f(ao_size));
    var ao = 0.0;
    for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
            ao += textureLoad(ambient_occlusion, clamp(ao_pixel + vec2i(x, y), vec2i(0), ao_size - 1), 0).r;
        }
    }
    c *= ao / 9.0;
    // Rain catches the light round it: brighter by lamps and lit windows.
    let streaks = rain_streaks(input.uv, view_distance(textureLoad(scene_depth, pixel, 0)));
    c += streaks * view.weather.y * (c * 0.3 + view.ambient.rgb * 0.15 + 0.01);
    let luma = dot(c, vec3f(0.2126, 0.7152, 0.0722));
    c = max(mix(vec3f(luma), c, 1.0), vec3f(0.0));
    c = clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), vec3f(0.0), vec3f(1.0));
    c = pow(c, vec3f(1.0 / 2.2));
    let d = input.uv - 0.5;
    c *= 1.0 - 0.22 * dot(d, d);
    return vec4f(c, 1.0);
}

struct HudVertex {
    @builtin(position) clip: vec4f,
    @location(0) color: vec4f,
}

@vertex
fn hud_vertex(@location(0) clip: vec2f, @location(1) color: vec4f) -> HudVertex {
    return HudVertex(vec4f(clip, 0.0, 1.0), color);
}

@fragment
fn hud_fragment(input: HudVertex) -> @location(0) vec4f {
    return input.color;
}
