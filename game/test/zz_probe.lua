local U = require "lib.util"
engine.on("tick", function()
  if engine.ticks() < 3 then return end
  local ex, ez = -511, -369
  local dx, dz = -302 - ex, -75 - ez
  local l = math.sqrt(dx * dx + dz * dz); dx, dz = dx / l, dz / l
  for _, s in ipairs{-12, -8, -4, 0, 2, 4, 6, 8, 12, 16, 20, 30} do
    local x, z = ex + dx * s, ez + dz * s
    print(string.format("ZZ s=%3d (%.0f,%.0f) ground %.2f terrain %.2f", s, x, z, U.ground(x, z), engine.terrain_height(x, z) or -1))
  end
  for _, q in ipairs{{-515, -376}, {-520, -382}} do print(string.format("ZZ drive (%d,%d) %.2f", q[1], q[2], U.ground(q[1], q[2]))) end
  engine.quit()
end)
