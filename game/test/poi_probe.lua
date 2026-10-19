-- Points-of-interest probe: the map's OSM points are there, lib/pois finds
-- them by tag and distance, every hit has a street to stop on, and the same
-- question gives the same answer twice.
local city = require "lib.city"
local pois = require "lib.pois"

engine.on("init", function()
  local map = city.map().id or city.map().name
  if not city.network() then
    assert(pois.count() == 0 and #pois.find{amenity = true} == 0, "a grid map has no points of interest")
    print("POI_PROBE: grid map, nothing to find")
    print("POI_PROBE: PASSED")
    return
  end
  local t0 = os.clock()
  local sx, sz = city.place("lot")
  local from = {sx, sz}
  local function show(label, q)
    q.from = from
    local hits = pois.find(q)
    for _, p in ipairs(hits) do
      assert(p.road and p.junction and city.pos(p.junction), label .. ": a hit without a street: " .. tostring(p.name))
      local d = math.sqrt((p.road[1] - p.x) ^ 2 + (p.road[2] - p.z) ^ 2)
      assert(d <= (q.road_dist or 80) + 1e-6, string.format("%s: %s is %.0f m off its street", label, tostring(p.name), d))
      if q.min_dist then assert(p.dist >= q.min_dist, label .. ": too near") end
      if q.max_dist then assert(p.dist <= q.max_dist, label .. ": too far") end
    end
    local near = hits[1] and string.format(", nearest %s at %.0f m", hits[1].name or "(unnamed)", hits[1].dist) or ""
    print(string.format("POI_PROBE %s: %s: %d%s", map, label, #hits, near))
    return hits
  end
  print(string.format("POI_PROBE %s: %d points of interest", map, pois.count()))
  show("churches", {amenity = "place_of_worship"})
  local burgers = show("Hesburgers", {amenity = "fast_food", brand = "Hesburger"})
  for _, p in ipairs(burgers) do assert(p.tags.amenity == "fast_food", "a Hesburger that isn't a restaurant") end
  show("supermarkets over 5 km away", {shop = "supermarket", min_dist = 5000})
  show("supermarkets 1-3 km away", {shop = "supermarket", min_dist = 1000, max_dist = 3000})
  show("basketball courts", {leisure = "pitch", sport = "basketball"})
  show("cafes or bars", {amenity = {"cafe", "bar", "pub"}})
  local a = pois.find{shop = true, from = from, max_dist = 4000}
  local b = pois.find{shop = true, from = from, max_dist = 4000}
  assert(#a == #b, "the same question, a different number of answers")
  for i = 1, #a do assert(a[i].x == b[i].x and a[i].z == b[i].z, "the same question, a different order") end
  assert(#pois.find{shop = true, from = from, limit = 3} <= 3, "limit")
  assert(#pois.find{amenity = "no_such_thing"} == 0, "a tag value nobody has")
  if map == "turku" then
    local dome = pois.find{amenity = "place_of_worship", name = "Turun tuomiokirkko"}
    assert(#dome == 1, "Turku has its cathedral")
    print(string.format("POI_PROBE turku: cathedral stops at %.0f, %.0f (junction %d)", dome[1].road[1], dome[1].road[2], dome[1].junction))
  end
  print(string.format("POI_PROBE %s: %.0f ms", map, (os.clock() - t0) * 1000))
  print("POI_PROBE: PASSED")
end)
