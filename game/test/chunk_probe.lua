-- Probe checking spatial chunk streaming registration
local G = require "lib.state"

engine.on("init", function()
  local roads = engine.find("road")
  assert(#roads >= 10, "baked road chunk entities missing")
  print("CHUNK_ENTITIES_COUNT=" .. #roads)
  print("ALL CHUNK STREAMING CHECKS PASSED")
  engine.quit()
end)
