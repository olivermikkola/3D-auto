-- Stairs you can run: the player, on foot, runs up a flight of the map's
-- outdoor stairs from its foot to its top, then back down; each must get
-- to the far end, at the stairs' height there, in time. Puolalanportaat
-- (down Puolalanmäki to Louhi) first, then the tallest others.
-- STAIRS_TEST=1 MAP=turku (STAIRS_TEST_N=n flights, default 12).
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local input = require "lib.input"

local map = city.map()
assert(map.stairs and #map.stairs > 0, "no stairs on this map")
local N = tonumber(os.getenv("STAIRS_TEST_N") or "") or 12

-- The flights with ground rising along them, tallest first; those near
-- Puolalanportaat's foot (by Louhi's entrance) before all. Picked once the
-- ground is there to measure.
local todo
local function pick()
  todo = {}
  for _, s in ipairs(map.stairs) do
    local a, b = s[2], s[#s]
    local ha, hb = engine.terrain_height(a[1], a[2]) or 0, engine.terrain_height(b[1], b[2]) or 0
    if math.abs(hb - ha) >= 1.5 then
      local pts = {}
      for i = 2, #s do pts[#pts + 1] = s[i] end
      if hb < ha then
        local r = {}
        for i = #pts, 1, -1 do r[#r + 1] = pts[i] end
        pts, ha, hb = r, hb, ha
      end
      local puolala = U.dist2d(pts[1][1], pts[1][2], -515, -368) < 60
      todo[#todo + 1] = {pts = pts, lo = ha, hi = hb, rank = (puolala and 1000 or 0) + hb - ha}
    end
end
table.sort(todo, function(a, b) return a.rank > b.rank end)
while #todo > N do table.remove(todo) end
assert(#todo > 0, "no stairs with ground rising along them")
end

local run, k, failed, passed = nil, 0, 0, 0

-- Run toward the next point of the way, whatever the camera's heading.
input.move = function()
  if not run or run.at or not G.player then return 0, 0 end
  local x, _, z = engine.pos(G.player)
  local p = run.way[run.i]
  local dx, dz = p[1] - x, p[2] - z
  local d = math.sqrt(dx * dx + dz * dz)
  if d < 1.2 and run.i < #run.way then run.i = run.i + 1 end
  if d < 1e-3 then return 0, 0 end
  dx, dz = dx / d, dz / d
  local fx, fz = U.forward(G.cam_yaw)
  local rx, rz = U.right(G.cam_yaw)
  return dx * fx + dz * fz, dx * rx + dz * rz
end
input.running = function() return run ~= nil end

local function start()
  k = k + 1
  local f = todo[math.floor((k + 1) / 2)]
  if not f then
    print(string.format("STAIRS: %d runs, %d failed", passed + failed, failed))
    assert(failed == 0, "a run up or down the stairs didn't get there")
    print("ALL STAIRS CHECKS PASSED")
    engine.quit()
    return
  end
  local up = k % 2 == 1
  local way = {}
  for i = 1, #f.pts do way[#way + 1] = f.pts[up and i or #f.pts + 1 - i] end
  -- Start 1.5 m out past the end, on the ground there.
  local a, b = way[1], way[2]
  local dx, dz = a[1] - b[1], a[2] - b[2]
  local d = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
  local sx, sz = a[1] + dx / d * 1.5, a[2] + dz / d * 1.5
  local len = 0
  for i = 2, #way do len = len + U.dist2d(way[i - 1][1], way[i - 1][2], way[i][1], way[i][2]) end
  local sy = (up and f.lo or f.hi) + 1.2
  engine.set_pos(G.player, sx, sy, sz)
  engine.set_vel(G.player, 0, 0, 0)
  run = {way = way, i = 1, t = 0, limit = len / 3 + 4, f = f, up = up, top = up and f.hi or f.lo,
         slope = (f.hi - f.lo) / math.max(len, 1)}
end

engine.on("tick", function(dt)
  if G.vehicle or not G.player then return end
  if engine.ticks() < 30 then return end
  if not todo then pick() end
  if not run then return start() end
  run.t = run.t + dt
  local x, y, z = engine.pos(G.player)
  local e = run.way[#run.way]
  local d = U.dist2d(x, z, e[1], e[2])
  -- There (running down, the player may still be in the air off the last
  -- steps, as off any steep slope: wait for the landing, a second at most).
  if d < 1.5 and not run.at then run.at = run.t end
  if (run.at and (engine.grounded(G.player) or run.t > run.at + 1)) or run.t > run.limit then
    -- Feet (the body's middle is 0.9 m up) within a step of the stairs'
    -- height where they stopped (short of the end: still on the slope).
    local ok = run.at ~= nil and d < 4 and math.abs(y - 0.9 - run.top) < 0.6 + run.slope * d
    print(string.format("STAIRS: %s %.1f m %s from (%.0f, %.0f): %s in %.1f s, feet %.2f m vs %.2f", ok and "ok" or "FAIL",
                        run.f.hi - run.f.lo, run.up and "up" or "down", run.way[1][1], run.way[1][2],
                        d < 1.5 and "there" or string.format("%.1f m short", d), run.t, y - 0.9, run.top))
    if ok then passed = passed + 1 else failed = failed + 1 end
    run = nil
  end
end)
