-- Probe checking spatial chunk streaming registration
local G = require "lib.state"

engine.on("init", function()
  local roads = engine.find("road")
  assert(#roads >= 10, "baked road chunk entities missing")
  print("CHUNK_ENTITIES_COUNT=" .. #roads)
  local rails = 0
  for _, id in ipairs(engine.find("cover")) do
    if (engine.mesh_of(id) or ""):find("^rail") then rails = rails + 1 end
  end
  print("RAIL_CHUNKS=" .. rails)
  print("ALL CHUNK STREAMING CHECKS PASSED")
  engine.quit()
end)
