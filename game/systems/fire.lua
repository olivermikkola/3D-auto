-- Fire brigade: a fire engine stands by the fire station (a real one on maps
-- with places, the nearest to the hospital; a red square on the minimap).
-- Drive it in free roam (no mission, no cops) and calls come: a fire at a
-- real place near you (a kitchen fire in a restaurant, a sauna stove that
-- got out of hand, a grass fire in a park, a pub's kitchen at night: a
-- closed list, picked by the hour), or a car on fire on a street corner on
-- a map without places. Get there before the clock runs out and stop by it:
-- the hose puts it out while you stand. Left alone, it grows. Paid by the
-- time left; every third in a row, a bonus. Leaving the engine or a star
-- calls it off.
local G = require "lib.state"
local U = require "lib.util"
local FX = require "lib.fx"
local city = require "lib.city"
local errand = require "lib.errand"
local pois = require "lib.pois"
local template = require "lib.template"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local F = {
  FIRST = 5,       -- seconds in the fire engine before the first call
  EVERY = 12,      -- between calls
  HURRY = 9,       -- m/s by road: the clock is the drive at this pace...
  SPARE = 40,      -- ...plus this many seconds
  REACH = 20,      -- m: the hose reaches this far
  PUT_OUT = 7,     -- seconds of hose a fire needs (at its first size)
  GROW = 90,       -- seconds a fire takes to grow by half again, left alone
  BIGGEST = 2,
  BASE = 100, PER_SECOND = 2, -- dollars: and for each second left
  STREAK = 3, BONUS = 300,    -- every third fire in a row
  RESPAWN = 60,    -- seconds before a lost engine is back at the station (when you're not by it)
}

-- Where calls come from: {tag conditions, hours or nil, weight, what's burning, where (unnamed)}.
local CALLS = {
  {{amenity = {"restaurant", "fast_food"}}, {10, 23}, 3, "A kitchen fire. The fryer went up.", "the restaurant"},
  {{leisure = "sauna"}, {15, 23}, 3, "A sauna stove got out of hand.", "the sauna"},
  {{leisure = "park"}, {10, 20}, 2, "A grass fire. Someone's disposable grill.", "the park"},
  {{amenity = {"pub", "bar", "nightclub"}}, {20, 4}, 3, "Smoke from the bar's kitchen.", "the bar"},
  {{shop = "supermarket"}, {7, 22}, 1, "Cardboard burning behind the shop.", "the shop"},
  {{shop = "car_repair"}, {8, 18}, 2, "A car caught fire on the lift.", "the garage"},
  {{amenity = "school"}, {8, 16}, 1, "The chemistry class went wrong.", "the school"},
}

local engine_id, lost_at -- the fire engine, and when it was lost
local state, fire, next_at, on_duty, streak = nil, nil, nil, nil, 0
-- fire = {where, line, x, z (the flames), stop = {x, z}, size, deadline, clock, marker, blip, light, siren}

-- The station: the nearest real one to the hospital, else by the hospital
-- on another road.
local function station()
  local hx, hz = city.place("hospital")
  local best, bd
  for _, p in ipairs(pois.find{amenity = "fire_station", from = {hx, hz}}) do
    local d = U.dist2d(p.x, p.z, hx, hz)
    if d < (bd or math.huge) then best, bd = p, d end
  end
  if best then
    local x, z, yaw = errand.park_spot(best.x, best.z)
    return x, z, yaw, best.name or "the fire station"
  end
  local x, z, yaw = errand.park_spot(hx, hz, 2)
  return x, z, yaw, "the fire station"
end

-- The fire engine, parked by the station.
function F.park()
  local x, z, yaw = station()
  engine_id = vehicle.spawn(x, z, yaw, 1, "firetruck")
  lost_at = nil
  return engine_id
end

function F.build() F.park() end

function F.in_engine()
  return G.vehicle ~= nil and require("lib.prefabs").car_kind(engine.mesh_of(G.vehicle)) == "firetruck"
end

-- Where a fire is near (x, z): the place (lib/pois, or a bare spot), where
-- (words), what's burning.
function F.cast(x, z, seed)
  if pois.count() > 0 then
    for _, kind in ipairs(errand.kinds(CALLS, seed)) do
      local role = {"fire", min_dist = 150, max_dist = 900, drive_max = 1500, relax = {{max_dist = 1500, drive_max = 2500}}}
      for k, v in pairs(kind[1]) do role[k] = v end
      local c = template.cast{seed = seed, from = {x, z}, roles = {role}}
      if c then
        local p = c.fire
        local street = city.street(p.road[1], p.road[2])
        return p, p.name or (kind[5] .. (street and (" on " .. street) or "")), kind[4]
      end
    end
  end
  local j = city.random_near(x, z, 150, 600)
  if not j then return nil end
  local jx, jz = city.pos(j)
  return {x = jx, z = jz, road = {jx, jz}}, city.street(jx, jz) or "a street corner", "A car on fire."
end

local function clear()
  if fire then
    if fire.siren then engine.stop(fire.siren) end
    if fire.light then engine.remove_light(fire.light) end
    if fire.marker and engine.exists(fire.marker) then engine.despawn(fire.marker) end
    errand.forget(fire.blip)
  end
  state, fire, G.errand, G.errand_deadline = nil, nil, nil, nil
  next_at = engine.time() + F.EVERY
end

local function cancel(why)
  U.message(why, 3)
  streak = 0
  engine.emit("fire_lost", why)
  clear()
end

local CALL_COLOR = {1, 0.5, 0.1}

-- A fire near (x, z). Returns true if one broke out.
function F.call(x, z)
  G.stats.fire_calls = (G.stats.fire_calls or 0) + 1
  local seed = G.stats.fire_calls
  local place, where, line = F.cast(x, z, seed)
  if not place then return false end
  local sx, sz, wx, wz
  if place.tags then sx, sz, wx, wz = errand.kerb(place) else sx, sz, wx, wz = place.x, place.z, place.x + 4, place.z end
  -- The flames: on the pavement by the place, a little further in.
  local dx, dz = wx - sx, wz - sz
  local l = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
  local fx, fz = wx + dx / l * 2, wz + dz / l * 2
  local marker, blip = errand.mark(sx, sz, CALL_COLOR)
  local px, _, pz = U.player_pos()
  local r = require("lib.gps").route_between(px, pz, nil, sx, sz, nil)
  local clock = (r and r.length or U.dist2d(px, pz, sx, sz) * 1.4) / F.HURRY + F.SPARE
  local fy = U.ground(fx, fz)
  fire = {where = where, line = line, x = fx, z = fz, y = fy, stop = {sx, sz}, size = 1, left = 1, clock = clock,
          deadline = engine.time() + clock, marker = marker, blip = blip,
          light = engine.light{pos = {fx, fy + 2, fz}, radius = 16, intensity = 2.5, color = {1, 0.55, 0.2}},
          siren = engine.play("siren", {loop = true, follow = G.vehicle}), puff_t = 0}
  state = "call"
  G.errand = "Fire: get to " .. where .. "."
  G.errand_deadline = fire.deadline
  U.message("FIRE: " .. where:upper(), 4)
  U.message("\"" .. line .. "\"", 3)
  engine.play("pickup")
  engine.emit("fire_call", where)
  return true
end

local function put_out()
  local left = math.max(0, fire.deadline - engine.time())
  local pay = F.BASE + math.floor(left) * F.PER_SECOND
  streak = streak + 1
  local bonus = streak % F.STREAK == 0 and F.BONUS or 0
  G.cash = G.cash + pay + bonus
  G.stats.fires_out = (G.stats.fires_out or 0) + 1
  require("lib.progress").touch()
  engine.play("pickup")
  U.message(string.format("FIRE OUT +$%d", pay), 4)
  if bonus > 0 then U.message(string.format("%d IN A ROW: BONUS +$%d", streak, bonus), 4) end
  engine.emit("fire_out", pay, streak)
  F.last = {pay = pay, bonus = bonus, left = left, streak = streak}
  clear()
end

-- Is the hose on: the engine stopped within reach of the flames?
function F.spraying()
  if state ~= "call" or not F.in_engine() then return false end
  local x, _, z = engine.pos(G.vehicle)
  return U.dist2d(x, z, fire.x, fire.z) < F.REACH and math.abs(vehicle.speed(G.vehicle)) < 2
end

-- The engine when you're not in it.
engine.on("minimap", function(map)
  if not (engine_id and engine.exists(engine_id)) or G.vehicle == engine_id then return end
  local x, _, z = engine.pos(engine_id)
  local mx, my = map(x, z)
  engine.rect(mx - 5, my - 5, 10, 10, 0.8, 0.1, 0.05, 1)
  engine.rect(mx - 3, my - 1, 6, 2, 1, 1, 1, 1)
end)

-- Flames, smoke and the hose, a few times a second.
local function show(dt)
  fire.puff_t = fire.puff_t - dt
  if fire.puff_t > 0 then return end
  fire.puff_t = 0.08
  local s = fire.size * math.max(fire.left, 0.15)
  for _ = 1, 2 do
    local a, r = math.random() * math.pi * 2, math.random() * 2.2 * s
    FX.puff(fire.x + math.cos(a) * r, fire.y + 0.4, fire.z + math.sin(a) * r, {1, 0.45 + math.random() * 0.35, 0.08},
            0.7 * s + 0.3, 3 + s, 0.6, 2)
  end
  local g = 0.18 + math.random() * 0.1
  FX.puff(fire.x, fire.y + 2.5 + 2 * s, fire.z, {g, g, g, 0.55}, 1.2 * s, 3, 2.5)
  engine.set_light(fire.light, {intensity = (1.8 + math.random()) * s})
  if F.spraying() then
    local x, y, z = engine.pos(G.vehicle)
    for _ = 1, 3 do
      local tx, tz = fire.x + (math.random() - 0.5) * 2, fire.z + (math.random() - 0.5) * 2
      FX.tracer(x, y + 1.4, z, tx, fire.y + 0.8, tz, {0.75, 0.85, 1, 0.7}, 0.12)
    end
    FX.puff(fire.x, fire.y + 1, fire.z, {0.9, 0.9, 0.92, 0.5}, 0.8, 2, 1.2) -- steam
  end
end

engine.on("tick", function(dt)
  local now = engine.time()
  if engine_id and not engine.exists(engine_id) then engine_id, lost_at = nil, now end
  if not engine_id and lost_at and now > lost_at + F.RESPAWN then
    local sx, sz = station()
    local px, _, pz = U.player_pos()
    if px and U.dist2d(px, pz, sx, sz) > 100 then F.park() end -- (not while you watch)
  end
  if F.in_engine() and G.vehicle ~= engine_id then engine_id = G.vehicle end

  local duty = F.in_engine() and not G.mission and not G.dead and wanted.stars() == 0
  if not state then
    if not duty then on_duty = nil; return end
    if not on_duty then
      on_duty, next_at = true, now + F.FIRST
      U.message("ON CALL: FIRES WILL BE CALLED IN", 3)
      return
    end
    if now >= next_at then
      local x, _, z = U.player_pos()
      if not F.call(x, z) then next_at = now + 30 end
    end
    return
  end
  if G.mission then return clear() end
  if not F.in_engine() then return cancel("CALL OFF: YOU LEFT THE FIRE ENGINE") end
  if wanted.stars() > 0 then return cancel("CALL HANDED TO ANOTHER CREW") end
  show(dt)
  if F.spraying() then
    if fire.siren then
      engine.stop(fire.siren); fire.siren = nil
      engine.set_visible(fire.marker, false) -- (there: the stop marker would sit on the engine; the blip stays)
    end
    fire.left = fire.left - dt / (F.PUT_OUT * fire.size)
    if fire.left <= 0 then return put_out() end
    G.errand = string.format("Fire: hold the hose, %d%% to go.", math.ceil(fire.left * 100))
  else
    fire.size = math.min(F.BIGGEST, fire.size + dt * 0.5 / F.GROW)
    if now > fire.deadline then return cancel("TOO LATE: " .. fire.where:upper() .. " BURNED DOWN") end
  end
end)

-- For tests.
F.state = function() return state end
F.fire_now = function() return fire end
F.vehicle = function() return engine_id end
F.streak = function() return streak end
F.station = station
function F.soon() next_at = engine.time() end

return F
