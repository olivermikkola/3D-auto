# Modding

A mod is a folder in `game/mods/`. Its `init.lua` runs when the game starts, after
`main.lua` has set things up, and again on every hot reload (save a file, or press F5).
Two mods ship as examples:

- `mods/taxi`: a side job with its own car model, sound effect and mission.
- `mods/debug_tools`: an F3 overlay (FPS, entity and light counts, position) and an F4
  crate tower.

## A minimal mod

```
game/mods/hello/init.lua
```
```lua
local U = require "lib.util"          -- the game's own modules are available

engine.on("key", function(k, down)
  if k == "g" and down then
    local x, y, z = U.player_pos()
    engine.spawn{mesh = "sphere", pos = {x, y + 5, z}, size = 1, color = {1, 0.3, 0.3},
                 body = "dynamic", mass = 5, restitution = 0.6}
  end
end)
```

Press G in game. That's the whole mod.

## What a mod can use

- **The engine API:** everything in the README's "Lua API" section, plus `engine.mod_name`.
  File paths (`load_obj`, `load_wav`, `files`, `dirs`) are relative to the mod's own folder,
  so ship assets next to `init.lua`. `engine.save`, `engine.load` and `engine.saves` work on
  the mod's own keys (stored as `mod.<name>.<key>`), so mods can't read or overwrite the
  game's saves or each other's. A mod can hold 16 keys.
- **Its own modules:** `require "jobs"` loads `mods/<name>/jobs.lua`, sandboxed.
- **The game's modules:** `lib.state`, `lib.util`, `lib.input` (`move`, `drive`, `look`,
  `connected`), `lib.city` (named places: `place`, `route`, `has`, `map`; the road graph:
  `road`, `neighbors`, `nodes`, `random_node`, `nearest_node`; and `district(i, j)`, `node`,
  `block_center`. Maps differ, so find things by place name and walk the graph rather than
  using grid positions), `lib.landmarks`,
  `lib.vehicle`, `lib.mission`, `lib.wanted`, `lib.prefabs`, `lib.health` (`damage`,
  `hurt_player`, `ragdoll`), `lib.fx` (`burst`, `tracer`, `flash`, `explosion`), `lib.pickups`
  (`place`), `systems.weapons` (`defs`, add your own), `systems.carnage` (`explode`),
  `systems.police`, `systems.peds`, `lib.daynight`, `lib.settings` (`get`), `lib.menu`
  (`add_page`, `show`), `lib.shop` (`add`, `pay`, `price`; see the shops in `systems/` for
  examples), and so on.
- **The event bus:** the engine's `init`, `tick`, `frame`, `key`, `contact`, `quit` (a good
  time to save), `pad_connected` and `pad_disconnected` events, the game's events
  (`vehicle_enter`, `carjacked`, `ped_down`, `damaged`, `killed`, `gunshot`, `explosion`,
  `player_hurt`, `wasted`, `respawned`, `pickup`, `wanted_changed`, `busted`, `mission_passed`,
  `stunt`, `purchase`, `resprayed`, `car_bought`, `minimap`), and any you `engine.emit`
  yourself. Gamepad buttons arrive as keys named `pad_a`, `pad_start` and so on. While the game
  is paused, keys arrive as `menu_key` instead of `key`, and `frame`'s `dt` is 0.
- **Safe standard library:** `math`, `string`, `table`, `coroutine`, `utf8`, and `os.time`,
  `os.clock` and `os.date`.

## Adding a mission

```lua
require("lib.mission").register{
  title = "Pizza Run", start = {city.place("lot")}, reward = 100,
  run = function(m)
    m:say("Get a car")
    m:wait(function() return m:in_car() end)
    -- Some street corner 150-250 m away, on whatever map is loaded.
    local x, z = city.place("lot")
    local door = m:marker(city.node(city.random_node(x, z, 150, 250)))
    m:timer(45)
    m:wait(function() return m:near(door, 5) end)
  end,
}
```

The mission object has `say`, `wait`, `sleep`, `timer`, `clear_timer`, `marker`, `remove`,
`spawn` (despawned when the mission ends), `near`, `in_car`, `fail`, `wanted` and `stars`.
Returning from `run` passes the mission.

## The sandbox

Mods are other people's code, so they don't get the keys to your computer:

- **Unavailable:** `os.execute`, `io`, `debug`, `package`, `dofile`/`loadfile`, and loading
  bytecode.
- **Paths:** anything given to the engine is relative to the game folder, and `..` or
  absolute paths are refused.
- **Saves:** a mod only sees its own save keys, saves are parsed as data rather than run, and
  keys can't contain path separators.
- **Isolation:** a mod's files only ever run inside its sandbox. Neither the game's `require`
  nor another mod can load them as trusted code.
- **Shared state:** mods share the game's Lua state, so they *can* break the game (replace a
  game function, emit nonsense events). They just can't reach outside it.

`game/test/sandbox_probe/` is a deliberately hostile mod that tries each of these escapes;
CI fails if any of them works. If you find another one, please add it there.

Errors in a mod are shown on screen with a traceback and don't stop other mods or the game.
