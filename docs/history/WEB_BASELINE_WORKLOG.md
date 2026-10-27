# Web performance baseline — resumable work log

## Scope and authority

Oliver approved the first PR: establish reproducible post-merge memory/performance measurements before further optimization. No subagents or provider changes; no deployment/merge. Independent review is pending until an approved reviewer route is available. Preserve the original checkout and unrelated untracked work.

## Resume coordinates

- Branch: `feat/web-performance-baseline`
- Worktree: `/home/olivermikkola/Projects/3D-auto-worktrees/web-performance-baseline`
- Base: `d627d92de02b8aa5311ddc02b3f55d3c75d96245` (merged #94/#95)
- Preparation: original checkout `.hermes/plans/2026-10-16_111448-web-performance-day-prep.md`
- Active conversation: Forge, Telegram with Oliver. No worker/task run was spawned.

## Checkpoint 1 — scope and prerequisites

- Fresh worktree created from fetched `origin/main`. Original checkout untouched.
- Existing web checker only prints a settled wasm allocation and page log; needs machine-readable evidence, repeated samples and strict runtime-failure reporting.
- `wasm32-unknown-unknown` target absent initially. wasi-sdk not found in checked home tools/opt/download locations. Native binary in original checkout predates merges, so must not be used as current evidence.
- Firefox/geckodriver and Chrome available. Headless browser rendering only; no visible host windows.

## Checkpoint 2 — real builds and first tests

- Installed the active Rust toolchain's wasm target; downloaded wasi-sdk 34 into Forge scratch, not a system installation.
- Fresh native and web release builds succeeded. Web pack: 108 files, 14.8 decimal MB; `auto.wasm` 15,906,391 bytes.
- Real native runs (`MAP=<map> SEED=1337 MESH_REPORT=1 /usr/bin/time -v target/release/auto game --headless 15`) all exited 0. Raisio: 198 decimal MB mesh data, maximum RSS 430144 KiB. Turku: 213 decimal MB mesh data, maximum RSS 489360 KiB. These are headless CPU measurements, NOT browser or GPU memory/FPS.
- TDD: missing-build CLI test failed against original checker, then passed after explicit prerequisite validation. Readiness/report and runtime-error tests also observed failing before implementation, then passed (3 tests currently).
- Extended checker is uncommitted: JSON samples, readiness/failure state, MiB labels, explicit Firefox binary and cleanup. More integration validation is needed.
- Firefox WebDriver session creation timed out with both default snap executable and explicit snap binary. No browser-memory result or screenshot claimed. Subsequent `ps` enumeration also timed out; do not launch duplicate Firefox jobs blindly.
- Available Python environment includes Playwright, offering an alternative execution path to investigate.
- Oliver asked whether Lua was replaced: inspected `web/Cargo.toml`, `web/lua-src/PATCHED.md` and `src/web.rs`. Answer: mlua remains; vendored C Lua compiles to wasm with wasi-sdk and internal WASI shims, not a pure-Rust Lua interpreter or replacement browser runtime.

## Checkpoint 3 — publication boundary

- Fresh native and web release builds passed; `cargo fmt --check`, `cargo clippy --release -- -D warnings`, 50 Rust release tests and 4 focused Python tests passed. Full Python/gameplay/render suites not run in this checkpoint.
- Playwright successfully launched installed headless Chrome and read a real data-URL title. However the game navigation attempt timed out before producing any map report or screenshot. This does not establish a game defect or a browser compatibility result; browser automation/runtime diagnosis remains open.
- No browser FPS, browser memory or phone-readiness figure is published. Draft PR only; independent review and real browser integration validation pending. No gameplay/rendering code changed.
- Native raw logs are preserved under `docs/baselines/2026-10-16/` for reproducibility. SDK and build outputs remain local/untracked.

## Checkpoint 4 — graphics initialization isolated

- Full local Python discovery completed: 68 tests, OK, one skipped. Existing PR commit `7f73a83` passed all three GitHub CI jobs (Linux, Windows, macOS). This does not include browser automation acceptance.
- Tight repro: installed Chrome can load a data URL, but evaluating `document.createElement('canvas').getContext('webgl2')` on a minimal page stalls. Same symptom with bundled Playwright Chromium and explicit SwiftShader; in-process software GPU also stalls. No additional graphics workaround attempted after these bounded probes.
- A temporary HTTP response wrapper (no source edit) traced real game imports: `now` returns, `web_query` returns, execution enters `init_webgl` and does not return. Literal `web/gl.js::init_webgl` calls `canvas.getContext('webgl2')` at that boundary. Thus the current Chrome blocker is reproducible without Lua, WASM game logic or map loading. Exact OS/driver/sandbox root cause remains unverified. Firefox session creation is a separate unresolved symptom.
- These measurements do NOT prove the browser port is broken on Oliver's desktop. Next requires checking WebGL2 on his actual Beelink browser/desktop or diagnosing the graphics environment with permission; do not rewrite Lua or the WASM execution model to work around this evidence.
- Added a regression rejecting a ready marker with zero wasm allocation: observed FAIL, fixed, then focused suite passed. The draft remains blocked on real browser integration and independent review; no merge.

## Checkpoint 5 — working software-rendered browser baseline

- Oliver explicitly requested returning #96 to draft, fixing it and shipping afterward. Converted and read back `isDraft=true` before further edits. No subagent restriction was lifted; independent review remains a separate gate.
- Minimal WebGL2 repro now passes with bundled Chromium using explicit SwiftShader/hardware-GPU-disabled and a child environment without DISPLAY/WAYLAND_DISPLAY/DBUS_SESSION_BUS_ADDRESS. The combination is verified; no claim about the individual variable or driver root cause. Host settings unchanged.
- Added optional `--browser chromium` to the actual checker with this isolated software route. The CLI option test was observed failing first, then passing. Firefox remains available as default but its environment-specific automation failure is not claimed fixed.
- Real changed CLI executed sequentially on starter/Raisio/Turku, each with 1280x720, seed 1337, hour 12, 12-second window. All returned 0, `ok=true`, empty sampled-log errors and empty page exceptions. Observed wasm allocation: 25559040 / 470417408 / 539426816 bytes respectively (24.38 / 448.62 / 514.44 MiB rounded). JSON evidence retained; screenshots in Forge scratch. These are single-run linear-memory high-water observations, not full load peaks or FPS.
- Earlier exploratory Chrome runs emitted pointer-lock user-gesture warnings; backend discloses exact warnings and tolerates only that precise known limitation. Changed checker runs had no such exceptions.
- Actual Raisio/Turku screenshots contain rendered scene, player, roads/buildings and HUD, not a blank canvas. Image inspection cannot prove movement/input, all landmarks or phone usability.
- Real-browser intentional JS exception integration test returned nonzero with exception preserved in JSON. All seven focused tests passed with WEB_CHECK_INTEGRATION=1. This fixture is explicitly synthetic test input, not game measurement data.
- Historic browser memory paragraph updated only from real current reports. No geometry/runtime changes, no deployment or merge. Remaining gates below are not erased by successful smoke runs.

## Remaining acceptance work

1. Obtain fresh independent review via an approved route; no subagents are currently authorized. Jack owns final acceptance. Keep draft until resolved.
2. Run CI on the final revision. Firefox-specific WebDriver environment trouble remains a documented optional-path limitation, not a verified cross-browser result.
3. Full load/steady-state frame tracing, repeated route tests and physical-device input/PWA tests belong to follow-up performance work; current PR delivers explicitly scoped sampled allocation evidence, not those results.

If inference fails, inspect git status and this log before restarting. Never replace missing measurements with plausible numbers.
