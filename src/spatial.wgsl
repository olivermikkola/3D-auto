// SPDX-License-Identifier: MIT
// EASU and RCAS adapted from AMD FidelityFX FSR 1 (2021).
// Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.
// Source: GPUOpen-Effects/FidelityFX-FSR a21ffb8, ffx-fsr/ffx_fsr1.h.
// License terms are in THIRD-PARTY-FSR.txt.
//
// The source and destination hold perceptual SDR RGB in rgba8unorm views.
// Passes operate on opaque scene colour before UI. Bind different textures
// for input and output, with an intermediate at output size for RCAS.

@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var destination: texture_storage_2d<rgba8unorm, write>;

fn source_rgb(pixel: vec2i) -> vec3f {
    let last = vec2i(textureDimensions(source)) - 1;
    return textureLoad(source, clamp(pixel, vec2i(0), last), 0).rgb;
}

fn luma(rgb: vec3f) -> f32 {
    return dot(rgb, vec3f(0.5, 1.0, 0.5));
}

const TAPS = array(
    vec2i(0, -1), vec2i(1, -1),
    vec2i(-1, 0), vec2i(0, 0), vec2i(1, 0), vec2i(2, 0),
    vec2i(-1, 1), vec2i(0, 1), vec2i(1, 1), vec2i(2, 1),
    vec2i(0, 2), vec2i(1, 2),
);

fn gradient(up: f32, left: f32, center: f32, right: f32, down: f32) -> vec3f {
    let direction = vec2f(right - left, down - up);
    let scale = max(abs(vec2f(right, down) - center), abs(center - vec2f(left, up)));
    let extent = clamp(abs(direction) / max(scale, vec2f(1e-6)), vec2f(0.0), vec2f(1.0));
    return vec3f(direction, dot(extent, extent));
}

fn easu(pixel: vec2u, out_size: vec2u) -> vec3f {
    let pixel_in = (vec2f(pixel) + 0.5) * vec2f(textureDimensions(source)) / vec2f(out_size) - 0.5;
    let base = vec2i(floor(pixel_in));
    let sub = fract(pixel_in);
    var colors: array<vec3f, 12>;
    var luminance: array<f32, 12>;
    for (var i = 0u; i < 12u; i++) {
        colors[i] = source_rgb(base + TAPS[i]);
        luminance[i] = luma(colors[i]);
    }

    // Estimate orientation and edge extent around the central 2×2 taps.
    let f = gradient(luminance[0], luminance[2], luminance[3], luminance[4], luminance[7]);
    let g = gradient(luminance[1], luminance[3], luminance[4], luminance[5], luminance[8]);
    let j = gradient(luminance[3], luminance[6], luminance[7], luminance[8], luminance[10]);
    let k = gradient(luminance[4], luminance[7], luminance[8], luminance[9], luminance[11]);
    let edge = mix(mix(f, g, sub.x), mix(j, k, sub.x), sub.y);
    let length_sq = dot(edge.xy, edge.xy);
    var dir = vec2f(1.0, 0.0);
    if length_sq >= 1.0 / 32768.0 {
        dir = edge.xy * inverseSqrt(length_sq);
    }
    let extent = edge.z * edge.z * 0.25;
    let stretch = 1.0 / max(abs(dir.x), abs(dir.y));
    let anisotropy = vec2f(mix(1.0, stretch, extent), 1.0 - 0.5 * extent);
    let lobe = mix(0.5, 0.21, extent);
    let limit = 1.0 / lobe;

    // Filter along the edge and constrain the result to the central range.
    var weighted = vec3f(0.0);
    var sum = 0.0;
    for (var i = 0u; i < 12u; i++) {
        let offset = vec2f(TAPS[i]) - sub;
        let rotated = vec2f(dot(offset, dir), dot(offset, vec2f(-dir.y, dir.x))) * anisotropy;
        let distance_sq = min(dot(rotated, rotated), limit);
        let base_weight = 0.4 * distance_sq - 1.0;
        let window = lobe * distance_sq - 1.0;
        let weight = (1.5625 * base_weight * base_weight - 0.5625) * window * window;
        weighted += colors[i] * weight;
        sum += weight;
    }
    let lo = min(min(colors[3], colors[4]), min(colors[7], colors[8]));
    let hi = max(max(colors[3], colors[4]), max(colors[7], colors[8]));
    return clamp(weighted / max(sum, 1e-6), lo, hi);
}

fn rcas(pixel: vec2i) -> vec3f {
    let north = source_rgb(pixel + vec2i(0, -1));
    let west = source_rgb(pixel + vec2i(-1, 0));
    let center = source_rgb(pixel);
    let east = source_rgb(pixel + vec2i(1, 0));
    let south = source_rgb(pixel + vec2i(0, 1));
    let lo = min(min(north, west), min(east, south));
    let hi = max(max(north, west), max(east, south));
    let hit_lo = min(lo, center) / max(4.0 * hi, vec3f(1e-6));
    let hit_hi = (vec3f(1.0) - max(hi, center)) / min(4.0 * lo - 4.0, vec3f(-1e-6));
    let factors = max(-hit_lo, hit_hi);
    // Freeze the experiment at one stop (0.5 linear sharpening strength).
    let lobe = clamp(max(factors.x, max(factors.y, factors.z)), -0.1875, 0.0) * 0.5;
    let sharpened = (center + lobe * (north + west + east + south)) / (1.0 + 4.0 * lobe);
    return clamp(sharpened, vec3f(0.0), vec3f(1.0));
}

@compute @workgroup_size(8, 8)
fn easu_pass(@builtin(global_invocation_id) gid: vec3u) {
    let size = textureDimensions(destination);
    if any(gid.xy >= size) { return; }
    textureStore(destination, gid.xy, vec4f(easu(gid.xy, size), 1.0));
}

@compute @workgroup_size(8, 8)
fn rcas_pass(@builtin(global_invocation_id) gid: vec3u) {
    if any(gid.xy >= textureDimensions(destination)) { return; }
    textureStore(destination, gid.xy, vec4f(rcas(vec2i(gid.xy)), 1.0));
}
