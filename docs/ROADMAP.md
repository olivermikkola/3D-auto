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

## Where things stand (v0.6.0)

- Raisio covers about 8 × 8 km: 2,936 junctions and 13,500 buildings from OpenStreetMap.
  Heights come from Maanmittauslaitos' 10 m elevation model.
- Roads are graded into the terrain and drive smoothly. Bridges are solid decks. Tunnels exist
  (Raisio 2030).
- Each road side is classified: pavement, grass verge before a separate path, median, or none.
  Kerbs are physical: the engine raises pavements 12 cm.
- Landmarks are placed by hand from Oliver's photos: church, police station, Mylly, the factory,
  the centre.
- Three Raisios (today, 2030, 1980) plus Manhattan and Harbor. Switch with **Esc → CITY**.
- Raisio loads in about 8.4 s, with everything built at load and kept in memory.

## Next, in order

### 1. Map edges and borders (next PR)

Today the map ends at a rectangle with an invisible wall, except where the sea stops you.

- **Raisio–Turku border as a natural barrier.** Import the municipal border from OpenStreetMap.
  Use the Raisio and Turku municipality boundaries (`admin_level=8`); don't hard-code them.
  Along the border, build a natural barrier from the river, dense trees, and fences by the
  motorway.
- **Crossings** are where roads cross the border, found automatically. Oliver's sketch also marks
  a pretty wooden footbridge as a walking-only crossing; footbridges are already supported.
  First version: crossings are closed ("end of the map") and the barrier is solid.
- **Off-limits areas from tags.** `landuse=military` becomes a fenced zone with a gate and a boom
  barrier. Pansion varuskunta, the navy base on Pansionnokka, is the first one. Crossing the gate
  gives you a wanted level.

### 2. Polish what the kerbs PR left

- **Rounded kerb corners at junctions.** Pavements are cut where a side street crosses them,
  which leaves a small gap in each corner. The physics raises those corners anyway, so people
  can float up to 12 cm there. Draw the corner (an arc between the two pavements) and make the
  physics match.
- **Traffic islands.** About 190 `area:highway` and island features in Raisio aren't imported
  yet. Raise them like medians.
- **Road widths from `lanes=*`.** Widths are fixed per class today: 9–13 m, about 2 m wider than
  the real roads, so paths had to be clipped where they ran under a road. Real widths would fix
  that, and allow lane markings.
- **Lamps from `lit=yes/no`.** Today lamps stand along every road at a fixed spacing.
- **Street trees** along boulevards and medians.

### 3. Buildings that look like Finland

- **Flats:** generate glazed balconies (`style = "balconies"` exists, but only three hand-placed
  buildings use it) on the sun or yard side, and vary panel colours.
- **Shops:** dark, glassy ground floors for `building=retail/commercial`, decided by tags, not at
  random (today one shop in three gets glass).
- Roof shapes from `roof:shape`.
- Later: real building heights and roof forms from MML laser-scan data (open data, CC BY 4.0).

### 4. Gameplay

- **Pansio:** at 5 stars, a military response comes out of the base: a heavy Sisu Pasi that
  shoves cars aside, built on the police AI. A base break-in where you steal a Pasi or a boat and
  escape into the archipelago.
- Föli buses on real routes, and a pizza delivery job.
- Feedback from Oliver's Raisio friends playing v0.6.0.

### 5. Engine: load the city in pieces (before Turku)

This is the one big engine step between Raisio and a city other people would play. Today the
whole town is built at load and kept in memory. That's fine for 64 km² (about 8 s), not for
Turku or Helsinki.

- Build and load **chunks around the player**, and unload far ones. Road pieces are already baked
  per 300 m square (`chunked()` in roadnet.lua), which is a start.
- Keep the deterministic headless tests working; the CI suite plays every map.

### 6. Many cities, and moving between them

- **Per-city config in the importer:** each country has its own defaults (Finnish street
  defaults vs American ones, which roads get pavements, building heights), so a new city is a
  config entry, not new code.
- **A city is its municipal area.** Neighbouring cities join at crossings, the roads over the
  border. Driving through a crossing loads the neighbouring city and puts you at the matching
  crossing on its side, keeping your car, speed and wanted level. At first with a short loading
  pause; seamless once chunk loading (step 5) exists.
- First real attempt: Turku, then Raisio ↔ Turku crossings.

## Data sources

| What | Where | Notes |
|---|---|---|
| Roads, buildings, land use | OpenStreetMap via Overpass | ODbL. Fetch in tiles (`osm_import.py --fetch`); public servers time out on whole towns. |
| Terrain | Maanmittauslaitos elevation model, 10 m (2 m available) | CC BY 4.0. Key in `~/.config/3d-auto/mml-key`. |
| Building heights and roofs | MML laser scanning | Open, CC BY 4.0. Not used yet. |
| Ground colour | MML orthophotos | Open. Not used yet. |
| Helsinki | City of Helsinki's open 3D city model | Not used yet. |
| Manhattan | NYC Open Data building footprints with heights | Not used yet. |
| Google Earth 3D | — | **Off limits:** its terms don't allow pulling its models into a game. |

## How to work on this repo (lessons learned)

- **Test like CI before every push.** Run the full suite:
  `python3 tools/headless_tests.py --output <dir> --jobs 3 --soak` (all maps, all seeds), plus
  `--maps starter`, `--maps raisio2030` and `--maps raisio1980` with `--seeds 1337`, plus
  `cargo fmt --check`, `cargo clippy --release -- -D warnings`, `cargo test --release`, and
  `python3 -m unittest discover -s tools -p "test_*.py"`. Police and pedestrian behaviour depends
  on the seed, and CI's machines differ: a test that passes "just barely" locally will fail in CI.
- **Check visuals headlessly.** Dump what you build and draw it top-down with PIL. Don't open game
  windows (`--screenshot`) on Oliver's laptop without asking.
- **Measure load time** with `/usr/bin/time env MAP=raisio target/release/auto game --headless 1`
  and compare against main. Lua is plain 5.4, not LuaJIT. Avoid per-piece spatial searches:
  gather neighbours once per road (see `neighbours()` in roadnet.lua).
- **Junction names like `n1446` are generated** and change whenever the map data is re-fetched.
  Hand-written maps must name junctions by street names, or look them up by position (see
  `raisio2030.lua`).
- **Map coordinates stay put:** the importer's `origin` is fixed, so the area can grow without
  moving hand-placed things. A map's middle is `center`, not 0, 0.
- **Road surface format for the engine:** 11 numbers per piece (see "Terrain" in the README).
  Side 1 is toward (dz, -dx).
- **Pedestrians walk 1.5 m outside the asphalt** (`width/2 + SIDEWALK/2`). Keep lamps and other
  solid things off that line: lamps there once failed the soak test.
- **Starting the game with `MAP=...`** is fine; a city picked in the menu still wins on restart.
- **The user merges fast.** Start a new branch from `origin/main` after each merge, and never push
  to a merged PR's branch.
- **Commit identity:** the laptop has no git user configured. Pass one with `git -c user.name=...
  -c user.email=... commit`; don't change the global config.
