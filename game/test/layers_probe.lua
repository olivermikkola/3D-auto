-- Layers (engine::Entity::layer): underground, under the hill by
-- Puolalanpuisto, a floor and a box in layer 1 stay where they are, the
-- terrain over them pushing nothing up, and the player stands on that
-- floor; rays from the street see the street, rays in layer 1 the cave.
-- LAYERS_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"

local log = {}
local function check(ok, what)
  print(string.format("LAYERS: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
end

local X, Z = -430, -200 -- on the hill
local step, t0, floor, box, y0 = 0, 0, nil, nil, nil
engine.on("tick", function()
  if not G.player or engine.ticks() < 30 then return end
  if step == 0 then
    G.vehicle = nil
    local g = engine.terrain_height(X, Z)
    y0 = g - 8 -- the cave floor's top, 8 m under the grass
    floor = engine.spawn{pos = {X, y0 - 0.5, Z}, size = {30, 1, 30}, body = "static", mesh = "cube", layer = 1, tag = "wall"}
    box = engine.spawn{pos = {X + 5, y0 + 1, Z}, size = {1, 1, 1}, body = "dynamic", mesh = "cube", layer = 1}
    check(engine.layer(floor) == 1 and engine.layer(box) == 1 and engine.layer(G.player) == 0, "spawned in layer 1")
    engine.set_layer(G.player, 1)
    engine.set_pos(G.player, X, y0 + 1.2, Z)
    engine.set_vel(G.player, 0, 0, 0)
    check(engine.layer(G.player) == 1, "the player went down to layer 1")
    check(engine.view_layer() == 0 and engine.view_layer(1) == 1 and engine.view_layer() == 1, "the view goes down with them")
    step, t0 = 1, engine.ticks()
  elseif step == 1 and engine.ticks() - t0 >= 120 then
    local _, by = engine.pos(box)
    local _, py = engine.pos(G.player)
    check(math.abs(by - (y0 + 0.5)) < 0.15, string.format("the box rests on the cave floor (y %.2f, floor %.2f)", by, y0))
    check(py > y0 and py < y0 + 2.5, string.format("the player stands in the cave (y %.2f, floor %.2f)", py, y0))
    local g = engine.terrain_height(X + 5, Z)
    local hit = engine.raycast(X + 5, g + 20, Z, 0, -1, 0, 60)
    check(hit and engine.tag(hit) == "terrain", "from the street, a ray down meets the grass")
    hit = engine.raycast(X + 5, g + 20, Z, 0, -1, 0, 60, nil, 1)
    check(hit == box, "in layer 1, the same ray meets the box under it")
    hit = engine.raycast(X + 5, y0 + 0.5, Z, 0, -1, 0, 5, box)
    check(hit == floor, "from the box, a ray (in its layer) meets the floor")
    hit = engine.raycast(X + 5, g + 20, Z, 0, -1, 0, 60, nil, -1)
    check(hit and engine.tag(hit) == "terrain", "every layer: the grass first")
    engine.set_layer(G.player, 0)
    engine.view_layer(0)
    local bad = 0
    for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
    print(string.format("LAYERS: %d checks, %d failed", #log, bad))
    assert(bad == 0, "layers don't keep to themselves")
    print("ALL LAYERS CHECKS PASSED")
    engine.quit()
  end
end)
