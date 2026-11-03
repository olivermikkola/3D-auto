# Underground and indoors: a layer under Turku

Oliver's idea (3 November 2026): build Hansa inside, joined underground to Louhi; "lowkey just a
layer, forget the ground floor". This is the research for it: what's really down there, why the
game can't build it today, and a plan in pieces. Nothing here is built yet.

## What's really there (OpenStreetMap, the importer's cache)

All in the game's metres (x east, z south, 0, 0 at 60.4515 N, 22.27 E).

| What | Where | OSM |
|---|---|---|
| Louhi's car entrance (portal, #246) | -511, -369, Ajurinkatu | node 26706967, maxheight 2.2 (Aimo Park says 2.4) |
| Louhi's tunnel | -511, -369 → -302, -75, ~360 m under Puolalanmäki | way 1193257263, layer -1 |
| Louhi, the hall | round -301, -57, level -2, **608 places** | way 1193258578, relation 11144133 |
| Toriparkki, next to it | round -154, -74, level -2, **620 places** | way 1207799675 |
| Louhi's foot exits | -263, -56 (Kauppatori) and -367, 24 (toward Hansa) | nodes 302797725, 5448929425; footway tunnels layer -1 |
| Hansakortteli | round -312, 115 | way 673836991 (shop=mall) |
| Hansa inside, level -1 | corridors round -266, 49; shops Partioaitta, Stadium | ways 524925062, 1275345953, node 6927766765 |
| Hansa's lifts | -330, 57 and -327, 55, levels -1 to 3 | ways 1276168764/5 |
| Hansa's door on Aurakatu | -241, 27 | node 5107508754 "Hansa Aurakatu 12a" |

So the real route already exists: Ajurinkatu portal → 360 m of tunnel → Louhi → on foot up into
Kauppatori or across into Hansa's lower floor → its lifts → out on Aurakatu. (Sources: OSM;
[Aimo Park, Louhi](https://aimopark.fi/en/cities/turku/louhi): Läntinen Pitkäkatu 12 b;
[Hansa (Wikipedia)](https://en.wikipedia.org/wiki/Hansa_(shopping_centre)): opened 1988, ~140
shops, next to Kauppatori. Neither publishes floor plans: the indoor detail is OSM's.)

## Why it can't be built today

`src/physics.rs` (2b, terrain contacts): any corner of a moving box **below the ground's
surface is pushed up onto it**, wherever it is. A car 12 m down in Louhi, under a hill, would be
thrown 30 m up. And the ground is one heightfield drawn everywhere: no holes, so no way down.

## The plan: layers

Every entity gets a **layer**: 0 is the surface (everything today), 1 is under and inside. The
engine draws only the layer the camera is in, and bodies only touch bodies of their own layer;
the ground (terrain) is layer 0 only. A **portal** (Louhi's mouth, Hansa's doors) is a trigger:
cross it and the player (and their car) switch layer, with a short fade, the sky and fog swapped
for the indoors'.

What that buys:
- Louhi and Hansa are built where they really are, at their real depth, under the real streets.
  The minimap, GPS and distances still make sense.
- Nothing up top is drawn while you're down there: the surface's ~1,000 draws drop out (phones).
- No holes cut in the ground, no camera clipping through it: the switch is the fade.
- Interiors are only built when you go in (and dropped when you leave), so they cost nothing up top.

The engine change is small: `layer: u8` on `Entity` (`src/engine.rs`), one skip in the render
cull (`src/render.rs`, "Cull, then split") and the shadow pass, one in the physics pair and
terrain loops (`src/physics.rs`), `engine.set_layer(id, n)` and `engine.view_layer(n)` in
`src/script.rs`. Lights: 16 at a time (`MAX_LIGHTS`) is too few for a car park lit end to end,
so the indoors light themselves (emissive ceiling strips) and the nearest few lamps are lights.

Gameplay to decide (Oliver):
- **Cops.** Follow you down (they switch layer at the portal too: a chase through the car park)
  or lose you at the mouth (like hiding in Logomo, #247)? Suggest: they follow at 3 stars and up.
- **Traffic.** A few parked cars, one or two driving round the levels looking for a space; no
  through traffic.

## In pieces (each a PR, each tested)

1. **Layers in the engine** (Rust): the field, render and physics skips, the two Lua calls;
   a test that a body in layer 1 under a hill isn't pushed up, and layer 1 isn't drawn from 0.
2. **Louhi drivable**: #246's portal opens; the 360 m tunnel (2.4 m high, lit, its bends from
   OSM) down to the hall at level -2: 608 places in rows, pillars, parked cars, ramps; out the
   same way. Test: drive in, park, drive out; cops per the decision above.
3. **On foot up into town**: Louhi's foot exits, stairs up to Kauppatori (-263, -56).
   Built (November 2026): through the stair house's door, see ROADMAP.
4. **Hansa's lower floor**: from Louhi's Hansa exit along OSM's level -1 corridors, its shops
   with their names, the lifts, up and out the Aurakatu door. More floors later if it's fun.
   Built (November 2026), see ROADMAP; the corridors are the game's, the lifts don't go.
5. **Toriparkki**, joined to Louhi.

Piece 1 is the only risky one (engine); 2 is the most fun on its own. Roughly a day each for
1 and 2, less for 3-5.

## Considered and not done

- **Holes in the ground** where the ramps go down: needs holes in both the drawn heightfield and
  its collision, and underground bodies away from the holes would still be pushed up. Layers
  are simpler and do more.
- **Interiors somewhere else** (a pocket off the map you're moved to): works without engine
  change, but the minimap and GPS lie while you're in, and Louhi couldn't join Hansa in place.
