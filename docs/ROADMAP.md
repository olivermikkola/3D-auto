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

## Where things stand (October 2026)

- The release line is **Aurajoki** (`aurajoki-v0.9.x`) with Raisio and Turku. Brands in the
  game are Finnish parodies (Häsburger, Pöli, Puskuri, Vicklund, Verkkari Stadion, Lumis).
- Turku at real size: OSM roads and buildings on 2 m MML LiDAR terrain; the Aurajoki with its
  bridges (decks level with their streets and arched over what passes under), boats and the
  Föri; covered tunnels (Myllyahde, Helsinginkatu); hand-made slices for Kauppatori, Vanha
  Suurtori and Tuomiokirkko, Kakolanmäki, Portsa, Turun linna, the harbour, Kupittaa and
  Yliopistonmäki. Raisio is about 8 × 8 km on the 10 m elevation model, one corridor away.
- **Missions on templates** (`docs/MISSION_TEMPLATES.md`): seven missions cast their places
  from the map's real points of interest by seed, so each run is another version (a real
  Hesburger, banks, garages, landmarks, pubs, marinas).
- **Free roam**: traffic of cars, vans, taxis and sports cars, Föli buses, pedestrians, police pursuits with roadblocks from three
  stars and a helicopter from four, Lumis cash vans to rob, street racers at night, street lamps that knock over, weather (clear, cloudy, rain,
  storm; snow in winter) with wet and snowy roads, and a city radio that answers what you do.
- **Side jobs and finding your way**: a GPS line on the radar to whatever you're after, a
  waypoint you set on the map (M), a radar that turns with you, taxi fares, ambulance calls,
  vigilante shifts, fires, Pöli bus routes and a police convoy at four stars. The jobs pick
  their places like the missions do (real hotels, pitches, bars, hospitals), by the hour.
- **Turku's look from open data**: roof and ground colours from the city's 2022 aerial photo,
  measured heights and LOD2 roofs from its 3D city model, procedural facades (old town,
  flats, glass, new) with lit windows at night, painted crossings, traffic lights that cycle,
  Föli shelters at the real stops, and low/medium/high quality presets in settings.
- **Phone**: the browser build (GitHub Pages) plays with touch controls, saves and sound.
- **Sweeps that drive the whole map** keep it playable: traffic (`DRIVE_SWEEP`), buses,
  pedestrians (`PED_SWEEP`), the player's car (`PLAYER_SWEEP`), bridges (`BRIDGE_AUDIT`), and
  landmark renders checked by pixel in CI.
- **Performance:** `PROFILE=1` prints fps, Lua, physics and draw time and the worst frame;
  `PROFILE_DRIVE=1` drives a robot round town. Turku headless peaks at about 540 MB RSS (it
  was 1.2 GB; vertices are 20 bytes now). On the Beelink's Radeon 890M the GPU takes 2-4 ms a
  frame at 1080p: it is not the limit.

## Learned in October 2026

- Lua's generational collector is worse here, not better: the heap drops from 215 to 84 MB,
  but a full collection stopped one tick for 210 ms. The default incremental one had one
  32 ms tick in two minutes of driving Turku. Hot code should still not make a table per
  item: a route search with one did run into a 104 ms collection step.
- The robot drivers (`test/robot.lua`) cut corners: at Hämeensilta's 87-degree slip road
  they meet the railing that keeps cars off a 7 m drop. Slowed down, it's drivable. Tests of
  a job tow the robot on after 12 s stuck, and print where.

## Done from the old list

- Every landmark has a render check in CI (`tools/test_landmark_renders.py`).
- Vertices packed to 20 bytes; memory roughly halved.
- The Gemini review's items: each vehicle class has its own pull and top speed (bus ~75 km/h),
  spot lights fade softly to their edge, the clock is 48 minutes a day, the help box shows on
  the first run only, and losing the cops takes time out of sight scaled by stars.
- The story catalogue and scorer (`lib/story.lua`, `story/radio.lua`).

## Done 27-28 October 2026

- Waves 0 and 1: these docs, postcard renders before and after (`tools/postcards.py`), the
  phone's low preset, mall and works facades, gulls and bells, parody adverts, the CI flakes.
- Wave 2, buildings: cornices and floor lines, shop signs from OSM `shop=*`, balconies. Not yet:
  LOD2 roofs beyond the old town, Ylioppilaskylä (both wait for the playtest).
- Wave 3, streets: stop lines and edge lines, worn and patched asphalt, setts on the old lanes,
  cycle paths you can see (painted bicycles, a line down the segregated ones, the squares of cycle
  crossings). Not yet: lane arrows (the importer doesn't export `turn:lanes`).
- Wave 4, life: cyclists, people at the shelters boarding the buses, market day on Kauppatori,
  terraces along the river, crowds outside the bars at night (every night: the game has no days
  of the week).
- Wave 6 begun before the playtest: businesses to buy (`systems/businesses.lua`) and a story
  through the missions (`story/arc.lua`), both first drafts for the playtest to tune.
- Wave 7 begun: big meshes go to the GPU as they're made and the CPU copy is dropped (the browser's
  peak on Turku 583 -> 353 MB); building walls stream in by 300 m chunk near the player; in the
  browser the collector keeps up while the city loads. The browser's number is CI's `web-check`
  artifact (`wasm_peak_bytes`), and `tools/web_check.py` gives the same number locally.
- The playtest itself: `docs/PLAYTEST.md`.

## Next (agreed with Oliver, 27 October 2026)

The game has more features than reasons to play them, and Turku is recognisable from above
but not yet from the street. So: make it look like Turku where you stand, make it feel alive,
then give the player something to work towards. In order:

0. **Groundwork.** These docs up to date, and **postcards**: fixed camera spots rendered
   before and after every visual PR, so a change is judged by looking. The spots: Ylioppilaskylä,
   the Aurajoki riverside, Kauppatori, Kakolanmäki, the Logomo railway yard, Puolalanmäki
   (the art museum and Puolalanpuisto) and Kupittaa (campus and park).
1. **Small wins.** The phone picks the low preset by itself (`engine.platform()`); pedestrians
   stop scanning every entity for `engine.nearest`; windows on malls and warehouses; the CI
   tests that flake on slow runners; sounds of the place (gulls by the river and the harbour,
   the cathedral's bells on the hour); Turku parody adverts.
2. **Buildings.** Cornices and floor lines, shop fronts from OSM `shop=*` (window, light,
   parody sign), balconies on the flats, LOD2 roofs beyond the old town, Ylioppilaskylä's
   unusual shapes.
3. **Streets.** Lane markings, stop lines and arrows; worn and patched asphalt; cobbles in the
   old town; cycle paths you can see.
4. **Life.** Cyclists, people who wait at the shelters and board the bus, stalls and crowds on
   Kauppatori by day, terraces along the river in summer, Aurakatu busy on weekend nights.
5. **Playtest** with Oliver, then tune the jobs (numbers at the top of `systems/fares.lua`,
   `ambulance.lua`, `vigilante.lua`, `fire.lua`).
6. **A reason to play.** Businesses to buy (a grill, a kiosk, a taxi firm) that pay while you
   play and are places to save, and a story that ties the eleven missions together through the
   radio and its characters.
7. **Phone for real.** Load Turku in pieces around the player instead of all 52,000 entities
   at once (the browser build is about 530 MB). The Raisio-Turku crossing waits for this.

### Later

- Helsinki, then 1:1 Manhattan.
- A small classifier behind the story scorer, only once the catalogue needs it.

## Data sources

| What | Where | Notes |
|---|---|---|
| Roads, buildings, land use | OpenStreetMap via Overpass | ODbL. Fetch in tiles (`osm_import.py --fetch`); public servers time out on whole towns. |
| Terrain | Maanmittauslaitos elevation model, 10 m (2 m available) | CC BY 4.0. Key in `~/.config/3d-auto/mml-key`. |
| Building heights and roofs | Turku's 3D city model (LOD1 everywhere, LOD2 in the centre) | CC BY 4.0. Used. |
| Roof and ground colour | Turku's 2022 true orthophoto (city WMS) | CC BY 4.0. Used. |
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
