-- Long-run health: traffic must keep flowing and pedestrians keep walking.
local T = require "systems.traffic"
local peds = require "systems.peds"
engine.on("tick", function()
  if engine.ticks() % 1800 ~= 0 then return end
  local n, moving = 0, 0
  for id in pairs(T.cars) do
    n = n + 1
    local vx, _, vz = engine.vel(id)
    if vx * vx + vz * vz > 9 then moving = moving + 1 end
  end
  local pn, pmoving = 0, 0
  for id in pairs(peds.peds) do
    pn = pn + 1
    local vx, _, vz = engine.vel(id)
    if vx * vx + vz * vz > 0.3 then pmoving = pmoving + 1 end
  end
  print(string.format("t=%ds traffic moving %d/%d, pedestrians walking %d/%d", engine.ticks() // 60, moving, n, pmoving, pn))
  if engine.ticks() >= 3600 and (moving < n * 0.6 or pmoving < pn * 0.7) then
    error("SOAK FAILED: the city is jammed")
  end
end)
