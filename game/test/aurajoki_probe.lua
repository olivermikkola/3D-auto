-- Probe checking Aurajoki bridges, riverboat moorings, Föri ferry, and landmarks
local aurajoki = require "systems.aurajoki"
local city = require "lib.city"

engine.on("init", function()
  if city.map().id ~= "turku" then
    print("SKIPPING AURAJOKI PROBE ON NON-TURKU MAP")
    engine.quit()
    return
  end

  assert(aurajoki.bridges and #aurajoki.bridges == 5, "expected 5 Aurajoki bridges")
  print("AURAJOKI_OK bridges=" .. #aurajoki.bridges)

  -- Check ferry exists
  assert(aurajoki.fori and engine.exists(aurajoki.fori.id), "Föri ferry entity missing")
  assert(#aurajoki.riverboats >= 4, "expected at least 4 moored riverboats")

  -- Check landmarks (Castle & Cathedral)
  assert(aurajoki.landmarks.castle and engine.exists(aurajoki.landmarks.castle), "Turun linna castle missing")
  assert(aurajoki.landmarks.cathedral and engine.exists(aurajoki.landmarks.cathedral), "Tuomiokirkko cathedral missing")
  print("LANDMARKS_OK castle=" .. aurajoki.landmarks.castle .. " cathedral=" .. aurajoki.landmarks.cathedral)

  print("FORI_SHUTTLE_OK id=" .. aurajoki.fori.id)
  print("ALL AURAJOKI CHECKS PASSED")
  engine.quit()
end)
