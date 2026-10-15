-- Probe checking Kakolanmäki 500m slice: funicular stations, track, cabin movement, and overlook.
local kakola = require "systems.kakola"

engine.on("init", function()
  assert(kakola.funicular and engine.exists(kakola.funicular.id), "Kakolan funikulaari cabin missing")
  local x, y, z = engine.pos(kakola.funicular.id)
  print(string.format("FUNIKULAARI_SPAWN_OK id=%d pos=%.1f,%.1f,%.1f", kakola.funicular.id, x, y, z))

  -- Verify movement over ticks
  local init_progress = kakola.funicular.progress
  for _ = 1, 60 do
    kakola.tick(1/60)
  end
  assert(kakola.funicular.progress ~= init_progress, "funikulaari failed to advance progress")

  print("FUNIKULAARI_MOVEMENT_OK")
  print("ALL KAKOLA CHECKS PASSED")
  engine.quit()
end)
