-- Probe checking Aurajoki bridges, riverboat moorings, and Föri cable ferry
local aurajoki = require "systems.aurajoki"

engine.on("init", function()
  assert(aurajoki.bridges and #aurajoki.bridges == 5, "expected 5 Aurajoki bridges")
  print("AURAJOKI_OK bridges=" .. #aurajoki.bridges)

  -- Check ferry exists
  assert(aurajoki.fori and engine.exists(aurajoki.fori.id), "Föri ferry entity missing")
  assert(#aurajoki.riverboats >= 3, "expected at least 3 moored riverboats")

  print("FORI_SHUTTLE_OK id=" .. aurajoki.fori.id)
  print("ALL AURAJOKI CHECKS PASSED")
  engine.quit()
end)
