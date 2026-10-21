-- Roadblock probe: at three stars, driving down a road, two squad cars
-- park across it ahead of you with officers behind them; past it, they
-- join the chase. ROADBLOCK_TEST=1 auto game --headless 3000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local police = require "systems.police"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local function check(ok, what)
  if not ok then engine.quit(); error("ROADBLOCK TEST FAILED: " .. what, 0) end
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

local function blocks()
  local out = {}
  for id, c in pairs(police.cops) do if c.block then out[#out + 1] = id end end
  return out
end

local function script()
  sleep(0.5)
  local map = city.map().id or "?"
  -- A road with somewhere to put a block ahead: 10 m out of a junction.
  local sx, sz, yaw, sy
  for _, r in ipairs(city.roads()) do
    local p = city.path(r[1], r[2])
    local ax, az, bx, bz = p[1][1], p[1][2], p[2][1], p[2][2]
    local l = U.dist2d(ax, az, bx, bz)
    if l > 30 then
      local fx, fz = (bx - ax) / l, (bz - az) / l
      local x, z = ax + fx * 10, az + fz * 10
      local y = city.height_on(r[1], r[2], x, z)
      local level = city.level(r[1])
      if (not level or math.abs(level - U.ground(x, z)) < 1) and police.block_spot(x, z, fx, fz, y) then
        sx, sz, yaw, sy = x, z, math.atan(fx, fz), y
        break
      end
    end
  end
  check(sx, "a road with room for a block ahead")
  local car = vehicle.spawn(sx, sz, yaw, 3, nil, nil, sy)
  local rx, rz = U.right(yaw)
  engine.set_pos(G.player, sx + rx * 3, 1.2 + U.ground(sx, sz), sz + rz * 3)
  sleep(0.2)
  engine.emit("key", "e", true)
  wait(function() return G.vehicle == car end, 1, "in the car")
  for id in pairs(require("systems.traffic").cars) do engine.despawn(id) end

  wanted.set(3)
  local fx, fz = U.forward(yaw)
  local function roll() engine.set_vel(car, fx * 12, select(2, engine.vel(car)), fz * 12) end
  wait(function() roll(); return #blocks() > 0 end, 3, "a roadblock goes up")
  local b = blocks()
  check(#b >= 2 and #b <= 4, #b .. " squad cars")
  local cx, cz = 0, 0
  for _, id in ipairs(b) do
    local x, _, z = engine.pos(id)
    cx, cz = cx + x / #b, cz + z / #b
    local across = math.abs(math.cos(engine.yaw(id) - yaw))
    check(across < 0.6, string.format("parked across the road (%.2f)", across))
  end
  local px, _, pz = engine.pos(car)
  local ahead = (cx - px) * fx + (cz - pz) * fz
  check(ahead > 90 and ahead < 230, string.format("ahead of you (%.0f m)", ahead))
  local posted = 0
  for _, o in pairs(police.officers) do if o.post then posted = posted + 1 end end
  check(posted == 2, "an officer posted behind the outer two")
  local all = 0
  for _ in pairs(police.cops) do all = all + 1 end
  check(police.count() == all - #b, "blocks don't count against the chasers")
  sleep(1)
  for _, id in ipairs(b) do
    local x, _, z = engine.pos(id)
    check(engine.exists(id) and U.dist2d(x, z, cx, cz) < 12, "they stay put")
  end
  -- Past it: they let go and join the chase.
  local bx, bz = police.cops[b[1]].block[1], police.cops[b[1]].block[2]
  local nx, nz = bx + fx * 30, bz + fz * 30
  engine.set_pos(car, nx, 1 + (sy or U.ground(nx, nz)), nz)
  sleep(0.5)
  check(#blocks() == 0, "once you're past, the block lets go")
  for _, o in pairs(police.officers) do check(not o.post, "and its officers leave their posts") end
  print("ROADBLOCK_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
