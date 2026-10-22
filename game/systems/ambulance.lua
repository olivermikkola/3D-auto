-- Ambulance calls: an ambulance stands by the hospital (a white square with
-- a red cross on the minimap). Drive it in free roam (no mission, no cops)
-- and calls come: someone's hurt at a real place near you (a footballer on
-- a pitch, a jogger in a park, a pupil at school by day, a bar stool at
-- night: a closed list, picked by the hour), or on a street corner on a map
-- without places. Stop by them, then get them to the nearest hospital by
-- road before the clock runs out; every knock costs them seconds. Paid by
-- the time left; every fourth in a row, a bonus. Leaving the ambulance or a
-- star calls it off.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local errand = require "lib.errand"
local pois = require "lib.pois"
local template = require "lib.template"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local A = {
  FIRST = 5,       -- seconds in the ambulance before the first call
  EVERY = 10,      -- between calls
  HURRY = 8,       -- m/s by road: the clock is the drive at this pace...
  SPARE = 45,      -- ...plus this many seconds
  KNOCK = 4,       -- seconds a knock costs
  BASE = 80, PER_SECOND = 2, -- dollars: and for each second left
  STREAK = 4, BONUS = 400,   -- every fourth patient in a row
  RESPAWN = 60,    -- seconds before a lost ambulance is back at the hospital
}

-- Where calls come from: {tag conditions, hours or nil, weight, what's wrong, where (unnamed)}.
local CALLS = {
  {{leisure = {"pitch", "sports_centre"}}, {8, 22}, 3, "A footballer down with a twisted knee.", "the pitch"},
  {{leisure = "park"}, nil, 3, "A jogger collapsed in the park.", "the park"},
  {{amenity = "school"}, {8, 16}, 2, "A pupil fell off the climbing frame.", "the school"},
  {{amenity = {"pub", "bar", "nightclub"}}, {20, 4}, 4, "Someone fell off a bar stool. Twice.", "the bar"},
  {{leisure = "marina"}, {8, 22}, 1, "A sailor slipped on the pier.", "the marina"},
  {{social_facility = true}, nil, 1, "An elderly resident had a fall.", "the care home"},
}

local amb, lost_at -- the ambulance, and when it was lost
local state, call, next_at, on_duty, streak = nil, nil, nil, nil, 0
-- call = {spot = {x, z}, label, line, patient, marker, blip, stop = {x, z}, hospital = {x, z, name}, deadline, siren}

local function hospital_spot()
  local hx, hz = city.place("hospital")
  if city.network() then
    local roadnet = require "lib.roadnet"
    local e, _, rx, rz = roadnet.nearest_edge(hx, hz, true)
    if e then
      local w = roadnet.net().edges[e].width
      local dx, dz = hx - rx, hz - rz
      local l = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
      -- At the kerb on the hospital's side, along the road.
      local p = roadnet.net().edges[e].pts
      local yaw = math.atan(p[#p][1] - p[1][1], p[#p][2] - p[1][2])
      return rx + dx / l * (w / 2 - 1.3), rz + dz / l * (w / 2 - 1.3), yaw
    end
  end
  -- A grid: in the lane of the road out of the nearest junction, 12 m on.
  local j = city.nearest(hx, hz)
  local jx, jz = city.pos(j)
  local n = city.links(j)[1]
  if not n then return hx, hz, 0 end
  local nx, nz = city.pos(n)
  local yaw = math.atan(nx - jx, nz - jz)
  local fx, fz = U.forward(yaw)
  local rx, rz = U.right(yaw)
  local lane = city.lane(j, n)
  return jx + fx * 12 + rx * lane, jz + fz * 12 + rz * lane, yaw
end

-- The ambulance, parked by the hospital.
function A.park()
  local x, z, yaw = hospital_spot()
  amb = vehicle.spawn(x, z, yaw, 1, "ambulance")
  lost_at = nil
  return amb
end

function A.build() A.park() end

function A.in_ambulance()
  return G.vehicle ~= nil and require("lib.prefabs").car_kind(engine.mesh_of(G.vehicle)) == "ambulance"
end

-- The nearest hospital by road from (x, z): x, z (where to stop), name.
local function hospital_from(x, z)
  local best, bd
  for _, p in ipairs(pois.find{amenity = "hospital", name = true}) do
    local d = template.drive(x, z, p)
    if d < (bd or math.huge) then best, bd = p, d end
  end
  if best then
    local sx, sz = errand.kerb(best)
    return sx, sz, best.name
  end
  local hx, hz = hospital_spot()
  return hx, hz, "the hospital"
end

-- Where a call comes from near (x, z): x, z (the patient), where (words),
-- what's wrong, the place (lib/pois) or nil.
function A.cast(x, z, seed)
  if pois.count() > 0 then
    for _, kind in ipairs(errand.kinds(CALLS, seed)) do
      local role = {"patient", min_dist = 150, max_dist = 900, drive_max = 1500, relax = {{max_dist = 1500, drive_max = 2500}}}
      for k, v in pairs(kind[1]) do role[k] = v end
      local c = template.cast{seed = seed, from = {x, z}, roles = {role}}
      if c then
        local p = c.patient
        local street = city.street(p.road[1], p.road[2])
        return p, p.name or (kind[5] .. (street and (" on " .. street) or "")), kind[4]
      end
    end
  end
  -- A street corner, on a map without places.
  local j = city.random_near(x, z, 150, 600)
  if not j then return nil end
  local jx, jz = city.pos(j)
  local street = city.street(jx, jz)
  return {x = jx, z = jz, road = {jx, jz}}, street or "a street corner", "Someone's been knocked down."
end

local function stop_siren()
  if call and call.siren then engine.stop(call.siren); call.siren = nil end
end

local function clear()
  if call then
    stop_siren()
    if call.patient and engine.exists(call.patient) then engine.despawn(call.patient) end
    if call.marker and engine.exists(call.marker) then engine.despawn(call.marker) end
    errand.forget(call.blip)
  end
  state, call, G.errand, G.errand_deadline = nil, nil, nil, nil
  next_at = engine.time() + A.EVERY
end

local function cancel(why)
  U.message(why, 3)
  streak = 0
  engine.emit("patient_lost", why)
  clear()
end

local CALL_COLOR, HOSPITAL_COLOR = {1, 0.3, 0.3}, {1, 1, 1}

-- A call from near (x, z). Returns true if one came.
function A.call(x, z)
  G.stats.ambulance_calls = (G.stats.ambulance_calls or 0) + 1
  local seed = G.stats.ambulance_calls
  local place, where, line = A.cast(x, z, seed)
  if not place then return false end
  local sx, sz, wx, wz
  if place.tags then sx, sz, wx, wz = errand.kerb(place) else sx, sz, wx, wz = place.x, place.z, place.x + 4, place.z end
  -- Lying on the pavement.
  local patient = engine.spawn{mesh = "ped" .. (seed % 12 + 1), pos = {wx, 0.3 + U.ground(wx, wz), wz}, size = {0.7, 1.8, 0.7}, tag = "patient"}
  engine.set_rot(patient, 0.7071, 0, 0, 0.7071)
  local marker, blip = errand.mark(sx, sz, CALL_COLOR)
  local hx, hz, hname = hospital_from(sx, sz)
  local px, _, pz = U.player_pos()
  local function drive(ax, az, bx, bz)
    local r = require("lib.gps").route_between(ax, az, nil, bx, bz, nil)
    return r and r.length or U.dist2d(ax, az, bx, bz) * 1.4
  end
  local clock = (drive(px, pz, sx, sz) + drive(sx, sz, hx, hz)) / A.HURRY + A.SPARE
  call = {where = where, line = line, patient = patient, marker = marker, blip = blip, stop = {sx, sz},
          hospital = {hx, hz, hname}, deadline = engine.time() + clock, clock = clock}
  state = "pickup"
  G.errand = "Ambulance: get to " .. where .. "."
  G.errand_deadline = call.deadline
  U.message("AMBULANCE CALL: " .. where:upper(), 4)
  engine.play("pickup")
  engine.emit("ambulance_call", where)
  return true
end

local function load()
  engine.despawn(call.patient)
  call.patient = nil
  engine.despawn(call.marker)
  errand.forget(call.blip)
  local h = call.hospital
  call.marker, call.blip = errand.mark(h[1], h[2], HOSPITAL_COLOR)
  call.stop = {h[1], h[2]}
  call.siren = engine.play("siren", {loop = true, follow = G.vehicle})
  state = "ride"
  G.errand = "Ambulance: get them to " .. h[3] .. "."
  U.message("\"" .. call.line .. "\"", 3)
  U.message("TO " .. h[3]:upper() .. ", QUICK", 3)
end

local function deliver()
  local left = math.max(0, call.deadline - engine.time())
  local pay = A.BASE + math.floor(left) * A.PER_SECOND
  streak = streak + 1
  local bonus = streak % A.STREAK == 0 and A.BONUS or 0
  G.cash = G.cash + pay + bonus
  G.stats.patients = (G.stats.patients or 0) + 1
  require("lib.progress").touch()
  engine.play("pickup")
  U.message(string.format("PATIENT DELIVERED +$%d", pay), 4)
  if bonus > 0 then U.message(string.format("%d IN A ROW: BONUS +$%d", streak, bonus), 4) end
  engine.emit("patient_saved", pay, streak)
  A.last = {pay = pay, bonus = bonus, left = left, streak = streak}
  clear()
end

-- A knock with a patient on board costs them seconds.
engine.on("damaged", function(id)
  if state ~= "ride" or id ~= G.vehicle then return end
  local now = engine.time()
  if now < (call.knocked or 0) + 1.5 then return end
  call.knocked = now
  call.deadline = call.deadline - A.KNOCK
  G.errand_deadline = call.deadline
  U.message("PATIENT: OUCH!", 1.5)
end)

-- The ambulance when you're not in it.
engine.on("minimap", function(map)
  if not (amb and engine.exists(amb)) or G.vehicle == amb then return end
  local x, _, z = engine.pos(amb)
  local mx, my = map(x, z)
  engine.rect(mx - 5, my - 5, 10, 10, 1, 1, 1, 1)
  engine.rect(mx - 3, my - 1, 6, 2, 0.85, 0.1, 0.1, 1)
  engine.rect(mx - 1, my - 3, 2, 6, 0.85, 0.1, 0.1, 1)
end)

engine.on("tick", function()
  local now = engine.time()
  -- A lost ambulance (wrecked, or gone) is back at the hospital after a while.
  if amb and not engine.exists(amb) then amb, lost_at = nil, now end
  if not amb and lost_at and now > lost_at + A.RESPAWN and G.vehicle == nil then A.park() end
  if A.in_ambulance() and G.vehicle ~= amb then amb = G.vehicle end

  local duty = A.in_ambulance() and not G.mission and not G.dead and wanted.stars() == 0
  if not state then
    if not duty then on_duty = nil; return end
    if not on_duty then
      on_duty, next_at = true, now + A.FIRST
      U.message("ON CALL: EMERGENCIES WILL COME IN", 3)
      return
    end
    if now >= next_at then
      local x, _, z = U.player_pos()
      if not A.call(x, z) then next_at = now + 30 end
    end
    return
  end
  if G.mission then return clear() end
  if not A.in_ambulance() then return cancel("CALL OFF: YOU LEFT THE AMBULANCE") end
  if wanted.stars() > 0 then return cancel("CALL HANDED TO ANOTHER CREW") end
  if now > call.deadline then
    local foli = city.map().id == "turku" or city.map().id == "raisio"
    return cancel(foli and "TOO LATE: THE PATIENT TOOK A FÖLI BUS" or "TOO LATE: THE PATIENT WALKED IT OFF")
  end
  if state == "pickup" and errand.stopped_at(call.stop[1], call.stop[2], 10) then load()
  elseif state == "ride" and errand.stopped_at(call.stop[1], call.stop[2], 10) then deliver() end
end)

-- For tests.
A.state = function() return state end
A.call_now = function() return call end
A.vehicle = function() return amb end
A.streak = function() return streak end
function A.soon() next_at = engine.time() end

return A
