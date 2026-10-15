-- Probe checking Turun linna (Castle) and Port of Turku container berths.
local harbor = require "systems.harbor"

engine.on("init", function()
  assert(harbor.castle_id and engine.exists(harbor.castle_id), "Turun linna keep entity missing")
  local cx, cy, cz = engine.pos(harbor.castle_id)
  print(string.format("CASTLE_OK id=%d pos=%.1f,%.1f,%.1f", harbor.castle_id, cx, cy, cz))

  assert(harbor.bore_id and engine.exists(harbor.bore_id), "S/S Bore steamship entity missing")
  local bx, by, bz = engine.pos(harbor.bore_id)
  print(string.format("BORE_SHIP_OK id=%d pos=%.1f,%.1f,%.1f", harbor.bore_id, bx, by, bz))

  assert(#harbor.cranes >= 2, "expected at least 2 quayside cranes")
  print("PORT_CRANES_OK count=" .. #harbor.cranes)

  assert(#harbor.containers >= 4, "expected at least 4 container stacks")
  print("CONTAINER_BERTHS_OK count=" .. #harbor.containers)

  print("ALL CASTLE AND HARBOR CHECKS PASSED")
  engine.quit()
end)
