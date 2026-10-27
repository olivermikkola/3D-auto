# v0.8.0 playtest findings

Source: user-provided gameplay notes captured 2026-10-14. These are observations, not diagnosed causes or repaired behaviors. Relevant shared systems need checks across all maps; do not claim every report is already reproduced elsewhere.

## Findings

1. Raisio centre pedestrian bridge cannot be climbed and looks clunky.
2. Finnish `ä` characters in street names render incorrectly. Check `ö` and other supported glyphs too rather than replacing real names with ASCII.
3. Jitter/frame problems around Pirilä (original note: `Piril* mäki nykii ja framet`; exact location/mechanism still needs reproduction).
4. Police appear out of nowhere, collide head-on, or follow extremely close. Reproduce spawn clearance, road placement and pursuit behavior separately.
5. Bus lag around Pirilä. Distinguish physics jitter, render/frame pacing and streamed-input latency before selecting a fix.
6. Föli bus becomes airborne.
7. On a four-lane road with two lanes per direction near the Raisio factory, oncoming AI appears in the left lane of the player's carriageway; an AI bus becomes airborne after hitting a pole.

8. Roundabouts behave incorrectly; exact geometry, routing and priority failures still need reproduction.
9. Pedestrian AI wanders unpredictably / is “all over the place.” Check paths, crossings, ground contact and road clearance.
10. AI traffic cars sometimes explode without an obvious cause. Reportedly less frequent than before, but still present. Do not assume random explosions share one cause with roundabouts or pedestrians; capture contact/damage events.

11. Coordinator observed a real cross-city runtime failure during the live v0.8.0 play session: `[lua:init] main.lua:66: attempt to call a nil value (field 'set_parent')` after loading Turku with vehicle transfer. Source calls an unavailable engine API. Preserve that observed error; transition completion/state preservation is not verified and needs its own regression.

## Priority and acceptance

- **Safety/playability:** lane direction and police spawn clearance first. Tests must preserve real road directionality and stop accepting correct-looking centreline geometry as lane behavior.
- **Vehicle dynamics:** reproduce bus/post impact and slope behavior without weakening collision tests or teleporting the bus through obstacles.
- **Movement/accessibility:** centre bridge approach and walkable deck continuity; foot-only clearance remains intentional.
- **Presentation/performance:** proper Unicode glyphs and measured frame pacing at a reproducible location.

For each repair: reproduce with exact map/seed/location, add a focused failing test, implement the root fix, rerun the same behavior, exercise other affected maps and retain fresh visual/input evidence. A registered bus, bridge mesh, police count or success marker is not the relevant acceptance criterion.

Turku development continues in a separate worktree. The frozen v0.8.0 play session is left unchanged so observations remain tied to that baseline. These defects may reprioritize the next PR before map/content expansion.
