-- Vigilante: steal a police car (one star), shake the cops off, and the
-- radio starts calling suspects in: a car with a crime from a closed list
-- (picked by the hour) pulls off a junction near you and runs, red on the
-- map. Wreck it, or box it in and sit on its bumper until the driver gives
-- up, before it gets away (the clock, or too far off). Rams on a suspect
-- aren't crimes. Each one caught raises the level: the next runs faster and
-- takes more beating, and pays more. Leaving the police car, a star or a
-- mission ends the shift.
local G = require "lib.state"
local H = require "lib.health"
local U = require "lib.util"
local city = require "lib.city"
local errand = require "lib.errand"
local traffic = require "systems.traffic"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local V = {
  FIRST = 5,         -- seconds in the police car before the first suspect
  EVERY = 12,        -- between suspects
  NEAR = 150, FAR = 450, -- m: where a suspect sets off from you
  CRUISE = 13, CRUISE_STEP = 1.2, CRUISE_MAX = 21, -- m/s it runs at, by level
  HP_STEP = 0.25,    -- a share of a car's hit points more per level
  CLOCK = 100,       -- seconds to catch one
  GONE = 700,        -- m off: it got away
  PIN = 9, PIN_SECS = 2, -- stopped within this many m of you this long: the driver gives up
  PAY = 150,         -- dollars a level
  MAX_LEVEL = 10,
  -- On the run: at each junction it takes the road away from you, most
  -- of the time (more often the higher the level), and floors it when
  -- you're close.
  SMART = 0.6, SMART_STEP = 0.05, SMART_MAX = 0.9,
  PANIC = 60, PANIC_BOOST = 3, -- m, m/s
}

-- Suspects: {crime, hours or nil, weight}.
local CRIMES = {
  {"A stolen Volvo, plates swapped.", nil, 3},
  {"A drunk driver, all over the road.", {20, 4}, 4},
  {"A getaway car from a kiosk robbery.", nil, 2},
  {"Someone doing 120 past a school.", {8, 16}, 3},
  {"A van full of copper cable.", {22, 5}, 2},
  {"Somebody who didn't pay for petrol.", nil, 2},
}

local state, suspect, next_at, on_duty, level = nil, nil, nil, nil, 1
-- suspect = {id, crime, blip, deadline, pinned}

function V.in_cop_car()
  return G.vehicle ~= nil and engine.mesh_of(G.vehicle) == "cop"
end

-- The next junction for a suspect: of opts, the one farthest from you
-- (from the junction it's at, so a road that doubles back loses), now and
-- then just any road. nil leaves it to traffic's own pick.
function V.flee(c, opts)
  local px, _, pz = U.player_pos()
  if not px or math.random() > math.min(V.SMART_MAX, V.SMART + (level - 1) * V.SMART_STEP) then return nil end
  local best, bd
  for _, n in ipairs(opts) do
    local x, z = city.pos(n)
    local d = U.dist2d(x, z, px, pz)
    if d > (bd or -1) then best, bd = n, d end
  end
  return best
end

-- Is id the suspect being chased? (lib/wanted: rams on it aren't crimes.)
function V.is_suspect(id) return suspect ~= nil and suspect.id == id end

local function clear()
  if suspect then
    errand.siren_off(suspect.siren)
    errand.forget(suspect.blip)
    local c = traffic.cars[suspect.id]
    -- Back to plain traffic, recycled out of sight like the rest.
    if c then c.keep, c.cruise, c.choose = nil, nil, nil end
  end
  state, suspect, G.errand, G.errand_deadline = nil, nil, nil, nil
  next_at = engine.time() + V.EVERY
end

local function end_shift(why)
  if why then U.message(why, 3) end
  if level > 1 then engine.emit("vigilante_over", level) end
  level, on_duty = 1, nil
  clear()
end

local function got_away(why)
  U.message(why, 3)
  engine.emit("suspect_escaped")
  -- It keeps going, out of the chase.
  clear()
end

-- A junction NEAR..FAR m from (x, z) that a car can drive off from, or nil.
local function start_near(x, z)
  for _ = 1, 8 do
    local j = city.random_near(x, z, V.NEAR, V.FAR)
    if j and #city.links(j) > 0 then return j end
  end
end

-- A suspect sets off from near (x, z). Returns its id, or nil.
function V.call(x, z)
  local j = start_near(x, z)
  if not j then return nil end
  G.stats.suspects = (G.stats.suspects or 0) + 1
  local kind = errand.kinds(CRIMES, G.stats.suspects)[1]
  local jx, jz = city.pos(j)
  local id = vehicle.spawn(jx, jz, 0, nil, "sports")
  H.set(id, H.VEHICLE_HP * (1 + (level - 1) * V.HP_STEP))
  local cruise = math.min(V.CRUISE_MAX, V.CRUISE + (level - 1) * V.CRUISE_STEP)
  local c = traffic.adopt(id, {keep = true, cruise = cruise})
  c.choose = V.flee
  local a, b = c.path and c.path[1], c.path and c.path[2]
  if a and b and (a[1] ~= b[1] or a[2] ~= b[2]) then engine.orient(id, math.atan(b[1] - a[1], b[2] - a[2])) end
  local blip = {id = id, color = {1, 0.15, 0.15}}
  G.markers[#G.markers + 1] = blip
  suspect = {id = id, crime = kind[1], blip = blip, deadline = engine.time() + V.CLOCK, pinned = 0, cruise = cruise,
             siren = errand.siren()}
  state = "chase"
  local street = city.street(jx, jz)
  G.errand = "Vigilante: stop the suspect" .. (street and (" (" .. street .. ")") or "") .. "."
  G.errand_deadline = suspect.deadline
  U.message("SUSPECT, LEVEL " .. level .. ": " .. kind[1]:upper(), 4)
  engine.play("pickup")
  engine.emit("suspect_called", kind[1], level)
  return id
end

local function caught(how)
  local pay = V.PAY * level
  G.cash = G.cash + pay
  G.stats.suspects_caught = (G.stats.suspects_caught or 0) + 1
  require("lib.progress").touch()
  engine.play("pickup")
  U.message(string.format("%s +$%d", how, pay), 4)
  engine.emit("suspect_caught", level, pay)
  V.last = {pay = pay, level = level, how = how}
  level = math.min(V.MAX_LEVEL, level + 1)
  clear()
end

engine.on("killed", function(id)
  if V.is_suspect(id) then caught("SUSPECT WRECKED") end
end)

engine.on("tick", function(dt)
  local now = engine.time()
  local duty = V.in_cop_car() and not G.mission and not G.dead and wanted.stars() == 0
  if not state then
    if not duty then
      if on_duty then end_shift() end
      return
    end
    if not on_duty then
      on_duty, next_at = true, now + V.FIRST
      U.message("ON PATROL: SUSPECTS WILL BE CALLED IN", 3)
      return
    end
    if now >= next_at then
      local x, _, z = U.player_pos()
      if not V.call(x, z) then next_at = now + 30 end
    end
    return
  end
  if G.mission then return end_shift() end
  if not V.in_cop_car() then return end_shift("SHIFT OVER: YOU LEFT THE POLICE CAR") end
  if wanted.stars() > 0 then return end_shift("SHIFT OVER: THE REAL POLICE WANT YOU") end
  local id = suspect.id
  if not engine.exists(id) then return got_away("THE SUSPECT IS GONE") end
  if now > suspect.deadline then return got_away("THE SUSPECT GOT AWAY") end
  local x, _, z = engine.pos(id)
  local px, _, pz = U.player_pos()
  if px and U.dist2d(x, z, px, pz) > V.GONE then return got_away("LOST THE SUSPECT") end
  -- You on its tail: it floors it.
  local c = traffic.cars[id]
  if c and suspect.cruise and px then
    c.cruise = suspect.cruise + (U.dist2d(x, z, px, pz) < V.PANIC and V.PANIC_BOOST or 0)
  end
  -- Boxed in: stopped, with you right there.
  local stopped = math.abs(vehicle.speed(id)) < 1.5 and px and U.dist2d(x, z, px, pz) < V.PIN
  suspect.pinned = stopped and suspect.pinned + dt or 0
  if suspect.pinned >= V.PIN_SECS then caught("SUSPECT ARRESTED") end
end)

-- For tests.
V.state = function() return state end
V.suspect = function() return suspect end
V.level = function() return level end
function V.soon() next_at = engine.time() end

return V
