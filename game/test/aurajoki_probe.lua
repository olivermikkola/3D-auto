-- Probe checking the Aurajoki: the real bridges clear the water, and every
-- boat, ship and the Föri floats on the surveyed river, not under a street.
local aurajoki = require "systems.aurajoki"
local R = require "lib.roadnet"

-- Is the whole of a hull (half sizes hw x hl, turned by yaw) on the water?
local function afloat(x, z, yaw, hw, hl)
  local c, s = math.cos(yaw), math.sin(yaw)
  for _, k in ipairs{{-1, -1}, {1, -1}, {-1, 1}, {1, 1}, {0, 0}} do
    local lx, lz = k[1] * hw, k[2] * hl
    if not R.water_level(x + lx * c + lz * s, z - lx * s + lz * c) then return false end
  end
  return true
end

engine.on("init", function()
  local named = {}
  for _, b in ipairs(aurajoki.bridges) do
    named[b.name] = true
    assert(b.deck - b.water >= 2.4, string.format("%s deck %.2f is on the water (%.2f)", b.name, b.deck, b.water))
  end
  for _, name in ipairs{"Tuomiokirkkosilta", "Auransilta", "Myllysilta", "Martinsilta"} do
    assert(named[name], name .. " is not a deck over the river")
  end
  print("AURAJOKI_OK bridges=" .. #aurajoki.bridges)

  -- The restaurant boats on the quays, where the map has them, and none
  -- of the map's boxes standing there as a house.
  assert(#aurajoki.riverboats >= 6, "expected the map's moored boats, got " .. #aurajoki.riverboats)
  for _, b in ipairs(aurajoki.riverboats) do
    local x, _, z = engine.pos(b.id)
    assert(afloat(x, z, engine.yaw(b.id), b.beam / 2 - 1, b.len / 2 - 3), string.format("riverboat at %.0f, %.0f is on land", x, z))
    for _, f in ipairs(require("lib.city").map().footprints) do
      assert(math.abs(f[1] - x) > 3 or math.abs(f[2] - z) > 3, string.format("a building box on the boat at %.0f, %.0f", x, z))
    end
  end
  local ship = aurajoki.joutsen
  assert(ship, "Suomen Joutsen missing")
  local x, _, z = engine.pos(ship.id)
  assert(afloat(x, z, engine.yaw(ship.id), ship.beam / 2 - 1, ship.len / 2 - 8), "Suomen Joutsen is on land")
  x, _, z = engine.pos(aurajoki.speedboat)
  assert(R.water_level(x, z), "speedboat is on land")
  print("BOATS_AFLOAT_OK")

  assert(aurajoki.fori and engine.exists(aurajoki.fori.id), "Föri ferry entity missing")
  local f = aurajoki.fori
  local p0, p1 = {-1166.2, 1174.0}, {-1258.2, 1117.2}
  for _, t in ipairs{f.t0, f.t1} do
    assert(R.water_level(p0[1] + (p1[1] - p0[1]) * t, p0[2] + (p1[2] - p0[2]) * t), "Föri runs onto land")
  end
  print("FORI_SHUTTLE_OK id=" .. f.id)

  -- Check Koroistenniemi bishop's cross landmark
  local landmarks = engine.find("landmark")
  local found_cross = false
  for _, id in ipairs(landmarks) do
    if engine.mesh_of(id) == "koroisten_risti" then
      found_cross = true
      break
    end
  end
  assert(found_cross, "Koroistenniemi White Bishop's Cross missing")
  print("KOROISTENNIEMI_CROSS_OK")

  print("ALL AURAJOKI CHECKS PASSED")
  engine.quit()
end)
