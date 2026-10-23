-- Pöli bus driver: on a map with bus stops (Turku's real ones, from OSM), a
-- Pöli bus stands at the bus station (a yellow square on the minimap).
-- Drive it in free roam (no mission, no cops) and you get a route: four
-- real stops one after another, each a few hundred metres on, with people
-- waiting. Pull in by the stop and stand with the doors open for a moment
-- to let them on. Each stop has a time in the timetable: on time pays the
-- whole fare, late pays less ("late again"). The whole route pays a bonus.
-- Leaving the bus, a star or a mission ends the route.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local errand = require "lib.errand"
local pois = require "lib.pois"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local B = {
  FIRST = 5,          -- seconds in the bus before the first route
  EVERY = 15,         -- between routes
  STOPS = 4,          -- on a route
  NEAR = 250, FAR = 700, -- m: from one stop to the next (straight line)
  PACE = 7, SPARE = 25,  -- the timetable: the drive at this pace (m/s, by road), plus seconds
  DOORS = 2,          -- seconds stood at a stop to let them on
  AT = 14,            -- m: by the stop
  FARE = 25,          -- dollars a passenger, on time
  LATE = 0.4,         -- of that when late
  BONUS = 150,        -- the whole route
  RESPAWN = 60,
}

local bus, lost_at
local state, route, next_at, on_duty
-- route = {stops = {{x, z, name, wx, wz}...}, at = n, due, waiting = {entity...}, marker, blip, doors, paid, late}

-- Where the bus stands: the kerb by the bus station nearest the taxi rank
-- (the middle of town), nil on a map without bus stops.
local function depot()
  if #pois.find{highway = "bus_stop", limit = 1} == 0 then return nil end
  local tx, tz = city.place("taxi_rank")
  if not tx then tx, tz = city.place("hospital") end
  local best, bd
  for _, p in ipairs(pois.find{amenity = "bus_station", from = {tx, tz}}) do
    local d = U.dist2d(p.x, p.z, tx, tz)
    if d < (bd or math.huge) then best, bd = p, d end
  end
  local x, z = tx, tz
  if best then x, z = best.x, best.z end
  local px, pz, yaw = errand.park_spot(x, z)
  return px, pz, yaw, best and best.name or "the bus station"
end
B.depot = depot

function B.park()
  local x, z, yaw = depot()
  if not x then return nil end
  bus = vehicle.spawn(x, z, yaw, nil, "bus")
  lost_at = nil
  return bus
end

function B.build() B.park() end

function B.in_bus()
  return G.vehicle ~= nil and engine.mesh_of(G.vehicle) == "bus" and engine.tag(G.vehicle) == "bus"
end

-- Four stops from (x, z) on: each NEAR..FAR m from the one before, never a
-- name twice, picked by seed. nil if the map can't make a route.
function B.plan(x, z, seed)
  local stops, used = {}, {}
  local fx, fz = x, z
  for k = 1, B.STOPS do
    local list = pois.find{highway = "bus_stop", from = {fx, fz}, min_dist = k == 1 and 60 or B.NEAR, max_dist = B.FAR}
    local ok = {}
    for _, p in ipairs(list) do
      if p.name and not used[p.name] then ok[#ok + 1] = p end
    end
    if #ok == 0 then return nil end
    table.sort(ok, function(a, b) return a.name < b.name or (a.name == b.name and a.x < b.x) end)
    local p = ok[(seed * 7919 + k * 104729) % #ok + 1]
    used[p.name] = true
    local sx, sz, wx, wz = errand.kerb(p)
    stops[k] = {sx, sz, p.name, wx, wz}
    fx, fz = p.x, p.z
  end
  return stops
end

local function drive_time(ax, az, bx, bz)
  local r = require("lib.gps").route_between(ax, az, nil, bx, bz, nil)
  return (r and r.length or U.dist2d(ax, az, bx, bz) * 1.4) / B.PACE + B.SPARE
end

local function forget_stop()
  if route.marker and engine.exists(route.marker) then engine.despawn(route.marker) end
  errand.forget(route.blip)
  for _, id in ipairs(route.waiting or {}) do
    if engine.exists(id) then engine.despawn(id) end
  end
  route.marker, route.blip, route.waiting = nil, nil, {}
end

-- Head for stop n: its marker, people waiting on the pavement, its time.
local function next_stop(n, fromx, fromz)
  local s = route.stops[n]
  route.at, route.doors = n, 0
  route.marker, route.blip = errand.mark(s[1], s[2], {1, 0.85, 0.1})
  route.waiting = {}
  local people = 1 + (G.stats.bus_routes * 3 + n) % 3
  for i = 1, people do
    local wx, wz = s[4] + (i - 2) * 0.9, s[5]
    route.waiting[i] = engine.spawn{mesh = "ped" .. ((G.stats.bus_routes + n * 5 + i) % 12 + 1),
                                    pos = {wx, 1.15 + U.ground(wx, wz), wz}, size = {0.7, 1.8, 0.7}, tag = "prop"}
  end
  route.due = engine.time() + drive_time(fromx, fromz, s[1], s[2])
  G.errand = string.format("Pöli: stop %d of %d, %s.", n, #route.stops, s[3])
  G.errand_deadline = route.due
end

local function clear()
  if route then forget_stop() end
  state, route, G.errand, G.errand_deadline = nil, nil, nil, nil
  next_at = engine.time() + B.EVERY
end

local function abandon(why)
  U.message(why, 3)
  engine.emit("bus_route_lost", why)
  clear()
end

-- A route from (x, z). Returns true if there was one.
function B.start(x, z)
  G.stats.bus_routes = (G.stats.bus_routes or 0) + 1
  local stops = B.plan(x, z, G.stats.bus_routes)
  if not stops then return false end
  route = {stops = stops, paid = 0, late = 0}
  state = "route"
  next_stop(1, x, z)
  U.message("PÖLI ROUTE: " .. #stops .. " STOPS, FIRST " .. stops[1][3]:upper(), 4)
  engine.play("pickup")
  engine.emit("bus_route", stops[1][3])
  return true
end

-- Doors open at the stop: they get on.
local function board()
  local n, s = route.at, route.stops[route.at]
  local people = #route.waiting
  local late = engine.time() > route.due
  local pay = math.floor(people * B.FARE * (late and B.LATE or 1))
  route.paid, route.late = route.paid + pay, route.late + (late and 1 or 0)
  G.cash = G.cash + pay
  G.stats.bus_passengers = (G.stats.bus_passengers or 0) + people
  U.message(string.format("%s: %d ON BOARD +$%d%s", s[3]:upper(), people, pay, late and " (LATE AGAIN)" or ""), 3)
  engine.play("pickup")
  forget_stop()
  if n == #route.stops then
    local bonus = route.late == 0 and B.BONUS or math.floor(B.BONUS / 2)
    G.cash = G.cash + bonus
    G.stats.bus_routes_done = (G.stats.bus_routes_done or 0) + 1
    U.message(string.format("ROUTE DONE%s: BONUS +$%d", route.late == 0 and ", ON TIME" or "", bonus), 4)
    engine.emit("bus_route_done", route.paid + bonus, route.late)
    B.last = {paid = route.paid, bonus = bonus, late = route.late}
    require("lib.progress").touch()
    return clear()
  end
  next_stop(n + 1, s[1], s[2])
  require("lib.progress").touch()
end

-- The bus when you're not in it.
engine.on("minimap", function(map)
  if not (bus and engine.exists(bus)) or G.vehicle == bus then return end
  local x, _, z = engine.pos(bus)
  local mx, my = map(x, z)
  engine.rect(mx - 5, my - 5, 10, 10, 0.95, 0.8, 0.1, 1)
  engine.rect(mx - 3, my - 2, 6, 3, 1, 1, 1, 1)
end)

engine.on("tick", function(dt)
  local now = engine.time()
  if bus and not engine.exists(bus) then bus, lost_at = nil, now end
  if not bus and lost_at and now > lost_at + B.RESPAWN then
    local dx, dz = depot()
    local px, _, pz = U.player_pos()
    if dx and px and U.dist2d(px, pz, dx, dz) > 100 then B.park() end
  end
  if B.in_bus() and G.vehicle ~= bus and not require("systems.traffic").cars[G.vehicle] then bus = G.vehicle end

  local duty = B.in_bus() and not G.mission and not G.dead and wanted.stars() == 0
  if not state then
    if not duty then on_duty = nil; return end
    if not on_duty then
      on_duty, next_at = true, now + B.FIRST
      U.message("PÖLI: A ROUTE WILL BE GIVEN", 3)
      return
    end
    if now >= next_at then
      local x, _, z = U.player_pos()
      if not B.start(x, z) then next_at = now + 30 end
    end
    return
  end
  if G.mission then return clear() end
  if not B.in_bus() then return abandon("ROUTE OFF: YOU LEFT THE BUS") end
  if wanted.stars() > 0 then return abandon("ROUTE OFF: PÖLI DOESN'T TAKE THE WANTED ON BOARD") end
  local s = route.stops[route.at]
  if errand.stopped_at(s[1], s[2], B.AT) and math.abs(vehicle.speed(G.vehicle)) < 1 then
    route.doors = route.doors + dt
    if route.doors >= B.DOORS then board() end
  else
    route.doors = 0
  end
end)

-- For tests.
B.state = function() return state end
B.route_now = function() return route end
B.vehicle = function() return bus end
function B.soon() next_at = engine.time() end

return B
