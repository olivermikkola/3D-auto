-- Each kind of vehicle pulls like itself: flat out on level ground, a car
-- levels off near 109 km/h, Pasi near 84 and the bus near 75, and the heavy
-- ones take longer to reach 50 km/h.
-- SPEED_TEST=1 MAP=starter auto game --headless 1800
local vehicle = require "lib.vehicle"

local function check(ok, what)
  if not ok then engine.quit(); error("SPEED TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

-- Out past the edge of town, one lane each, all facing +x.
local X0, Z0 = 6000, 6000
local runs = {
  {tag = "car", lo = 100, hi = 115},
  {tag = "pasi", lo = 78, hi = 90},
  {tag = "bus", lo = 68, hi = 80},
}
local t = 0
engine.on("tick", function()
  t = t + 1
  if t == 1 then
    engine.spawn{mesh = "cube", pos = {X0 + 1500, -0.5, Z0 + 30}, size = {3200, 1, 120}, body = "static", tag = "ground"}
    for i, r in ipairs(runs) do
      r.id = vehicle.spawn(X0, Z0 + i * 20, math.pi / 2, 1, r.tag ~= "car" and r.tag or nil, r.tag, 0)
      r.top = 0
    end
  elseif t > 60 then -- settled on the wheels
    for _, r in ipairs(runs) do
      vehicle.drive(r.id, 1 / 60, {throttle = 1})
      local kmh = vehicle.speed(r.id) * 3.6
      r.top = math.max(r.top, kmh)
      if kmh >= 50 and not r.to50 then r.to50 = (t - 60) / 60 end
    end
    if t == 60 + 60 * 25 then
      for _, r in ipairs(runs) do
        check(r.top >= r.lo and r.top <= r.hi,
              string.format("%s tops out at %.0f km/h (%d-%d)", r.tag, r.top, r.lo, r.hi))
        check(math.abs(r.top - vehicle.top_speed(r.id) * 3.6) < 3,
              string.format("%s: vehicle.top_speed says %.0f km/h", r.tag, vehicle.top_speed(r.id) * 3.6))
      end
      local car, pasi, bus = runs[1], runs[2], runs[3]
      check(car.to50 and bus.to50 and pasi.to50 and bus.to50 > car.to50 * 2 and pasi.to50 > car.to50 * 1.5,
            string.format("0-50 km/h: car %.1f s, Pasi %.1f s, bus %.1f s", car.to50 or -1, pasi.to50 or -1, bus.to50 or -1))
      print("SPEED TEST PASSED")
      engine.quit()
    end
  end
end)
