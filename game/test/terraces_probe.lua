-- Terraces probe: the cafés, restaurants and bars by the Aurajoki's quays
-- have terraces, on dry, level ground off the road and nearer the water
-- than the place itself; people sit at them by day and in the evening,
-- facing their table, and none in the small hours.
-- TERRACES_TEST=1 auto game --headless 3000   (MAP=turku)
local G = require "lib.state"
local U = require "lib.util"
local daynight = require "lib.daynight"
local roadnet = require "lib.roadnet"
local T = require "systems.terraces"

local function check(ok, what)
  if not ok then engine.quit(); error("TERRACES TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local function wait(pred, timeout, what)
  local t = engine.time() + timeout
  while not pred() do
    if engine.time() > t then check(false, what .. " (timed out)") end
    coroutine.yield()
  end
end

local function sleep(s)
  local t = engine.time() + s
  wait(function() return engine.time() >= t end, s + 1, "sleep")
end

local function move_player(x, z)
  local id = G.vehicle or G.player
  engine.set_pos(id, x, U.ground(x, z) + 1.5, z)
  engine.set_vel(id, 0, 0, 0)
end

local function seated()
  local n = 0
  for _, t in ipairs(T.list) do n = n + #(t.people or {}) end
  return n
end

local function script()
  wait(function() return #T.list > 0 end, 5, "terraces are up")
  check(#T.list >= 15, string.format("%d terraces by the river", #T.list))
  local bad = 0
  for _, t in ipairs(T.list) do
    if os.getenv("TERRACES_LIST") then
      print(string.format("TERRACE %s (%s) %.0f,%.0f yaw %.2f", t.name or "?", t.kind, t.x, t.z, t.yaw))
    end
    if roadnet.on_carriageway(t.x, t.z, 1) or roadnet.wet(t.x, t.z) then bad = bad + 1 end
  end
  check(bad == 0, "none on a road or in the water")

  -- By the busiest: noon, then evening, then 3 at night.
  local t1 = T.list[1]
  move_player(t1.x + 20, t1.z)
  daynight.set_hour(13.2)
  sleep(3)
  local noon = seated()
  daynight.set_hour(19.2)
  move_player(t1.x + 300, t1.z) -- away, so they're reseated for the hour
  sleep(2)
  move_player(t1.x + 20, t1.z)
  sleep(2)
  local evening = seated()
  print(string.format("TERRACES_PROBE: %d seated at noon, %d in the evening", noon, evening))
  check(noon > 0, "people sit at the terraces by day")
  check(evening > noon, "more in the evening")
  -- Each faces the table beside them: it's 0.65 m ahead of them.
  local facing, n = 0, 0
  for _, t in ipairs(T.list) do
    local fx, fz = U.forward(t.yaw)
    local rx, rz = U.right(t.yaw)
    for _, id in ipairs(t.people or {}) do
      n = n + 1
      local x, _, z = engine.pos(id)
      local ax, az = U.forward(engine.yaw(id))
      ax, az = x + ax * 0.65, z + az * 0.65
      for _, tb in ipairs(T.TABLES) do
        if U.dist2d(ax, az, t.x - rx * tb[1] + fx * tb[2], t.z - rz * tb[1] + fz * tb[2]) < 0.2 then
          facing = facing + 1
          break
        end
      end
    end
  end
  check(facing == n, string.format("each faces a table (%d of %d)", facing, n))
  daynight.set_hour(3)
  move_player(t1.x + 300, t1.z)
  sleep(2)
  move_player(t1.x + 20, t1.z)
  sleep(2)
  check(seated() == 0, "nobody at 3 at night")
  print("TERRACES_PROBE: PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
