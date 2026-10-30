-- Police: cop cars that hunt the player while the wanted level is up.
-- They path along the street grid toward the player, switch to direct
-- pursuit once they can see you, and bust you if you stop next to one.
-- From two stars up, officers get out and shoot when they catch you.
-- Escape by leaving the search circle unseen. Pure Lua, no engine help.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"
local H = require "lib.health"
local FX = require "lib.fx"

local P = {cops = {}, officers = {}}
local DEPLOY_STARS, DEPLOY_RANGE, SHOOT_RANGE = 2, 28, 35
local COPS_PER_LEVEL = {1, 2, 3, 5, 7}
local SIGHT = 90
local STATION_RANGE = 250 -- a station this close sends some of the backup (it arrives in seconds)
local RESPAWN_AFTER = 6 -- seconds before a car left behind or wrecked is replaced
local spawn_timer, busted_for = 0, 0
local LANE = 3.2 -- meters right of the center line on a grid (on a road map: city.lane)

function P.build()
  local parts = require("lib.prefabs").car_parts({0.95, 0.95, 0.97})
  parts[#parts + 1] = {mesh = "cube", pos = {0, -0.2, 0.2}, size = {2.03, 0.3, 2.6}, color = {0.08, 0.08, 0.1}}
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.71, -0.3}, size = {1.2, 0.06, 0.35}, color = {0.2, 0.2, 0.2}}
  engine.mesh("cop", parts)
  engine.mesh("beacon", {{mesh = "cube", size = {0.5, 0.16, 0.3}, color = {1, 1, 1}, emissive = 1}})
  require("lib.prefabs").person("officer", {0.12, 0.16, 0.36}, {0.07, 0.08, 0.16}, {0.8, 0.62, 0.48}, {0.05, 0.05, 0.08})
  -- A map with a police station has squad cars parked outside it.
  if city.has("police_station") then
    local sx, sz = city.place("police_station")
    for k = -1, 1, 2 do
      engine.spawn{mesh = "cop", pos = {sx + k * 3, 0.75 + U.ground(sx + k * 3, sz), sz}, yaw = math.pi / 2, size = {2, 1.5, 4.5}, body = "static", tag = "prop"}
    end
  end
end

function P.count()
  local n = 0
  for _, c in pairs(P.cops) do if not c.block then n = n + 1 end end
  return n
end

function P.is_cop(id) return P.cops[id] ~= nil end

-- ---- spawning ------------------------------------------------------------

-- Is something a cop car would land on standing within 6 m of (x, z)?
-- Only what moves counts: scenery (road meshes, lamps, trees) is
-- already off the asphalt.
local function occupied(x, z)
  for _, tag in ipairs{"car", "cop", "player", "officer", "ped"} do
    if engine.nearest(x, 1, z, 6, tag) then return true end
  end
  return false
end

-- How far it is by road from each junction to junction `to` (meters),
-- driving the right way down one-way streets, for every junction up to
-- `limit` m away (further ones may be missing or too far: the search
-- stops there, rather than going on across the whole city).
local function road_dist(to, limit)
  local dist, done = {[to] = 0}, {}
  while true do
    local best, u = math.huge
    for j, d in pairs(dist) do
      if not done[j] and (d < best or (d == best and j < u)) then best, u = d, j end
    end
    if not u or best > limit then return dist end
    done[u] = true
    for _, n in ipairs(city.links_in(u)) do
      local p, len = city.path(n, u), 0
      for i = 2, #p do len = len + U.dist2d(p[i - 1][1], p[i - 1][2], p[i][1], p[i][2]) end
      if not dist[n] or best + len < dist[n] then dist[n] = best + len end
    end
  end
end

-- Would a car turning up at (x, y, z) be unfair: in plain sight of the
-- player, so it's on them the moment it appears (and resets the escape),
-- or on their tail while they're getting away? The player in a fast car
-- has driven past wherever "behind" is; it should have come from ahead.
-- (Out in the open there may be nowhere in range out of sight: then
-- spawn_point asks again, `lenient`, and in sight will do.)
local lenient = false
local function unfair(x, y, z)
  local target = G.vehicle or G.player
  if not target then return false end
  local px, py, pz = engine.pos(target)
  local d = U.dist2d(x, z, px, pz)
  if d < 60 then return true end
  local vx, _, vz = engine.vel(target)
  local v = math.sqrt(vx * vx + vz * vz)
  if v > 8 and d < 140 and ((x - px) * vx + (z - pz) * vz) / (d * v) < -0.5 then return true end
  if lenient or d > SIGHT + 15 then return false end
  y = (y or U.ground(x, z)) + 1
  local dx, dy, dz = px - x, py + 0.4 - y, pz - z
  local hit = engine.raycast(x, y, z, dx, dy, dz, math.sqrt(dx * dx + dy * dy + dz * dz), nil)
  return hit == nil or hit == target
end

-- A junction 70-130 m from where the cops think the player is (further,
-- in a town whose junctions are far apart). On a map drawn as roads,
-- 70-160 m by road (up to 320 up a long dead end): a junction that's close as the crow flies can be a long
-- drive round, and a cop sent the long way ends up too far off and is
-- recycled, again and again.
local spawn_point_at
local function spawn_point()
  lenient = false
  local x, z, yaw, y, launch = spawn_point_at()
  if x then return x, z, yaw, y, launch end
  lenient = true
  x, z, yaw, y, launch = spawn_point_at()
  lenient = false
  return x, z, yaw, y, launch
end
function spawn_point_at()
  local px, pz, py = wanted.center[1], wanted.center[2], wanted.center[3]
  -- Not down in a tunnel when they're up in the street, or the other way.
  local function level(j)
    local y = city.level(j)
    return not (py and y) or math.abs(y - py) < 4
  end
  if city.network() then
    -- Up a long dead end there may be none that near: then the nearest
    -- by road, up to twice as far.
    -- (Whether a spot is free is asked last, of the one drawn: each ask
    -- looks through every entity on the map, and asking it of every
    -- candidate took 11 ms in central Turku.)
    local dist, j = road_dist(city.nearest(px, pz, py), 320)
    for _, far in ipairs{160, 320} do
      local cands = {}
      for c, d in pairs(dist) do
        local x, z = city.pos(c)
        if d >= 70 and d <= far and U.dist2d(x, z, px, pz) >= 50 and level(c) then cands[#cands + 1] = c end
      end
      table.sort(cands) -- (pairs' order isn't fixed: the same seed, the same pick)
      while #cands > 0 and not j do
        local i = math.random(#cands)
        local x, z = city.pos(cands[i])
        if occupied(x, z) or unfair(x, city.level(cands[i]), z) then
          cands[i] = cands[#cands]
          cands[#cands] = nil
        else
          j = cands[i]
        end
      end
      if j then break end
    end
    if j then
      local x, z = city.pos(j)
      -- Align police squad car along outgoing road lane rather than direct line-of-sight pointing
      local links = city.links(j)
      local yaw = math.atan(px - x, pz - z)
      if links and #links > 0 then
        local best_dot, best_yaw = -2, yaw
        for _, nxt in ipairs(links) do
          local path = city.path(j, nxt)
          if path and #path >= 2 then
            local lx, lz = path[2][1] - x, path[2][2] - z
            local lyaw = math.atan(lx, lz)
            local fx, fz = U.forward(lyaw)
            local dx, dz = px - x, pz - z
            local dl = math.sqrt(dx * dx + dz * dz) + 1e-5
            local dot = (fx * dx + fz * dz) / dl
            if dot > best_dot then best_dot, best_yaw = dot, lyaw end
          end
        end
        yaw = best_yaw
      end
      -- From further off, time to get here before it may be recycled.
      return x, z, yaw, city.level(j), U.dist2d(x, z, px, pz) > 150 and 25 or nil
    end
  end
  for _ = 1, 10 do
    local j = city.random_near(px, pz, 70, 130) or city.random_near(px, pz, 40, 260)
    if not j then return end
    local x, z = city.pos(j)
    if not occupied(x, z) and level(j) and not unfair(x, city.level(j), z) then return x, z, math.atan(px - x, pz - z), city.level(j) end
  end
  -- A town's junctions can be few and far apart (and busy): anywhere
  -- along a road in range will do, in the lane heading for the player.
  if not city.network() then return end
  local roads = city.roads()
  for _ = 1, 20 do
    local r = roads[math.random(#roads)]
    local path = city.path(r[1], r[2])
    local i = math.random(2, #path)
    local a, b = path[i - 1], path[i]
    local t = math.random()
    local x, z = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
    local d = U.dist2d(x, z, px, pz)
    local y = city.height_on(r[1], r[2], x, z)
    local yaw = math.atan(b[1] - a[1], b[2] - a[2])
    local rx, rz = U.right(yaw)
    x, z = x + rx * 3.2, z + rz * 3.2
    if d >= 60 and d <= 200 and not occupied(x, z) and not (py and y and math.abs(y - py) >= 4) and not unfair(x, y, z) then
      return x, z, yaw, y
    end
  end
end


-- Out of the station's yard onto the nearest road, if the station is close
-- enough to send a unit from.
local function station_exit(px, pz)
  if not (city.network() and city.has("police_station")) then return end
  local sx, sz = city.place("police_station")
  if U.dist2d(sx, sz, px, pz) > STATION_RANGE then return end
  local roadnet = require "lib.roadnet"
  local _, _, rx, rz = roadnet.nearest_edge(sx, sz)
  if occupied(rx, rz) or unfair(rx, nil, rz) then return end
  return rx, rz, math.atan(px - rx, pz - rz)
end

-- A unit on the street at (x, z) facing yaw: lights, siren, in P.cops.
local function add_unit(x, z, yaw, y, launch, mesh)
  local id = vehicle.spawn(x, z, yaw, nil, mesh, "cop", y)
  vehicle.headlights(id)
  local c = {id = id, stuck = 0, reverse = 0, launch = launch, is_pasi = (mesh == "pasi")}
  c.red = engine.spawn{mesh = "beacon", color = {1, 0.1, 0.1}}
  c.blue = engine.spawn{mesh = "beacon", color = {0.1, 0.2, 1}}
  c.siren = engine.play("siren", {loop = true, follow = id})
  P.cops[id] = c
  return id
end

local function spawn_cop()
  local px, _, pz = U.player_pos()
  local x, z, yaw, launch, y
  local stars = wanted.stars()
  local is_military_pasi = (stars >= 5 and math.random() < 0.6)

  -- 5-star military response: deploy from Pansio naval garrison gate if present on map
  if is_military_pasi and city.has and city.has("heist_start") then
    x, z, yaw = -348.4, 2583.1, 1.85
    launch = 45
  elseif px and P.count() >= 1 then
    local sx, sz, syaw = station_exit(px, pz)
    if sx and math.random() < 0.5 then -- rolled for only with a station in reach
      x, z, yaw = sx, sz, syaw
      launch = 30 -- seconds to get to the player before it may be recycled
    end
  end
  if not x then x, z, yaw, y, launch = spawn_point() end
  if not x then return end
  local mesh = (is_military_pasi and city.has and city.has("heist_start")) and "pasi" or "cop"
  return add_unit(x, z, yaw, y, launch, mesh)
end

-- ---- the convoy ------------------------------------------------------------
-- From CONVOY_STARS up, every CONVOY_EVERY s, CONVOY units come at once in a
-- column down one road, CONVOY_GAP m apart, CONVOY_NEAR to CONVOY_FAR m off
-- and heading the player's way, on top of COPS_PER_LEVEL. At five stars a
-- Pasi leads it.
local CONVOY_STARS, CONVOY_EVERY, CONVOY, CONVOY_GAP = 4, 40, 3, 11
local CONVOY_NEAR, CONVOY_FAR = 100, 220
local next_convoy = 0

-- The convoy's leader's spot and its road heading (a to b), or nil: a
-- stretch of road between bends long enough for the column, in range, on
-- the player's level, pointing their way, with nothing on it.
local function convoy_spot(px, py, pz)
  -- Junctions in range (one pass over the map), then their roads out.
  local near = {}
  for _, j in ipairs(city.junctions()) do
    local x, z = city.pos(j)
    local d = U.dist2d(x, z, px, pz)
    if d >= CONVOY_NEAR - 40 and d <= CONVOY_FAR + 40 then near[#near + 1] = j end
  end
  if #near == 0 then return end
  local need = CONVOY_GAP * (CONVOY - 1) + 6
  -- Every stretch long enough, tried in a random order (30 random draws
  -- missed now and then where there were good ones).
  local cands = {}
  for _, j in ipairs(near) do
    for _, n in ipairs(city.links(j) or {}) do
      local path = city.path(j, n)
      for i = 2, #path do
        if U.dist2d(path[i - 1][1], path[i - 1][2], path[i][1], path[i][2]) >= need + 4 then
          cands[#cands + 1] = {j, n, path[i - 1], path[i]}
        end
      end
    end
  end
  for k = #cands, 2, -1 do
    local m = math.random(k)
    cands[k], cands[m] = cands[m], cands[k]
  end
  for _, cand in ipairs(cands) do
    local j, n, a, b = cand[1], cand[2], cand[3], cand[4]
    local len = U.dist2d(a[1], a[2], b[1], b[2])
    local yaw = math.atan(b[1] - a[1], b[2] - a[2])
    local fx, fz = U.forward(yaw)
    local rx, rz = U.right(yaw)
    local lane = city.lane(j, n)
    -- The leader as far down the stretch as there's room behind it for.
    local along = need + math.random() * (len - need - 4)
    local x, z = a[1] + fx * along + rx * lane, a[2] + fz * along + rz * lane
    local d = U.dist2d(x, z, px, pz)
    local toward = ((px - x) * fx + (pz - z) * fz) / math.max(d, 1)
    local y = city.height_on(j, n, x, z)
    if d >= CONVOY_NEAR and d <= CONVOY_FAR and toward > 0.3
        and not (py and y and math.abs(y - py) >= 4) then
      local free = true
      for k = 0, CONVOY - 1 do
        if occupied(x - fx * CONVOY_GAP * k, z - fz * CONVOY_GAP * k) then free = false break end
      end
      if free then return x, z, yaw, {j, n} end
    end
  end
end

-- Send a convoy now, if there's room for it under the cap. Its units, or nil.
function P.convoy()
  local px, py, pz = U.player_pos()
  if not px or wanted.stars() < CONVOY_STARS then return end
  -- It comes on top of the level's usual units (at most once a convoy's worth).
  if P.count() > COPS_PER_LEVEL[wanted.stars()] then return end
  local x, z, yaw, r = convoy_spot(px, py, pz)
  if not x then return end
  local fx, fz = U.forward(yaw)
  local ids = {}
  for k = 0, CONVOY - 1 do
    local cx, cz = x - fx * CONVOY_GAP * k, z - fz * CONVOY_GAP * k
    local mesh = (k == 0 and wanted.stars() >= 5) and "pasi" or "cop"
    -- Time enough to get here from the far end before it may be recycled.
    ids[#ids + 1] = add_unit(cx, cz, yaw, city.height_on(r[1], r[2], cx, cz), 35, mesh)
    P.cops[ids[#ids]].convoy = true
  end
  engine.emit("convoy", #ids, wanted.stars())
  return ids
end

local function remove(id)
  local c = P.cops[id]
  if not c then return end
  engine.despawn(c.red)
  engine.despawn(c.blue)
  if c.siren then engine.stop(c.siren) end
  P.cops[id] = nil
end

function P.clear()
  for id in pairs(P.cops) do
    remove(id)
    engine.despawn(id)
  end
  for id in pairs(P.officers) do engine.despawn(id) end
  P.officers = {}
end

function P.officer_count()
  local n = 0
  for _ in pairs(P.officers) do n = n + 1 end
  return n
end

-- ---- perception ----------------------------------------------------------

local function sees_player(id)
  local target = G.vehicle or G.player
  if not target then return false end
  local x, y, z = engine.pos(id)
  local px, py, pz = engine.pos(target)
  local dx, dy, dz = px - x, py + 0.4 - (y + 1), pz - z
  local d = math.sqrt(dx * dx + dy * dy + dz * dz)
  if d > SIGHT then return false end
  -- People in the way don't hide you: a bystander next to the player kept
  -- a car of cops from ever seeing them (Raisio seed 8).
  local ox, oy, oz, left, skip = x, y + 1, z, d, id
  for _ = 1, 4 do
    local hit, t = engine.raycast(ox, oy, oz, dx, dy, dz, left, skip)
    if hit == nil or hit == target then return true end
    local tag = engine.tag(hit)
    if not (tag == "ped" or tag == "ped_down" or tag == "officer" or tag == "cyclist") then return false end
    t = t + 0.05
    ox, oy, oz, left, skip = ox + dx / d * t, oy + dy / d * t, oz + dz / d * t, left - t, hit
    if left <= 0 then return true end
  end
  return false
end

-- ---- driving -------------------------------------------------------------

-- Sight and driving must agree: ignoring a visible off-road target just
-- because it is 50-90m away sends cars searching away from it.
function P.direct_pursuit(sees, dist) return sees and dist < SIGHT end

-- On a map drawn as roads, a car out between junctions drives its own
-- road to whichever end is fewer roads from the goal, rather than heading
-- straight for the nearest junction (which may be across back gardens).
local function road_route(x, y, z, goal)
  local roadnet = require "lib.roadnet"
  local hops, queue = {[goal] = 0}, {goal} -- roads from each junction to the goal
  for _, q in ipairs(queue) do
    for _, nb in ipairs(city.links_in(q)) do
      if not hops[nb] then hops[nb] = hops[q] + 1; queue[#queue + 1] = nb end
    end
  end
  local e, i = roadnet.nearest_edge(x, z, nil, y)
  local E = roadnet.net().edges[e]
  local route = {}
  if E.oneway or (hops[E.b] or math.huge) <= (hops[E.a] or math.huge) then -- (a one-way street only on)
    for k = i, #E.pts do route[#route + 1] = E.pts[k] end
  else
    for k = i - 1, 1, -1 do route[#route + 1] = E.pts[k] end
  end
  return route
end

local function drive_cop(c, dt)
  local id = c.id
  local x, y, z = engine.pos(id)
  local px, py, pz = U.player_pos()
  local yaw = engine.yaw(id)
  local speed = vehicle.speed(id)
  local dist = U.dist2d(x, z, px, pz)
  local tx, tz, want

  local now = engine.time()
  local dash = (c.dash_until or 0) > now
  local direct = (P.direct_pursuit(c.sees, dist) or dash) and now >= (c.roads_until or 0)
  local lx, lz = wanted.center[1], wanted.center[2]
  local last = U.dist2d(x, z, lx, lz)
  if direct and not c.sees then
    -- Off the road after them, to where they were last seen (unhurried:
    -- across a park, a yard, round a block's corner).
    tx, tz = lx, lz
    want = math.min(14, math.max(0, last - 4) * 1.5)
  elseif direct then
    -- Direct pursuit, leading the target a little, and slowing in time to
    -- stop beside them rather than overshoot.
    local vx, _, vz = engine.vel(G.vehicle or G.player)
    tx, tz = px + vx * 0.4, pz + vz * 0.4
    want = math.min(30, math.max(0, dist - 4) * 1.5)
    -- After someone on foot, slow for whatever's in the way: at full tilt a
    -- cop drove into a parked car beside them and threw it onto them.
    if G.player then
      local fx, fz = U.forward(yaw)
      local hit, d = engine.raycast(x + fx * 2.5, y, z + fz * 2.5, fx, 0, fz, 16, id)
      if hit and hit ~= G.player and d < 8 then want = math.min(want, 4) end
    end
  elseif not c.sees and last < 30 and engine.time() >= (c.roads_until or 0) then
    -- Lost sight just short of them (behind a parked car, round a corner):
    -- creep up to where they were last seen, not off round the block.
    tx, tz = lx, lz
    want = math.min(10, math.max(0, last - 4) * 1.5)
  else
    -- Follow the roads one junction at a time toward the player if seen,
    -- otherwise toward the last sighting; once there, search nearby streets.
    -- A route may start out away from them, round water or a park.
    -- (Nearest at the same level: not the tunnel under a street, or the
    -- street over it.)
    local at = city.nearest(x, z, y)
    local gx, gy, gz = wanted.seen and px or wanted.center[1], wanted.seen and py or wanted.center[3],
                       wanted.seen and pz or wanted.center[2]
    local goal = city.nearest(gx, gz, gy)
    -- Off the road: head for the stretch of road nearest them, not just the
    -- nearest junction (which may be a block away), and on it, for the spot
    -- closest to them; from there, off the road after them (given up, as a
    -- direct chase is, after two jams).
    local on_it = false
    if city.network() then
      local roadnet = require "lib.roadnet"
      local net = roadnet.net()
      local te, _, sx, sz, off = roadnet.nearest_edge(gx, gz, nil, gy)
      if te and off > 12 then
        local E = net.edges[te]
        goal = (E.oneway or U.dist2d(x, z, city.pos(E.a)) <= U.dist2d(x, z, city.pos(E.b))) and E.a or E.b
        -- On that stretch: the nearest road to the car, or the car is on its
        -- end (at the junction, another road meeting there can be nearer).
        local beside = false
        for i = 2, #E.pts do
          local a, b = E.pts[i - 1], E.pts[i]
          local dx, dz = b[1] - a[1], b[2] - a[2]
          local l2 = math.max(dx * dx + dz * dz, 1e-6)
          local t = U.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / l2, 0, 1)
          if U.dist2d(x, z, a[1] + dx * t, a[2] + dz * t) < E.width / 2 + 4 then beside = true; break end
        end
        if beside or roadnet.nearest_edge(x, z, nil, y) == te then
          on_it = true
          c.goal, c.route, c.ri = {sx, sz}, {{sx, sz}}, 1
          if U.dist2d(x, z, sx, sz) < 12 and now >= (c.roads_until or 0) then c.dash_until = now + 10 end
        end
      end
    end
    if on_it then
      -- (Along this stretch to the spot nearest them.)
    elseif c.goal and U.dist2d(x, z, c.goal[1], c.goal[2]) < 9 and c.ri < #c.route then
      c.ri = c.ri + 1 -- round the next bend of this road
      c.goal = c.route[c.ri]
    elseif city.network() and (not c.goal or U.dist2d(x, z, c.goal[1], c.goal[2]) < 9)
        and U.dist2d(x, z, city.pos(at)) > 15 then
      c.route, c.ri = road_route(x, y, z, goal), 1
      c.goal = c.route[1]
    elseif not c.goal or U.dist2d(x, z, c.goal[1], c.goal[2]) < 9 then
      local from = at
      if at == goal then
        -- There: search a street nearby, every other time the one that
        -- passes nearest them. (At random, a cop on Harbor seed 5 went up
        -- and down the streets either side of a lot for 40 s, never along
        -- the one it faced.)
        local opts = city.links(at)
        c.searches = (c.searches or 0) + 1
        local pick = opts[math.random(math.max(1, #opts))]
        if c.searches % 2 == 1 then
          local ax, az = city.pos(at)
          local best = math.huge
          for _, o in ipairs(opts) do
            local bx, bz = city.pos(o)
            local dx, dz = bx - ax, bz - az
            local t = U.clamp(((gx - ax) * dx + (gz - az) * dz) / math.max(dx * dx + dz * dz, 1e-6), 0, 1)
            local d = U.dist2d(gx, gz, ax + dx * t, az + dz * t)
            if d < best then best, pick = d, o end
          end
        end
        at = pick or at
      else
        at = city.step_toward(at, goal)
      end
      -- Pick the road up at the bend after the stretch the car is on.
      c.route, c.ri, c.lane = city.path(from, at), 2, city.lane(from, at)
      local best = math.huge
      for i = 2, #c.route do
        local d = U.dist2d(x, z, c.route[i][1], c.route[i][2]) + U.dist2d(x, z, c.route[i - 1][1], c.route[i - 1][2])
        if d < best then best, c.ri = d, i end
      end
      c.goal = c.route[c.ri]
    end
    -- Drive in the right-hand lane, like traffic, so oncoming cars pass
    -- by; pull out into the other lane to overtake whatever's ahead in ours.
    local gx, gz = c.goal[1], c.goal[2]
    local rx, rz = U.right(math.atan(gx - x, gz - z))
    local fx, fz = U.forward(yaw)
    -- (At the car's own height: 0.8 m above sea level, on Turku's hills,
    -- went through the ground or over the traffic, and cops drove into it.)
    local hit, d = engine.raycast(x + fx * 2.5, y, z + fz * 2.5, fx, 0, fz, 16, id)
    local tag = hit and engine.tag(hit)
    if (tag == "car" or tag == "cop") and math.cos(U.angle_diff(yaw, engine.yaw(hit))) > 0.5 then c.overtake = 2 end
    -- On a road map, a parked or stuck car in the lane is passed too.
    if (tag == "car" or tag == "cop") and city.network() and math.abs(vehicle.speed(hit)) < 1 then c.overtake = 2 end
    c.overtake = math.max(0, (c.overtake or 0) - dt)
    local lane = (c.overtake > 0 and -1 or 1) * (c.lane or LANE)
    tx, tz = gx + rx * lane, gz + rz * lane
    -- Slow for the corner coming up at the next intersection, and for
    -- anything in the way.
    want = U.dist2d(x, z, gx, gz) < 22 and 13 or 30
    if hit and tag ~= "player" and d < 8 then want = math.min(want, 8) end
  end

  local diff = U.angle_diff(yaw, math.atan(tx - x, tz - z))
  local throttle = speed < want and 1 or (speed > want + 3 and -1 or 0)
  if math.abs(diff) > 1.1 and speed > 12 then throttle = -1 end
  local input = {throttle = throttle, steer = U.clamp(diff * 2.5, -1, 1), handbrake = math.abs(diff) > 0.9 and speed > 14}

  -- Wedged against something: back up with opposite lock for a second.
  c.stuck = (throttle > 0 and math.abs(speed) < 1.5) and c.stuck + dt or 0
  c.wedged = math.max(0, (c.wedged or 0) - dt / 8) -- recent jams, fading
  if c.stuck > 1.2 then
    c.reverse, c.stuck = 1.0, 0
    c.wedged = c.wedged + 1
    -- Repeated direct approaches into a fence or quay need a road detour.
    if direct then
      c.direct_jams = (c.direct_jams or 0) + 1
      if c.direct_jams >= 2 then c.roads_until, c.direct_jams, c.goal, c.dash_until = engine.time() + 6, 0, nil, nil end
    end
    -- Wedged again and again (a U-turn on a narrow street, a corner cut
    -- into a building): back up further, a proper three-point turn, and
    -- think again about the way. (On the grid maps too: a cop that cut a
    -- corner overtaking hit the same building for 40 s, Harbor seed 5.)
    c.jams = (c.jams or 0) + 1
    if c.jams >= 2 then c.reverse = 2.2 end
    -- Swung wide round a corner into a wall: back to the middle of the
    -- junction, where there's room, then on along the road.
    if c.jams == 2 and c.route then
      local jx, jz = city.pos(city.nearest(x, z, y))
      if U.dist2d(x, z, jx, jz) < 25 then
        table.insert(c.route, c.ri, {jx, jz})
        c.goal = c.route[c.ri]
      end
    end
    if c.jams >= 4 then c.goal, c.jams = nil, 0 end
  end
  if c.reverse > 0 then
    c.reverse = c.reverse - dt
    input = {throttle = -1, steer = -input.steer}
  end
  vehicle.drive(id, dt, input)
end

-- ---- officers on foot ----------------------------------------------------------
-- From two stars up, cops that catch up with you get out and shoot. At any
-- level, one stuck short of you gets out and walks over to arrest you.

local function deploy(c)
  c.deployed = true
  local x, y, z = engine.pos(c.id)
  local rx, _, rz = engine.right(c.id)
  for _, side in ipairs{-1, 1} do
    local id = engine.spawn{mesh = "officer", pos = {x + rx * side * 2.2, y + 0.4, z + rz * side * 2.2}, size = {0.7, 1.8, 0.7},
                            body = "dynamic", mass = 85, friction = 0, step = 0.45, lock_rotation = true, tag = "officer"}
    H.set(id, 60)
    P.officers[id] = {car = c.id, cool = 0.6 + math.random()}
  end
end

local function recall(c)
  c.deployed, c.arrest = false, nil
  for id, o in pairs(P.officers) do
    if o.car == c.id then
      engine.despawn(id)
      P.officers[id] = nil
    end
  end
end

local function officer_shoot(id, o)
  local target = G.vehicle or G.player
  local x, y, z = engine.pos(id)
  local tx, ty, tz = engine.pos(target)
  local d = U.dist2d(x, z, tx, tz)
  local vx, _, vz = engine.vel(target)
  local chance = U.clamp(0.65 - d / 55 - math.sqrt(vx * vx + vz * vz) * 0.02, 0.08, 0.65)
  local hit = math.random() < chance
  local ex, ey, ez = tx, ty + 0.3, tz
  if not hit then ex, ey, ez = tx + (math.random() - 0.5) * 3, ty + math.random() * 1.5, tz + (math.random() - 0.5) * 3 end
  local mx, my, mz = x, y + 0.5, z
  FX.flash(mx + (tx - x) / d * 0.6, my, mz + (tz - z) / d * 0.6, 0.25)
  FX.tracer(mx, my, mz, ex, ey, ez)
  engine.play("pistol", {pos = {x, y, z}, volume = 0.8})
  if hit then
    if G.vehicle then H.damage(G.vehicle, 5, id) else H.hurt_player(7, id) end
  end
end

local function run_officers(dt, px, pz)
  local seen, close = false, false
  for id, o in pairs(P.officers) do
    if not engine.exists(id) then
      P.officers[id] = nil
    else
      local x, _, z = engine.pos(id)
      local d = U.dist2d(x, z, px, pz)
      local sees = sees_player(id)
      seen = seen or sees
      local _, vy = engine.vel(id)
      local dx, dz = px - x, pz - z
      engine.set_yaw(id, math.atan(dx, dz))
      -- Below two stars they've only come to arrest you: no shooting.
      if sees and d < SHOOT_RANGE and d > 6 and wanted.stars() >= DEPLOY_STARS then
        -- Stand and shoot.
        engine.set_vel(id, 0, vy, 0)
        o.cool = o.cool - dt
        if o.cool <= 0 then
          o.cool = 0.9 + math.random() * 0.5
          officer_shoot(id, o)
        end
      elseif o.post then
        -- At a roadblock: stay behind the car.
        engine.set_vel(id, 0, vy, 0)
      else
        -- Close in (or come around the corner).
        local s = d > 2 and 5 or 0
        engine.set_vel(id, dx / (d + 1e-3) * s, vy, dz / (d + 1e-3) * s)
      end
      if d < 2.5 then close = true end
    end
  end
  return seen, close
end

engine.on("killed", function(id, by, dx, dy, dz)
  if not P.officers[id] then return end
  P.officers[id] = nil
  local body = H.ragdoll(id, "officer", dx, dy, dz, 5)
  require("systems.peds").down[body] = engine.time() + 12
  if by == G.player or by == G.vehicle then wanted.crime() end
end)

-- Run them over and they go down too.
engine.on("contact", function(a, b, speed)
  local o, other
  if P.officers[a] then o, other = a, b elseif P.officers[b] then o, other = b, a else return end
  local tag = engine.tag(other)
  -- A squad car's driver doesn't run down their own (unless it's you at
  -- the wheel): arriving cars nudged deployed officers to death.
  if tag == "cop" and other ~= G.vehicle then return end
  if (tag == "car" or tag == "cop") and speed > 4 then
    local vx, vy, vz = engine.vel(other)
    H.damage(o, 200, other, vx, vy, vz)
  end
end)

-- ---- roadblocks ----------------------------------------------------------
-- From three stars up, now and then, two squad cars park across the road
-- ahead of you, 110-220 m on, with officers posted behind them. Ram through
-- or turn off; once you're past (or gone another way), they join the chase.

local BLOCK_STARS, BLOCK_EVERY = 3, 30
local next_block = 0

-- The junction ahead of a car going (fx, fz) from (x, z): the nearest one
-- within 60 degrees of straight on.
local function junction_ahead(x, z, fx, fz, y)
  local best, bd
  for _, j in ipairs(city.junctions()) do
    local jx, jz = city.pos(j)
    local dx, dz = jx - x, jz - z
    local d = math.sqrt(dx * dx + dz * dz)
    local ly = city.level(j)
    if d > 5 and d < 250 and (dx * fx + dz * fz) / d > 0.5 and (bd == nil or d < bd)
       and not (y and ly and math.abs(ly - y) > 4) then
      best, bd = j, d
    end
  end
  return best, bd
end

-- Where a block goes: on the way straight on from the junction ahead, as
-- x, z, the road's heading there, its height (nil on the ground), and the
-- half-width of what to block; nil if there's no such road in range.
function P.block_spot(x, z, fx, fz, y)
  local j, d = junction_ahead(x, z, fx, fz, y)
  if not j then return end
  local hx, hz = fx, fz
  for _ = 1, 8 do
    -- Straight on from j: the road leaving it closest to the heading.
    local jx, jz = city.pos(j)
    local best, bdot, bpath
    for _, n in ipairs(city.links(j) or {}) do
      local path = city.path(j, n)
      local p = path[2]
      local dx, dz = p[1] - jx, p[2] - jz
      local l = math.sqrt(dx * dx + dz * dz)
      if l > 1 and (dx * hx + dz * hz) / l > (bdot or 0.6) then best, bdot, bpath = n, (dx * hx + dz * hz) / l, path end
    end
    if not best then return end
    -- 25 m along it (half way on a short one).
    local len = 0
    for i = 2, #bpath do len = len + U.dist2d(bpath[i - 1][1], bpath[i - 1][2], bpath[i][1], bpath[i][2]) end
    local want = math.min(25, len / 2)
    if d + want >= 110 then
      if d + want > 220 or len < 24 then return end
      for i = 2, #bpath do
        local a, b = bpath[i - 1], bpath[i]
        local l = U.dist2d(a[1], a[2], b[1], b[2])
        if want <= l then
          local t = want / l
          local bx, bz = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
          local by = city.height_on(j, best, bx, bz)
          local net = city.network() and require("lib.roadnet").net()
          local e = net and net.edges[net.edge_of[j .. ">" .. best] or 0]
          local half = e and e.width / 2 or 6
          return bx, bz, math.atan(b[1] - a[1], b[2] - a[2]), by, half
        end
        want = want - l
      end
      return
    end
    -- Not far enough yet: on through the next junction.
    local bx, bz = city.pos(best)
    local dx, dz = bx - jx, bz - jz
    local l = math.sqrt(dx * dx + dz * dz)
    hx, hz = dx / l, dz / l
    d, j = d + len, best
  end
end

function P.place_block(bx, bz, yaw, by, half)
  -- Clear the spot of traffic (it's far off, round the bend ahead).
  for _, id in ipairs(engine.find("car")) do
    local x, _, z = engine.pos(id)
    if id ~= G.vehicle and U.dist2d(x, z, bx, bz) < half + 8 then engine.despawn(id) end
  end
  local fx, fz = U.forward(yaw)
  local rx, rz = U.right(yaw)
  -- Cars side by side across the road, turned a little each way and
  -- staggered so none touches the next (a car spans 4.7 m across it): two
  -- on a street (their ends on the kerbs), up to four on a wide avenue.
  local STEP = 4.9
  local n = U.clamp(math.floor((half * 2 + 1.5) / STEP), 2, 4)
  for k = 1, n do
    local side = k % 2 == 0 and 1 or -1
    local o = (k - (n + 1) / 2) * STEP
    local x, z = bx + rx * o + fx * side * 0.9, bz + rz * o + fz * side * 0.9
    local cyaw = yaw + math.pi / 2 + side * 0.2
    local id = vehicle.spawn(x, z, cyaw, nil, "cop", "cop", by)
    vehicle.headlights(id)
    local c = {id = id, stuck = 0, reverse = 0, block = {bx, bz, fx, fz}, deployed = true, launch = 45}
    c.red = engine.spawn{mesh = "beacon", color = {1, 0.1, 0.1}}
    c.blue = engine.spawn{mesh = "beacon", color = {0.1, 0.2, 1}}
    P.cops[id] = c
    -- An officer stands behind each of the outer two, on the far side from you.
    if k ~= 1 and k ~= n then goto next end
    local ox, oz = x + fx * 4, z + fz * 4
    local oid = engine.spawn{mesh = "officer", pos = {ox, (by or U.ground(ox, oz)) + 1.3, oz}, size = {0.7, 1.8, 0.7},
                             body = "dynamic", mass = 85, friction = 0, step = 0.45, lock_rotation = true, tag = "officer"}
    H.set(oid, 60)
    P.officers[oid] = {car = id, cool = 1, post = true}
    ::next::
  end
  local street = city.street(bx, bz)
  U.message("ROADBLOCK AHEAD" .. (street and (" ON " .. street:upper()) or ""), 3)
  engine.emit("roadblock", bx, bz)
end

local function blocks()
  local n = 0
  for _, c in pairs(P.cops) do if c.block then n = n + 1 end end
  return n
end

local function roadblocks(px, py, pz)
  if wanted.stars() < BLOCK_STARS or not G.vehicle or engine.time() < next_block or blocks() > 0 then return end
  local v = vehicle.speed(G.vehicle)
  if v < 8 then return end
  next_block = engine.time() + BLOCK_EVERY
  local fx, fz = U.forward(engine.yaw(G.vehicle))
  local bx, bz, yaw, by, half = P.block_spot(px, pz, fx, fz, py)
  if not bx then return end
  -- Facing the way you're going: the road may run either way from there.
  local rfx, rfz = U.forward(yaw)
  if rfx * fx + rfz * fz < 0 then yaw = yaw + math.pi end
  P.place_block(bx, bz, yaw, by, half)
end

-- A block holds until you're past it, or gone another way.
local function hold_block(c, px, pz)
  local b = c.block
  local ahead = (b[1] - px) * b[3] + (b[2] - pz) * b[4]
  local d = U.dist2d(b[1], b[2], px, pz)
  if ahead < -15 or d > 260 or engine.time() > (c.held_until or math.huge) then
    c.block = nil
    for _, o in pairs(P.officers) do if o.car == c.id then o.post = nil end end
    if c.siren == nil then c.siren = engine.play("siren", {loop = true, follow = c.id}) end
    return
  end
  if d < 30 then c.held_until = c.held_until or engine.time() + 8 end -- you stopped there: they come for you
end

-- ---- the loop ------------------------------------------------------------



local function busted()
  local fine = math.min(G.cash, 100 + math.floor(G.cash * 0.1))
  G.cash = G.cash - fine
  engine.emit("busted", fine)
  wanted.clear()
  P.clear()
  -- Released on foot outside the station: the map's police station, or the
  -- start of the game.
  if G.vehicle then
    engine.set_vel(G.vehicle, 0, 0, 0)
    G.vehicle = nil
  elseif G.player then
    engine.despawn(G.player)
  end
  if city.has("police_station") then
    local sx, sz = city.place("police_station")
    require("lib.player").spawn(sx, 1.2 + U.ground(sx, sz + 5), sz + 5, 0)
  else
    require("lib.player").spawn(G.spawn[1], G.spawn[2], G.spawn[3], 0)
  end
  U.message("BUSTED", 4)
  U.message(string.format("-$%d", fine), 4)
  busted_for = 0
end

engine.on("tick", function(dt)
  -- Cops that are gone, wrecked, or far away get recycled.
  local px, py, pz = U.player_pos()
  if not px then return end
  for id, c in pairs(P.cops) do
    local x, _, z = engine.pos(id)
    local wrecked = not engine.exists(id) or vehicle.upside_down(id)
    c.wrecked_for = wrecked and (c.wrecked_for or 0) + dt or 0
    c.launch = c.launch and c.launch > 0 and c.launch - dt or nil
    -- (Not while its crew is out of it: see below.)
    if not x or (c.wrecked_for > 3 and not c.deployed) or (U.dist2d(x, z, px, pz) > 170 and not c.launch) then
      remove(id)
      if x then engine.despawn(id) end
      -- Left behind (or wrecked): a breather before the next one turns up,
      -- so getting away from one is worth something.
      spawn_timer = math.max(spawn_timer, RESPAWN_AFTER)
    end
  end

  if wanted.stars() == 0 then
    -- Off duty: idle, and leave once out of sight.
    for id, o in pairs(P.officers) do
      local x, _, z = engine.pos(id)
      if not x or U.dist2d(x, z, px, pz) > 50 then
        if x then engine.despawn(id) end
        P.officers[id] = nil
      end
    end
    for id, c in pairs(P.cops) do
      local x, _, z = engine.pos(id)
      vehicle.drive(id, dt, {throttle = 0})
      if U.dist2d(x, z, px, pz) > 60 then
        remove(id)
        engine.despawn(id)
      end
    end
    return
  end

  -- Keep the right number of units on the street.
  spawn_timer = spawn_timer - dt
  if wanted.stars() >= CONVOY_STARS and engine.time() >= next_convoy then
    -- (Tried again in a few seconds if there's no room or no road for it.)
    next_convoy = engine.time() + (P.convoy() and CONVOY_EVERY or 3)
  end
  if spawn_timer <= 0 and P.count() < COPS_PER_LEVEL[wanted.stars()] then
    spawn_timer = 1.5
    spawn_cop()
  end

  roadblocks(px, py, pz)
  local seen, close = run_officers(dt, px, pz)
  -- An officer may just have killed the player; nothing more to chase this tick.
  if not (G.player or G.vehicle) then return end
  local slow_player = G.player ~= nil or math.abs(vehicle.speed(G.vehicle)) < 4
  for id, c in pairs(P.cops) do
    if c.block then hold_block(c, px, pz) end
    c.siren = c.siren or (not c.block and engine.play("siren", {loop = true, follow = id})) or nil
    c.sees = sees_player(id)
    seen = seen or c.sees
    local x, _, z = engine.pos(id)
    local d = U.dist2d(x, z, px, pz)
    if c.deployed then
      vehicle.drive(id, dt, {throttle = 0, handbrake = true})
      local crew = false
      for oid, o in pairs(P.officers) do
        if o.car == id and engine.exists(oid) then crew = true break end
      end
      if c.block then -- held across the road (hold_block lets it go)
      elseif d > 60 or wanted.stars() == 0 or (wanted.stars() < DEPLOY_STARS and not c.arrest) then recall(c)
      elseif crew then c.redeploy = nil
      elseif not c.redeploy then c.redeploy = engine.time() + 5 -- its officers are down: a fresh pair soon
      elseif engine.time() >= c.redeploy and c.sees and d < DEPLOY_RANGE then
        c.redeploy = nil
        deploy(c)
      end
    else
      drive_cop(c, dt)
      if wanted.stars() >= DEPLOY_STARS and c.sees and d < DEPLOY_RANGE and slow_player then deploy(c)
      -- Jammed again and again just short of you (round a corner, against a
      -- wall), or close for seconds without getting to you: at any level
      -- they get out and walk over to arrest you.
      elseif ((c.wedged or 0) >= 1.5 and d < 30 or (c.near_for or 0) > 4) and slow_player then
        c.arrest, c.wedged, c.near_for = true, 0, 0
        deploy(c)
      -- Rolled over near you (into a tree or a lamp post at speed): they
      -- climb out and come for you on foot. Left to be recycled, the next
      -- car was a minute off, and rolled over in the same place (Harbor
      -- seed 2 on CI, every time).
      elseif (c.wrecked_for or 0) > 1 and engine.exists(id) and d < 40 and slow_player then
        c.arrest = true
        deploy(c)
      end
      -- How long it has been close to you without getting to you.
      c.near_for = (d < 22 and slow_player) and (c.near_for or 0) + dt or 0
      if d < 7 and math.abs(vehicle.speed(id)) < 6 then close = true end
    end
  end

  -- The helicopter keeps you in sight wherever the sky is open over you.
  local heli = package.loaded["systems.heli"]
  if heli and heli.sees() then seen = true end

  -- Evasion: out of sight and outside the search circle for a while, longer
  -- the more stars (see wanted.escape_time).
  if seen then
    wanted.seen, wanted.unseen_for, wanted.center = true, 0, {px, pz, py}
  elseif wanted.unseen(dt, px, pz) then
    U.message("LOST THE COPS", 3)
    return
  end

  -- Busted: stopped (or on foot) right next to a cop.
  local slow = G.player ~= nil or math.abs(vehicle.speed(G.vehicle)) < 2
  busted_for = (close and slow) and busted_for + dt or 0
  if busted_for > 1.5 then busted() end
end)

-- Stealing a cop car is its own crime.
engine.on("vehicle_enter", function(id)
  if P.cops[id] then
    remove(id)
    engine.set_visible(id, true)
    wanted.add(1)
  end
end)

engine.on("wanted_changed", function(new)
  if new == 0 then
    for _, c in pairs(P.cops) do if c.siren then engine.stop(c.siren) end c.siren = nil end
  end
end)

-- Light bars ride on the roof and alternate red/blue.
engine.on("frame", function()
  local on = math.floor(engine.time() * 6) % 2 == 0
  local active = wanted.stars() > 0
  for id, c in pairs(P.cops) do
    -- A car blown up this tick is only dropped from P.cops on the next one.
    if not engine.exists(id) then goto continue end
    local x, y, z = engine.pos(id)
    local ux, uy, uz = engine.up(id)
    local rx, ry, rz = engine.right(id)
    local fx, fy, fz = engine.forward(id)
    local qx, qy, qz, qw = engine.rot(id)
    for side, light in pairs{[1] = c.red, [-1] = c.blue} do
      local s = side * 0.3
      engine.set_pos(light, x + ux * 0.8 + rx * s - fx * 0.3, y + uy * 0.8 + ry * s - fy * 0.3, z + uz * 0.8 + rz * s - fz * 0.3)
      engine.set_rot(light, qx, qy, qz, qw)
      local lit = active and (on == (side == 1))
      local k = lit and 1 or 0.25
      if side == 1 then engine.set_color(light, k, 0.1 * k, 0.1 * k) else engine.set_color(light, 0.1 * k, 0.2 * k, k) end
    end
    ::continue::
  end
end)

-- Blips and the search circle on the minimap.
engine.on("minimap", function(map)
  local blink = math.floor(engine.time() * 4) % 2 == 0
  for id in pairs(P.cops) do
    if engine.exists(id) then
      local x, _, z = engine.pos(id)
      local mx, my = map(x, z)
      engine.rect(mx - 2.5, my - 2.5, 5, 5, blink and 1 or 0.2, 0.1, blink and 0.2 or 1, 1)
    end
  end
  if wanted.stars() > 0 then
    local r = wanted.radius()
    for k = 0, 47 do
      local a = k / 48 * math.pi * 2
      local mx, my = map(wanted.center[1] + math.cos(a) * r, wanted.center[2] + math.sin(a) * r)
      engine.rect(mx - 1, my - 1, 2, 2, 1, 0.3, 0.3, wanted.seen and 0.9 or 0.5)
    end
  end
end)

return P
