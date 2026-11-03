-- Passages through to courtyards: the player runs through each of
-- Ylioppilaskylä's Tyyssija and Aitiopaikka passages (each a way through
-- one building door to door, OpenStreetMap's tunnel=building_passage),
-- from 3 m out in front of one door to 3 m past the other, and must get there.
-- PASSAGE_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local input = require "lib.input"

local AREA = {900, 1080, -1290, -960} -- x0, x1, z0, z1: the two buildings

local todo = {}
for _, o in ipairs(city.map().outlines or {}) do
  local ws = o.ways or {}
  for k = 1, #ws, 6 do
    local ax, az, bx, bz = ws[k], ws[k + 1], ws[k + 2], ws[k + 3]
    if ax > AREA[1] and ax < AREA[2] and az > AREA[3] and az < AREA[4] then
      local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
      local dx, dz = (bx - ax) / len, (bz - az) / len
      todo[#todo + 1] = {{ax - dx * 3, az - dz * 3}, {bx + dx * 3, bz + dz * 3}}
    end
  end
end

local run, k, failed = nil, 0, 0

input.move = function()
  if not run or not G.player then return 0, 0 end
  local x, _, z = engine.pos(G.player)
  local p = run.to
  local dx, dz = p[1] - x, p[2] - z
  local d = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
  dx, dz = dx / d, dz / d
  local fx, fz = U.forward(G.cam_yaw)
  local rx, rz = U.right(G.cam_yaw)
  return dx * fx + dz * fz, dx * rx + dz * rz
end

engine.on("tick", function(dt)
  if G.vehicle or not G.player or engine.ticks() < 30 then return end
  if not run then
    k = k + 1
    local p = todo[k]
    if not p then
      print(string.format("PASSAGE: %d passages, %d failed", #todo, failed))
      assert(#todo >= 8, "the passages to the yards are missing")
      assert(failed == 0, "a passage can't be walked through")
      print("ALL PASSAGE CHECKS PASSED")
      engine.quit()
      return
    end
    engine.set_pos(G.player, p[1][1], U.ground(p[1][1], p[1][2]) + 1.2, p[1][2])
    engine.set_vel(G.player, 0, 0, 0)
    run = {to = p[2], from = p[1], t = 0}
    return
  end
  run.t = run.t + dt
  local x, _, z = engine.pos(G.player)
  local d = U.dist2d(x, z, run.to[1], run.to[2])
  if d < 1.2 or run.t > 8 then
    print(string.format("PASSAGE: %s from (%.0f, %.0f) to (%.0f, %.0f): %s", d < 1.2 and "ok" or "FAIL", run.from[1], run.from[2],
                        run.to[1], run.to[2], d < 1.2 and string.format("through in %.1f s", run.t) or string.format("stuck %.1f m short", d)))
    if d >= 1.2 then failed = failed + 1 end
    run = nil
  end
end)
