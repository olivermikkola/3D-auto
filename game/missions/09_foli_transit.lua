-- Drive a Pöli municipal bus down a line of real stops. On a map with
-- points of interest the line is cast per run (lib/template,
-- docs/MISSION_TEMPLATES.md): from the bus station (Turku: Kauppatori; on
-- a map without one, Raisiontori) past a school or library and a clinic
-- or hospital to a shopping centre or supermarket, each 400 m to 1.8 km on
-- by road. The grid maps have no stops, so no line.
local city = require "lib.city"
local U = require "lib.util"
local vehicle = require "lib.vehicle"
local pois = require "lib.pois"
local template = require "lib.template"

local is_turku = city.map().id == "turku"
-- Where the bus waits: the bus station nearest the old hand-placed rank
-- (Turku), or Raisiontori by hand (Raisio has no bus station in its data).
local start
local station = pois.find{amenity = "bus_station", name = true, from = {-180, 80}, limit = 1}[1]
if station then
  start = {station.road[1], station.road[2]}
elseif city.map().id == "raisio" then
  start = {870, -1700}
end
if not start then return false end

-- Each leg 400 m to 1.8 km by road (3 km if it must) from where the bus
-- stood at the last stop.
local LEG = {name = true, drive_min = 400, drive_max = 1800, relax = {{drive_max = 3000}},
             weight = function(p) return 1 / (1 + math.abs(p.drive - 900) / 500) end}
local STOPS = {
  {"school", amenity = {"school", "library", "college", "university"}},
  {"clinic", amenity = {"clinic", "hospital"}},
  {"shops", shop = {"mall", "supermarket"}},
}
local TRIES = 5

-- A line from `start`, or nil if some leg has no place in reach. `long`
-- lets a leg be as long as it takes.
local function line(seed, long)
  local stops, from, drive = {}, start, 0
  for i, stop in ipairs(STOPS) do
    local role = {}
    for k, v in pairs(stop) do role[k] = v end
    for k, v in pairs(LEG) do role[k] = v end
    if long then role.relax = {{drive_max = 3000}, {drive_min = 200, drive_max = false}} end
    local c = template.cast{seed = seed, from = from, roles = {role}}
    if not c then return end
    local p = c[stop[1]]
    stops[i], from, drive = p, {p.road[1], p.road[2]}, drive + p.drive
  end
  return stops, drive
end

-- The line's three stops and the time allowed for a seed, or nil. A stop
-- the road network leads badly out of (TYKS's driveways: the nearest shop
-- by road is kilometres off) makes another line be tried.
local function cast(seed)
  local stops, drive
  for k = 0, TRIES - 1 do
    stops, drive = line(seed + k * 1000)
    if stops then break end
  end
  if not stops then stops, drive = line(seed, true) end
  if not stops then return end
  -- A bus at about 8 m/s, 20 s at each stop, and a minute to get going.
  return stops, math.floor((60 + 20 * #stops + drive / 8) / 10 + 0.5) * 10
end

if not cast(1) then return false end

local title = is_turku and "Pöli Transit: Line 1" or "Pöli Transit: Line 7"
local from_name = station and station.name or "Raisiontori"

return {
  title = title,
  after = "01_joyride",
  start = start,
  reward = 1500,
  cast = cast, -- for test/template_probe
  run = function(m)
    local stops, seconds = cast(template.next_seed())
    local last = stops[#stops]
    m.goal = {last.road[1], last.road[2]}
    m:timer(seconds)
    m:say("Take the wheel of the Pöli bus at " .. from_name .. ".")
    local bus_id = m:spawn(vehicle.spawn(start[1], start[2], 0, nil, "bus", "bus"))
    m:wait(function() return m:in_vehicle(bus_id) end)
    U.message(title:upper() .. ": " .. from_name:upper() .. " - " .. last.name:upper(), 3)
    engine.play("star")

    for i, stop in ipairs(stops) do
      local sx, sz = stop.road[1], stop.road[2]
      local marker = m:marker(sx, sz, {0.95, 0.85, 0.1}) -- Pöli yellow
      m:say(string.format("Next stop (%d/%d): %s%s.", i, #stops, stop.name, m:on_street(sx, sz)))
      m:wait(function()
        local in_bus = m:in_vehicle(bus_id)
        if not in_bus then m:say("Get back in your Pöli bus!") end
        return in_bus and m:near(marker, 12) and math.abs(vehicle.speed(bus_id)) < 2.0
      end)
      m:remove(marker)
      engine.play("pickup")
      U.message("STOP: " .. stop.name:upper(), 2)
      m:sleep(2.0) -- passengers on and off
    end
    U.message("PÖLI TRANSIT COMPLETE: ALL PASSENGERS DELIVERED!", 4)
  end,
}
