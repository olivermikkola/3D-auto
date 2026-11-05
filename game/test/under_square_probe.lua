-- Under the Square (missions/12_under_the_square.lua) played through: the
-- van robbed at Kauppatori, three stars; then driven by the robot down
-- Toriparkki's ramp, through the link into Louhi's hall and up its tunnel to
-- Ajurinkatu; on foot into Logomo, where the cops lose you; passed and paid.
-- (While the robot drives the cop cars are cleared, as it can't outrun them,
-- but the three stars stay, as if they had you in sight; that they follow
-- you down is louhi_probe's and toriparkki_probe's. Logomo has to lose them.)
-- UNDER_SQUARE_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local mission = require "lib.mission"
local player = require "lib.player"
local vehicle = require "lib.vehicle"
local robot = require "test.robot"
local wanted = require "lib.wanted"
local police = require "systems.police"
local Lh = require "systems.louhi"
local Tp = require "systems.toriparkki"
local hideouts = require "systems.hideouts"

local log = {}
local function check(ok, what)
  print(string.format("UNDER_SQUARE: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
  if not ok then log.bad = (log.bad and log.bad .. "; " or "") .. what end
end
local function finish()
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("UNDER_SQUARE: %d checks, %d failed", #log, bad))
  if bad > 0 then engine.quit(); error("Under the Square doesn't play: " .. log.bad, 0) end
  print("ALL UNDER_SQUARE CHECKS PASSED")
  engine.quit()
end

local driver
input.drive = function()
  if not (G.vehicle and driver) then return 0, 0, true end
  return driver.inputs(G.vehicle)
end
local function hall(a, c) local x, z = Lh.hall_xz(a, c); return {x, z} end

local passed, failed
engine.on("mission_passed", function(def) passed = def end)
engine.on("mission_failed", function(_, reason) failed = reason or "?" end)

local step, t, car, def, cash, went_down, through_link = 0, 0, nil, nil, 0, false, false
local mid = 37.45
local told
local function objective() return G.mission and G.mission.objective or "" end
-- The chase without the cop cars: none on the road (the robot can't outrun
-- them), but the stars stay and they've still got you in sight.
local function pursued()
  police.clear()
  wanted.unseen_for = 0
end

engine.on("tick", function(dt)
  if engine.ticks() < 30 or not G.player and not G.vehicle then return end
  t = t + dt
  if step == 0 then
    for _, d in ipairs(mission.defs) do if d.id == "12_under_the_square" then def = d end end
    check(def ~= nil, "the mission is on Turku's list")
    if not def then return finish() end
    for id in pairs(require("systems.traffic").cars) do engine.despawn(id) end
    cash = G.cash
    mission.start(def)
    -- a car at the van: in, stopped
    local rx, rz = require("lib.city").place("taxi_rank")
    car = vehicle.spawn(rx, rz, 0, 3)
    if G.player then engine.despawn(G.player) end
    G.player, G.vehicle = nil, car
    engine.emit("vehicle_enter", car)
    step, t = 1, 0
  elseif step == 1 then
    engine.set_vel(car, 0, 0, 0)
    if wanted.stars() >= 3 then
      check(objective():find("Toriparkki") ~= nil, "van robbed, three stars: '" .. objective() .. "'")
      pursued()
      -- to the street outside Toriparkki's mouth, facing in, and down
      local p, q = hall(224, mid), hall(223, mid)
      engine.set_pos(car, p[1], U.ground(p[1], p[2]) + 0.9, p[2])
      engine.orient(car, math.atan(q[1] - p[1], q[2] - p[2]), 0, 0)
      local pts = {}
      for _, ac in ipairs{{210, mid}, {195, mid}, {170, mid}, {155, mid}, {140, mid}, {128, 40}, {120, 40}, {116, 36}, {115, 30},
                          {115, 22}, {115, 15}, {112, 9}, {106, 6.75}, {100, 6.75}, {80, 6.5}, {60, Lh.AISLES[1]},
                          {Lh.mouth_along + 25, Lh.AISLES[1]}, {Lh.mouth_along + 8, Lh.AISLES[1]},
                          {Lh.mouth_along - 4, Lh.AISLES[1]}} do
        pts[#pts + 1] = hall(ac[1], ac[2])
      end
      local T = Lh.frame()
      for u = T.u_end - 2, -25, -5 do pts[#pts + 1] = {Lh.at(u, 0)} end
      driver = robot.driver(pts, 7, 3)
      step, t = 2, 0
    elseif failed or t > 20 then
      check(false, "the van wasn't robbed (" .. tostring(failed) .. ", '" .. objective() .. "')")
      return finish()
    end
  elseif step == 2 then
    pursued()
    local x, _, z = engine.pos(car)
    if Lh.down(car) then
      went_down = true
      if Lh.part(x, z) == "link" then through_link = true end
    end
    if objective():find("Logomo") or failed or t > 240 then
      check(went_down, "down Toriparkki's ramp into layer 1")
      check(through_link, "through the link into Louhi's hall")
      check(not Lh.down(car) and engine.layer(car) == 0, "up Louhi's tunnel, back in layer 0")
      check(objective():find("Logomo") ~= nil, string.format("out on Ajurinkatu after %.0f s: '%s'", t, objective()))
      if not objective():find("Logomo") then return finish() end
      -- out of the car and on foot to Logomo's door
      engine.set_vel(car, 0, 0, 0)
      driver = nil
      player.exit()
      local h = hideouts.list[1]
      local sx, sz = h.x + h.nx * 6, h.z + h.nz * 6
      engine.set_pos(G.player, sx, U.ground(sx, sz) + 1.0, sz)
      engine.set_vel(G.player, 0, 0, 0)
      -- the stars back for the end (Logomo's door takes you in only wanted),
      -- and nobody sees you go in: they have to lose you
      police.clear()
      check(wanted.stars() == 3, "still three stars")
      wanted.seen = false
      step, t = 3, 0
    end
  elseif step == 3 then
    local h = hideouts.list[1]
    if hideouts.hidden() then
      check(true, string.format("walked into Logomo at %d stars", wanted.stars()))
      step, t = 4, 0
    elseif t > 10 then
      check(false, "didn't get into Logomo on foot")
      return finish()
    else
      local x, _, z = engine.pos(G.player)
      local dx, dz = h.x - x, h.z - z
      local l = math.max(0.1, math.sqrt(dx * dx + dz * dz))
      local _, vy = engine.vel(G.player)
      engine.set_vel(G.player, dx / l * 3, vy, dz / l * 3)
    end
  elseif step == 4 then
    if not told and t > 0.3 then
      told = true
      check(passed or objective():find("Lie low") ~= nil, "hiding: '" .. objective() .. "'")
    end
    if passed or failed or t > 90 then
      check(passed == def, string.format("lost them in Logomo after %.0f s: mission passed (%s)", t, tostring(failed)))
      check(G.cash >= cash + def.reward, string.format("paid $%d", def.reward))
      finish()
    end
  end
end)
