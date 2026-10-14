-- Drive Föli municipal bus: Line 7 in Raisio (Raisiontori -> Mylly)
-- or Line 1 in Turku (Kauppatori -> Tuomiokirkko -> Kupittaa -> Satama).
local city = require "lib.city"
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local is_turku = city.map().id == "turku" or city.map().name == "Turku"

local start_pos = is_turku and {-180, 80} or {870, -1700}
local stops = is_turku and {
  {name = "Kauppatori D-laituri", pos = {-180, 80}},
  {name = "Tuomiokirkontori", pos = {320, -90}},
  {name = "Kupittaan asema & TYKS", pos = {850, 490}},
  {name = "Turun Satama & Linna", pos = {-2600, 1750}},
} or {
  {name = "Tasalanaukio", pos = {750, -1650}},
  {name = "Raision lukio & kirjasto", pos = {1077, -1144}},
  {name = "Kuloisten koulu", pos = {1850, -1750}},
  {name = "Kauppakeskus Mylly Terminal", pos = {2700, -2200}},
}

local title = is_turku and "Föli Transit: Line 1" or "Föli Transit: Line 7"

return {
  title = title,
  after = "01_joyride",
  start = start_pos,
  reward = 1500,
  run = function(m)
    m:timer(260)
    m:say("Take the wheel of the Föli municipal bus at " .. (is_turku and "Kauppatori." or "Raisiontori."))

    -- Spawn assigned Föli bus at the bus rank
    local bus_id = m:spawn(vehicle.spawn(start_pos[1], start_pos[2], 0, nil, "bus", "bus"))

    m:wait(function()
      return m:in_vehicle(bus_id)
    end)
    U.message(is_turku and "LINE 1: KAUPPATORI - SATAMA ACTIVE" or "LINE 7: RAISIO - MYLLY SERVICE ACTIVE", 3)
    engine.play("star")

    for i, stop in ipairs(stops) do
      local sp = stop.pos
      local marker = m:marker(sp[1], sp[2], {0.95, 0.85, 0.1}) -- Föli yellow marker
      m:say(string.format("Next stop (%d/%d): %s.", i, #stops, stop.name))

      -- Wait until bus halts inside the stop zone
      m:wait(function()
        local in_bus = m:in_vehicle(bus_id)
        local near = m:near(marker, 12)
        local stopped = math.abs(vehicle.speed(bus_id)) < 2.0
        if not in_bus then
          m:say("Get back in your Föli bus!")
        end
        return in_bus and near and stopped
      end)

      m:remove(marker)
      engine.play("pickup")
      U.message(string.format("STOP COMPLETED: %s", stop.name), 2)
      m:sleep(2.0) -- passenger boarding/alighting pause
    end

    U.message("FÖLI TRANSIT COMPLETE: ALL PASSENGERS DELIVERED!", 4)
  end,
}
