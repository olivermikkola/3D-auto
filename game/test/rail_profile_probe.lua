-- RAIL_PROFILE_TEST=1: the ground along every railway track (what the bed
-- and a car on it follow), sampled every 2 m: its steepest grade and how
-- much the grade changes from one 10 m to the next (a bumpy track's does
-- all the time). Tracks across a road are left out there.
local R = require "lib.roadnet"
local done = false
engine.on("tick", function()
  if done or engine.ticks() < 5 then return end
  done = true
  local steep, wiggle, n, metres = 0, 0, 0, 0
  for _, r in ipairs((R.net() and R.net().map or {}).railways or {}) do
    local ys, last = {}, nil
    for k = 4, #r do
      local a, b = r[k - 1], r[k]
      local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
      for m = 0, math.floor(len / 2) - 1 do
        local x, z = a[1] + (b[1] - a[1]) * m * 2 / len, a[2] + (b[2] - a[2]) * m * 2 / len
        ys[#ys + 1] = not R.on_carriageway(x, z, 2) and engine.terrain_height(x, z) or false
      end
    end
    for i = 6, #ys - 5, 5 do -- grades over 10 m either side of every 10th metre
      local a, b, c = ys[i - 5], ys[i], ys[i + 5]
      if a and b and c then
        local g1, g2 = (b - a) / 10, (c - b) / 10
        steep = math.max(steep, math.abs(g1), math.abs(g2))
        wiggle = wiggle + math.abs(g2 - g1)
        n = n + 1
      end
    end
    metres = metres + #ys * 2
  end
  print(string.format("RAIL_PROFILE %.0f m of track, steepest %.1f %%, grade change %.2f %% per 10 m on average",
                      metres, steep * 100, n > 0 and wiggle / n * 100 or 0))
  engine.quit()
end)
