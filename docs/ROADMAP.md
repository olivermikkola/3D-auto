# Roadmap

Where 3D-auto is going, what's next, and what we've learned on the way. Written for whoever picks
up the work next, human or model. The main README describes how things work today. This file says
what to build next and why.

## The goal

The long-term goal is a GTA-style game that can be built for **any real city from open data**.
Raisio, Finland is the testbed because Oliver lived there for 20 years and can say what's right
and what's off. It is not the end product.

Targets after Raisio, roughly in order of difficulty:

- **Turku**: the next city over, and Oliver's home town now.
- **1:1 Manhattan**: about 60 km², dense, a grid, with tall buildings.
- **Helsinki**: combines Raisio's problems (terrain, Finnish streets, sea) with Manhattan's
  (density, size).

Everything built for Raisio should be generic and driven by map tags, in `tools/osm_import.py`
and `game/lib/roadnet.lua`. Raisio-only facts belong in `game/maps/raisio*.lua`.

## Where things stand (v0.9.1, "Aurajoki")

- The release is called **Aurajoki** and ships Raisio and Turku (`aurajoki-v0.9.1-*`). Brands
  in the game are Finnish parodies (Häsburger, Pöli, Puskuri, Vicklund, Verkkari Stadion).
- Turku at real size: OSM roads and 2 m MML LiDAR terrain, the Aurajoki with real bridges,
  boats and the Föri, and hand-made 500 m slices: Kauppatori, Vanha Suurtori and Tuomiokirkko,
  Kakolanmäki with the funicular, Portsa, Turun linna and the harbour.
- Raisio is about 8 × 8 km of OSM data on the 10 m elevation model. Raisio ↔ Turku is one
  corridor, and you keep your car when you cross.
- Föli buses, Pasi the APC, police pursuits, pedestrians that keep to pavements and avoid
  traffic, and a camera spring arm.
- **Memory:** Turku peaks at about 1.2 GB RSS and Raisio at 1.1 GB. Lua accounts for 60–120 MB
  of that. About 800 MB is 6 M triangles of CPU-side geometry at 132 bytes each (a 40-byte
  vertex ×3, plus indices). Roads alone are 3.1 M triangles.

## Next, in order

### 1. See every landmark in CI

`tools/test_landmark_renders.py` renders Turku's landmarks and checks the pixels: a landmark
that is black, buried or in the wrong place fails. Extend it to every slice (Portsa, harbour,
Koroistenniemi, Raisio's centre) as each one is touched. A slice isn't done until it has a
camera here.

### 2. Halve the memory

- Pack vertices from 40 to 20 bytes: f32 position, i8 normal, u8 colour, emissive in alpha.
- Free the CPU copy of a mesh once the GPU has it; keep it only where something reads it back.
- Fewer road triangles: check what makes 3.1 M (kerbs, fillets, segment length).

Target: Turku under 500 MB, measured with `/usr/bin/time -v` on `--headless`.

### 3. What the Gemini review found that is still open

- One speed for everything: the bus does 107 km/h like a sedan. Give each vehicle class its
  own acceleration and top speed (bus about 70–80 km/h).
- Headlight and lamp cones are hard-edged polygons that add up to white. Soften and clamp them.
- Explosions are big white cubes. Make them smaller and short-lived.
- A 6-star wanted level is lost in 10 s of driving straight. Losing the cops should need time
  out of sight, scaled by stars.
- A whole evening passes in under two minutes. Slow the clock.
- The controls help box covers the top left on every start. Show it on the first run only.

### 4. A story that reacts: catalogue + scorer

The world stays fixed. What happens in it is picked from hand-written material:

- **Catalogue** (Lua): story fragments, mission branches and reactions. Each one has
  preconditions (place, wanted level, time, what just happened), weights and cooldowns.
- **Scorer** (Lua, deterministic): scores the fragments that fit the current state and picks
  the best (same state and seed give the same pick), so tests stay stable. It costs no
  noticeable memory.
- Only once the catalogue is big enough to need it: swap the scorer for a small classifier
  behind the same interface (ONNX through `tract`). A 400 M-parameter model is 0.4–1.7 GB,
  more than the whole game today. Keep it out of the open world, and load it only for story
  missions.

### 5. More Turku

Kupittaa and Yliopistonmäki (from Forge's list), then Turku's other districts. Each slice comes
with a render check (see 1).

### Later

- Laser-scan roof shapes and heights (MML, CC BY 4.0) matched to OSM footprints.
- In-game credits screen for OSM and MML (attribution is in `game/maps/LICENSE` and the
  generated files today).
- Helsinki, then 1:1 Manhattan.

## Data sources

| What | Where | Notes |
|---|---|---|
| Roads, buildings, land use | OpenStreetMap via Overpass | ODbL. Fetch in tiles (`osm_import.py --fetch`); public servers time out on whole towns. |
| Terrain | Maanmittauslaitos elevation model, 10 m (2 m available) | CC BY 4.0. Key in `~/.config/3d-auto/mml-key`. |
| Building heights and roofs | MML laser scanning | Open, CC BY 4.0. |
| Ground colour | MML orthophotos | Open. Not used yet. |
| Helsinki | City of Helsinki's open 3D city model | Not used yet. |
| Manhattan | NYC Open Data building footprints with heights | Not used yet. |
| Google Earth 3D | — | **Off limits:** its terms don't allow pulling its models into a game. |

## How to work on this repo (lessons learned)

- **Test like CI before every push.** Run the full suite:
  `python3 tools/headless_tests.py --output <dir> --jobs 3 --soak` (all maps, all seeds), plus
  `--maps starter`, `--maps raisio` and `--maps turku` with `--seeds 1337`, plus
  `cargo fmt --check`, `cargo clippy --release -- -D warnings`, `cargo test --release`, and
  `python3 -m unittest discover -s tools -p "test_*.py"`.
- **Maintain PRNG determinism:** keep `math.random` calls consistent across vehicle spawns so
  soak tests don't desynchronize between seeds.
- **Check visuals by looking at pixels.** Probes like `KAKOLA_TEST` only prove an entity exists. In
  v0.9.1, Kakola rendered black, Kauppatori's paving was half under the hillside, and Turun linna
  stood on a road, all with green CI. Run `RENDER_CHECKS=1 python -m unittest
  tools/test_landmark_renders.py`, and look at the frames yourself. The older
  `tools/*_render_checks.py` only check that a PPM file was written.
- **Place landmarks from the map data, not by eye.** Compute the position from latitude and
  longitude with the map's `origin`. Filter the OSM boxes the prefab replaces (see `maps/turku.lua`).
- **Nothing hand-placed goes on a carriageway.** Check every tree, lamp, bench and wall with
  `roadnet.on_carriageway` (or move it with `roadnet.off_carriageway`). The Aurajoki promenade put
  208 of them on Turku's streets. `tools/test_road_clear.py` keeps the count at zero.
- **A look's colour multiplies the mesh's.** Mesh walls that a look colours must be white.
- **PRs run the seed-1337 smoke test only.** The full seed suite runs after merge, so run it
  locally before merging.
- **Fewer, checked PRs beat many fast ones.** 79 PRs in four days meant no one looked at a frame
  before merging.
- Never pop open GUI windows on the host desktop without permission.
- **Always branch fresh from `origin/main`** after every merge and delete merged branches immediately.
