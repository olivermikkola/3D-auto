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

return R
