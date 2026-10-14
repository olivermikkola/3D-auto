-- Drive Föli municipal bus: pick up passengers at the central transit hub,
-- make scheduled stops along regional corridors, and deliver passengers to the destination terminal.
local city = require "lib.city"
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local function get_route()
  if city.map().id == "turku" then
    return {
      line = "Line 1: Kauppatori - Satama",
      start_pos = {0, 0}, -- Kauppatori
      stops = {
        {name = "Turun Tuomiokirkko (Cathedral)", pos = {320, -180}},
        {name = "TYKS / University Hospital", pos = {450, 200}},
        {name = "Kupittaanpuisto / Campus", pos = {950, -450}},
        {name = "Turun linna (Castle) Terminal", pos = {-1350, 800}},
      },
    }
  else
    return {
      line = "Line 7: Raisio - Mylly",
      start_pos = {870, -1700}, -- Raisiontori
      stops = {
        {name = "Tasalanaukio", pos = {750, -1650}},
        {name = "Raision lukio & kirjasto", pos = {1077, -1144}},
        {name = "Kuloisten koulu", pos = {1850, -1750}},
        {name = "Kauppakeskus Mylly Terminal", pos = {2700, -2200}},
      },
    }
  end
end

local route = get_route()

return {
  title = "Föli Transit Run",
  after = "01_joyride",
  start = route.start_pos,
  reward = 1800,
  run = function(m)
    local cur_route = get_route()
    local start_pos = cur_route.start_pos
    local stops = cur_route.stops

    m:timer(280)
    m:say("Take the wheel of the Föli municipal bus at the transit rank.")

    -- Spawn assigned Föli bus at the bus rank
    local bus_id = m:spawn(vehicle.spawn(start_pos[1], start_pos[2], 0, nil, "bus", "bus"))

    m:wait(function()
      return m:in_vehicle(bus_id)
    end)
    U.message(string.format("%s SERVICE ACTIVE", string.upper(route.line)), 3)
    engine.play("star")

    for i, stop in ipairs(stops) do
      local sp = stop.pos
      local marker = m:marker(sp[1], sp[2], {0.95, 0.85, 0.1}) -- Föli yellow marker
      m:say(string.format("Next stop (%d/%d): %s.", i, #stops, stop.name))

      -- Wait until bus halts inside the stop zone
      m:wait(function()
        local in_bus = m:in_vehicle(bus_id)
        local near = m:near(marker, 10)
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

    U.message("TRANSIT RUN COMPLETE: ALL PASSENGERS DELIVERED!", 4)
  end,
}
