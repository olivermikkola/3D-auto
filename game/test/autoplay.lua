-- Scripted playthrough: fakes the keyboard, checks the game reacts, quits.
-- Run: AUTO_TEST=1 auto game --headless 3000
local G = require "lib.state"
local vehicle = require "lib.vehicle"
local mission = require "lib.mission"
local city = require "lib.city"

local held = {}
engine.key = function(k) return held[k] == true end
local function press(k) engine.emit("key", k, true) end
local function check(cond, what)
  if not cond then error("AUTOPLAY FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local steps, t0, step_i = {}, nil, 1
local function at(sec, fn) steps[#steps + 1] = {sec, fn} end

local yaw0, car
at(0.5, function()
  check(G.player and engine.grounded(G.player), "player spawned on the ground")
  local x, y, z = engine.pos(G.player)
  local id = engine.nearest(x, y, z, 50, "car")
  local cx, _, cz = engine.pos(id)
  engine.set_pos(G.player, cx, 1.0, cz - 3.5) -- just behind its trunk
  press("e")
  check(G.vehicle == id, "entered the nearest car")
  car = id
  -- Put it at the start of a long north-south avenue.
  local ax, az = city.node(4, 0)
  engine.set_pos(car, ax, 0.8, az + 10)
  engine.set_yaw(car, 0)
  yaw0 = 0
  held.w = true
end)
at(3.5, function()
  check(vehicle.speed(car) > 15, string.format("car accelerates (%.1f m/s)", vehicle.speed(car)))
  held.a = true
end)
at(4.2, function()
  held.a, held.w = false, false
  check(math.abs(engine.yaw(car) - yaw0) > 0.3, "car steers")
  held.s = true
end)
at(7.0, function()
  held.s = false
  check(math.abs(vehicle.speed(car)) < 12, "car brakes")
  -- Teleport onto the Joyride start marker.
  local def = mission.defs[1]
  engine.set_pos(car, def.start[1], 0.8, def.start[2])
  engine.set_vel(car, 0, 0, 0)
end)
at(7.5, function()
  check(G.mission and G.mission.def.title == "Joyride", "mission starts at its marker")
  local gx, gz = city.node(1, 7)
  engine.set_pos(car, gx, 0.8, gz)
  engine.set_vel(car, 0, 0, 0)
end)
local stunts, cash0, max_y = 0, 0, 0
engine.on("stunt", function() stunts = stunts + 1 end)
at(8.5, function()
  check(G.mission == nil and G.cash == 250, "joyride passed, cash = " .. G.cash)
  check(engine.stats().voices > 0, "engine sounds playing (" .. engine.stats().voices .. " voices)")
  -- Line up on the big kicker in the stunt park and floor it.
  local cx, cz = city.block_center(G.city.stunt[1], G.city.stunt[2])
  engine.set_pos(car, cx, 0.8, cz - 26)
  engine.orient(car, 0)
  engine.set_vel(car, 0, 0, 26)
  engine.set_angvel(car, 0, 0, 0)
  cash0 = G.cash
  held.w = true
end)
engine.on("tick", function()
  if car and engine.exists(car) then
    local _, y = engine.pos(car)
    max_y = math.max(max_y, y)
  end
end)
at(13.0, function()
  held.w = false
  check(max_y > 4, string.format("ramp launched the car (peak %.1f m)", max_y))
  check(stunts >= 1 and G.cash > cash0, "stunt scored, cash = " .. G.cash)
  press("e")
  check(G.player and not G.vehicle, "got out of the car")
end)
at(13.5, function()
  local n = 0
  for _ in pairs(require("systems.traffic").cars) do n = n + 1 end
  local moving = 0
  for _, id in ipairs(engine.find("car")) do
    local vx, _, vz = engine.vel(id)
    if math.sqrt(vx * vx + vz * vz) > 3 then moving = moving + 1 end
  end
  check(moving >= n // 2, string.format("traffic is flowing (%d of %d moving)", moving, n))
  print("AUTOPLAY PASSED")
  engine.quit()
end)

engine.on("tick", function()
  t0 = t0 or engine.time()
  local s = steps[step_i]
  if s and engine.time() - t0 >= s[1] then
    step_i = step_i + 1
    s[2]()
  end
end)
