# KAT-Coder Audit Report: 01_rust_physics_collision

**Generated:** 2026-10-15 17:51:53
**Elapsed Time:** 536.7s
**Tokens:** 25920 (Prompt: 24420, Output: 1500)

## Reasoning Trace

```
Let me analyze the codebase carefully for the three areas requested.

## 1. Raycasting edge-cases against static bodies and terrain

### Raycasting against static bodies (`ray_test` in physics.rs)

Looking at `ray_test` (around line 530-580):

```rust
fn ray_test(ents: &[Option<Entity>], i: usize, o: Vec3, dir: Vec3, max: f32, ignore: Option<u32>, best: &mut Option<RayHit>) {
```

**Issue 1: Ray starting inside a box**
At line ~575:
```rust
if !ok || axis_hit == usize::MAX || best.as_ref().is_some_and(|h| h.dist <= t0) {
    return; // miss, or ray starts inside the box
}
```
The comment says "ray starts inside the box" but there's no explicit check for that. When a ray starts inside a box, `t0` would be negative (the ray exits the box in the forward direction), and `t0` could be negative. The slab test computes `t0` as the max of all entry times, which could be negative if the ray starts inside. This means a ray starting inside a box would report a hit at negative distance, which is wrong. Actually wait - let me re-read. `t0` is the max of entry times. If the ray starts inside, some entry times are negative and some exit times are positive. `t0` would be the max entry time, which could be negative. Then `t0` would be negative, and the hit point would be behind the ray origin. This is a bug - rays starting inside boxes would report a hit at negative distance.

Actually, looking more carefully: `t0` starts at 0.0 and is only increased (`t0 = ta` where `ta` could be negative). So if the ray starts inside, `t0` could end up negative. Then `best` would be set with a negative distance. This is indeed a bug.

Wait, let me re-check. `t0` is initialized to 0.0. Then for each axis, if `ta > t0`, `t0 = ta`. If the ray starts inside, some `ta` values are negative, so `t0` stays at 0.0 or becomes a small negative value. Actually no - `ta` could be negative, and if `ta > t0` (where t0=0), then t0 becomes negative. So yes, a ray starting inside a box could get a negative t0.

But actually, the bounding sphere reject at the top might catch this:
```rust
let (r, t) = (b.half.len(), oc.dot(dir));
let reach = best.as_ref().map_or(max, |h| h.dist);
if t + r < 0.0 || t - r > reach || oc.dot(oc) - t * t > r * r {
    return;
}
```
If the ray starts inside, `oc.dot(oc) - t*t` would be negative (since the closest point on the ray to the center is the origin itself, and the origin is inside), so the sphere test passes. Then the slab test would give a negative t0. This is a real edge case.

**Issue 2: `raycast_near` DDA cell walking**
Looking at `raycast_near` (around line 490-540):

The DDA walks cells in XZ. But there's a subtle issue: when `dir.x` or `dir.z` is exactly 0, the code handles it with `1e-9` checks. But what about when the ray origin is exactly on a cell boundary? The initial cell is computed as `(o.x / c).floor() as i32`, which could be off by one if `o.x` is exactly on a boundary and `dir.x < 0`. Actually, `floor()` handles this correctly for positive directions, but for negative directions, if `o.x` is exactly on a boundary, `floor()` gives the correct cell.

Wait, there's another issue. The DDA starts at the cell containing the origin, but the first cell is tested before any movement. However, `tx` and `tz` are computed as the distance to the *next* cell boundary, not the current one. So the first cell is tested, then we advance. This seems correct.

But there's a more subtle issue: the DDA only walks in X and Z. What if the ray is nearly vertical (dir.y is large)? The DDA still works fine since it only cares about XZ.

**Issue 3: Terrain ray (`Terrain::ray`)**
Looking at `Terrain::ray` (around line 260-290):

```rust
pub fn ray(&self, o: Vec3, dir: Vec3, max: f32) -> Option<(f32, Vec3)> {
```

The marching step is `dt = self.step * 0.5`. This means for a coarse heightfield (large step), the ray could miss narrow features. The bisect then refines, but only within the cell where the first underground sample was found. If the ray passes through a narrow gap between two tall features within a single marching step, it could miss the hit entirely.

Also, the `below` check uses `self.surface(p.x, p.z)` which includes road blending. This is correct for collision but could cause issues at road boundaries where the surface changes discontinuously in derivative.

**Issue 4: `raycast_near` early termination**
```rust
let reach = best.as_ref().map_or(max, |h: &RayHit| h.dist);
let t_next = tx.min(tz);
if !t_next.is_finite() || t_next > reach {
    break;
}
```
This stops when the next cell is beyond the current nearest hit. But what if a static body spans multiple cells and the hit is on the far side of it? The body was already tested when its cell was first encountered, so this is fine.

However, there's a subtle issue: the code tests `broad.big` and `broad.movers` first, then spawned entities, then touched entities, then walks cells. But `broad.movers` includes ALL movers from the last step, not just those near the ray. This is fine for correctness but could be inefficient.

## 2. Vehicle snagging / spurious collision impulses on road seams

**Issue 1: Road seam height discontinuities**
Looking at `Terrain::road()` (around line 150-230):

The road blending uses a smooth falloff (`on = 1.0 - (d2.sqrt() - r.half) / ROAD_BLEND`), and overlapping roads are blended. The test claims steps are < 0.03m
```

## Findings & Actionable Recommendations

*(No direct content, see reasoning trace)*