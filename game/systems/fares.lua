-- Taxi fares: drive a cab in free roam (no mission, no cops) and fares call.
-- A passenger waits by a real place near you (a hotel, the hospital, a pub
-- at night: a closed list, picked by the hour), wanting to go to another
-- 0.7-2.5 km off by road. Stop by them, then take them there. The fare is
-- by the road distance; a quick ride adds a tip, and every knock the cab
-- takes on the way cuts it. Leave the cab, get a star or take too long and
-- the fare's off. The places come from lib/template, by a seed kept with
-- the progress save, so every call is another version.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local template = require "lib.template"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local F = {
  FIRST = 6,      -- seconds in a cab before the first call
  EVERY = 12,     -- between fares
  WAIT = 120,     -- a passenger waits this long to be picked up
  BASE = 15, PER_KM = 40, -- dollars
  HURRY = 9,      -- m/s by road: there by then, the whole tip
  TIP = 0.5,      -- of the fare, at most
  KNOCK = 0.7,    -- what's left of the tip after each knock
}

-- Where fares are picked up: {tag conditions, hours (from, to) or nil for
-- any, weight, what they say getting in}.
local PICKUPS = {
  {{tourism = "hotel"}, nil, 3, "To the address on this card, please. I don't speak Finnish."},
  {{amenity = "hospital"}, nil, 2, "Gently with the corners. I've just had stitches."},
  {{amenity = {"bus_station", "ferry_terminal"}}, nil, 2, "Long trip. Just get me home."},
  {{shop = "mall"}, {9, 21}, 2, "Mind the bags, they're full of glass."},
  {{amenity = {"university", "college"}}, {8, 19}, 2, "I have an exam in twenty minutes. Drive."},
  {{amenity = {"theatre", "cinema"}}, {18, 24}, 2, "Did you see the second act? Never mind. Drive."},
  {{amenity = {"pub", "bar", "nightclub"}}, {20, 4}, 4, "Kuule... I love this city. Do you love this city?"},
}
-- Where they go.
local DROPS = {
  {{tourism = "hotel"}, nil, 3},
  {{amenity = "hospital"}, nil, 1},
  {{amenity = {"bus_station", "ferry_terminal"}}, nil, 2},
  {{shop = "mall"}, {9, 21}, 2},
  {{tourism = "museum"}, {10, 18}, 1},
  {{amenity = {"restaurant", "pub"}}, {17, 24}, 2},
  {{amenity = {"nightclub", "bar"}}, {21, 4}, 2},
}

local state, fare, next_at, on_duty
-- fare = {pickup, drop, rider (entity), marker, blip, at (s), drive (m), tip (0..1), knocked}

local function hours_ok(h)
  if not h then return true end
  local now = require("lib.daynight").hour
  if h[1] < h[2] then return now >= h[1] and now < h[2] end
  return now >= h[1] or now < h[2]
end

-- The kinds that fit the hour, heaviest first by a seeded draw.
local function kinds(list, seed)
  local out = {}
  for i, k in ipairs(list) do
    if hours_ok(k[2]) then out[#out + 1] = {k, ((seed * 7919 + i * 104729) % 1000) / 1000 * k[3]} end
  end
  table.sort(out, function(a, b) return a[2] > b[2] end)
  for i, k in ipairs(out) do out[i] = k[1] end
  return out
end

local function role(name, kind, extra)
  local r = {name, name = true}
  for k, v in pairs(kind[1]) do r[k] = v end
  for k, v in pairs(extra) do r[k] = v end
  return r
end

-- A pickup near (x, z) and a drop from there, or nil.
function F.cast(x, z, seed)
  for _, pk in ipairs(kinds(PICKUPS, seed)) do
    for _, dk in ipairs(kinds(DROPS, seed + 1)) do
      local c = template.cast{seed = seed, from = {x, z}, roles = {
        role("pickup", pk, {min_dist = 80, max_dist = 600, drive_max = 1200, relax = {{max_dist = 1000, drive_max = 2000}}}),
        role("drop", dk, {from = "pickup", drive_min = 700, drive_max = 2500, relax = {{drive_min = 400, drive_max = 4000}}}),
      }}
      if c then return c.pickup, c.drop, pk end
    end
  end
end

-- Is the player at the wheel of a cab (traffic's, or the taxi mod's)?
function F.in_cab()
  local id = G.vehicle
  if not id then return false end
  local mesh = engine.mesh_of(id)
  return require("lib.prefabs").car_kind(mesh) == "cab" or mesh == "taxi"
end

local function forget(blip)
  for i, b in ipairs(G.markers) do if b == blip then table.remove(G.markers, i) break end end
end

local function clear()
  if fare then
    if fare.rider and engine.exists(fare.rider) then engine.despawn(fare.rider) end
    if fare.marker and engine.exists(fare.marker) then engine.despawn(fare.marker) end
    forget(fare.blip)
  end
  state, fare, G.errand = nil, nil, nil
  next_at = engine.time() + F.EVERY
end

local function cancel(why)
  U.message(why, 3)
  engine.emit("fare_lost", why)
  clear()
end

-- Where a car stops for place p, and a spot on the pavement beside it on
-- the place's side.
local function kerb(p)
  local rx, rz = p.road[1], p.road[2]
  local dx, dz = p.x - rx, p.z - rz
  local l = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
  local e = require("lib.roadnet").nearest_edge(rx, rz)
  local w = e and require("lib.roadnet").net().edges[e].width or 8
  return rx, rz, rx + dx / l * (w / 2 + 1.2), rz + dz / l * (w / 2 + 1.2)
end

local function mark(x, z, color)
  local id = engine.spawn{mesh = "marker", pos = {x, 2.5 + U.ground(x, z), z}, scale = 4, color = {color[1], color[2], color[3], 0.35}}
  local blip = {id = id, color = color}
  G.markers[#G.markers + 1] = blip
  return id, blip
end

local PICK_COLOR, DROP_COLOR = {1, 0.85, 0.1}, {0.3, 0.8, 1}

-- A fare calls from near (x, z). Returns true if one did.
function F.call(x, z)
  G.stats.fares_called = (G.stats.fares_called or 0) + 1
  local pickup, drop, kind = F.cast(x, z, G.stats.fares_called)
  if not pickup then return false end
  local sx, sz, wx, wz = kerb(pickup)
  local rider = engine.spawn{mesh = "ped" .. (G.stats.fares_called % 12 + 1), pos = {wx, 1.15 + U.ground(wx, wz), wz},
                             size = {0.7, 1.8, 0.7}, tag = "rider"}
  engine.orient(rider, math.atan(sx - wx, sz - wz))
  local marker, blip = mark(sx, sz, PICK_COLOR)
  fare = {pickup = pickup, drop = drop, rider = rider, marker = marker, blip = blip, at = engine.time(), line = kind[4], stop = {sx, sz}}
  state = "pickup"
  G.errand = "Fare: pick up at " .. pickup.name .. "."
  U.message("FARE CALLING: " .. pickup.name:upper(), 4)
  engine.play("pickup")
  engine.emit("fare_called", pickup.name)
  return true
end

local function stopped_at(x, z, r)
  local px, _, pz = U.player_pos()
  return px and U.dist2d(px, pz, x, z) < r and math.abs(vehicle.speed(G.vehicle)) < 2
end

local function board()
  engine.despawn(fare.rider)
  fare.rider = nil
  engine.despawn(fare.marker)
  forget(fare.blip)
  local sx, sz = kerb(fare.drop)
  fare.marker, fare.blip = mark(sx, sz, DROP_COLOR)
  fare.stop = {sx, sz}
  local px, _, pz = U.player_pos()
  fare.drive = template.drive(px, pz, fare.drop)
  if fare.drive == math.huge then fare.drive = U.dist2d(px, pz, sx, sz) * 1.4 end
  fare.at, fare.tip = engine.time(), 1
  state = "ride"
  G.errand = "Fare: take them to " .. fare.drop.name .. "."
  U.message("\"" .. fare.line .. "\"", 4)
  U.message("TAKE THEM TO " .. fare.drop.name:upper(), 4)
end

local function pay()
  local took = engine.time() - fare.at
  local hurry = fare.drive / F.HURRY + 15
  local base = math.floor(F.BASE + F.PER_KM * fare.drive / 1000)
  local quick = U.clamp(2 - took / hurry, 0, 1) -- the whole tip in time, none at twice that
  local tip = math.floor(base * F.TIP * quick * fare.tip)
  G.cash = G.cash + base + tip
  G.stats.fares = (G.stats.fares or 0) + 1
  require("lib.progress").touch()
  engine.play("pickup")
  U.message(string.format("FARE +$%d", base) .. (tip > 0 and string.format("  TIP +$%d", tip) or ""), 4)
  engine.emit("fare_paid", base, tip, fare.drop.name)
  F.last = {base = base, tip = tip, took = took, drive = fare.drive}
  clear()
end

-- A knock on the cab with a passenger in it costs some of the tip.
engine.on("damaged", function(id)
  if state ~= "ride" or id ~= G.vehicle then return end
  local now = engine.time()
  if now < (fare.knocked or 0) + 1.5 then return end
  fare.knocked, fare.tip = now, fare.tip * F.KNOCK
  U.message("PASSENGER: EASY!", 1.5)
end)

engine.on("tick", function()
  local now = engine.time()
  local cab = F.in_cab() and not G.mission and not G.dead and wanted.stars() == 0 and city.network()
  if not state then
    if not cab then
      on_duty = nil
      return
    end
    if not on_duty then
      on_duty, next_at = true, now + F.FIRST
      U.message("ON DUTY: FARES WILL CALL", 3)
      return
    end
    if now >= next_at then
      local x, _, z = U.player_pos()
      if not F.call(x, z) then next_at = now + 30 end
    end
    return
  end
  -- A fare on: off if you're not in a cab with no cops on you any more.
  if G.mission then return clear() end
  if not F.in_cab() then return cancel("FARE OFF: YOU LEFT THE CAB") end
  if wanted.stars() > 0 then return cancel(state == "ride" and "THE PASSENGER JUMPED OUT" or "FARE OFF: COPS") end
  if state == "pickup" then
    if now > fare.at + F.WAIT then return cancel("THE FARE TOOK ANOTHER CAB") end
    if stopped_at(fare.stop[1], fare.stop[2], 9) then board() end
  elseif state == "ride" then
    if now > fare.at + 3 * (fare.drive / F.HURRY + 15) then return cancel("THE PASSENGER GAVE UP AND WALKED") end
    if stopped_at(fare.stop[1], fare.stop[2], 9) then pay() end
  end
end)

-- For tests.
F.state = function() return state end
F.fare = function() return fare end
function F.soon() next_at = engine.time() end

return F
