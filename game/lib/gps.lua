-- The GPS: the shortest way by road to where you're going, drawn on the
-- minimap like GTA's route line. Where you're going is the waypoint you set
-- on the map (M), else the nearest blip that isn't a mission's start marker
-- (a mission's goal, the cash van, the street racer's finish); with
-- neither, there's no route.
--
-- Distances to the goal come from one search out backwards from it (one-way
-- streets the right way round), kept while the goal stays on the same
-- stretch of road; the route from wherever you are is then just a walk
-- downhill through them, so it's redrawn as you drive for next to nothing.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"

local M = {}
local REDRAW = 0.4 -- s between redraws of the route from the player
local DOT = 6 -- m between the dots the route is drawn as

-- ---- searching -----------------------------------------------------------------------

local lengths = setmetatable({}, {__mode = "k"})
local function road_length(a, b)
  local map = city.map()
  local per = lengths[map]
  if not per then per = {}; lengths[map] = per end
  local key = a .. ">" .. b
  local l = per[key]
  if not l then
    l = 0
    local pts = city.path(a, b)
    for i = 2, #pts do l = l + U.dist2d(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]) end
    per[key] = l
  end
  return l
end

-- Meters along polyline pts from its start to the point (x, z) on its
-- piece i-1 -> i, and the whole length.
local function along(pts, i, x, z)
  local s, total = 0, 0
  for k = 2, #pts do
    local l = U.dist2d(pts[k - 1][1], pts[k - 1][2], pts[k][1], pts[k][2])
    if k < i then s = s + l end
    total = total + l
  end
  return s + U.dist2d(pts[i - 1][1], pts[i - 1][2], x, z), total
end

-- Where (x, z) (at height y, if known) joins the roads: the stretch of
-- road {a, b, pts, i, x, z, s, len, oneway, edge} it's nearest, at point
-- (x, z) on its piece i-1 -> i, s meters along its len.
local function attach(x, z, y)
  if not city.network() then -- a grid: few roads, all straight and two-way
    local best, out = math.huge
    for ri, r in ipairs(city.roads()) do
      local pts = city.path(r[1], r[2])
      local ax, az, bx, bz = pts[1][1], pts[1][2], pts[2][1], pts[2][2]
      local dx, dz = bx - ax, bz - az
      local t = U.clamp(((x - ax) * dx + (z - az) * dz) / math.max(dx * dx + dz * dz, 1e-6), 0, 1)
      local cx, cz = ax + dx * t, az + dz * t
      local d = U.dist2d(x, z, cx, cz)
      if d < best then
        best = d
        local len = U.dist2d(ax, az, bx, bz)
        out = {a = r[1], b = r[2], pts = pts, i = 2, x = cx, z = cz, s = len * t, len = len, oneway = false, edge = ri}
      end
    end
    return out
  end
  local roadnet = require "lib.roadnet"
  local ei, i, cx, cz = roadnet.nearest_edge(x, z, nil, y)
  local e = ei and roadnet.net().edges[ei]
  if not e then return nil end
  local s, len = along(e.pts, i, cx, cz)
  return {a = e.a, b = e.b, pts = e.pts, i = i, x = cx, z = cz, s = s, len = len, oneway = e.oneway, edge = ei}
end

-- Meters to the goal from every junction that leads to it, and each one's
-- next junction on the way (`true`: off down the goal's own stretch).
local function search(goal)
  -- A binary heap as two arrays (keys, ids): no table per entry for the
  -- garbage collector, with ~3k junctions pushed per search.
  local dist, nxt, hk, hv, n = {}, {}, {}, {}, 0
  local function push(d, id)
    n = n + 1
    local i = n
    while i > 1 do
      local up = i // 2
      if hk[up] <= d then break end
      hk[i], hv[i] = hk[up], hv[up]
      i = up
    end
    hk[i], hv[i] = d, id
  end
  local function pop()
    local d, id = hk[1], hv[1]
    local lk, lv = hk[n], hv[n]
    hk[n], hv[n] = nil, nil
    n = n - 1
    if n > 0 then
      local i = 1
      while true do
        local l = 2 * i
        if l > n then break end
        if l < n and hk[l + 1] < hk[l] then l = l + 1 end
        if lk <= hk[l] then break end
        hk[i], hv[i] = hk[l], hv[l]
        i = l
      end
      hk[i], hv[i] = lk, lv
    end
    return d, id
  end
  local function seed(j, d)
    if d < (dist[j] or math.huge) then dist[j], nxt[j] = d, true; push(d, j) end
  end
  seed(goal.a, goal.s) -- in from its start
  if not goal.oneway then seed(goal.b, goal.len - goal.s) end -- or back from its end
  while n > 0 do
    local d, u = pop()
    if d <= dist[u] then
      for _, n in ipairs(city.links_in(u)) do
        local nd = d + road_length(n, u)
        if nd < (dist[n] or math.huge) then dist[n], nxt[n] = nd, u; push(nd, n) end
      end
    end
  end
  return dist, nxt
end

-- ---- the route -----------------------------------------------------------------------

-- The way from `from` to `goal` (both attach()ed) through distances `dist`:
-- {pts = {{x, z}, ...}, js = {junctions}, length = m}, or nil if there's none.
local function route(from, goal, dist, nxt)
  local pts = {{from.x, from.z}}
  local function add(p)
    local q = pts[#pts]
    if q[1] ~= p[1] or q[2] ~= p[2] then pts[#pts + 1] = {p[1], p[2]} end
  end
  -- Along its own stretch: straight there, if the goal's on it ahead (or
  -- behind, on a two-way street).
  local direct = math.huge
  if from.edge and from.edge == goal.edge then
    if goal.s >= from.s then direct = goal.s - from.s
    elseif not from.oneway then direct = from.s - goal.s end
  end
  local via_b = from.len - from.s + (dist[from.b] or math.huge)
  local via_a = from.oneway and math.huge or from.s + (dist[from.a] or math.huge)
  local best = math.min(direct, via_a, via_b)
  if best == math.huge then return nil end
  if best == direct then
    if goal.s >= from.s then
      for k = from.i, goal.i - 1 do add(from.pts[k]) end
    else
      for k = from.i - 1, goal.i, -1 do add(from.pts[k]) end
    end
    add({goal.x, goal.z})
    return {pts = pts, js = {}, length = direct}
  end
  local j
  if best == via_b then
    for k = from.i, #from.pts do add(from.pts[k]) end
    j = from.b
  else
    for k = from.i - 1, 1, -1 do add(from.pts[k]) end
    j = from.a
  end
  local js = {j}
  while nxt[j] ~= true do
    local n = nxt[j]
    local p = city.path(j, n)
    for k = 2, #p do add(p[k]) end
    js[#js + 1] = n
    j = n
  end
  -- Onto the goal's stretch: in from its start, or back from its end.
  if j == goal.a and dist[j] == goal.s then
    for k = 2, goal.i - 1 do add(goal.pts[k]) end
  else
    for k = #goal.pts - 1, goal.i, -1 do add(goal.pts[k]) end
  end
  add({goal.x, goal.z})
  return {pts = pts, js = js, length = best}
end
-- The route from (fx, fz) to (gx, gz) (heights fy, gy if known), or nil.
function M.route_between(fx, fz, fy, gx, gz, gy)
  local from, goal = attach(fx, fz, fy), attach(gx, gz, gy)
  if not (from and goal) then return nil end
  local dist, nxt = search(goal)
  return route(from, goal, dist, nxt)
end

-- The route as dots DOT m apart, for drawing: one flat array x1, z1, x2,
-- z2, ... (one table per redraw, not one per dot).
local function dots(pts)
  local out = {}
  for i = 2, #pts do
    local ax, az, bx, bz = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
    local n = math.max(1, math.floor(U.dist2d(ax, az, bx, bz) / DOT))
    for k = 0, n - 1 do
      out[#out + 1] = ax + (bx - ax) * k / n
      out[#out + 1] = az + (bz - az) * k / n
    end
  end
  out[#out + 1] = pts[#pts][1]
  out[#out + 1] = pts[#pts][2]
  return out
end

-- ---- following the goal --------------------------------------------------------------

local cur = {} -- {id, color, goal, dist, nxt, route, dots, at}

-- A waypoint of the player's own (set on the map), or nil: {id = "waypoint",
-- x, z, color}. It goes before every blip, and is cleared on getting there.
local WAYPOINT_COLOR = {0.85, 0.35, 1}
local ARRIVED = 20 -- m
function M.set_waypoint(x, z)
  M.waypoint = {id = "waypoint", x = x, z = z, color = WAYPOINT_COLOR}
  cur.at = nil -- redraw at once
end
function M.clear_waypoint() M.waypoint = nil end

-- What the GPS heads for: the player's waypoint, else the nearest goal (a
-- blip that isn't a mission's start marker, nor `ambient`: a cash van or a
-- racer waiting by the road, which only count with no goal); nil if none.
local function is_start(id) -- (called every frame: no table for the garbage collector)
  for _, def in ipairs(require("lib.mission").defs) do
    if def.marker == id then return true end
  end
  return false
end

function M.target()
  if M.waypoint then return M.waypoint end
  local px, _, pz = U.player_pos()
  if not px then return nil end
  local best, bd = nil, math.huge
  for _, m in ipairs(G.markers or {}) do
    if engine.exists(m.id) and not is_start(m.id) then
      local x, _, z = engine.pos(m.id)
      local d = U.dist2d(x, z, px, pz) + (m.ambient and 1e9 or 0)
      if d < bd then best, bd = m, d end
    end
  end
  return best
end

-- Keep the route up to date; called every frame by the HUD, it only does
-- work every REDRAW s (or at once when the goal changes).
function M.update()
  local m = M.target()
  if not m then cur = {}; return nil end
  local now = engine.time()
  if cur.id == m.id and cur.at and now < cur.at + REDRAW then return cur.route end
  local px, py, pz = U.player_pos()
  if not px then return nil end
  local gx, gy, gz
  if m == M.waypoint then gx, gz = m.x, m.z else gx, gy, gz = engine.pos(m.id); gy = gy - 2 end
  local goal = attach(gx, gz, gy)
  if not goal then cur = {}; return nil end
  if m == M.waypoint and (U.dist2d(px, pz, gx, gz) < ARRIVED or U.dist2d(px, pz, goal.x, goal.z) < ARRIVED) then
    M.waypoint, cur = nil, {}
    U.message("WAYPOINT REACHED", 2)
    return M.update()
  end
  -- A new search only when the goal moves to another stretch of road (or
  -- along it; the cash van drives).
  if cur.id ~= m.id or not cur.goal or cur.goal.edge ~= goal.edge or math.abs(cur.goal.s - goal.s) > 15
      or cur.goal.a ~= goal.a then
    cur.dist, cur.nxt = search(goal)
    cur.goal = goal
  end
  cur.id, cur.color, cur.at = m.id, m.color, now
  local from = attach(px, pz, py)
  cur.route = from and route(from, cur.goal, cur.dist, cur.nxt)
  cur.dots = cur.route and dots(cur.route.pts)
  return cur.route
end

-- The waypoint on the minimap (an off-radar one pinned to its edge).
engine.on("minimap", function(map)
  local w = M.waypoint
  if not w then return end
  local x, y = map(w.x, w.z)
  engine.rect(x - 5, y - 5, 10, 10, 0, 0, 0, 0.8)
  engine.rect(x - 4, y - 4, 8, 8, w.color[1], w.color[2], w.color[3], 1)
end)

-- The route's dots (flat: x1, z1, x2, z2, ...) and colour, for the
-- minimap; nil with no route.
function M.dots()
  return cur.route and cur.dots, cur.color
end

-- Meters left to drive, or nil.
function M.left() return cur.route and cur.route.length end

return M
