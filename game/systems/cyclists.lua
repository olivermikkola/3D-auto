-- Cyclists: people on bikes riding the map's cycle paths near the player,
-- fewer at night. At a path's end they go on along the next one that starts
-- there, or turn back. They slow for whatever is ahead of them, and a car
-- that hits one knocks the rider off: a crime, like running anyone over.
local U = require "lib.util"
local G = require "lib.state"
local city = require "lib.city"
local quality = require "lib.quality"
local roadnet = require "lib.roadnet"

local C = {riders = {}, routes = {}}
C.MOST = {4, 9, 14}        -- riders about, by quality tier
C.NEAR, C.FAR = 150, 190   -- m: they start within NEAR of the player and go beyond FAR
C.APPEAR = 60              -- m: not closer than this (they'd pop up in view)
C.SPEED = {4.2, 6.5}       -- m/s, slowest and fastest
local CELL = 100           -- m: routes by CELL square, to find the ones near the player
local LINK = 12           -- m: a path passing this near another's end goes on from it (across a street, say)
local VARIANTS = 8
local AHEAD = {ped = true, car = true, cop = true, player = true, cyclist = true, officer = true} -- what they slow for

local SKINS = {{0.95, 0.8, 0.65}, {0.85, 0.65, 0.5}, {0.6, 0.42, 0.3}, {0.4, 0.28, 0.2}}
local SHIRTS = {{0.8, 0.2, 0.2}, {0.2, 0.4, 0.8}, {0.9, 0.8, 0.3}, {0.3, 0.6, 0.35}, {0.15, 0.15, 0.15}, {0.9, 0.9, 0.9}, {0.6, 0.3, 0.6}, {0.9, 0.5, 0.2}}
local PANTS = {{0.15, 0.2, 0.4}, {0.25, 0.25, 0.25}, {0.5, 0.4, 0.3}, {0.1, 0.1, 0.1}}
local HAIR = {{0.1, 0.07, 0.04}, {0.45, 0.3, 0.12}, {0.8, 0.7, 0.4}, {0.5, 0.5, 0.5}}
local FRAMES = {{0.1, 0.1, 0.1}, {0.55, 0.1, 0.1}, {0.15, 0.3, 0.55}, {0.85, 0.85, 0.85}, {0.2, 0.4, 0.25}}

local function peds() return require "systems.peds" end

-- Their own random numbers, so riders coming and going don't change what
-- the traffic, the walkers and the missions draw.
local seed = 1990
local function rand(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  local r = seed / 2147483648
  return n and math.floor(r * n) + 1 or r
end

-- A bike, its wheels in line along +z, with or without its rider (body
-- centre at 0: feet would be at -0.9).
local function bike_parts(frame)
  local tyre, metal = {0.08, 0.08, 0.08}, {0.6, 0.6, 0.62}
  return {
    {mesh = "cylinder", pos = {0, -0.56, 0.52}, size = {0.68, 0.06, 0.68}, roll = math.pi / 2, color = tyre},
    {mesh = "cylinder", pos = {0, -0.56, -0.52}, size = {0.68, 0.06, 0.68}, roll = math.pi / 2, color = tyre},
    {mesh = "cube", pos = {0, -0.42, 0}, size = {0.05, 0.05, 0.9}, color = frame},              -- down tube
    {mesh = "cube", pos = {0, -0.2, 0.05}, size = {0.05, 0.05, 0.75}, pitch = -0.35, color = frame}, -- top tube
    {mesh = "cube", pos = {0, -0.3, -0.25}, size = {0.05, 0.5, 0.05}, color = frame},           -- seat tube
    {mesh = "cube", pos = {0, -0.3, 0.45}, size = {0.05, 0.55, 0.05}, pitch = 0.3, color = frame}, -- fork
    {mesh = "cube", pos = {0, 0.0, 0.38}, size = {0.55, 0.04, 0.04}, color = metal},            -- handlebar
    {mesh = "cube", pos = {0, -0.03, -0.27}, size = {0.16, 0.05, 0.24}, color = {0.1, 0.1, 0.1}}, -- saddle
  }
end

local function rider_mesh(name, frame, shirt, pants, skin, hair)
  local parts = bike_parts(frame)
  for _, p in ipairs{
    {mesh = "cube", pos = {0.13, -0.25, -0.02}, size = {0.17, 0.55, 0.17}, pitch = 0.5, color = pants},  -- legs to the pedals
    {mesh = "cube", pos = {-0.13, -0.32, -0.08}, size = {0.17, 0.55, 0.17}, pitch = -0.2, color = pants},
    {mesh = "cube", pos = {0, 0.32, -0.12}, size = {0.5, 0.64, 0.3}, pitch = 0.35, color = shirt},     -- leaning on
    {mesh = "cube", pos = {0.25, 0.22, 0.14}, size = {0.12, 0.12, 0.5}, pitch = 0.6, color = shirt},   -- arms to the bar
    {mesh = "cube", pos = {-0.25, 0.22, 0.14}, size = {0.12, 0.12, 0.5}, pitch = 0.6, color = shirt},
    {mesh = "sphere", pos = {0, 0.78, 0.04}, size = 0.32, color = skin},
    {mesh = "cube", pos = {0, 0.87, 0.01}, size = {0.34, 0.11, 0.34}, color = hair},
  } do parts[#parts + 1] = p end
  engine.mesh(name, parts)
end

local function cell(x, z) return math.floor(x / CELL) .. "," .. math.floor(z / CELL) end

function C.build()
  C.routes, C.cells, C.riders = {}, {}, {}
  local function pick(t, i) return t[i % #t + 1] end
  -- You on a bike you've taken (lib/vehicle's "bike").
  rider_mesh("cyclist_you", FRAMES[1], {0.22, 0.26, 0.32}, {0.15, 0.2, 0.4}, SKINS[1], HAIR[1])
  for i = 1, VARIANTS do
    rider_mesh("cyclist" .. i, pick(FRAMES, i * 3), pick(SHIRTS, i * 5), pick(PANTS, i), pick(SKINS, i * 7), pick(HAIR, i * 3))
    engine.mesh("bike" .. i, bike_parts(pick(FRAMES, i * 3)))
  end
  -- The cycle paths (3 m wide in the import), each a run of points.
  local corners = {} -- every path point by LINK square
  for _, p in ipairs(city.map().paved or {}) do
    if p.path and p[1] >= 3 and #p >= 4 then
      local pts, len = {}, 0
      for i = 3, #p do
        pts[#pts + 1] = p[i]
        if i > 3 then len = len + U.dist2d(p[i - 1][1], p[i - 1][2], p[i][1], p[i][2]) end
      end
      if len > 8 then
        local r = {pts = pts, len = len, links = {{}, {}}}
        C.routes[#C.routes + 1] = r
        for i = 2, #pts do
          local k = cell((pts[i - 1][1] + pts[i][1]) / 2, (pts[i - 1][2] + pts[i][2]) / 2)
          C.cells[k] = C.cells[k] or {}
          if C.cells[k][#C.cells[k]] ~= r then table.insert(C.cells[k], r) end
        end
        for i, q in ipairs(pts) do
          local k = math.floor(q[1] / LINK) .. "," .. math.floor(q[2] / LINK)
          corners[k] = corners[k] or {}
          table.insert(corners[k], {r, i, q})
        end
      end
    end
  end
  -- Which paths go on from each end: any other that passes near it, at
  -- its end or along it.
  for _, r in ipairs(C.routes) do
    for side, q in ipairs{r.pts[1], r.pts[#r.pts]} do
      local ci, cj = math.floor(q[1] / LINK), math.floor(q[2] / LINK)
      local seen = {}
      for i = ci - 1, ci + 1 do
        for j = cj - 1, cj + 1 do
          for _, o in ipairs(corners[i .. "," .. j] or {}) do
            if o[1] ~= r and not seen[o[1]] and U.dist2d(q[1], q[2], o[3][1], o[3][2]) < LINK then
              seen[o[1]] = true
              table.insert(r.links[side], o)
            end
          end
        end
      end
    end
  end
  C.paths = #C.routes
end

-- How many at this hour, of the most: all by day, a quarter late at night.
function C.busy(hour)
  if hour >= 7 and hour < 21 then return 1 end
  if hour >= 23 or hour < 5 then return 0.25 end
  return 0.6
end

function C.count()
  local n = 0
  for _ in pairs(C.riders) do n = n + 1 end
  return n
end

-- Head for point i of the rider's route.
local function aim(c, i)
  c.i = i
  local q = c.r.pts[i]
  c.tx, c.tz = q[1], q[2]
end

-- At the end of its path: on along one that goes on from here, or back at
-- a dead end.
local function path_end(c)
  local side = c.dir > 0 and 2 or 1
  local links = c.r.links[side]
  if #links > 0 then
    local o = links[rand(#links)]
    c.r = o[1]
    -- Into it at that point, whichever way it has more of (or either, by chance).
    local n = #c.r.pts
    if o[2] == 1 then c.dir = 1
    elseif o[2] == n then c.dir = -1
    else c.dir = rand() < 0.5 and 1 or -1 end
    -- (Over to where it joins first: across a street, say.)
    aim(c, o[2])
    c.joining = true
  else
    c.turns = (c.turns or 0) + 1
    c.dir = -c.dir
    aim(c, U.clamp(c.i + c.dir, 1, #c.r.pts))
  end
end

local function spawn(px, pz, still)
  -- A path near the player and a point on it out of sight.
  local ci, cj = math.floor(px / CELL), math.floor(pz / CELL)
  local reach = math.ceil(C.NEAR / CELL)
  local i, j = ci + rand(2 * reach + 1) - reach - 1, cj + rand(2 * reach + 1) - reach - 1
  local list = C.cells[i .. "," .. j]
  if not list then return end
  local r = list[rand(#list)]
  local k = rand(#r.pts - 1) + 1
  local a, b = r.pts[k - 1], r.pts[k]
  local t = rand()
  local x, z = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
  local d = U.dist2d(x, z, px, pz)
  -- (A still picture: close to its camera, where they'll be in it.)
  if d > (still and 45 or C.NEAR) or (d < C.APPEAR and not still) or roadnet.wet(x, z) then return end
  local y = U.ground(x, z)
  -- Nothing standing there.
  local hit = engine.raycast(x, y + 3, z, 0, -1, 0, 2.8)
  if hit and (AHEAD[engine.tag(hit)] or engine.tag(hit) == "prop") then return end
  local dir = rand() < 0.5 and 1 or -1
  local n = rand(VARIANTS)
  local yaw = dir > 0 and math.atan(b[1] - a[1], b[2] - a[2]) or math.atan(a[1] - b[1], a[2] - b[2])
  local id = engine.spawn{mesh = "cyclist" .. n, pos = {x, y + 1.0, z}, yaw = yaw, size = {0.6, 1.8, 1.7},
                          body = "dynamic", mass = 85, friction = 0, step = 0.3, lock_rotation = true, tag = "cyclist"}
  require("lib.health").set(id, 30)
  local c = {id = id, r = r, dir = dir, n = n, speed = C.SPEED[1] + rand() * (C.SPEED[2] - C.SPEED[1]), stuck = 0, slow = 0}
  aim(c, dir > 0 and k or k - 1)
  C.riders[id] = c
  return id
end

local function remove(id)
  C.riders[id] = nil
  engine.despawn(id)
end

-- Off the bike: the rider tumbles one way and the bike another.
local function fall(id, vx, vy, vz, by, keep_bike)
  local c = C.riders[id]
  if not c then return end
  C.riders[id] = nil
  local x, y, z = engine.pos(id)
  local yaw = engine.yaw(id)
  engine.despawn(id)
  local P = peds()
  local body = engine.spawn{mesh = "ped" .. c.n, pos = {x, y + 0.4, z}, yaw = yaw, size = {0.7, 1.8, 0.7},
                            body = "dynamic", mass = 70, friction = 0.8, tag = "ped_down"}
  engine.set_vel(body, vx * 0.9, math.max(vy, 0) + 3, vz * 0.9)
  engine.set_angvel(body, (rand() - 0.5) * 8, (rand() - 0.5) * 4, (rand() - 0.5) * 8)
  P.down[body] = engine.time() + 12
  engine.emit("ped_down", body, by)
  if keep_bike then return x, y, z, yaw end
  local bike = engine.spawn{mesh = "bike" .. c.n, pos = {x, y - 0.3, z}, yaw = yaw, size = {0.4, 1.0, 1.6},
                            body = "dynamic", mass = 15, friction = 0.8, tag = "fallen_bike"}
  engine.set_vel(bike, vx * 0.6, 1.5, vz * 0.6)
  engine.set_angvel(bike, 0, (rand() - 0.5) * 3, 4 + rand() * 4)
  P.down[bike] = engine.time() + 20
end

-- Taking a bike (lib/player's enter): pull a rider within reach off theirs,
-- or pick up one lying where its rider was knocked off. Returns the bike,
-- now yours to ride (lib/vehicle's "bike"), or nil.
function C.take(x, y, z)
  local vehicle = require "lib.vehicle"
  local id, d = engine.nearest(x, y, z, 3, "cyclist")
  if id and C.riders[id] then
    local rx, rz = U.right(engine.yaw(id))
    local bx, by, bz, yaw = fall(id, -rx * 2, 0, -rz * 2, G.player, true)
    return vehicle.spawn(bx, bz, yaw, nil, nil, "bike", by - 1.0)
  end
  local fb = engine.nearest(x, y, z, 2.5, "fallen_bike")
  if fb then
    local bx, by, bz = engine.pos(fb)
    local yaw = engine.yaw(fb)
    peds().down[fb] = nil
    engine.despawn(fb)
    return vehicle.spawn(bx, bz, yaw, nil, nil, "bike")
  end
end

engine.on("contact", function(a, b, speed)
  local id, other
  if C.riders[a] then id, other = a, b elseif C.riders[b] then id, other = b, a else return end
  local tag = engine.tag(other)
  if (tag == "car" or tag == "cop") and speed > 4 then
    local vx, vy, vz = engine.vel(other)
    fall(id, vx, vy, vz, other)
  end
end)

engine.on("killed", function(id, by, dx, dy, dz)
  if not C.riders[id] then return end
  local l = math.sqrt(dx * dx + dy * dy + dz * dz) + 1e-3
  fall(id, dx / l * 4, 0, dz / l * 4, by)
end)

local function ride(id, c, dt)
  local x, y, z = engine.pos(id)
  local _, vy = engine.vel(id)
  local dx, dz = c.tx - x, c.tz - z
  local d = math.sqrt(dx * dx + dz * dz)
  if d < 1.5 then
    c.joining = nil
    local nxt = c.i + c.dir
    if nxt < 1 or nxt > #c.r.pts then path_end(c) else aim(c, nxt) end
    dx, dz = c.tx - x, c.tz - z
    d = math.sqrt(dx * dx + dz * dz)
  end
  if d < 1e-3 then return end
  local fx, fz = dx / d, dz / d
  -- Slow for whatever is in front: someone walking, a car across the path.
  local want = c.speed
  local hit, at = engine.raycast(x + fx * 1.0, y, z + fz * 1.0, fx, 0, fz, 6, id)
  if hit and AHEAD[engine.tag(hit)] then
    want = at < 2.5 and 0 or c.speed * (at - 2.5) / 3.5
    c.slow = c.slow + dt
  else
    c.slow = 0
  end
  -- Held up for long: turn back the way they came.
  if c.slow > 6 then
    c.held = (c.held or 0) + 1
    c.slow, c.dir = 0, -c.dir
    aim(c, U.clamp(c.i + c.dir, 1, #c.r.pts))
  end
  engine.set_vel(id, fx * want, vy, fz * want)
  local yaw = engine.yaw(id)
  engine.set_yaw(id, yaw + U.angle_diff(yaw, math.atan(fx, fz)) * math.min(1, dt * 6))
  -- Not getting anywhere though nothing is in the way (a kerb, a fence):
  -- the same.
  local vx, _, vz = engine.vel(id)
  if want > 1 and vx * vx + vz * vz < 0.25 then c.stuck = c.stuck + dt else c.stuck = 0 end
  return c.stuck > 8 or y < U.ground(x, z) - 3
end

local top_up = 0
engine.on("tick", function(dt)
  if not C.cells or engine.ticks() < 2 then return end
  local still = os.getenv("SHOT_CAM")
  local px, _, pz = U.player_pos()
  if still then px, pz = still:match("^([^,]+),[^,]+,([^,]+)") end
  px, pz = tonumber(px), tonumber(pz)
  if not px then return end
  for id, c in pairs(C.riders) do
    if not engine.exists(id) then C.riders[id] = nil
    elseif ride(id, c, dt) then remove(id)
    end
  end
  top_up = top_up - dt
  if top_up > 0 then return end
  top_up = 0.5
  for id in pairs(C.riders) do
    local x, _, z = engine.pos(id)
    if U.dist2d(x, z, px, pz) > C.FAR then remove(id) break end
  end
  -- (A test holding the crowd still holds the riders too.)
  if peds().hold then return end
  local want = math.floor(quality.pick(C.MOST) * C.busy(require("lib.daynight").hour) + 0.5)
  -- (A still picture has a few frames: everyone at once.)
  for _ = 1, still and 60 or 4 do
    if C.count() >= want then break end
    spawn(px, pz, still)
  end
end)

return C
