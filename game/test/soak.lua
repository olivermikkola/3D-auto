local T = require "systems.traffic"
engine.on("tick", function()
  if engine.ticks() % 1800 ~= 0 then return end
  local n, moving = 0, 0
  for id in pairs(T.cars) do
    n = n + 1
    local vx, _, vz = engine.vel(id)
    if vx * vx + vz * vz > 9 then moving = moving + 1 end
  end
  print(string.format("t=%ds traffic moving %d/%d", engine.ticks() // 60, moving, n))
end)
