-- Toriparkki (systems/toriparkki, docs/UNDERGROUND.md piece 5): from
-- Louhi's hall by car out its east end, round into Toriparkki's arm, up
-- its ramp and out into the street; back down the ramp and into the car
-- park's first aisle; then at two stars a cop car comes in down the ramp
-- after you.
-- TORIPARKKI_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local vehicle = require "lib.vehicle"
local robot = require "test.robot"
local Lh = require "systems.louhi"
local Tp = require "systems.toriparkki"
local wanted = require "lib.wanted"
local police = require "systems.police"

local log = {}
local function check(ok, what)
  print(string.format("TORIPARKKI: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
  if not ok then log.bad = (log.bad and log.bad .. "; " or "") .. what end
end
local function finish()
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("TORIPARKKI: %d checks, %d failed", #log, bad))
  if bad > 0 then engine.quit(); error("Toriparkki doesn't work: " .. log.bad, 0) end
  print("ALL TORIPARKKI CHECKS PASSED")
  engine.quit()
end

local driver
input.drive = function()
  if not (G.vehicle and driver) then return 0, 0, true end
  return driver.inputs(G.vehicle)
end
local function route(pts)
  local out = {}
  for _, p in ipairs(pts) do out[#out + 1] = {Lh.hall_xz(p[1], p[2])} end
  return out
end

local step, t, car, worst, hurt = 0, 0, nil, 0, false
local taken -- a parked car down here, got into (made a car like any other)
local cop_down, closest, busted = false, math.huge, false
local mid = 37.45
engine.on("damaged", function(id) if id == car then hurt = true end end)
engine.on("busted", function() if step == 3 then busted = true end end)

engine.on("tick", function(dt)
  if engine.ticks() < 30 or not G.player and not G.vehicle then return end
  t = t + dt
  if car and engine.exists(car) and Lh.down(car) then
    local x, y, z = engine.pos(car)
    local f = Lh.area_floor(x, z, 0)
    if f then worst = math.max(worst, math.abs(y - 0.75 - f)) end
  end
  if step == 0 then
    check(Lh.built and Tp.portal ~= nil, "Toriparkki is built")
    check(Tp.ys and Tp.ys > 4 and Tp.ys < 14, string.format("its ramp comes up to the street at %.1f m", Tp.ys or 0))
    check(#Tp.cars > 30 and engine.tag(Tp.cars[1]) == "parked", string.format("%d cars parked, standing still till taken", #Tp.cars))
    taken = require("systems.parking").release(Tp.cars[1])
    -- A car in Louhi's hall, by its east end, facing the way through.
    local sx, sz = Lh.hall_xz(80, 6.5)
    local ex, ez = Lh.hall_xz(81, 6.5)
    car = vehicle.spawn(sx, sz, math.atan(ex - sx, ez - sz), 3, nil, nil, Lh.HALL_Y)
    engine.set_layer(car, Lh.LAYER)
    Lh.took[car] = true
    if G.player then engine.despawn(G.player) end
    G.player, G.vehicle = nil, car
    engine.emit("vehicle_enter", car)
    driver = robot.driver(route{{100, 6.75}, {106, 6.75}, {112, 9}, {115, 15}, {115, 30}, {116, 40}, {125, 41}, {140, mid}, {155, mid},
                                {170, mid}, {195, mid}, {210, mid}, {222, mid}}, 7, 4)
    step, t = 1, 0
  elseif step == 1 then
    local x, _, z = engine.pos(car)
    if engine.layer(car) == 1 and Lh.part(x, z) == "tori" then Tp.seen_tori = true end
    local a = Lh.hall_ab(x, z)
    if a > 216 or t > 90 then
      check(Tp.seen_tori == true, "through the link into Toriparkki")
      check(engine.layer(car) == 0 and engine.view_layer() == 0, "up the ramp and out, in layer 0")
      check(a > 205, string.format("out in the street (%.0f m along, the mouth at 203)", a))
      local _, y = engine.pos(car)
      check(math.abs(y - 0.75 - U.ground(x, z)) < 1.2, string.format("on the street (y %.1f, it at %.1f)", y, U.ground(x, z)))
      check(worst < 0.8, string.format("on the floor all the way down there (worst %.2f m off)", worst))
      check(not hurt, "not a scratch")
      local tx, ty, tz = engine.pos(taken)
      check(engine.layer(taken) == 1 and math.abs(ty - 0.75 - Lh.area_floor(tx, tz, 0)) < 0.3,
            string.format("a parked one taken is a car down here, on the floor (y %.2f)", ty))
      -- Back in: turn round and down.
      engine.set_vel(car, 0, 0, 0)
      local px, pz = Lh.hall_xz(224, mid)
      local qx, qz = Lh.hall_xz(223, mid)
      engine.set_pos(car, px, U.ground(px, pz) + 0.9, pz)
      engine.set_yaw(car, math.atan(qx - px, qz - pz))
      worst = 0
      driver = robot.driver(route{{210, mid}, {195, mid}, {170, mid}, {150, mid}, {130, 42}, {124, 49}, {118, Tp.AISLES[1]},
                                  {100, Tp.AISLES[1]}, {80, Tp.AISLES[1]}}, 7, 4)
      step, t = 2, 0
    end
  elseif step == 2 then
    local x, _, z = engine.pos(car)
    local a, c = Lh.hall_ab(x, z)
    if (a < 84 and c > 48) or t > 90 then
      check(engine.layer(car) == 1 and engine.view_layer() == 1, "back down the ramp, in layer 1")
      check(Lh.part(x, z) == "tori" and a < 95 and math.abs(c - Tp.AISLES[1]) < 4,
            string.format("along the first aisle (%.0f, %.0f)", a, c))
      check(worst < 0.8, string.format("on the floor all the way (worst %.2f m off)", worst))
      engine.set_vel(car, 0, 0, 0)
      driver.pts = {}
      -- Wanted: they saw you go in at the ramp. (None of them down here
      -- already: a patrol car can come down the ramp behind you.)
      police.clear()
      wanted.set(2)
      local ox, oz = Lh.hall_xz(Tp.portal.outside[1], Tp.portal.outside[2])
      wanted.center = {ox, oz, Tp.ys}
      step, t = 3, 0
    end
  elseif step == 3 then
    if G.vehicle == car then engine.set_vel(car, 0, 0, 0) end
    local x, _, z = engine.pos(car)
    for id in pairs(police.cops) do
      local cx, _, cz = engine.pos(id)
      if cx and engine.layer(id) == 1 then
        cop_down = true
        closest = math.min(closest, U.dist2d(cx, cz, x, z))
      end
    end
    if (cop_down and closest < 30) or busted or t > 150 then
      check(busted or wanted.stars() > 0, "parked 130 m from the ramp, you didn't lose them just by being down here")
      check(cop_down, string.format("a cop car came down the ramp after you (after %.0f s)", t))
      check(closest < 30 or busted, string.format("and got to you (%.0f m%s)", closest, busted and ", busted" or ""))
      finish()
    end
  end
end)

