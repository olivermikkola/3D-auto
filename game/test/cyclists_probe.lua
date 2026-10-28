-- Cyclists probe: people ride the cycle paths near the player, on the
-- paths (not in the river, not sunk or flying), going somewhere; fewer late
-- at night; a car that hits one knocks the rider off the bike.
-- CYCLISTS_TEST=1 auto game --headless 6000   (MAP=turku)
local G = require "lib.state"
local U = require "lib.util"
local daynight = require "lib.daynight"
local quality = require "lib.quality"
local roadnet = require "lib.roadnet"
local C = require "systems.cyclists"

local function check(ok, what)
  if not ok then engine.quit(); error("CYCLISTS TEST FAILED: " .. what, 0) end
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

-- How far (x, z) is from route r.
local function off_route(r, x, z)
  local best = math.huge
  for i = 2, #r.pts do
    local a, b = r.pts[i - 1], r.pts[i]
    local dx, dz = b[1] - a[1], b[2] - a[2]
    local t = U.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / math.max(1e-6, dx * dx + dz * dz), 0, 1)
    best = math.min(best, U.dist2d(x, z, a[1] + dx * t, a[2] + dz * t))
  end
  return best
end

local function riders()
  local list = {}
  for id, c in pairs(C.riders) do list[#list + 1] = {id, c} end
  return list
end

local function script()
  check(C.paths >= 500, string.format("%d cycle paths", C.paths))
  -- The CELL square with the most paths near the centre.
  local best, bx, bz = 0
  for k, list in pairs(C.cells) do
    local i, j = k:match("^(-?%d+),(-?%d+)$")
    local x, z = (tonumber(i) + 0.5) * 100, (tonumber(j) + 0.5) * 100
    if #list > best and math.abs(x) < 1500 and math.abs(z) < 1500 and not roadnet.wet(x, z) then best, bx, bz = #list, x, z end
  end
  print(string.format("CYCLISTS_PROBE: player at %.0f, %.0f (%d paths in its square)", bx, bz, best))

  daynight.set_hour(12)
  move_player(bx, bz)
  local want = quality.pick(C.MOST)
  wait(function() return C.count() >= want end, 30, "riders come out by day")
  check(C.count() == want, string.format("%d riding by day", C.count()))

  local from = {}
  for _, rc in ipairs(riders()) do from[rc[1]] = {engine.pos(rc[1])} end
  sleep(20)
  local on_path, level, moving, went, n, old = 0, 0, 0, 0, 0, 0
  for _, rc in ipairs(riders()) do
    local id, c = rc[1], rc[2]
    local x, y, z = engine.pos(id)
    local vx, _, vz = engine.vel(id)
    n = n + 1
    -- (Or on the way over to the next path, across a street.)
    if off_route(c.r, x, z) < 3 or c.joining then on_path = on_path + 1 end
    local _, d = engine.raycast(x, y, z, 0, -1, 0, 3, id)
    if d and math.abs(d - 0.9) < 0.4 and not roadnet.wet(x, z) then level = level + 1 end
    if vx * vx + vz * vz > 4 then moving = moving + 1 end
    local f = from[id]
    if f then old = old + 1 end
    if f and U.dist2d(x, z, f[1], f[3]) > 40 then went = went + 1 end
    if os.getenv("CYC_TRACE") then print(string.format("TRACE moved=%.0f turns=%d held=%d stuck=%.1f len=%.0f links=%d/%d v=%.1f", f and U.dist2d(x, z, f[1], f[3]) or -1, c.turns or 0, c.held or 0, c.stuck, c.r.len, #c.r.links[1], #c.r.links[2], math.sqrt(vx*vx+vz*vz))) end
  end
  print(string.format("CYCLISTS_PROBE: %d riders, %d on their path, %d wheels on the ground, %d riding, %d went 40 m+", n, on_path, level, moving, went))
  check(n >= want - 2, "most still about")
  check(on_path >= n * 0.9, "on the cycle paths")
  check(level >= n * 0.9, "on the ground, not sunk or flying")
  check(moving >= n * 0.6, "riding, not stood still")
  check(went >= old * 0.6, string.format("going somewhere (%d of %d)", went, old))

  -- Knocked off by a car.
  local rc = riders()[1]
  local id, c = rc[1], rc[2]
  c.speed = 0
  sleep(1)
  local x, y, z = engine.pos(id)
  local car = engine.spawn{mesh = "car1", pos = {x - 7, y + 0.2, z}, size = {1.9, 1.4, 4.4}, yaw = math.pi / 2,
                           body = "dynamic", mass = 1300, friction = 0.5, tag = "car"}
  engine.set_vel(car, 14, 0, 0)
  wait(function() return C.riders[id] == nil end, 4, "a car knocks the rider off")
  sleep(0.5)
  local fallen = #engine.find("ped_down")
  check(fallen >= 1, "the rider tumbles (" .. fallen .. " down)")
  engine.despawn(car)

  -- Late at night, fewer.
  daynight.set_hour(2)
  local day = {}
  for id in pairs(C.riders) do day[id] = true end
  -- Somewhere dry 600 m off (the player would swim, or drown, in the river).
  local ax, az
  for k = 0, 7 do
    local x, z = bx + math.cos(k * math.pi / 4) * 600, bz + math.sin(k * math.pi / 4) * 600
    if not ax and not roadnet.wet(x, z) and not roadnet.on_carriageway(x, z, 1) then ax, az = x, z end
  end
  move_player(ax, az)
  wait(function()
    for id in pairs(day) do
      if C.riders[id] then
        if os.getenv("CYC_TRACE") then local x, _, z = engine.pos(id); local px, _, pz = U.player_pos(); print("TRACE left", id, U.dist2d(x, z, px, pz)) end
        return false
      end
    end
    return true
  end, 15, "riders far off go")
  move_player(bx, bz)
  sleep(15)
  local night = C.count()
  check(night <= math.ceil(want * 0.25 + 0.5), string.format("fewer at night (%d)", night))
  print("CYCLISTS_PROBE: PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
