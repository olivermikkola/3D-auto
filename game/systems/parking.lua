-- Cars parked by the kerb on the streets that have a parking lane
-- (OpenStreetMap parking:* tags; tools/osm_import.py widened those streets
-- by it where the buildings left room, and city.lane keeps traffic inside
-- it). One every SLOT m, some gaps, none by a junction, a crossing, a
-- traffic light, a bus stop or a place the game parks its own vehicles.
--
-- They stand still (static) until you get in one, or hit one hard enough
-- to shove it: then it's a car like any other.
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local pois = require "lib.pois"
local quality = require "lib.quality"
local vehicle = require "lib.vehicle"
local prefabs = require "lib.prefabs"

local P = {list = {}} -- list: id -> {x, z, yaw, mesh}

local SLOT = 6.2          -- kerb length per car (m)
local FILL = {0, 55, 80}  -- per cent of the slots taken, by quality tier
local CLEAR_END = 14      -- none this near a junction, past its stop line
local CLEAR_STOP = 16     -- nor a bus stop (the bus pulls in there)
local CLEAR_CROSSING = 7  -- nor a crossing or a traffic light
local BREAKS_AT = 4       -- hit harder than this (m/s), it's shoved
local ROOM = 2.3          -- from the middle of the lane beside to a parked car's (m): a car's width and a little
local KINDS = {"car", "car", "car", "car", "van", "sports", "car", "van"}

local function hash(a, b) return (a * 7919 + b * 104729 + a * b * 31) % 1000 end

-- Spots to keep clear: {x, z, r}s, in a coarse grid.
local function keep_clear()
  local G, CELL = {}, 50
  local function add(x, z, r)
    local k = math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
    G[k] = G[k] or {}
    table.insert(G[k], {x, z, r})
  end
  local map = city.map()
  for k = 1, #(map.zebras or {}), 2 do add(map.zebras[k], map.zebras[k + 1], CLEAR_CROSSING) end
  for k = 1, #(map.signals or {}), 2 do add(map.signals[k], map.signals[k + 1], CLEAR_CROSSING + 3) end
  for _, p in ipairs(pois.find{highway = "bus_stop", road = false}) do add(p.x, p.z, CLEAR_STOP) end
  for _, p in pairs(map.places or {}) do
    if p.at then add(p.at[1], p.at[2], 30) end
  end
  for _, p in pairs(map.specials or {}) do add(p[1], p[2], 35) end
  return function(x, z)
    local i, j = math.floor(x / CELL), math.floor(z / CELL)
    for di = -1, 1 do
      for dj = -1, 1 do
        for _, c in ipairs(G[(i + di) .. ":" .. (j + dj)] or {}) do
          if (x - c[1]) ^ 2 + (z - c[2]) ^ 2 < c[3] ^ 2 then return true end
        end
      end
    end
    return false
  end
end

-- A lamp there, or a vehicle the game's put there already?
local function taken(x, y, z)
  if engine.nearest(x, y, z, 3, "lamp") then return true end
  for tag in pairs(vehicle.tags) do
    if engine.nearest(x, y, z, 5, tag) then return true end
  end
  return false
end

local function park(x, z, yaw, mesh, kind, edge)
  local k = prefabs.CAR_KINDS[kind]
  local id = engine.spawn{mesh = mesh, pos = {x, U.ground(x, z) + k.lift, z}, yaw = yaw, size = k.size,
                          body = "static", tag = "parked", breaks_at = BREAKS_AT}
  P.list[id] = {x = x, z = z, yaw = yaw, mesh = mesh, edge = edge}
  return id
end

local function put_up()
  local net = roadnet.net()
  local fill = quality.pick(FILL)
  if not net or fill == 0 then return end
  local clear = keep_clear()
  local signals = roadnet.signals and roadnet.signals().junctions or {}
  for ei, e in ipairs(net.edges) do
    if e.parking and not e.tunnel and not e.height then
      local stop_a = signals[e.a] and signals[e.a].stop or 0
      local stop_b = signals[e.b] and signals[e.b].stop or 0
      local total = 0
      for i = 2, #e.pts do total = total + U.dist2d(e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]) end
      local s0 = 0
      for i = 2, #e.pts do
        local a, b = e.pts[i - 1], e.pts[i]
        local len = U.dist2d(a[1], a[2], b[1], b[2])
        local fx, fz = (b[1] - a[1]) / math.max(len, 1e-3), (b[2] - a[2]) / math.max(len, 1e-3)
        local yaw = math.atan(fx, fz)
        for side = 1, 2 do -- 1 left, 2 right of a to b
          -- (Only where the lane beside leaves a car room: a narrow
          -- street's lanes are narrow already.)
          local lane = side == 2 and city.lane(e.a, e.b) or (e.oneway and nil or city.lane(e.b, e.a))
          local o = e.width / 2 - city.PARK_W / 2
          if e.parking[side] and (not lane or o - lane >= ROOM) then
            o = o * (side == 1 and -1 or 1)
            local rx, rz = fz, -fx
            -- The right side faces a to b; the left faces back, unless one way.
            local facing = (side == 2 or e.oneway) and yaw or yaw + math.pi
            local first = math.ceil((s0 + SLOT / 2) / SLOT)
            for n = first, math.floor((s0 + len - SLOT / 2) / SLOT) do
              local s = n * SLOT
              local t = s - s0
              if s > CLEAR_END + stop_a and s < total - CLEAR_END - stop_b and t >= SLOT / 2 - 0.01 and t <= len - SLOT / 2 + 0.01
                 and hash(ei * 2 + side, n) < fill * 10 then
                local x, z = a[1] + fx * t + rx * o, a[2] + fz * t + rz * o
                if not clear(x, z) and not taken(x, U.ground(x, z), z) then
                  local h = hash(n, ei + side)
                  local kind = KINDS[h % #KINDS + 1]
                  local mesh = kind .. (h % 8 + 1)
                  park(x, z, facing, mesh, kind, ei)
                end
              end
            end
          end
        end
        s0 = s0 + len
      end
    end
  end
  local n = 0
  for _ in pairs(P.list) do n = n + 1 end
  print(string.format("parking: %d cars by the kerb", n))
end

local function take_down()
  for id in pairs(P.list) do
    if engine.exists(id) then engine.despawn(id) end
  end
  P.list = {}
end

-- A parked one becomes a car like any other: driven off, or shoved.
local function release(id)
  local p = P.list[id]
  if not p or not engine.exists(id) then return end
  local kind = prefabs.car_kind(p.mesh) or "car"
  local n = tonumber(p.mesh:match("%d+$")) or 1
  local x, _, z = engine.pos(id)
  engine.despawn(id)
  P.list[id] = nil
  return vehicle.spawn(x, z, p.yaw, n, kind ~= "car" and kind or nil)
end
P.release = release

-- Clear the kerb round (x, z) for a vehicle the game puts there.
function P.clear(x, z, r)
  for id, p in pairs(P.list) do
    if (p.x - x) ^ 2 + (p.z - z) ^ 2 < r * r then
      if engine.exists(id) then engine.despawn(id) end
      P.list[id] = nil
    end
  end
end

function P.build()
  P.pending = city.network() ~= nil
end

quality.watch(function()
  if P.pending == nil then return end
  take_down()
  P.pending = true
end)

-- Getting in: the nearest parked car, if it's nearer than any other.
local player = require "lib.player"
local enter = player.enter_nearest
function player.enter_nearest()
  local G = require "lib.state"
  if G.player then
    local x, y, z = engine.pos(G.player)
    local id, d = engine.nearest(x, y, z, 4.5, "parked")
    if id then
      local other = math.huge
      for tag in pairs(vehicle.tags) do
        local _, dd = engine.nearest(x, y, z, 4.5, tag)
        if dd and dd < other then other = dd end
      end
      if d < other then release(id) end
    end
  end
  return enter()
end

engine.on("contact", function(a, b, _, broke)
  if not broke then return end
  local car, hit = a, b
  if not P.list[car] then car, hit = b, a end
  if not P.list[car] or not engine.exists(hit) then return end
  local vx, vy, vz = engine.vel(hit)
  local id = release(car)
  if id then
    engine.set_vel(id, vx * 0.5, 0.5, vz * 0.5)
    engine.set_vel(hit, vx * 0.7, vy, vz * 0.7)
    engine.play("thud", {pos = {engine.pos(id)}, volume = 1.0, pitch = 0.8})
  end
end)

engine.on("tick", function()
  if P.pending and engine.ticks() > 2 then
    P.pending = false
    put_up()
  end
end)

return P
