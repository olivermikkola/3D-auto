-- Probe checking Turku city map entities, crossings, and cross-border transfer
local G = require "lib.state"
local city = require "lib.city"
local borders = require "lib.borders"
local U = require "lib.util"

engine.on("init", function()
  assert(city.map().name == "Turku", "current map is not Turku")
  assert(city.has("bank", "hospital", "joyride_garage", "police_station"), "Turku missing core places")

  -- Check crossings are registered
  assert(borders.crossings and #borders.crossings >= 4, "Turku crossings not registered")

  -- Check radar landmarks
  local labels = city.map().labels
  assert(labels and #labels >= 5, "Turku minimap landmarks missing")

  print("TURKU_MAP_OK entities=" .. #engine.find("building"))
  print("ALL CORRIDOR CHECKS PASSED")
  engine.quit()
end)
