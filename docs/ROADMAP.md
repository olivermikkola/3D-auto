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
- **Free roam**: traffic, Föli buses, pedestrians, police pursuits with roadblocks from three
  stars, Lumis cash vans to rob, street lamps that knock over, weather (clear, cloudy, rain,
  storm) with wet roads, and a city radio that answers what you do.
- **Sweeps that drive the whole map** keep it playable: traffic (`DRIVE_SWEEP`), buses,
  pedestrians (`PED_SWEEP`), the player's car (`PLAYER_SWEEP`), bridges (`BRIDGE_AUDIT`), and
  landmark renders checked by pixel in CI.
- **Performance:** `PROFILE=1` prints fps, Lua, physics and draw time and the worst frame;
  `PROFILE_DRIVE=1` drives a robot round town. Turku headless peaks at about 540 MB RSS (it
  was 1.2 GB; vertices are 20 bytes now). The GPU side on real hardware is still unmeasured.

## Done from the old list

- Every landmark has a render check in CI (`tools/test_landmark_renders.py`).
- Vertices packed to 20 bytes; memory roughly halved.
- The Gemini review's items: each vehicle class has its own pull and top speed (bus ~75 km/h),
  spot lights fade softly to their edge, the clock is 48 minutes a day, the help box shows on
  the first run only, and losing the cops takes time out of sight scaled by stars.
- The story catalogue and scorer (`lib/story.lua`, `story/radio.lua`).

## Next

1. **Measure the GPU.** A `PROFILE=1` line from a real machine in Turku, driving. Everything
   CPU-side is a few ms; what the GPU costs at 1.4k draw calls is unknown.
2. **Weather, part two:** wet asphalt that looks wet (the roads are part of the terrain mesh,
   so this is a renderer change), and snow in winter.
3. **More free-roam events**, like the cash van: picked from a closed list by game state,
   never made up (a taxi fare that calls, a street racer at a red light, a convoy at four
   stars).
4. **Templates:** an "across the river" condition (needs the water as a line), and the
   map-specific missions (Pansio heist, Föli, archipelago) where it makes sense.
5. **More Turku:** the next districts, each with a render check.

### Later

- Laser-scan roof shapes and heights (MML, CC BY 4.0) matched to OSM footprints.
- A small classifier behind the story scorer, only once the catalogue needs it.
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
