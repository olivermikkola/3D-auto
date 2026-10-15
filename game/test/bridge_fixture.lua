-- Synthetic surveyed bridges, built by the production roadnet caller.
local R = require "lib.roadnet"
local twin = CASE == "twin" or CASE == "twin_reverse"
local overlap = CASE == "overlap"
local same = CASE == "same_level"
local high = CASE == "high_crossing"
local nx = overlap and 7 or 10
local nh = same and 5 or high and 0 or 4.2
local heights = {}
for z = -40, 40, 2 do
  for x = -40, 40, 2 do
    -- End abutments at 5 m, a valley under the deck, and a lower road beside it.
    local end_height = x >= 6 and nh or 5
    heights[#heights + 1] = math.abs(z) >= 30 and end_height or (x >= 6 and not twin and nh or 0)
  end
end
local deck = {name = "deck", width = 8, bridge = true, deck = true, lit = false, {0, -30}, {0, 30}}
local neighbour = {name = "neighbour", width = 8, lit = false, {nx, -30}, {nx, 30}}
if twin then neighbour.bridge, neighbour.deck = true, true end
local roads = CASE == "twin_reverse" and {neighbour, deck} or {deck, neighbour}
local map = {name = "bridge fixture", size = {80, 80}, junctions = {}, roads = roads,
             terrain = {x0 = -40, z0 = -40, step = 2, w = 41, d = 41, file = heights, classes = {}},
             footprints = {}, trees = 0, cover = {}}
R.load(map)
local slabs, concrete = {}, {}
local mesh = engine.mesh
engine.mesh = function(name, parts)
  if name:match("^road%d+$") then
    for _, p in ipairs(parts) do
      if p.mesh == "cube" and p.size[2] == 1.2 then concrete[#concrete + 1] = p end
    end
  end
  return mesh(name, parts)
end
R.build(map, {CURB = 0.2, FLOOR = 3.5,
  rng = function() return function(lo, hi) return lo and math.floor((lo + hi) / 2) or 0.5 end end,
  static = function(t)
    t.body = "static"
    if t.tag == "bridge" then slabs[#slabs + 1] = t end
    return engine.spawn(t)
  end})

local function lane_clear(x, y)
  for z = -29, 28 do
    local id = engine.raycast(x, y + 0.7, z, 0, 0, 1, 1)
    assert(not id, string.format("%s lane obstructed at x=%.2f z=%d by %s", CASE, x, z, id and engine.tag(id) or "?"))
  end
end
if CASE == "adjacent" or twin then
  lane_clear(nx - 3.5, nh)
  lane_clear(nx + 2, nh)
  lane_clear(nx - 3.5, nh + 0.5) -- also above slab height, where a railing would stand
  if twin then
    -- A lower twin must retain its own deck, not silently fall back to terrain.
    for k = -100, 100 do
      local id, _, _, y = engine.raycast(nx, nh + 0.4, k / 4, 0, -1, 0, 0.8)
      assert(id and engine.tag(id) == "bridge" and math.abs(y - nh) < 0.02, "lower twin lost its deck")
    end
  end
  assert(#concrete == #slabs, "each collider retains its concrete underside")
  local cut = 0
  for i, s in ipairs(slabs) do
    assert(s.size[1] >= 8, "must not cut into own asphalt")
    assert(math.abs(s.size[1] - concrete[i].size[1]) < 1e-6, "visible concrete must match collider width")
    if s.size[1] < 14 then cut = cut + 1 end
  end
  assert(cut > 0, "fixture must actually trim a deck")
elseif overlap then
  local id = engine.raycast(3.5, nh + 0.7, -31, 0, 0, 1, 4)
  assert(id and engine.tag(id) == "bridge", "real overlapping asphalt must remain detectable")
elseif same or high then
  for _, s in ipairs(slabs) do assert(s.size[1] == 14, "non-conflicting deck must keep full width") end
end
-- Downward collision support at both lanes and almost at each asphalt edge,
-- every 25 cm along all pieces, including their seams and both abutments.
for _, x in ipairs{-3.9, -2, 0, 2, 3.9} do
  for k = -120, 120 do
    local id, _, _, y = engine.raycast(x, 5.4, k / 4, 0, -1, 0, 1)
    assert(id and engine.tag(id) == "bridge", "gap in drivable bridge support")
    assert(math.abs(y - 5) < 0.02, "bridge surface height changed")
  end
  lane_clear(x, 5)
end
assert(#slabs >= 10 and #concrete == #slabs, "bridge structure was not built")
local piers = 0
for _, id in ipairs(engine.find("wall")) do
  local _, y = engine.pos(id)
  if y < 3 then piers = piers + 1 end
end
assert(piers > 0, "valley must retain bridge piers")
print("BRIDGE FIXTURE PASSED " .. CASE)
