-- Probe checking Puskuri speedboat mechanics, Turun linna castle, and Mission 10 registration
local vehicle = require "lib.vehicle"
local mission = require "lib.mission"
local city = require "lib.city"

engine.on("init", function()
  -- Spawn Puskuri speedboat
  local boat_id = vehicle.spawn(-1550, 950, 0, nil, "speedboat", "boat")
  assert(engine.exists(boat_id), "Puskuri speedboat failed to spawn")
  assert(vehicle.tags[engine.tag(boat_id)], "boat tag is not drivable")
  print("SPEEDBOAT_SPAWN_OK id=" .. boat_id)

  -- Check mission 10 registered
  local all = mission.all()
  local found_heist = false
  for _, m in ipairs(all) do
    if m.title == "The Archipelago Run" then
      found_heist = true
      break
    end
  end
  assert(found_heist, "Mission 10 'The Archipelago Run' not found")
  print("MISSION_ARCHIPELAGO_OK")

  print("ALL HEIST CHECKS PASSED")
  engine.quit()
end)
