# Real Turku and the Yo-kylä–Kupittaa Loop Implementation Plan

**Goal:** Build recognizable, geographically grounded Turku in the game's own visual style, starting with connected Ylioppilaskylä, Kupittaa and downtown, while Oliver plays the frozen v0.8.0 baseline.

**Architecture:** Extend the existing OSM → roadnet/terrain pipeline rather than create a second engine or an invented grid. Open data establishes structure; curated district/landmark overrides establish character. Keep acquired 2 m ground data, runtime resolution/LOD, building-height sources and personal visual references distinct.

**Tech stack:** Existing Rust/miniquad engine, Lua game, Python stdlib importer, available system Python/Pillow/NumPy, OpenStreetMap (ODbL), MML elevation model 2 m (CC BY 4.0). No new global packages, paid services, model routing changes or extracted Google assets.

## Authority and baseline

- User approved: start v0.8.0 for Xbox play, write a thoughtful potential-PR roadmap first, then work on Turku with the supplied references while playtest feedback arrives.
- Actual executor for initial local work: Jack, directly in the existing GPT-6.1-sol/Nous conversation. Do not misattribute work to Forge or a phantom worker.
- Baseline: v0.8.0 / `36b373e08dd2bde5b2b78cd61ea748171d78f173`.
- Canonical repository: `/home/olivermikkola/Projects/3D-auto`.
- Isolated development worktree: `/home/olivermikkola/Projects/3D-auto-worktrees/turku-geodata-foundation`, branch `feat/turku-geodata-foundation`.
- Frozen play source/binary: `/home/olivermikkola/.hermes/profiles/jack/artifacts/gta-v0.8.0-play`; running process handle `proc_b035b45801ab`. Do not change its files, saves, focus, display or controller while Oliver plays.
- Local planning, implementation, downloads and tests are approved. Public PR publication, merge and release remain distinct gates; roadmap labels are working titles, not assigned GitHub PR numbers.
- Independent source/test review is required before accepting consequential implementation. Oliver explicitly approved Gemini review to conserve Nous usage; keep implementation with Jack and use the configured Gemini/OmniRoute isolated review route. Jack's default Gemini route is also approved as fallback if GPT quota fills; a saved chain is not proof of an exercised failover.
- Personal context is only why these districts were chosen. Do not publish Oliver's residence, education or private screenshots as repository content. Public docs say “district comparison areas.”

## Observed state, not inherited claims

- Six selectable maps plus Starter Town; Turku is currently an 8×8 grid, not an imported real city.
- Importer supports only Raisio; defaults are shared, output terrain step is a global 10 m constant.
- Terrain helper downloads old 10 m sheet URLs and silently returns 0 for outside/no-data samples. A real city import must fail rather than manufacture a flat success.
- Existing chunk check only counts road entities; it does not prove residency, camera correctness or memory boundedness.
- Castle prefab is defined but not instantiated. Default river geometry extends outside the city into empty space. Existing probes/mission registration don't establish playability.
- Native v0.8.0 images and 39 Rust / 31 Python unit checks are historical baseline evidence, not acceptance of new Turku.
- MML 2 m is a bare-earth raster derived from laser scanning, not building roofs. Roof shape/height data needs its own later source.
- Existing MML project key file is present. New OGC process requests returned 401 unauthenticated and 403 with that key; values/URLs containing credentials were not printed. Overpass POST timed out, but a bounded GET returned genuine district nodes. Retry supported public routes before concluding acquisition is blocked.

## Reference and geographic anchors

Private reference files remain outside the repository:
- Yo-kylä aerial: `/home/olivermikkola/.hermes/profiles/jack/cache/images/img_823ad6886485.jpg` (also prior duplicate).
- Kupittaa aerial: `/home/olivermikkola/.hermes/profiles/jack/cache/images/img_e0e7f991a623.jpg`.
- City overview: `/home/olivermikkola/.hermes/profiles/jack/cache/images/img_fd438e25ae15.jpg`.
- Wooden pedestrian bridge: `/home/olivermikkola/.hermes/profiles/jack/cache/images/img_6578ec75a24f.jpg`.
- Boundary sketch: `/home/olivermikkola/.hermes/profiles/jack/cache/images/img_4692778864f3.jpg` (user-intent reference, not surveyed geometry).

Genuine OSM node 25417668 places Ylioppilaskylä at 60.4637095, 22.293054. OSM node 25426007 places Yliopistonmäki at 60.4556899, 22.2841185 and tags elevation 39 m. Retrieved snapshot time 2026-10-14T13:15:11Z.
Turku AMK's official campus page identifies EduCity at Joukahaisenkatu 7 and ICT-City at Joukahaisenkatu 3; neither is assumed to be Oliver's exact building.

Sources:
- `https://www.maanmittauslaitos.fi/en/maps-and-spatial-data/datasets-and-interfaces/product-descriptions/elevation-model-2-m`
- `https://www.maanmittauslaitos.fi/paikkatiedon-tiedostopalvelu/tekninen-kuvaus`
- `https://www.turkuamk.fi/en/about-us/campuses/kupittaa-campus/`
- Existing `docs/ROADMAP.md`, `tools/osm_import.py`, `tools/dem.py`, `game/lib/roadnet.lua`, `game/maps/raisio.lua`.

## Proposed PR sequence

### A. City-data foundation and honest 2 m acquisition — begin now

**Parallel priority:** The user's newly supplied v0.8.0 reports are captured in `docs/PLAYTEST_V0.8.0.md`. Before promoting map expansion, reproduce lane-direction and police spawn/clearance faults, bus/post collisions and bridge access in shared systems; text glyphs and Pirilä frame jitter also need focused checks. These may outrank the next content PR. Do not fix the running play copy.

**Outcome:** Turku becomes an explicit, reproducible importer target with a frozen geographic region and real input provenance. Resolve a working acquisition route for MML 2 m data; validate resolution, reference system, bounds, no-data and storage before game integration. Keep Raisio output/defaults compatible.

Likely files:
- `tools/osm_import.py`: extract per-area configuration and support per-area/source-specific terrain inputs without changing legacy defaults.
- `tools/dem.py` or a narrowly scoped `tools/geodata.py`: validation/sampling/acquisition of verified GeoTIFF inputs; reject uncovered/no-data points for new imports.
- `tools/test_city_geodata.py`, `tools/test_dem.py`: actual consuming-path positive/negative tests.
- `docs/TURKU_ROADMAP.md` and source/attribution manifest; raw downloads stay ignored.

Steps:
1. Add one failing test that Turku has explicit valid bounds/origin and no fake grid fallback; run RED.
2. Add the smallest per-city configuration; run GREEN and legacy tests.
3. Add failing malformed bounds / unsupported step / missing terrain tests one behavior at a time, then implement validation.
4. Resolve the actual MML process or MapSite download links without exposing credentials; preserve failed responses separately.
5. Fetch OSM in bounded cached requests (GET if verified workable), store raw source timestamps/hashes; resume partial acquisition instead of starting again.
6. Read GeoTIFF pixel scale/tiepoint/CRS and sample actual points; retain 2 m source metadata. Never label a 10 m sample output as a 2 m runtime map.
7. Use tiny deterministic fixture rasters for tests, explicitly labelled synthetic—not as geographic evidence.
8. Independently review the foundation before calling it ready. If data access remains blocked, deliver validated importer capability and name the acquisition gap; don't pretend the city exists.

Acceptance:
- Explicit Turku configuration covers both comparison areas, with provisional regional bounds clearly distinguished from the municipal boundary.
- Actual acquired data is hashed and dimensions/resolution checked; missing/corrupt/no-data inputs fail clearly.
- Focused RED→GREEN logs and legacy suite pass; map-generation record distinguishes downloaded input from generated output.
- Frozen play copy remains unchanged and running.

### B. Real Turku base and first Yo-kylä–Kupittaa driveable loop

Depends on A.
- Replace `game/maps/turku.lua` grid with imported real roads, footprints, water, land cover and terrain.
- Create `game/maps/turku_osm.lua`, terrain assets and provenance from real inputs.
- Choose public parking/start/hospital/garage points by inspecting actual data and clearance; do not overwrite real buildings with arbitrary pads.
- Preserve Yo-kylä courtyard/block pattern, Nummenranta riverside, university hill, Kupittaa park and campus-scale footprints.
- Remove/disable incompatible prototype river props rather than leave duplicate channels and bridges across land.
- Define a public district loop between Yo-kylä, Kupittaa and downtown based on actual connected roads, not assumed personal commuting directions.

Acceptance: matched aerial frames for the two districts and connecting area; inspect recognizable layout rather than exact Google rendering; real vehicle/input route traversed without respawn, broken junctions or invisible walls; full map/seed regression coverage and attribution.

### C. Terrain streaming, render residency and foot routes

- Profile actual B before scaling up the region; don't build a huge 2 m Lua grid solely to claim resolution.
- Keep high-resolution source retained; make runtime tile/LOD choice explicit and measured.
- Fix/extend chunk residency tests to move the real player and inspect visible scene state, load counts and road/terrain collision continuity.
- Verify riverbank walks and pedestrian crossings, with dry deck checks preventing false water respawns.

Acceptance: sustained native route over multiple tile boundaries, bounded observed residency/load behavior and no missing terrain. Headless/Xvfb checks while Oliver plays; native performance capture waits until his desktop is free.

### D. Raisio–Turku continuity and real crossings

- Use official municipal border geometry and shared georeferenced crossing IDs/positions.
- Repair real transfer consumers for exact vehicle identity/velocity/heading, health, inventory and wanted state rather than registration-only probes.
- Include the wooden walking-only crossing with believable timber railings and vegetation; do not silently turn it into a car bridge.

Acceptance: drive both directions at real road crossings, compare state before/after; foot-only path exercised; errors after a PASS marker still fail the harness.

### E. District character and verified landmarks

- Generic building categories first; selected overrides for recognizable public places in Yo-kylä/Kupittaa and central Turku.
- Roof shapes/heights: assess real MML building/laser coverage; don't assume ground DTM yields roofs.
- Reposition bridges, Föri and boats against imported geography and water levels; instantiate the castle at its actual position.

Acceptance: same-framing aerial comparison, detail and street-level views, actual instantiated meshes and collisions. Oliver's local feedback remains aesthetic/user acceptance, not a substitute for engineering checks.

### F. Gameplay and release truth

- Fold Oliver's v0.8.0 playtest notes into focused bug-fix PRs; reprioritize serious control/collision defects ahead of content.
- Only resume archipelago/boat mission polishing once the real map/river is usable; exercise mission progression and pursuit, not just registration.
- Add map coverage/screenshot evidence to PR/release templates and correct stale README/roadmap claims.
- Evaluate engine/game 1.0 readiness by exercised outcomes, not PR count. Merge and release remain Oliver's gates.

## Validation and rollback

All changes/tests run in the development worktree. Build with a worktree-owned `target`; no overwrite of the play executable.

Baseline/focused commands:
- `cargo fmt --check`
- `cargo clippy --release -- -D warnings`
- `cargo test --release`
- `cargo build --release --locked`
- `/usr/bin/python3 -m unittest discover -s tools -p 'test_*.py'`
- `python3 tools/headless_tests.py --output <fresh-output> --jobs 2 --soak`
- After B, explicit Turku headless tests and a checked map/seed matrix; existing default runner omits Turku.
- Screenshot work: Xvfb/software GL, no host-native popup while Oliver plays. Final native target captures and manual input after his session is free.

Preserve rejected candidate logs and captures. Don't reset the baseline/main, delete existing work or publish a partial repair as a finished city.

## Current unresolved dependencies

- Resolved a working legacy MML 2 m download route using the existing project key after the new OGC service rejected it. Downloaded genuine L3324B GeoTIFF: 3000×3000, pixel scale 2 m, EPSG:3067; 25,333,601 bytes; SHA-256 `599645032a4c11f6cda887b7e1eaf57573c2612575f5a131d614a3baa3545e8f`. Full requested regional coverage still needs verification/additional tiles.
- Runtime cost of retaining 2 m resolution over city-scale ground: must be profiled and tiled, not guessed.
- Exact public route and comparison camera alignment: derive from source coordinates and inspect, not automatic image descriptions.
- Fresh independent discovery reviewer is dispatched through the approved configured Gemini route; actual native tool qualification passed with session `20261014_163322_7d9d4f`. Foundation acceptance still awaits a separate frozen candidate review.
- Running v0.8.0 reports `Sunshine X-Box One (virtual) pad` connected. Specific gameplay input remains Oliver's playtest, not coordinator-tested controller acceptance.
