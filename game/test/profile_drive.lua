-- Profile drive: the player's own car driven across the map by a robot at
-- city speed, with traffic, crowds and (after a while) police around it as
-- in real play, so PROFILE=1 shows where a stutter while driving comes
-- from without anyone at the wheel. It steers through the player's inputs
-- (lib.input), so it drives with the player's physics too. Run:
--   PROFILE=1 PROFILE_DRIVE=1 MAP=turku auto game --headless 12000
-- PROFILE_DRIVE_SECS=n: drive this long (default 180), then quit.
-- PROFILE_DRIVE_WANTED=s: at s seconds in, two stars (default 60; 0 = never).
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local vehicle = require "lib.vehicle"
local input = require "lib.input"

local SECS = tonumber(os.getenv("PROFILE_DRIVE_SECS") or "") or 180
local WANTED = tonumber(os.getenv("PROFILE_DRIVE_WANTED") or "") or 60
local AHEAD, FAST, SLOW = 10, 17, 7 -- m to aim ahead; m/s on straights and into bends

-- Junctions from a to b by the fewest roads, nil if b can't be reached.
local function junctions(a, b)
  local from, queue, i = {[a] = false}, {a}, 1
  while i <= #queue do
    local n = queue[i]
    i = i + 1
    if n == b then
      local out = {}
      while n do table.insert(out, 1, n); n = from[n] end
      return out
    end
    for _, nb in ipairs(city.links(n)) do
      if from[nb] == nil then from[nb] = n; queue[#queue + 1] = nb end
    end
  end
end

-- The points to drive through from junction a to b: each road's bends,
-- moved over into its right-hand lane.
local function lane_points(js, out)
  for k = 2, #js do
    local a, b = js[k - 1], js[k]
    local path, lane = city.path(a, b), city.lane(a, b)
    for i = 2, #path do
      local p, q = path[i - 1], path[i]
      local rx, rz = U.right(math.atan(q[1] - p[1], q[2] - p[2]))
      out[#out + 1] = {p[1] + rx * lane, p[2] + rz * lane}
      out[#out + 1] = {q[1] + rx * lane, q[2] + rz * lane}
    end
  end
  return out
end

local pts, at, last_j = {}, 1, nil
-- Another leg, 500-1500 m on from where the last one ended.
local function extend()
  local x, z = city.pos(last_j)
  for _ = 1, 20 do
    local goal = city.random_near(x, z, 500, 1500)
    local js = goal and junctions(last_j, goal)
    if js and #js > 1 then
      lane_points(js, pts)
      last_j = goal
      return true
    end
  end
end

local t, stuck, backing, stucks, km, px, pz, cops = 0, 0, 0, {}, 0, nil, nil, 0
local function aim(x, z)
  -- Move on past the points already reached (or passed).
  while at < #pts and U.dist2d(x, z, pts[at][1], pts[at][2]) < AHEAD do at = at + 1 end
  if #pts - at < 40 then extend() end
  return pts[at], pts[math.min(#pts, at + 4)]
end

input.drive = function()
  local car = G.vehicle
  if not car or #pts == 0 then return 0, 0, false end
  local x, _, z = engine.pos(car)
  local yaw = engine.yaw(car)
  local vx, _, vz = engine.vel(car)
  local fx, fz = U.forward(yaw)
  local v = vx * fx + vz * fz
  local p, far = aim(x, z)
  local function side(q)
    local dx, dz = q[1] - x, q[2] - z
    local l = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
    local rx, rz = U.right(yaw)
    return (dx * rx + dz * rz) / l, (dx * fx + dz * fz) / l
  end
  local s, ahead = side(p)
  local _, far_ahead = side(far)
  local steer = U.clamp(-s * 2.5, -1, 1)
  if ahead < 0 then steer = s > 0 and -1 or 1 end -- the point is behind: turn round to it
  -- Slow into bends: the further off the nose the road goes, the slower.
  local want = SLOW + (FAST - SLOW) * U.clamp((far_ahead - 0.5) * 2, 0, 1)
  if backing > 0 then return -1, -steer, false end
  return U.clamp((want - v) * 0.4, -1, 1), steer, false
end

engine.on("tick", function(dt)
  t = t + dt
  if t > SECS then
    print(string.format("PROFILE_DRIVE: drove %.1f km in %.0f s, %d stuck spot(s), up to %d police cars", km, SECS, #stucks, cops))
    for _, s in ipairs(stucks) do print(string.format("  stuck at %.0f, %.0f (%.0f s in)", s[1], s[2], s[3])) end
    engine.quit()
    return
  end
  if t > 0.5 and not G.vehicle and #pts == 0 then
    -- Into a car on the road nearest the player, facing the way to go.
    local x, _, z = engine.pos(G.player)
    last_j = city.nearest(x, z, U.ground(x, z))
    if not extend() then error("PROFILE_DRIVE: no road to drive from junction " .. tostring(last_j)) end
    local p, q = pts[1], pts[2]
    local yaw = math.atan(q[1] - p[1], q[2] - p[2])
    local car = vehicle.spawn(p[1], p[2], yaw, 1, nil, "car", city.height_on(city.nearest(p[1], p[2]), last_j, p[1], p[2]))
    engine.despawn(G.player)
    G.player, G.vehicle = nil, car
    engine.emit("vehicle_enter", car)
    print("PROFILE_DRIVE: driving from " .. string.format("%.0f, %.0f", p[1], p[2]))
  end
  if WANTED > 0 and t > WANTED and t - dt <= WANTED then require("lib.wanted").set(2) end
  cops = math.max(cops, require("systems.police").count())
  local car = G.vehicle
  if not car then return end
  -- Stuck (nose in a wall, a bus in the way): back off a second, and
  -- after the third time in one place, give up on the spot and hop on.
  backing = math.max(0, backing - dt)
  local x, _, z = engine.pos(car)
  if px then km = km + U.dist2d(x, z, px, pz) / 1000 end
  px, pz = x, z
  if os.getenv("PROFILE_DRIVE_TRACE") and math.floor(t) ~= math.floor(t - dt) and math.floor(t) % 5 == 0 then
    print(string.format("PROFILE_DRIVE: %3.0f s at %.0f, %.0f, %.2f km, point %d/%d", t, x, z, km, at, #pts))
  end
  local vx, _, vz = engine.vel(car)
  stuck = math.sqrt(vx * vx + vz * vz) < 1 and backing == 0 and stuck + dt or 0
  if stuck > 3 then
    stuck, backing = 0, 1.2
    local s = stucks[#stucks]
    if s and U.dist2d(x, z, s[1], s[2]) < 15 then
      s[4] = s[4] + 1
      if s[4] >= 3 then
        at = math.min(#pts, at + 8)
        local p, q = pts[at], pts[math.min(#pts, at + 1)]
        engine.set_pos(car, p[1], U.ground(p[1], p[2]) + 1.5, p[2])
        engine.set_yaw(car, math.atan(q[1] - p[1], q[2] - p[2]))
        engine.set_vel(car, 0, 0, 0)
        backing = 0
      end
    else
      stucks[#stucks + 1] = {x, z, t, 1}
    end
  end
end)

