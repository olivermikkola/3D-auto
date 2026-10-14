-- Drive Föli Line 7 municipal bus: pick up passengers at Raisiontori,
-- make scheduled stops along Raisiontie and Tiedonpuisto, and arrive at Kauppakeskus Mylly.
local city = require "lib.city"
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local start_pos = {870, -1700} -- Raisiontori transit stop
local stops = {
  {name = "Tasalanaukio", pos = {750, -1650}},
  {name = "Raision lukio & kirjasto", pos = {1077, -1144}},
  {name = "Kuloisten koulu", pos = {1850, -1750}},
  {name = "Kauppakeskus Mylly Terminal", pos = {2700, -2200}},
}

return {
  title = "Föli Transit: Line 7",
  after = "01_joyride",
  start = start_pos,
  reward = 1500,
  run = function(m)
    m:timer(260)
    m:say("Take the wheel of the Föli municipal bus at Raisiontori.")

    -- Spawn assigned Föli bus at the bus rank
    local bus_id = m:spawn(vehicle.spawn(start_pos[1], start_pos[2], 0, nil, "bus", "bus"))

    m:wait(function()
      return m:in_vehicle(bus_id)
    end)
    U.message("LINE 7: RAISIO - MYLLY SERVICE ACTIVE", 3)
    engine.play("star")

    for i, stop in ipairs(stops) do
      local sp = stop.pos
      local marker = m:marker(sp[1], sp[2], {0.95, 0.85, 0.1}) -- Föli yellow marker
      m:say(string.format("Next stop (%d/%d): %s.", i, #stops, stop.name))

      -- Wait until bus halts inside the stop zone
      m:wait(function()
        local in_bus = m:in_vehicle(bus_id)
        local near = m:near(marker, 8)
        local stopped = math.abs(vehicle.speed(bus_id)) < 1.5
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

    U.message("LINE 7 COMPLETE: ALL PASSENGERS DELIVERED!", 4)
  end,
}
