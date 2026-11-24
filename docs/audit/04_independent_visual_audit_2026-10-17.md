# Independent audit — 2026-10-17 (Jack, GLM; not Forge, not Claude)

Scope: fresh audit of main @ 5415e06 (merge of #114), requested by Oliver.
Method: repo's own headless suites re-run locally, landmark render harness re-run
under xvfb, plus fresh custom frames (night captures) inspected visually — not
just pixel-checked. Prior KAT-Coder reports (01–03, 2026-10-15) are treated as
input, not acceptance.

## Verified working
- CI green on main through #114 (includes multi-seed soak + landmark pixel checks).
- Local autoplay smoke: 4/4 (manhattan, harbor, raisio, turku @ seed 1337).
- Local reliability: 4/4 (turku, raisio @ seeds 1337, 0).
- Landmark renders: all 13 shots pass black/colour checks locally.
- Night square frame: no white blowouts from overlapping lamps/headlights —
  the clamp concern from the 10-16 plan is closed in practice.
- 2026-10-16 plan wave items are in main: per-class speeds (test passes),
  wanted escape/give-up timers (wanted.lua), small coloured explosions (fx.lua),
  worktrees archived, PR queue empty.
- Web wasm builds today: web/dist produced end-to-end via build.sh
  (auto.wasm 15.9 MB). wasi-sdk present at ~/tools/wasi-sdk-34.0.

## Visual weaknesses (judged from frames, fresh on this date)
1. Water is the weakest element. Föri frame ~4/10: flat uncoloured plane, no
   waterline/wake, ferry reads as pasted on top or sunk; far-bank buildings
   meet the water with no quay. Night riverside ~5/10: zero reflections.
2. Dark/unreadable faces: Raisio has a pure-black blob on the parking lot
   east of the big roof. CORRECTION (same day, after Oliver's push-back):
   this is real-world content, not a glitch — it is Raision Lasikuutio, the
   dark glass-cube building at Raisiontori 1a (Mehiläinen), placed by the
   importer (raisio.lua:153 hospital = {at = {945, -1741}}; live OSM way
   "Raision Lasikuutio" at 60.48610, 22.16744; Google satellite shows the
   dark-roofed cube with the parking lot south/west). It stays fixed across
   HOUR=10/14/18, so it is geometry, not a sun shadow. The real ticket is
   therefore legibility, not existence: render the glass cube dark-but-
   readable (dark blue-grey with window banding/sheen) instead of pure
   black. Remaining true black-face cases: Kauppatori's near-black gabled
   building; Portsa shadow faces going near black.
3. Landmark silhouettes short of real: cathedral tower far too squat (real
   ~97 m), market hall a plain gray slab (no brick), Portsa houses flat-roofed
   slabs rather than pitched wooden rows, Veritas missing goalposts and
   floodlights.
4. Scale drift in Raisio: arterial reads ~6–8 lanes; background towers too
   tall for a small-town centre.
5. Life density: landmark frames at 14:00 show zero traffic/peds in view.
6. Night street level: roads near-invisible away from lamp pools (square is
   fine at ~7/10; open street ~3/10). Lamp coverage sparse.

## Structural gaps
- No web/wasm job in CI. The browser build regresses invisibly even though
  "playable on a phone" is a stated goal. Add a wasm build + smoke job.
- auto.wasm is 15.9 MB uncompressed — slow first load on a phone. Strip/opt
  belongs in the phone wave.

## Recommended next wave (PR-sized, each with a visible proof shot)
1. Water pass: boat draft/waterline, fake reflection streaks under lamps and
   lit windows, quay strip on far banks. (Highest visual ROI.)
2. Prefab lifts: brick look for the market hall, pitched wooden rows for
   Portsa, cathedral tower to scale, floodlights + goalposts at Veritas.
3. Black-face sweep + widen the render black-check outside the centre band.
4. CI: wasm build + browser smoke (geckodriver is on PATH).
5. Ambient density floor near landmark cameras.
6. Lamp density pass for Kauppatori/central streets at night.
