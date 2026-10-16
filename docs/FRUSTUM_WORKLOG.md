# Frustum culling — resumable work log

## Scope / authority
Oliver approved continuing to the next optimization PR after trusting #96. Work directly; no subagents, provider changes, deployment or merge. Trust is not independent review; fresh independent review remains pending before final acceptance. #96 final revision 5641cb8 passed Linux/Windows/macOS CI; its software-rendered baseline is not hardware FPS or total memory.

## Coordinates
- Branch: perf/frustum-culling
- Worktree: /home/olivermikkola/Projects/3D-auto-worktrees/frustum-culling
- Base: d627d92de02b8aa5311ddc02b3f55d3c75d96245 (origin/main at start)
- Original checkout and #96 worktree preserved.

## Outcome / acceptance
Replace rear-half-space-only view rejection with conservative six-plane sphere/frustum tests using accurate local mesh bounds transformed by entity translation/rotation/scale. Preserve fog-distance culling and offscreen shadow casters. Do not implement LOD/eviction or claim resident-memory reduction. Terrain vertices are world coordinates on origin-positioned entities: use mesh center, not entity origin.

## Sequence
1. Read actual draw caller, upload path, matrix conventions and existing tests.
2. Add failing tests through render visibility decision; implement bounded plane tests and transformed mesh bounds incrementally.
3. Verify Rust gates and current headless gameplay tests; compare deterministic actual browser rendered frames and draw submissions before/after using software rendering. Do not claim hardware FPS.
4. Publish separate draft PR with raw evidence and exact pending independent review.

## Checkpoint 2 — implementation and exercised render caller

- Failing tests for six-plane sphere rejection and offset/rotated/negative-scale bounds were run before implementation; both initially failed to compile due to missing functions, then passed. The real draw loop now calls the tested sphere decision; real mesh upload computes local bounds before CPU copy release.
- 52 Rust release tests pass, Clippy with warnings denied passes, fresh native+wasm builds succeed; full Python discovery: 64 tests, one skipped, no failures. This branch starts from main without #96's checker tests, explaining the lower count.
- Actual WebGL draw methods counted before/after at animation callback 30, seed 1337, hour 12, 1280x720, isolated Chromium SwiftShader. All draw variants (elements/instanced/arrays) counted, including shadows/HUD. Raisio: 3398→752 submissions; Turku: 7470→1507. These are sample draw counts, not hardware FPS, CPU timing or resident-memory savings. Wall-clock simulation timing differs; not pixel-identical deterministic scenes.
- An initial instrumentation attempt counted only drawElements and used RAF polling after stopping RAF; discarded zero counts/timeout as invalid evidence. Corrected harness counts all variants and polls with timers.
- Actual after images show scene/ground/buildings/HUD; no obvious blank terrain or severe clipping in sampled spawn views. Not enough to prove every landmark/camera angle.
- Raw comparison JSON and reproducible browser harness preserved with this PR. Screenshots remain in Forge scratch; no screenshot-only acceptance claim.

## Remaining acceptance
- Independent review pending under no-subagents constraint; user trust is not independent acceptance. No merge or ready-state changes made to #96.
- CI on this PR's exact head and broader landmark/camera tests required. Need measure CPU overhead of plane tests and optimize plane extraction once per frame if it becomes material.
- No LOD, eviction, asset migration or PWA changes bundled.
