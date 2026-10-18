# Mission templates: one story, played in many places

Status: 2026-10-18. Step 1 (POIs in the map data) and step 2 (`lib/template.lua`) are done.

## The idea

A mission today names its places by hand, per map: `places.cargo_drop =
{junction = "Aninkaistenkatu / Linnankatu"}` in `maps/turku.lua`, or a table of
coordinates for Turku and another for Raisio (`11_hesburger_express.lua`). A
new map gets none of these missions until someone writes its places.

Instead a mission describes **roles**, and each role is a **condition on real
map data** (OpenStreetMap tags plus game facts):

```
Story "church money":
  A = pickup:  amenity=place_of_worship, under 2 km from the player
  B = hideout: leisure=pitch, 3-6 km from A
  C = drop:    shop=supermarket, across the river from B
  chase:       the road route A -> B is at least 2 km and uses a main road
```

The game picks one real place for each role. With ~10 candidates per role,
three roles give ~1000 versions of the same story, and any map the importer
can build (Turku, Raisio, the next city) gets the story for free. Names come
from OSM, so the text says "Pick up the bag at Mikaelinkirkko".

## Decisions

- **No model at run time.** A choice has 5-7 inputs (distance, route length,
  recently used, time of day, landmark or not, police nearby...). A weighted
  score in Lua does it: no megabytes, deterministic, and when it picks badly
  you can see which weight did it. The worst case is a worse place, never a
  place that isn't there, because only real candidates are ever scored.
- **Variety comes from the seed.** Valid candidates are picked by weighted
  random choice from the mission seed. Same seed, same mission; new seed, new
  mission. Headless tests stay reproducible.
- **A model only if tags can't say it.** If we later want "a quiet spot" or
  "somewhere spooky", a small encoder can score POIs once, at import time, and
  the score is stored in the map file. Never in the game loop, never in the
  web build.
- **Hard conditions always include playability:** reachable by road, not in
  water or a tunnel, a stopping point on a street (`m:on_street`).

## Steps (one PR each)

1. **POIs in the map data.** `tools/osm_import.py <area> --only-pois` fetches
   named points of interest (shops, amenities, leisure, tourism, historic,
   with their tags) and splices a `pois` list into `<area>_osm.lua` without
   touching anything else. `lib/pois.lua` answers `pois.find{shop =
   "supermarket", from = {x, z}, min_dist = 5000}`. Each POI carries its
   nearest road junction, so "reachable" is a lookup.
2. **Template format.** Roles, conditions between roles (distance, river
   side, route length for chases), a weighted score, and a seeded pick.
   Missing roles mean the mission doesn't start on that map (like
   `city.has` today). Conditions need a way to give: Turku's map is about
   6 x 6 km, so "a supermarket over 5 km away" finds none there from the
   start lot (Raisio: one). A role says how far a condition may be relaxed
   ("5 km, or as far as there is").
   Done in `lib/template.lua`: `template.cast{seed, from, roles}` with tag
   conditions, straight-line and by-road distances between roles (Dijkstra
   over the junctions, one-way streets the right way; a place cars can't
   reach is never picked), relax steps, weights, places to avoid, and no
   place in two roles. Not yet: "across the river" (needs the water as a
   line to test against).
3. **Port 2-3 missions** (Häsburger Express first: `amenity=fast_food,
   brand=Hesburger`) and add a seed test: each template at N seeds on Turku
   and Raisio, reporting how many versions have every role filled, a
   drivable route and a reachable goal. That number is the measure of
   "infinite missions": versions that are really playable, per map.

Later: a "director" that, a few times a minute, picks from a closed list of
events (cops block a bridge, a taxi fare calls) from game state. Same rule:
it only ever chooses among things that exist.

## What step 1 found (POI_TEST=1, from the start lot)

| | Turku | Raisio |
|---|---|---|
| points of interest | 3219 | 1211 |
| churches | 34 | 9 |
| Hesburgers (restaurants) | 11 | 5 |
| supermarkets 1-3 km away | 8 | 0 |
| supermarkets over 5 km away | 0 | 1 |
| basketball courts | 14 | 8 |

Step 2, the example story above (`TEMPLATE_TEST=1`, seeds 1-50, from the
start lot): Turku 50/50 seeds cast into 50 different versions, Raisio
50/50 into 50; no relax step was needed. Seed 1 in Turku: Turun synagoga ->
Kuhilaspuiston kenttä -> Lidl, 5.4 km by road. 100 casts take 0.35 s.

Names alone would mislead: Turku has charging stations called "Helen
Hesburger ...". Tags tell them apart (`amenity=fast_food`).

## Data notes

- Many shops and cafés are OSM *nodes*, not buildings; the main import only
  fetches ways, so POIs are a separate small query (`<area>_pois.json`).
- OSM data is (c) OpenStreetMap contributors, ODbL, like the rest of the map.
