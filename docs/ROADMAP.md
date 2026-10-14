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

## Where things stand (v0.7.0)

- Raisio covers about 8 × 8 km: 2,936 junctions and 13,500 buildings from OpenStreetMap.
  Heights come from Maanmittauslaitos' 10 m elevation model.
- Roads are graded into the terrain and drive smoothly. Bridges are solid decks. Tunnels exist
  (Raisio 2030).
- Dynamic road widths from `lanes=*`, rounded corner fillets at junctions, and raised physical
  traffic islands.
- Real municipal border from OSM relation data with Raisionjoki wooden footbridge (Punttamäenpolun
  silta) and perimeter military barriers around Pansion varuskunta.
- Authentic Finnish architecture: glazed balconies (`style = "balconies"`) on flats ($\ge 3$ floors),
  commercial glass shopfronts, and roof tagging.
- Sisu XA-180 "Pasi" 6x6 APC (13.5 tons) with 5-star military response and Pansio Base Heist mission.
- Föli regional municipal buses navigating real routes, drivable with heavy transit bus handling.
- Engine spatial chunk streaming: 300 m grid meshes dynamically culled beyond active 9x9 tile ring.
- Four Raisios (today, 2030, 1980) plus Manhattan and Harbor. Switch with **Esc → CITY**.

## Next, in order

### 1. Many cities, and moving between them (Turku first)

- **Per-city config in the importer:** each country has its own defaults (Finnish street
  defaults vs American ones, which roads get pavements, building heights), so a new city is a
  config entry, not new code.
- **A city is its municipal area.** Neighbouring cities join at crossings, the roads over the
  border. Driving through a crossing loads the neighbouring city and puts you at the matching
  crossing on its side, keeping your car, speed and wanted level. Seamless with spatial chunk
  streaming.
- First real attempt: Turku, then Raisio ↔ Turku crossings.

### 2. Laser-scan 3D roof shapes & heights

- Import 3D roof structures and laser point clouds from Maanmittauslaitos open data (CC BY 4.0).
- Match roof ridges, pitches, and heights to OSM building polygons.

### 3. More gameplay & jobs

- Pizza delivery job in Raisio center.
- Archipelago speedboats and water police pursuit.
- Tow truck missions.

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
- **Check visuals headlessly:** use `tools/*_render_checks.py` under Xvfb with llvmpipe software GL.
  Never pop open GUI windows on the host desktop without permission.
- **Always branch fresh from `origin/main`** after every merge and delete merged branches immediately.
