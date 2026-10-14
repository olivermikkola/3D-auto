-- Probe checking glazed balconies and commercial glass facades
local G = require "lib.state"

engine.on("init", function()
  local buildings = engine.find("building")
  assert(#buildings >= 200, "not enough buildings spawned")

  local balconies = 0
  local glass_shops = 0
  for _, id in ipairs(buildings) do
    local m = engine.mesh_of(id) or ""
    if m:find("^balconies") then
      balconies = balconies + 1
    elseif m:find("^glass") then
      glass_shops = glass_shops + 1
    end
  end

  print(string.format("ARCHITECTURE_COUNTS balconies=%d glass_shops=%d", balconies, glass_shops))
  assert(balconies >= 20, "procedural glazed balconies not generated for flats")
  assert(glass_shops >= 10, "glass facades not generated for commercial/retail buildings")
  print("ALL ARCHITECTURE CHECKS PASSED")
  engine.quit()
end)
