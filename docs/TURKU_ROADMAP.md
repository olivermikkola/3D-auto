# Turku roadmap after v0.8.0

## Outcome

A recognizable Turku in the game's own visual style: real streets, terrain, river, parks and building footprints, with carefully modelled public landmarks. Ylioppilaskylä and Kupittaa are the first district comparison areas; a connected district loop provides a meaningful driving and walking test.

Low-poly is deliberate. An invented grid in place of real geography is not.

## Baseline and work isolation

v0.8.0 is frozen at `36b373e08dd2bde5b2b78cd61ea748171d78f173`. Its ongoing playtest uses a separate source/binary copy. Development happens on isolated branches/worktrees; playtest saves and the running game are not changed by development.

The current Turku map is a prototype grid. The new geographic map is not yet implemented. Plan entries below are proposed PR titles, not assigned GitHub numbers or completed work.

## PR-sized sequence

### 1. Real city data foundation

- Extend the existing importer with explicit per-city geographic bounds and origin.
- Acquire and validate MML's actual 2 m elevation GeoTIFFs, retaining source resolution, coordinate system, attribution and provenance.
- Import actual OSM roads, building footprints, land cover, paths and water.
- Reject missing terrain or uncovered/no-data samples instead of substituting flat sea-level ground.
- Keep 2 m source accuracy separate from runtime mesh resolution/LOD; profile before scaling.

**Evidence:** actual source hashes/metadata, input-validation negatives, generated-map checks and legacy regression tests.

### 2. Shared traffic and movement correctness

The new playtest findings can move this ahead of map integration:
- Preserve OSM one-way/roundabout direction and carriageway/lane semantics end to end.
- Reproduce wrong-way traffic, unsafe police spawning and extreme following distances.
- Reproduce bus/post impacts, airborne buses and unintended car explosions.
- Repair pedestrian path/ground behavior and centre-bridge access without weakening physics tests.
- Fix Finnish street-name glyphs; measure Pirilä jitter/frame issues before assuming their cause.

**Evidence:** defect reproduction → focused failing test → repair → same behavior rerun, plus affected-map regressions. See `PLAYTEST_V0.8.0.md` for observations; not every issue has a diagnosed cause yet.

### 3. Real Turku base and the district loop

- Replace the prototype grid with the real imported network and terrain.
- Ground Ylioppilaskylä courtyard/block layout, Nummenranta riverside, university hill and Kupittaa park/campus footprints in source data.
- Define a public district loop through actual connected roads; no assumed personal commute.
- Remove incompatible prototype geometry rather than overlay duplicate rivers and bridges.

**Evidence:** comparable district aerial views, ground-level route traversal, no broken junctions/water respawns/invisible walls, explicit Turku simulation coverage.

### 4. Streaming and Raisio–Turku continuity

- Verify tile residency with real player movement; counting road meshes alone is insufficient.
- Keep terrain/collision continuous through tile boundaries and measure sustained performance.
- Join cities using surveyed municipal crossings and shared coordinates.
- Preserve actual vehicle identity, speed, heading, health, inventory and wanted state in exercised two-way transfers.
- Verify the wooden pedestrian crossing as a walkable, car-excluding route.

**Evidence:** sustained multi-tile route, residency observations and both-direction transition state checks.

### 5. District character and landmarks

- Improve building categories, roofs, courtyard gaps, park hills and vegetation.
- Assess MML roof/building/laser data separately: a ground elevation raster is not a roof model.
- Place actual castle, bridges, Föri and boats against imported geography and water levels.
- Treat visual references as inspiration, not downloadable Google models/assets.

**Evidence:** inspected aerial/detail/street-level images, instantiated scene objects, collision/walkability checks and local user feedback.

### 6. Gameplay and a truthful release gate

- Integrate new playtest notes as focused fixes, prioritizing playability over content.
- Exercise boat mission progression and pursuit only once the real waterways are usable.
- Require screenshots and behavior evidence in PR/release claims; correct stale documentation.
- Judge 1.0 by actual player outcomes and reusable engine behavior, not PR count.

Public publication, merge and release are distinct decisions; no new release is authorized by this plan.

## Current first-slice evidence

- Actual MML 2 m tile L3324B downloaded and checked: 3000×3000 pixels, 2×2 m pixel scale, EPSG:3067. Samples returned real ground heights for the two comparison districts and Yliopistonmäki.
- Actual 2 m source tiles cover the district anchors and map-box corners; a denser 17×17 sweep found a missing north-east source tile. Added L3413C to close that coverage gap; full generation/no-data behavior still needs exercise.
- Importer validation development is in progress. Focused checks for configuration, missing source files, wrong resolution/CRS, outside coverage and no-data are passing locally.
- OSM acquisition is incomplete: successful raw tiles are retained, while some Overpass requests return HTTP 504. No partial dataset is presented as complete Turku.
- Shared gameplay findings are recorded; an independent Gemini discovery review is running. No repaired behavior is claimed yet.

## Sources and licenses

- OpenStreetMap: ODbL, `https://www.openstreetmap.org/copyright`.
- MML elevation model 2 m: CC BY 4.0, `https://www.maanmittauslaitos.fi/en/maps-and-spatial-data/datasets-and-interfaces/product-descriptions/elevation-model-2-m`.
- Turku AMK public campus reference: `https://www.turkuamk.fi/en/about-us/campuses/kupittaa-campus/`.

Code, map data and curated game content retain separate license attribution. No private reference screenshots or personal-location facts belong in published source.
