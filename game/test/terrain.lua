-- The ground as a heightfield (engine.terrain): a 10 m hill out past the
-- edge of town. Its height and slope are where the surface says, a crate
-- lands and rests on it, rays stop at it, and a car drives up and over.
-- TERRAIN_TEST=1 auto game --headless 2400
local G = require "lib.state"
local vehicle = require "lib.vehicle"

local function check(ok, what)
  if not ok then engine.quit(); error("TERRAIN TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

-- 300 x 200 m at 5 m, a round hill in the middle.
local X0, Z0, STEP, W, D = 6000, -100, 5, 61, 41
local CX, CZ, PEAK, R = X0 + 150, Z0 + 100, 10, 45
local function hill(x, z) return 0.2 + PEAK * math.exp(-((x - CX) ^ 2 + (z - CZ) ^ 2) / (2 * R * R)) end
local heights = {}
for j = 0, D - 1 do
  for i = 0, W - 1 do heights[#heights + 1] = hill(X0 + i * STEP, Z0 + j * STEP) end
end
engine.terrain{x0 = X0, z0 = Z0, step = STEP, w = W, d = D, heights = heights}

local h, nx, ny = engine.terrain_height(CX, CZ)
check(h and math.abs(h - hill(CX, CZ)) < 1e-3 and ny > 0.999, string.format("the top is %.1f m high and level", h or -1))
h, nx, ny = engine.terrain_height(CX - R, CZ)
check(h and nx < -0.05 and ny < 1, string.format("partway up, %.1f m, the ground leans (normal x %.2f)", h, nx))
check(engine.terrain_height(X0 - 1, CZ) == nil, "off the edge there's no terrain")
check(#engine.find("terrain") == 1 and #engine.find("terrain_mesh") > 0, "one terrain body, drawn in chunks")

local hit, dist = engine.raycast(CX, 50, CZ, 0, -1, 0, 100)
check(hit and engine.tag(hit) == "terrain" and math.abs(50 - dist - hill(CX, CZ)) < 0.05,
      "a ray straight down stops at the hilltop")

local crate, car
local t, top, phase = 0, 0, "fall"
engine.on("tick", function()
  t = t + 1
  if t == 1 then -- once the game's models exist
    crate = engine.spawn{mesh = "crate", pos = {CX - 20, 25, CZ + 10}, size = 1, body = "dynamic", mass = 30, tag = "crate"}
    car = vehicle.spawn(X0 + 20, CZ, math.pi / 2, 1)
    engine.set_pos(car, X0 + 20, hill(X0 + 20, CZ) + 1, CZ)
  elseif phase == "fall" and t == 180 then
    local x, y, z = engine.pos(crate)
    local g = engine.terrain_height(x, z)
    local _, vy = engine.vel(crate)
    check(math.abs(vy) < 0.1 and y > g and y < g + 1.2, string.format("the crate landed and rests on the slope (%.2f m over it)", y - g))
    check(engine.grounded(crate), "and counts as grounded")
    phase = "drive"
  elseif phase == "drive" then
    vehicle.drive(car, 1 / 60, {throttle = 1})
    local x, y = engine.pos(car)
    top = math.max(top, y)
    if x > CX + 70 then
      check(top > hill(CX, CZ), string.format("a car drove up and over the hill (topped %.1f m)", top))
      check(vehicle.on_wheels(car), "and it's still on its wheels")
      engine.terrain(nil)
      check(#engine.find("terrain") == 0 and #engine.find("terrain_mesh") == 0 and engine.terrain_height(CX, CZ) == nil,
            "engine.terrain(nil) takes it all away")
      print("TERRAIN TEST PASSED")
      engine.quit()
      phase = "done"
    elseif t > 1800 then
      check(false, string.format("the car got stuck at x %.0f (hilltop %.0f), y %.1f", x, CX, y))
    end
  end
end)
