-- Debug tools: F3 toggles an overlay, F4 drops a crate tower in front of you.
local G = require "lib.state"
local U = require "lib.util"

local show, frames, fps, t_last = false, 0, 0, 0

engine.on("key", function(k, down)
  if not down then return end
  if k == "f3" then show = not show end
  if k == "f4" then
    local x, y, z = U.player_pos()
    if not x then return end
    local id = G.vehicle or G.player
    local fx, _, fz = engine.forward(id)
    for level = 0, 4 do
      for side = -1, 1 do
        engine.spawn{mesh = "crate", pos = {x + fx * 6 + side * 1.05, 0.5 + level * 1.0 + U.ground(x + fx * 6 + side * 1.05, z + fz * 6), z + fz * 6},
                     size = 1, body = "dynamic", mass = 30, tag = "crate"}
      end
    end
  end
end)

engine.on("frame", function(dt)
  frames = frames + 1
  if engine.time() - t_last >= 1 then
    fps, frames, t_last = frames / (engine.time() - t_last), 0, engine.time()
  end
  if not show then return end
  local st = engine.stats()
  local x, y, z = U.player_pos()
  local lines = {
    string.format("FPS %d   TICK %d", math.floor(fps + 0.5), engine.ticks()),
    string.format("ENTITIES %d  MESHES %d  LIGHTS %d  VOICES %d", st.entities, st.meshes, st.lights, st.voices),
    x and string.format("POS %.1f %.1f %.1f", x, y, z) or "POS -",
    "F4: CRATE TOWER",
  }
  local text = table.concat(lines, "\n")
  local w = engine.screen()
  engine.rect(w / 2 - 200, 160, 400, 82, 0, 0, 0, 0.6)
  engine.text(text, w / 2 - 190, 170, 12, 0.6, 1, 0.6)
end)

print("press F3 for the debug overlay")
