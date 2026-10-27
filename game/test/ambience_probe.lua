-- AMBIENCE_TEST=1 MAP=turku HOUR=11.95: the cathedral chimes noon and
-- strikes twelve, and gulls call over the Aurajoki (systems/ambience).
local G = require "lib.state"
local A = require "systems.ambience"
local roadnet = require "lib.roadnet"

local ticks, moved = 0, false
engine.on("tick", function()
  ticks = ticks + 1
  if not moved and G.player then -- onto the river bank, by the water
    local x, z = -250, 466
    for r = 0, 60, 2 do
      if not roadnet.water_at(x, z - r) then z = z - r; break end
    end
    engine.set_pos(G.player, x, roadnet.ground(x, z) + 1.2, z)
    moved = true
  end
  if ticks == 2400 then
    assert(A.strikes(12) == 12 and A.strikes(13) == 1 and A.strikes(0) == 0 and A.strikes(7) == 7, "strike counts")
    assert(A.bell_volume(0) > 0.5 and A.bell_volume(800) > 0.03 and A.bell_volume(1500) == 0, "bell volume by distance")
    print(string.format("AMBIENCE bells=%d gulls=%d", A.played.bell, A.played.gull))
    assert(A.played.bell == 13, "noon: a chime and twelve strikes, got " .. A.played.bell)
    assert(A.played.gull >= 2, "gulls over the river, got " .. A.played.gull)
    print("ALL AMBIENCE CHECKS PASSED")
    engine.quit()
  end
end)
