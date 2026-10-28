-- Look behind: in a car, holding C (or the right stick's click) turns the
-- camera to look back the way you came at once, and letting go turns it
-- straight back. LOOKBACK_TEST=1 auto game --headless 600
local G = require "lib.state"
local U = require "lib.util"
local vehicle = require "lib.vehicle"
local real_key, held = engine.key, false
engine.key = function(k) if k == "pad_r3" then return held end return real_key(k) end

local function check(ok, what)
  if not ok then engine.quit(); error("LOOKBACK TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end
local function frames(n) for _ = 1, n do coroutine.yield() end end
-- Where the camera looks, against the car's heading (0 = ahead).
local function looking()
  local e, t = G.cam_eye, G.cam_target
  return math.abs(U.angle_diff(engine.yaw(G.vehicle), math.atan(t[1] - e[1], t[3] - e[3])))
end

local co = coroutine.create(function()
  frames(30)
  local x, y, z = engine.pos(G.player)
  local car = vehicle.spawn(x + 4, z, 0.7)
  engine.despawn(G.player)
  G.player, G.vehicle = nil, car
  engine.emit("vehicle_enter", car)
  frames(120)
  check(looking() < 0.3, string.format("looking ahead in the car (%.2f rad off)", looking()))
  held = true
  frames(2)
  check(looking() > math.pi - 0.3, string.format("held: looking back (%.2f rad off)", looking()))
  frames(60)
  check(looking() > math.pi - 0.3, "still looking back while held")
  held = false
  frames(2)
  check(looking() < 0.3, string.format("let go: ahead again (%.2f rad off)", looking()))
  print("LOOKBACK_PROBE: PASSED")
  engine.quit()
end)
engine.on("frame", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
