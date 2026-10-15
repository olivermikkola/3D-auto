Bridge slab clearance verification
==================================

Scope: recover only db5bf5c / 91b2837 from the recovery branch, independently
based on origin/main 24804ed6e890b5378493c389bd7ac7dd73634685. No railway,
police, pedestrian, terrain-data, engine-runtime or dependency changes.

Mechanism
---------
The real caller is city.build() in game/lib/city.lua, calling roadnet.build().
Previously roadnet built a full-width slab and underside below each deck,
including 3m pavements on either side. That could extend into a neighbouring
lower carriageway. The recovered change computes all deck height functions
before building any slabs (so twin-deck order does not affect the result).
At both ends and the midpoint of each <=6m piece it samples outward at 0.5m
intervals. The decisive condition is:

    if dh > 0.15 and dh < 4 then return math.max(w, o - 0.5) end

The own asphalt half-width w is a hard floor. Only the excess lateral slab
is cut; asphalt geometry, centerline, height profile and pier generation are
unchanged. The shifted collider and concrete underside share sw=left+right.
Railings are omitted on trimmed sides, not moved into a carriageway.

This is bounded sampling, not exact polygon clipping. It cannot repair real
asphalt overlap, surveyed grade discontinuities, or unrelated sidewalk and
terrain obstacles. Height differences <=0.15m or >=4m and tunnel neighbours
are intentionally not trimmed. No map errors are filtered out of probes.

Focused RED / GREEN
-------------------
Tests use the production Lua roadnet.load/build, real engine bindings and
static bodies, actual mesh baking, and engine.raycast. The test kit supplies
only a deterministic RNG and the same static-spawn adapter city uses.

Before production changes:
    nice -n 10 cargo test bridge_tests -- --nocapture --test-threads=1
    Exit 101: 3 pass / 2 fail. Adjacent and twin fail because a bridge collider
    blocks the lower lane at x=6.50,z=-25. See bridge-red.log.
After production changes:
    Same command: exit 0, 5 tests / 7 scenarios pass (bridge-green.log).

Final fixtures additionally put the lower twin over a valley, check its own
support and reverse build order. They probe own-deck support every 25cm,
including seams/abutments, at x=-3.9,-2,0,2,3.9; height remains 5m; piers
remain. They check collider/concrete widths match, rail-height lane clearance,
true own-asphalt overlap remains detectable, and same-height / high-clearance
non-conflicts keep full width. Final debug/release runs include these checks.

Lane probes, seed 1337
----------------------
Using this worktree's target/release/auto and game Lua, sequentially:
    MAP=<city> SEED=1337 ROAD_CLEAR_TEST=1 ROAD_CLUTTER_MAX=0
    ROAD_CLEAR_MAX=<limit> target/release/auto game --headless 5

Before, limit=0 deliberately fails: Raisio 21 obstacles / 17728 lane segments;
Turku 22 / 16046. Clutter is 0 in each. After, limits 6 and 21 pass, completion
markers present; ROAD_CLEAR_DEBUG=1 records nearby road widths/heights.
Raisio: 6 = 5 bridge + 1 terrain. Turku: 21 = 17 bridge + 3 sidewalk + 1 terrain.
No threshold was raised (21->6,22->21).

Raisio's removed hits include Pernontie/Kustavintie's twin-deck protrusions.
Remaining sites include Upalingontie, Kuninkojantie/Turun kehatie and terrain
at Raisionlahdentie. Turku retains deck/ramp conflicts around Virusmaenramppi /
Ratapihankatu and Helsinginkatu, plus sidewalk hits on Aurakatu, Vanha Suurtori
and Piispankatu. The fix preserves own asphalt rather than hiding those hits.
Counts identify distinct struck colliders, not a proof every road is clear.

Verification commands and results
--------------------------------
All build/test commands run from this worktree, CARGO_BUILD_JOBS=2, nice -n 10;
Rust test threads bounded to 2 and headless --jobs 1. No windows or GPU runs.

    cargo fmt --check                                  PASS
    cargo test -- --test-threads=2                      PASS 48/48
    cargo test --release -- --test-threads=2            PASS 48/48
    cargo clippy --release -- -D warnings               PASS (CI form)
    cargo build --release                              PASS
    python -m unittest discover -s tools -p 'test_*.py'  PASS 51, 7 skipped

    python tools/headless_tests.py --binary target/release/auto --game game
      --output bridge-pr-smoke --seeds 1337 --jobs 1 --timeout 1200
    PASS 39/39 (standard PR maps manhattan,harbor,raisio).

    python tools/headless_tests.py --binary target/release/auto --game game
      --output bridge-headless-results --maps raisio turku --seeds 1337
      --jobs 1 --timeout 1200
    22/26 pass; Raisio 13/13, Turku 9/13.

Baseline comparison: git archive HEAD game | tar -x -C bridge-baseline,
then same extended command with --game bridge-baseline/game --maps turku
--output bridge-baseline-headless. Same binary, baseline Lua. Turku 9/13,
identical four failures:
    autoplay: stunt ramp peak 1.2m;
    city: Unioninkatu max grade 22%;
    mission: Smuggler's Run marker start timeout;
    reliability: pursuit step must reduce shortest road distance.
No assertions or timeouts changed to conceal these existing failures.

Additional stricter cargo clippy --release --all-targets -- -D warnings fails
on the unchanged pre-existing src/audio.rs:468 field_reassign_with_default
(test code). CI's actual clippy command passes. No unrelated lint cleanup.

Not run: full multi-seed/soak matrix, software GL screenshot suites (7 Python
render/display skips), other platforms. Fresh independent reviewer must inspect
source and rerun appropriate acceptance checks before publishing any PR; these
results are an implementation handoff, not independent acceptance or CI proof.
