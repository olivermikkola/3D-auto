-- Districts and landmarks, and a drive up the car park: every ramp is
-- climbed with the real car controls, then off the roof kicker.
-- CITY_TEST=1 auto game --headless 2400
local G = require "lib.state"
local city = require "lib.city"
local vehicle = require "lib.vehicle"
local landmarks = require "lib.landmarks"

local held = {}
engine.key = function(k) return held[k] == true end
local function check(ok, what)
  if not ok then engine.quit(); error("CITY TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local car, stage, t0, stunts, peak = nil, 0, 0, 0, 0
local cx, cz, D, CURB

-- Put the car somewhere, pointing somewhere, at rest.
local function place(x, y, z, yaw)
  engine.set_pos(car, x, y + 0.8, z)
  engine.orient(car, yaw)
  engine.set_vel(car, 0, 0, 0)
  engine.set_angvel(car, 0, 0, 0)
  held = {w = true}
end

engine.on("stunt", function() stunts = stunts + 1 end)

local function setup()
  local L = G.city
  local count = {}
  for i = 0, L.N - 1 do
    for j = 0, L.N - 1 do
      local d = city.district(i, j)
      count[d] = (count[d] or 0) + 1
    end
  end
  check(count.industrial == 16 and count.residential == 12 and count.downtown == 36, "16 industrial, 12 residential, 36 downtown blocks")
  local houses, sheds = 0, 0
  for _, id in ipairs(engine.find("building")) do
    local m = engine.mesh_of(id) or ""
    if m:find("^house") then houses = houses + 1 elseif m:find("^warehouse") then sheds = sheds + 1 end
  end
  check(houses >= 20, houses .. " houses in the residential district")
  check(sheds >= 20, sheds .. " warehouses in the industrial district")
  check(#engine.find("container") >= 20, #engine.find("container") .. " yards of shipping containers")
  check(#L.landmarks == 2 and #engine.find("landmark") == 1, "a TV tower and a car park")
  local tx, tz = city.block_center(L.tower[1], L.tower[2])
  local hit = engine.raycast(tx - 20, 60, tz, 1, 0, 0, 40)
  check(hit and engine.tag(hit) == "landmark", "the tower is solid at 60 m up")

  cx, cz = city.block_center(L.carpark[1], L.carpark[2])
  D, CURB = landmarks.DECK, L.curb
  engine.despawn(G.player)
  G.player = nil
  car = vehicle.spawn(cx + 12, cz + 17, math.pi)
  G.vehicle = car
  place(cx + 12, 0, cz + 17, math.pi) -- south of the first ramp, facing north
end

-- Each leg: drive until past `z_stop`, brake, and check the deck we're on.
local legs = {
  {dir = -1, z_stop = -6, deck = 1, next = function() place(cx - 12, CURB + D, cz - 12, 0) end},
  {dir = 1, z_stop = 6, deck = 2, next = function() place(cx + 12, CURB + 2 * D, cz + 12, math.pi) end},
  {dir = -1, z_stop = -6, deck = 3, next = function() place(cx, CURB + 3 * D, cz - 8, 0) end},
}

engine.on("tick", function(dt)
  if stage == 0 then
    if engine.ticks() < 30 then return end
    setup()
    stage, t0 = 1, engine.time()
    return
  end
  local x, y, z = engine.pos(car)
  local leg = legs[stage]
  if leg then
    if held.w and (z - cz - leg.z_stop) * leg.dir > 0 then
      held = {space = true, s = true}
    end
    if not held.w and math.abs(vehicle.speed(car)) < 0.5 then
      local want = CURB + leg.deck * D
      check(math.abs(y - 0.75 - want) < 0.5, string.format("drove up to deck %d (%.1f m)", leg.deck, y - 0.75))
      leg.next()
      stage, t0 = stage + 1, engine.time()
    elseif engine.time() - t0 > 12 then
      check(false, string.format("stuck on the way to deck %d at (%.1f, %.1f, %.1f)", leg.deck, x - cx, y, z - cz))
    end
  elseif stage == 4 then
    peak = math.max(peak, y)
    if stunts > 0 then
      check(peak > CURB + 3 * D + 2, string.format("the roof kicker launches the car (peak %.1f m)", peak))
      print("CITY TEST PASSED")
      stage = 5
      engine.quit()
    elseif engine.time() - t0 > 10 then
      check(false, "no stunt off the roof")
    end
  end
end)
