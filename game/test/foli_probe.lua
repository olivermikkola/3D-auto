-- Probe checking Föli bus vehicle mechanics and Line 7 mission registration
local G = require "lib.state"
local vehicle = require "lib.vehicle"
local mission = require "lib.mission"

engine.on("init", function()
  -- Spawn Föli bus
  local bus_id = vehicle.spawn(870, -1700, 0, nil, "bus", "bus")
  assert(engine.exists(bus_id), "Föli bus failed to spawn")
  assert(vehicle.tags[engine.tag(bus_id)], "bus tag is not drivable")
  print("FOLI_BUS_SPAWN_OK id=" .. bus_id)

  -- Verify Line 7 transit mission loaded
  local all = mission.all()
  local found_foli = false
  for _, m in ipairs(all) do
    if m.title == "Pöli Transit: Line 7" then
      found_foli = true
      break
    end
  end
  assert(found_foli, "09_foli_transit mission was not loaded")
  print("ALL FOLI CHECKS PASSED")
  engine.quit()
end)
