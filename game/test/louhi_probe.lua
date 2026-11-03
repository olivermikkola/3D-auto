-- Louhi drivable (systems/louhi): from Ajurinkatu, drive through the portal
-- and down the 360 m tunnel to the hall under Kauppatori, round it, get out
-- and back in, and drive back out into the street. Down there the car and
-- the player are in layer 1 and so is the view; out again, layer 0; and
-- the car keeps to the tunnel's floor all the way.
-- LOUHI_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local vehicle = require "lib.vehicle"
local player = require "lib.player"
local robot = require "test.robot"
local Lh = require "systems.louhi"
local wanted = require "lib.wanted"
local police = require "systems.police"
local heli = require "systems.heli"

local log = {}
local function check(ok, what)
  print(string.format("LOUHI: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
  if not ok then log.bad = (log.bad and log.bad .. "; " or "") .. what end
end
local function finish()
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("LOUHI: %d checks, %d failed", #log, bad))
  if bad > 0 then engine.quit(); error("Louhi isn't drivable: " .. log.bad, 0) end
  print("ALL LOUHI CHECKS PASSED")
  engine.quit()
end

local driver
input.drive = function()
  if not (G.vehicle and driver) then return 0, 0, true end
  return driver.inputs(G.vehicle)
end

local step, t, car, worst, went_down, deepest = 0, 0, nil, 0, nil, math.huge
local heli_saw, cop_down, closest, lost, overhead = false, false, math.huge, false, 0
local function tunnel_pts(u0, u1, v)
  local pts = {}
  local du = u1 > u0 and 5 or -5
  for u = u0, u1, du do
    local x, z = Lh.at(u, v)
    pts[#pts + 1] = {x, z}
  end
  return pts
end

engine.on("tick", function(dt)
  if engine.ticks() < 30 or not G.player and not G.vehicle then return end
  t = t + dt
  local T = Lh.frame()
  if step == 0 then
    check(Lh.built and T ~= nil, "Louhi is built")
    check(T and T.u_end > 340 and T.u_end < 380, string.format("the tunnel is %.0f m long", T and T.u_end or 0))
    -- A car 30 m out on Ajurinkatu, facing the portal.
    local x, z = Lh.at(-30, 0)
    car = vehicle.spawn(x, z, T.yaw, 3)
    if G.player then engine.despawn(G.player) end
    G.player, G.vehicle = nil, car
    engine.emit("vehicle_enter", car)
    -- In: keep to the right (v > 0 is... the right of the way in).
    local pts = tunnel_pts(-25, T.u_end + 6, 0)
    -- then into the far aisle through the way across, along it to the end,
    -- back up the near aisle to the tunnel.
    local A = Lh.AISLES
    local function hall(along, across) local hx, hz = Lh.hall_at(along, across); return {hx, hz} end
    local m = Lh.mouth_along
    local L2 = Lh.HALL.len / 2
    for _, q in ipairs{{m, 0}, {m + 4, A[2]}, {m + 20, A[2]}, {L2 - 30, A[2]}, {L2 - 5, A[2] - 3}, {L2 - 5, 0}, {L2 - 5, A[1] + 3},
                       {L2 - 30, A[1]}, {m + 25, A[1]}, {m + 8, A[1]}} do
      pts[#pts + 1] = hall(q[1], q[2])
    end
    driver = robot.driver(pts, 9, 4)
    step, t = 1, 0
  elseif step == 1 then
    -- Down the tunnel: never off its floor.
    local x, y, z = engine.pos(car)
    local u = Lh.local_uv(x, z)
    if Lh.down(car) then
      went_down = went_down or t
      local f = Lh.ground(x, z)
      if f then worst = math.max(worst, math.abs(y - 0.75 - f)) end
      deepest = math.min(deepest, y)
    end
    if driver.at >= #driver.pts - 1 or t > 150 then
      check(went_down ~= nil, string.format("through the portal into layer 1 (after %.1f s)", went_down or -1))
      check(engine.view_layer() == 1, "the view went down too")
      check(worst < 0.6, string.format("on the tunnel's floor all the way (worst %.2f m off)", worst))
      check(deepest < Lh.HALL_Y + 1.5, string.format("down to the hall (%.1f m, its floor at %.1f)", deepest, Lh.HALL_Y))
      check(driver.at >= #driver.pts - 1, string.format("round the hall in %.0f s (point %d of %d)", t, driver.at, #driver.pts))
      check(u > T.u_end - 20, "back by the tunnel's foot")
      -- Out of the car, down here.
      engine.set_vel(car, 0, 0, 0)
      player.exit()
      step, t = 2, 0
    end
  elseif step == 2 and t > 2 then
    local _, py = engine.pos(G.player)
    check(engine.layer(G.player) == 1, "got out in layer 1")
    check(py > Lh.HALL_Y and py < Lh.HALL_Y + 2, string.format("standing on the hall's floor (y %.1f)", py))
    player.enter_nearest()
    check(G.vehicle == car, "back in the car")
    driver = robot.driver(tunnel_pts(T.u_end - 2, -25, 0), 9, 4)
    -- (It starts facing along the aisle: the first points turn it into the tunnel.)
    local hx, hz = Lh.hall_at(Lh.mouth_along - 4, Lh.AISLES[1])
    table.insert(driver.pts, 1, {hx, hz})
    step, t = 3, 0
  elseif step == 3 then
    if driver.at >= #driver.pts - 1 or t > 120 then
      local x, y, z = engine.pos(car)
      check(not Lh.down(car) and engine.layer(car) == 0, "out through the portal, back in layer 0")
      check(engine.view_layer() == 0, "the view came up too")
      local g = U.ground(x, z)
      check(math.abs(y - 0.75 - g) < 1, string.format("on Ajurinkatu (y %.1f, the street at %.1f)", y, g))
      -- Now wanted: back in, with the cops after you.
      local sx, sz = Lh.at(-45, 0)
      engine.set_pos(car, sx, U.ground(sx, sz) + 0.9, sz)
      engine.set_yaw(car, T.yaw)
      engine.set_vel(car, 0, 0, 0)
      wanted.set(2)
      wanted.center = {sx, sz, U.ground(sx, sz)}
      local pts = tunnel_pts(-40, T.u_end + 6, 0)
      local hx, hz = Lh.hall_at(Lh.mouth_along + 20, Lh.AISLES[1])
      pts[#pts + 1] = {hx, hz}
      driver = robot.driver(pts, 9, 4)
      step, t = 4, 0
    end
  elseif step == 4 then
    -- Wait for a car of them to come up behind before going in.
    local near = false
    local mx, _, mz = engine.pos(car)
    for id in pairs(police.cops) do
      local x, _, z = engine.pos(id)
      if x and U.dist2d(x, z, mx, mz) < 90 then near = true end
    end
    if not (near or t > 40) then
      engine.set_vel(car, 0, 0, 0)
    else
      step, t = 5, 0
    end
  elseif step == 5 then
    if Lh.down(car) and heli.sees() then heli_saw = true end
    local x, _, z = engine.pos(car)
    for id in pairs(police.cops) do
      local cx, _, cz = engine.pos(id)
      if cx and engine.layer(id) == 1 then
        cop_down = true
        if Lh.down(car) then closest = math.min(closest, U.dist2d(cx, cz, x, z)) end
      end
    end
    if driver.at >= #driver.pts then engine.set_vel(car, 0, 0, 0); driver.pts = {} end
    if wanted.stars() == 0 then lost = true end
    if (cop_down and closest < 15) or t > 120 or lost or not G.vehicle then
      check(Lh.down(car) or not G.vehicle, "in the hall, wanted")
      check(cop_down, string.format("a cop car followed you down (after %.0f s)", t))
      check(closest < 15, string.format("and got to you (%.0f m)", closest))
      -- Four stars: the helicopter comes, and doesn't see you down here.
      wanted.set(4)
      step, t = 6, 0
    end
  elseif step == 6 then
    local hid = heli.id()
    if hid and heli.active() and G.vehicle then
      local hx, _, hz = engine.pos(hid)
      local x, _, z = engine.pos(G.vehicle)
      if U.dist2d(hx, hz, x, z) < heli.SIGHT then
        overhead = overhead + dt
        if heli.sees() then heli_saw = true end
      end
    end
    if overhead > 5 or t > 60 or not G.vehicle then
      check(overhead > 5, string.format("the helicopter came over (%.1f s within sight range)", overhead))
      check(not heli_saw, "and never saw you underground")
      finish()
    end
  end
end)
