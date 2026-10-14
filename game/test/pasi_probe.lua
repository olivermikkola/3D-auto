-- Probe checking Sisu Pasi 6x6 APC vehicle mechanics and heist mission registration
local G = require "lib.state"
local vehicle = require "lib.vehicle"
local mission = require "lib.mission"
local wanted = require "lib.wanted"

engine.on("init", function()
  -- Test spawning Sisu Pasi vehicle directly
  local pasi_id = vehicle.spawn(850, -1700, 0, nil, "pasi", "pasi")
  assert(engine.exists(pasi_id), "Sisu Pasi vehicle failed to spawn")
  assert(vehicle.tags[engine.tag(pasi_id)], "pasi tag is not drivable")

  -- Check mass and size
  print("PASI_SPAWN_OK id=" .. pasi_id)

  -- Check mission 08_pansio_heist loaded
  local all = mission.all()
  local found_heist = false
  for _, m in ipairs(all) do
    if m.title == "Pansio Base Heist" then
      found_heist = true
      break
    end
  end
  assert(found_heist, "08_pansio_heist mission was not registered")

  -- Test 5-star wanted level dispatch of Pasi
  wanted.set(5)
  assert(wanted.stars() == 5, "5 star wanted level not set")

  print("ALL PASI PROBE CHECKS PASSED")
  engine.quit()
end)
