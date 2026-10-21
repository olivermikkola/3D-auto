-- Street lamps give way (systems/lamps): a car or bus driven into one at
-- speed knocks it flat and carries on; a car creeping into one stops.
-- LAMP_TEST=1 MAP=starter auto game --headless 1200
local vehicle = require "lib.vehicle"
local lamps = require "systems.lamps"

local function check(ok, what)
  if not ok then engine.quit(); error("LAMP TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

-- Out past the edge of town, one lane each, all facing +x, a lamp 70 m on.
local X0, Z0, AT = 6000, 6000, 70
local runs = {
  {name = "car flat out", tag = "car", knocks = true},
  {name = "car creeping", tag = "car", creep = 3.5, knocks = false, at = 25},
  {name = "bus flat out", tag = "bus", knocks = true},
}
local by_car = {}
engine.on("lamp_down", function(pole, car)
  local r = by_car[car]
  if r then r.pole, r.after = pole, vehicle.speed(car) end
end)

engine.on("contact", function(a, b)
  for _, r in ipairs(runs) do
    if (a == r.id and b == r.lamp) or (b == r.id and a == r.lamp) then r.touched = true end
  end
end)

local t = 0
engine.on("tick", function()
  t = t + 1
  if t == 1 then
    engine.spawn{mesh = "cube", pos = {X0 + 200, -0.5, Z0 + 40}, size = {500, 1, 120}, body = "static", tag = "ground"}
    for i, r in ipairs(runs) do
      local z = Z0 + i * 20
      r.lamp = engine.spawn{mesh = "lamp", pos = {X0 + (r.at or AT), 0, z}, yaw = math.pi / 2, size = {0.3, 10, 0.3}, tag = "lamp",
                            body = "static", breaks_at = lamps.BREAKS_AT}
      r.id = vehicle.spawn(X0, z, math.pi / 2, 1, r.tag ~= "car" and r.tag or nil, r.tag, 0)
      by_car[r.id] = r
    end
  elseif t > 60 then -- settled on the wheels
    for _, r in ipairs(runs) do
      local v = vehicle.speed(r.id)
      if not r.pole then r.before = v end
      r.top = math.max(r.top or 0, v)
      vehicle.drive(r.id, 1 / 60, {throttle = (not r.creep or v < r.creep) and 1 or 0})
    end
    if t == 60 + 60 * 14 then
      for _, r in ipairs(runs) do
        local x = engine.pos(r.id)
        if r.knocks then
          check(r.pole and not engine.exists(r.lamp),
                string.format("%s knocks the lamp over at %.0f km/h", r.name, (r.before or 0) * 3.6))
          check(x > X0 + AT + 10, string.format("%s carries on past it (%.0f m on)", r.name, x - X0 - AT))
          check(r.after > r.before * 0.6, string.format("%s keeps its speed: %.0f -> %.0f km/h", r.name, r.before * 3.6, r.after * 3.6))
          local px, py, pz = engine.pos(r.pole)
          local qx, _, qz = engine.rot(r.pole)
          local up = 1 - 2 * (qx * qx + qz * qz)
          check(py < 1.2 and math.abs(up) < 0.5,
                string.format("%s: the lamp lies on the ground (middle %.1f m up, upright %.2f)", r.name, py, up))
          check(px > X0 + AT and px < X0 + AT + 30,
                string.format("%s: it fell the way the car went, not pushed along (%.1f m on)", r.name, px - X0 - AT))
        else
          check(engine.exists(r.lamp) and not r.pole, string.format("%s doesn't knock it over (%.0f km/h)", r.name, r.top * 3.6))
          check(r.touched and x < X0 + r.at, string.format("%s runs into the post and stops there (%.1f m short)", r.name, X0 + r.at - x))
        end
      end
      print("LAMP TEST PASSED")
      engine.quit()
    end
  end
end)
