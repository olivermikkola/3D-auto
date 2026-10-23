-- Street racers: at night, between missions, a sports car now and then
-- waits at a junction near you, orange on the map. Pull up beside it and
-- stop: three, two, one, and it's a race by the streets to a landmark
-- 1.2-2.5 km away (lib/template picks it, and the racer drives the
-- shortest way there; the finish is the junction by it). Get there first for the money. Leave it and
-- it drives off; on a map without points of interest there are none.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local template = require "lib.template"
local traffic = require "systems.traffic"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local R = {
  FIRST = 90, EVERY = 240, -- seconds of night before the first, and between
  WAIT = 90,               -- how long a racer waits for you
  PRIZE = 600,
  NIGHT = {20, 4},         -- hours
}
local state, car, blip, finish, flag, marker, countdown_at, until_at
local next_at = nil
R.forced = false -- tests: any hour

local FINISHES = {
  {tourism = {"attraction", "museum", "gallery"}},
  {historic = {"castle", "church", "manor", "monument"}},
  {amenity = "place_of_worship"},
  {leisure = {"stadium", "marina"}},
}

local function night()
  local h = require("lib.daynight").hour
  return R.forced or h >= R.NIGHT[1] or h < R.NIGHT[2]
end

local function forget()
  if blip then
    for i, b in ipairs(G.markers) do if b == blip then table.remove(G.markers, i) break end end
  end
  if flag then
    for i, b in ipairs(G.markers) do if b == flag then table.remove(G.markers, i) break end end
  end
  if marker and engine.exists(marker) then engine.despawn(marker) end
  blip, flag, marker = nil, nil, nil
end

-- Done: the racer becomes ordinary traffic (or is gone), the next one later.
local function done()
  forget()
  local c = car and traffic.cars[car]
  if c then c.keep, c.cruise, c.plan = nil, nil, nil end
  state, car, finish = nil, nil, nil
  next_at = engine.time() + R.EVERY
end

-- A junction 80-200 m from you with a race from it: the junction, the
-- way (junctions) and the finish (a point of interest), or nil.
local function find_start(px, pz, seed)
  local cands = {}
  for _, j in ipairs(city.junctions()) do
    local x, z = city.pos(j)
    local d = U.dist2d(x, z, px, pz)
    local level = city.level(j)
    if d > 80 and d < 200 and (#city.links(j) or 0) >= 2 and (not level or math.abs(level - U.ground(x, z)) < 1) then
      cands[#cands + 1] = j
    end
  end
  table.sort(cands)
  for k = 0, math.min(#cands, 6) - 1 do
    local j = cands[(seed + k) % #cands + 1]
    local x, z = city.pos(j)
    for i = 0, #FINISHES - 1 do
      local role = {"finish", name = true, drive_min = 1200, drive_max = 2500, relax = {{drive_min = 800, drive_max = 4000}}}
      for key, v in pairs(FINISHES[(seed + i) % #FINISHES + 1]) do role[key] = v end
      local c = template.cast{seed = seed, from = {x, z}, roles = {role}}
      local way = c and template.route(x, z, c.finish)
      if way and #way >= 3 and way[1] == j then return j, way, c.finish end
    end
  end
end

-- Set a racer waiting near (px, pz). Returns its car, or nil.
function R.start(px, pz, seed)
  local j, way, fin = find_start(px, pz, seed or 1)
  if not j then return nil end
  local x, z = city.pos(j)
  local a, b = city.pos(way[2])
  -- Clear the junction of traffic.
  for _, id in ipairs(engine.find("car")) do
    local cx, _, cz = engine.pos(id)
    if id ~= G.vehicle and U.dist2d(cx, cz, x, z) < 10 then engine.despawn(id) end
  end
  car = vehicle.spawn(x, z, math.atan(a - x, b - z), 7, "sports")
  vehicle.headlights(car)
  state, finish, R.way, until_at = "waiting", fin, way, engine.time() + R.WAIT
  blip = {id = car, color = {1, 0.55, 0.1}, ambient = true} -- (the GPS takes a job's goal first)
  G.markers[#G.markers + 1] = blip
  local street = city.street(x, z)
  U.message("STREET RACER" .. (street and (" ON " .. street:upper()) or ""), 5)
  U.message("PULL UP BESIDE IT AND STOP", 5)
  engine.emit("racer_waiting")
  return car
end

local function go()
  state = "racing"
  forget()
  local c = traffic.adopt(car, {keep = true, cruise = 23})
  traffic.set_plan(car, R.way)
  c.speed = 0
  local fx, fz = city.pos(finish.junction)
  marker = engine.spawn{mesh = "marker", pos = {fx, 2.5 + U.ground(fx, fz), fz}, scale = 5, color = {1, 0.55, 0.1, 0.35}}
  flag = {id = marker, color = {1, 0.55, 0.1}}
  G.markers[#G.markers + 1] = flag
  U.message("GO! RACE TO " .. finish.name:upper(), 3)
  engine.play("star")
end

engine.on("tick", function()
  local now = engine.time()
  next_at = next_at or now + R.FIRST
  local px, _, pz = U.player_pos()
  if not px then return end
  if state == nil then
    if now < next_at or not night() or not city.network() or G.mission or G.dead or wanted.stars() > 0 or not G.vehicle then return end
    if not R.start(px, pz, math.floor(now)) then next_at = now + 30 end
    return
  end
  if not engine.exists(car) or G.vehicle == car then return done() end
  local x, _, z = engine.pos(car)
  if state == "waiting" then
    if now > until_at or U.dist2d(x, z, px, pz) > 400 or G.mission or wanted.stars() > 0 then return done() end
    local beside = G.vehicle and U.dist2d(x, z, px, pz) < 9 and math.abs(vehicle.speed(G.vehicle)) < 3
    if beside then
      state, countdown_at = "countdown", now
      engine.play("pickup")
    end
  elseif state == "countdown" then
    local t = now - countdown_at
    local n = 3 - math.floor(t)
    if n >= 1 then
      if not R.said or R.said ~= n then R.said = n; U.message(tostring(n), 0.9) end
    else
      R.said = nil
      go()
    end
  elseif state == "racing" then
    local fx, fz = city.pos(finish.junction)
    if not G.vehicle or U.dist2d(px, pz, x, z) > 450 and U.dist2d(px, pz, fx, fz) > 450 then
      U.message("YOU GAVE UP THE RACE", 3)
      return done()
    end
    if U.dist2d(px, pz, fx, fz) < 9 then
      G.cash = G.cash + R.PRIZE
      require("lib.progress").touch()
      U.message(string.format("YOU WON THE RACE! +$%d", R.PRIZE), 4)
      engine.emit("racer_won")
      return done()
    end
    if U.dist2d(x, z, fx, fz) < 12 then
      U.message("THE RACER GOT THERE FIRST", 3)
      engine.emit("racer_lost")
      return done()
    end
  end
end)

R.state = function() return state end
R.car = function() return car end
R.finish = function() return finish end
function R.soon() next_at = engine.time() end

return R
