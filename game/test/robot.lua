-- A robot at the wheel, for tests: it steers a car through a list of
-- points ({x, z}, in order) at city speed, slowing into bends, by working
-- out the inputs a player would give (throttle, steer), so the car moves
-- by the player's own physics.
local U = require "lib.util"
local city = require "lib.city"

local R = {}
local AHEAD = 10 -- m ahead to aim at

-- Junctions from a to b by the fewest roads, nil if b can't be reached.
function R.junctions(a, b)
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

-- The points to drive through along junctions js: each road's bends,
-- moved over into its right-hand lane. Appended to `out`.
function R.lane_points(js, out)
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

-- A driver through d.pts (which may grow as it goes), at up to `fast` m/s
-- on straights and `slow` into bends. d.inputs(car) -> throttle, steer;
-- d.at is the point it's heading for; while d.backing > 0 (the caller
-- counts it down) it backs up instead, with opposite lock.
function R.driver(pts, fast, slow)
  local d = {pts = pts, at = 1, backing = 0}
  function d.inputs(car)
    if #d.pts == 0 then return 0, 0 end
    local x, _, z = engine.pos(car)
    local yaw = engine.yaw(car)
    local vx, _, vz = engine.vel(car)
    local fx, fz = U.forward(yaw)
    local rx, rz = U.right(yaw)
    local v = vx * fx + vz * fz
    while d.at < #d.pts and U.dist2d(x, z, d.pts[d.at][1], d.pts[d.at][2]) < AHEAD do d.at = d.at + 1 end
    local function side(q)
      local dx, dz = q[1] - x, q[2] - z
      local l = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
      return (dx * rx + dz * rz) / l, (dx * fx + dz * fz) / l
    end
    local s, ahead = side(d.pts[d.at])
    local _, far_ahead = side(d.pts[math.min(#d.pts, d.at + 4)])
    local steer = U.clamp(-s * 2.5, -1, 1)
    if ahead < 0 then steer = s > 0 and -1 or 1 end -- the point is behind: turn round to it
    if d.backing > 0 then return -1, -steer end
    -- Slow into bends: the further off the nose the road goes, the slower.
    local want = slow + (fast - slow) * U.clamp((far_ahead - 0.5) * 2, 0, 1)
    return U.clamp((want - v) * 0.4, -1, 1), steer
  end
  return d
end

-- The GPS line moved over into the right-hand lane: 1.8 m, the middle of
-- it on a narrow two-way street (2.5 put the car's side into the lamps
-- along a 7.3 m one).
local function keep_right(pts)
  local out = {}
  for i = 2, #pts do
    local p, q = pts[i - 1], pts[i]
    if U.dist2d(p[1], p[2], q[1], q[2]) > 0.5 then
      local rx, rz = U.right(math.atan(q[1] - p[1], q[2] - p[2]))
      out[#out + 1] = {p[1] + rx * 1.8, p[2] + rz * 1.8}
      out[#out + 1] = {q[1] + rx * 1.8, q[2] + rz * 1.8}
    end
  end
  return out
end

-- A driver that follows the GPS line (lib/gps) as it's redrawn and stops
-- where it ends. d.inputs(car) -> throttle, steer, handbrake, for
-- input.drive; d.arrived once stopped with `there` m of the line left (12
-- if not given). It
-- backs up for 1.5 s when stuck for 2. Stuck within 15 m of one spot for
-- 12 s all told, it's towed 15 m on along the line (at most twice; the
-- spot is printed: a place on the map a car gets stuck), so a test of a
-- job isn't a test of the robot's driving.
local TOW_AFTER, TOW_MAX = 12, 2
function R.gps_driver(fast, slow, there)
  local gps = require "lib.gps"
  local g = {redraws = 0, still = 0, arrived = false, tows = 0, stuck_for = 0}
  local inner, last
  function g.inputs(car)
    local route = gps.update()
    if not route then return 0, 0, true end
    if route ~= last then
      if not inner or g.redraws % 5 == 0 then
        local backing = inner and inner.backing or 0
        inner = R.driver(keep_right(route.pts), fast or 14, slow or 6)
        inner.backing = backing
      end
      last, g.redraws = route, g.redraws + 1
    end
    local speed = math.abs(require("lib.vehicle").speed(car))
    if route.length < (there or 12) then -- there: stop
      g.arrived = speed < 1
      return 0, 0, true
    end
    g.arrived = false
    -- Towed on, stuck at one spot for too long.
    local x, y, z = engine.pos(car)
    if not g.spot or U.dist2d(x, z, g.spot[1], g.spot[2]) > 15 then g.spot, g.stuck_for = {x, z}, 0 end
    g.stuck_for = g.stuck_for + 1 / 60
    if g.stuck_for > TOW_AFTER and g.tows < TOW_MAX and #route.pts >= 2 then
      local d, k, tx, tz, yaw = 0, 2
      while k <= #route.pts do
        local p, q = route.pts[k - 1], route.pts[k]
        local l = U.dist2d(p[1], p[2], q[1], q[2])
        if d + l >= 15 then
          local t = (15 - d) / math.max(l, 1e-3)
          tx, tz, yaw = p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, math.atan(q[1] - p[1], q[2] - p[2])
          break
        end
        d, k = d + l, k + 1
      end
      if tx then
        g.tows = g.tows + 1
        print(string.format("ROBOT: stuck at %.0f, %.0f (y %.1f) for %d s: towed 15 m on (%s)", x, z, y, TOW_AFTER,
          city.network() and require("lib.roadnet").where(x, z) or "?"))
        engine.set_pos(car, tx, y + 0.5, tz)
        engine.set_rot(car, 0, 0, 0, 1)
        engine.set_yaw(car, yaw)
        engine.set_vel(car, 0, 0, 0)
        engine.set_angvel(car, 0, 0, 0)
        g.spot, g.stuck_for, inner.backing = nil, 0, 0
      end
    end
    g.still = speed < 1 and g.still + 1 / 60 or 0
    if g.still > 2 then inner.backing, g.still = 1.5, 0 end
    if inner.backing > 0 then inner.backing = inner.backing - 1 / 60 end
    -- Slow down for the end.
    local throttle, steer = inner.inputs(car)
    if route.length < 40 and speed > route.length / 3 + 2 then throttle = -1 end
    return throttle, steer, false
  end
  return g
end

return R
