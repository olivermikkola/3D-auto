# KAT-Coder Audit Report: Zero-Dependency Simplicity & Code Cleanup

**Generated:** 2026-10-15 18:34:31
**Elapsed Time:** 244.5s
**Tokens:** 12005 (Prompt: 10505, Output: 1500)

## Reasoning Trace

```
Let me analyze each file for over-engineering, unnecessary abstractions, and opportunities for simplification.

## src/math.rs Analysis

1. **Vec3::mul** - This is component-wise multiplication, but there's no `Mul<Vec3>` impl. The method exists but isn't used via operator. It's fine as a method but could be removed if unused. Let me check... it's not used anywhere in the code shown. Actually, looking at the code, `mul` is a method on Vec3 but there's no `impl Mul<Vec3> for Vec3`. The method exists but is never called via operator. It's a bit odd to have a method that's not used as an operator. But it might be used internally. Let me check... I don't see it used anywhere. Could be dead code.

2. **Vec3::get/set** - These use array indexing with match. Could be simplified with a direct array access pattern, but the match is actually fine for safety. However, they could be eliminated if unused. Let me check... not used in the shown code.

3. **Quat::euler** - The comment says "Yaw about +Y, then pitch about local +X, then roll about local +Z" but the implementation multiplies axis-angle quaternions in world space order. This is actually yaw * pitch * roll in world space, which gives a different result than local Euler angles. The comment is misleading but the code might be correct for the intended use. Not really over-engineering though.

4. **Mat4 multiplication** - The nested loop with map/sum is a bit heavy. Could be unrolled or simplified, but it's correct. Not a major issue.

5. **Vec3::rot_y** - This is a standalone method. It could potentially be inlined where used, but as a method it's fine.

6. **Vec3::mul** (component-wise) - This method exists but there's no `Mul<Vec3>` impl. If it's not used, it's dead code.

7. **Quat::nlerp** - The dot product check for sign flipping is correct but the implementation is a bit verbose. Could be simplified slightly.

8. **Mat4::look_at** - The cross product for `s` could fail if `f` and `up` are parallel, which is handled. Fine.

9. **Vec3 constants** - `ZERO`, `ONE`, `UP` are fine.

10. **Quat::axis_angle** - Calls `axis.norm()` which allocates... wait, no, Vec3 is Copy. Fine.

Actually, let me look more carefully:

- `Vec3::mul` (component-wise) - unused method, dead code
- `Vec3::get`/`set` - unused methods, dead code
- The `Mul<Vec3>` for Vec3 is not implemented but `mul` method exists - inconsistent

## src/engine.rs Analysis

1. **Entity::new** - The default values are verbose. Could use `Default` trait more effectively, but it's fine.

2. **Engine::spawn** - The `tagged` entry insertion is fine.

3. **Engine::despawn** - The binary search for tag removal is correct but could be simplified. The `if let` chain is a bit complex.

4. **Engine::set_terrain** - This is quite long and complex. The chunking logic with nested loops is necessary but could be cleaner.

5. **Engine::blend/unblend** - The saved data structure `(usize, [Vec3; 2], [Quat; 2])` is a bit awkward. Could use a struct but that adds complexity.

6. **Engine::hud_rect** - The hardcoded vertex pairs for a rectangle are a bit magic-number-y. Could be a small array.

7. **Engine::hud_text** - The bitmap text rendering is fine.

8. **tagged HashMap** - Uses `Vec<u32>` for each tag, kept in spawn order. The despawn uses binary search which is O(log n) but removal from Vec is O(n). For typical tag counts this is fine.

9. **Light struct** - Has `follow: Option<u32>` which is an entity id. Fine.

10. **Engine fields** - Many fields, but this is a game engine, so it's expected.

## game/lib/util.lua Analysis

1. **U.clamp** - Fine, idiomatic Lua.

2. **U.lerp** - Fine.

3. **U.angle_diff** - The modulo operation with `math.pi` is correct for Lua's `%` operator. Fine.

4. **U.forward** / **U.right** - Fine.

5. **U.dist2d** - Fine.

6. **U.inside_polygon** - The ray-casting algorithm is standard. Fine.

7. **U.ground** - Requires "lib.roadnet" every call. This creates garbage. Could be cached at module load time.

8. **U.player_pos** / **U.player_yaw** - Each requires "lib.state" every call. Could be cached.

9. **U.message** - Requires "lib.state" every call. Could be cached.

The main Lua issue is repeated `require` calls that create garbage collection pressure. In Lua 5.4, `require` results are cached in `_G._REQUIREDNAME` or the package cache, so the returned table is reused, but the `require` call itself still has some overhead and the `local G = require "lib.state"` pattern creates a local binding each time.

Actually, in Lua, `require` is cached, so the table is the same object. The overhead is minimal but the pattern of `local G = require "lib.state"` inside functions is repetitive. These could be module-level locals.

Let me also look for other issues:

In `math.rs`:
- `Vec3::mul` (component-wise) is a method but there's no `Mul<Vec3>` impl. If unused, it's dead code.
- `Vec3::get`/`set` are unused.
- The `Quat::euler` comment says "local +X" and "local +Z" but the implementation uses world-space axes. This is a documentation issue, not over-engineering.

In `engine.rs`:
- `Engine::new` has a very long initialization block. Could be split but that's style.
- The `blend`/`unblend` system with the saved vector is a bit complex but necessary for interpolation.
- `tagged` uses `binary_search` for despawn - this is correct but the `if let` chain is verbose.

Let me now write the recommendations.

For `math.rs`:
1. Remove unused `Vec3::mul`, `Vec3::get`, `Vec3::set` methods
2. The `Quat::nlerp` can be slightly simplified

For `engine.rs
```

## Proposed Simplifications & Refactorings

*(See reasoning trace)*