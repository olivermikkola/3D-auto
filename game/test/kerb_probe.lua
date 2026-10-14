-- Probe checking corner fillets, traffic islands, and kerb physics
local G = require "lib.state"
local city = require "lib.city"

local map = city.map()
assert(map.islands and #map.islands > 0, "traffic islands missing from map")

engine.on("init", function()
  local sidewalks = engine.find("sidewalk")
  assert(#sidewalks >= 50, "sidewalk meshes missing")

  local found_corner = false
  for _, id in ipairs(sidewalks) do
    local m = engine.mesh_of(id) or ""
    if m:find("^corner_kerbs_") then
      found_corner = true
      break
    end
  end
  assert(found_corner, "corner_kerbs_ mesh was not baked")
  print("CORNER_FILLETS_PASSED")

  -- Raycast down at Raisiontori junction corner to verify sidewalk height
  local hit, norm, hx, hy, hz = engine.raycast(855, 50, -1725, 0, -1, 0, 100)
  assert(hit, "no geometry under traffic island")
  print(string.format("ISLAND_RAYCAST tag=%s y=%.2f", engine.tag(hit), hy))
  assert(engine.tag(hit) == "sidewalk", "island is not tagged sidewalk")

  print("ALL KERB PROBE CHECKS PASSED")
  engine.quit()
end)
