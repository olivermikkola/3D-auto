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
  if not cond then
    engine.quit()
    error("AUTOPLAY FAILED: " .. what, 0)
  end
  print("  ok  " .. what)
end

-- Steps run in order: at(t) fires at an absolute time, after(d) a delay
-- after the previous step, and until(pred) as soon as pred() holds (or fails).
local steps, t0, step_i, step_start = {}, nil, 1, nil
local function at(sec, fn) steps[#steps + 1] = {at = sec, fn = fn} end
local function after(sec, fn) steps[#steps + 1] = {after = sec, fn = fn} end
local function until_(pred, timeout, what, fn) steps[#steps + 1] = {pred = pred, timeout = timeout, what = what, fn = fn} end

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
  local def
  for _, d in ipairs(mission.defs) do if d.title == "Joyride" then def = d end end
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
end)

-- ---- pedestrians ------------------------------------------------------------
local peds = require "systems.peds"
local downed, victim = 0, nil
engine.on("ped_down", function(body) downed = downed + 1; victim = body end)
local function walking_peds()
  local n = 0
  for id in pairs(peds.peds) do
    local vx, _, vz = engine.vel(id)
    if vx * vx + vz * vz > 0.5 then n = n + 1 end
  end
  return n
end
-- Nearest ped in `state`, optionally only mid-block (away from corner lamps).
local function nearest_ped(state, mid_block)
  local px, _, pz = engine.pos(G.vehicle or G.player)
  local best, bid = math.huge
  for id, p in pairs(peds.peds) do
    local x, _, z = engine.pos(id)
    local bx, bz = city.block_center(p.i, p.j)
    local ok = not mid_block or math.min(math.abs(x - bx), math.abs(z - bz)) < G.city.block / 2 - 7
    local d = (x - px) ^ 2 + (z - pz) ^ 2
    if p.state == state and ok and d < best then best, bid = d, id end
  end
  return bid
end
local scared
after(0.2, function()
  check(peds.count() >= 35, "pedestrians spawned (" .. peds.count() .. ")")
  check(walking_peds() >= 20, "pedestrians are walking (" .. walking_peds() .. " moving)")
  -- Back in the car, parked next to someone, lean on the horn.
  press("e")
  check(G.vehicle == car, "back in the car")
  scared = nearest_ped("walk")
  local x, _, z = engine.pos(scared)
  engine.set_pos(car, x + 6, 0.8, z)
  engine.set_vel(car, 0, 0, 0)
end)
after(0.3, function() press("h") end)
until_(function() return peds.peds[scared] and peds.peds[scared].state == "flee" end, 1, "the horn makes a pedestrian run")
after(5.0, function()
  -- Line up behind a walker and drive straight through them.
  require("lib.wanted").clear()
  -- Start out on the road and drive across the curb at them.
  local id = nearest_ped("walk", true)
  local x, _, z = engine.pos(id)
  local p = peds.peds[id]
  local bx, bz = city.block_center(p.i, p.j)
  local nx, nz = 0, 0
  if math.abs(x - bx) > math.abs(z - bz) then nx = x > bx and 1 or -1 else nz = z > bz and 1 or -1 end
  engine.set_pos(car, x + nx * 9, 0.8, z + nz * 9)
  engine.orient(car, math.atan(-nx, -nz))
  engine.set_angvel(car, 0, 0, 0)
  engine.set_vel(car, -nx * 16, 0, -nz * 16)
end)
until_(function() return downed >= 1 end, 3, "running someone over knocks them down", function()
  check(require("lib.wanted").stars() >= 1, "hitting a pedestrian is a crime (" .. require("lib.wanted").stars() .. " star)")
end)
until_(function()
  local _, uy = engine.up(victim)
  return uy < 0.7
end, 3, "the victim tumbles (rigid body, no longer upright)", function()
  require("lib.wanted").clear()
  require("systems.police").clear()
  engine.set_vel(car, 0, 0, 0)
  press("e")
  check(G.player and not G.vehicle, "on foot again")
end)

-- ---- police -----------------------------------------------------------------
local wanted = require "lib.wanted"
local police = require "systems.police"
local busts, cash_before = 0, 0
engine.on("busted", function() busts = busts + 1 end)
local function nearest_cop()
  local px, _, pz = engine.pos(G.vehicle or G.player)
  local best = math.huge
  for id in pairs(police.cops) do
    local x, _, z = engine.pos(id)
    best = math.min(best, math.sqrt((x - px) ^ 2 + (z - pz) ^ 2))
  end
  return best
end

after(0.5, function()
  cash_before = G.cash
  wanted.set(1)
  check(wanted.stars() == 1, "wanted level set to 1 star")
end)
until_(function() return police.count() == 1 end, 6, "a cop is dispatched for 1 star")
until_(function() return nearest_cop() < 25 end, 40, "cops chased the player down the grid")
until_(function() return busts == 1 end, 30, "busted when caught standing next to a cop", function()
  check(wanted.stars() == 0 and police.count() == 0, "busting clears the wanted level and the cops")
  check(G.cash < cash_before, string.format("fined $%d", cash_before - G.cash))
end)

after(1.0, function() wanted.set(1) end)
until_(function() return police.count() == 1 end, 6, "a cop is dispatched for 1 star", function()
  -- Teleport to whichever corner of town is farthest from the cop.
  local cop = next(police.cops)
  local cx, _, cz = engine.pos(cop)
  local best, bx, bz = -1
  for _, n in ipairs{{0, 0}, {0, G.city.N}, {G.city.N, 0}, {G.city.N, G.city.N}} do
    local x, z = city.node(n[1], n[2])
    local d = (x - cx) ^ 2 + (z - cz) ^ 2
    if d > best then best, bx, bz = d, x, z end
  end
  engine.set_pos(G.player, bx, 1.2, bz)
end)
until_(function() return wanted.stars() == 0 end, 10, "lost the cops by leaving the search circle unseen")
-- ---- combat -----------------------------------------------------------------
local H = require "lib.health"
local W = require "systems.weapons"
local pickups = require "lib.pickups"
local kills, booms, wastes, respawned = 0, 0, 0, false
engine.on("ped_down", function(_, by) if by == G.player then kills = kills + 1 end end)
engine.on("explosion", function() booms = booms + 1 end)
engine.on("wasted", function() wastes = wastes + 1 end)
engine.on("respawned", function() respawned = true end)
local target, victim
after(0.5, function()
  wanted.clear()
  police.clear()
  G.weapon, G.ammo.pistol = "pistol", 40
  -- Stand on the sidewalk in front of someone walking toward us.
  target = nearest_ped("walk", true)
  local x, _, z = engine.pos(target)
  local p = peds.peds[target]
  local dx, dz = p.tx - x, p.tz - z
  local l = math.sqrt(dx * dx + dz * dz) + 1e-3
  engine.set_pos(G.player, x + dx / l * 6, 1.2, z + dz / l * 6)
  -- Arrange an actual witness: new scenery changes entity ids and the
  -- ambient population's iteration order, so proximity isn't guaranteed.
  for id in pairs(peds.peds) do
    if id ~= target then
      engine.set_pos(id, x + 8, 1.2, z)
      break
    end
  end
end)
until_(function()
  if not peds.peds[target] then return true end
  local x, y, z = engine.pos(target)
  W.fire_at(x, y + 0.3, z)
end, 5, "shooting a pedestrian kills them", function()
  check(kills >= 1, "the kill is credited to the player")
  check(wanted.stars() >= 1, "murder raises the wanted level (" .. wanted.stars() .. " stars)")
  local fleeing = 0
  for _, p in pairs(peds.peds) do if p.state == "flee" then fleeing = fleeing + 1 end end
  check(fleeing >= 1, fleeing .. " bystanders ran from the gunfire")
end)

after(0.3, function()
  wanted.clear()
  police.clear()
  -- A parked car in the lot, from nine meters away.
  local lx, lz = city.block_center(G.city.lot[1], G.city.lot[2])
  victim = engine.nearest(lx, 1, lz, 30, "car")
  local x, _, z = engine.pos(victim)
  engine.set_pos(G.player, x, 1.4, z - 9)
  G.ammo.pistol = 60
end)
until_(function()
  if not engine.exists(victim) then return true end
  local x, y, z = engine.pos(victim)
  W.fire_at(x, y, z)
end, 15, "a shot-up car catches fire and explodes", function()
  check(booms >= 1 and #engine.find("wreck") >= 1, "it leaves a burnt-out wreck")
end)

after(1.0, function()
  H.heal_player(100)
  wanted.clear()
  police.clear()
  wanted.set(3)
end)
until_(function() return police.officer_count() > 0 end, 45, "at 3 stars, officers get out of their cars")
until_(function() return H.player.hp < H.player.max end, 25, "officers shoot at the player", function()
  H.player.hp = 12 -- skip ahead
end)
until_(function() return wastes == 1 end, 30, "out of health: WASTED")
until_(function() return respawned end, 8, "respawned outside the hospital", function()
  check(H.player.hp == H.player.max, "health restored")
  check(wanted.stars() == 0 and police.count() == 0 and police.officer_count() == 0, "wanted cleared, police gone")
  local x, _, z = engine.pos(G.player)
  check(math.abs(x - G.hospital[1]) < 3 and math.abs(z - G.hospital[3]) < 3, "standing at the hospital")
end)

after(0.5, function()
  H.player.hp = 40
  local spot
  for _, s in ipairs(pickups.spots) do if s.kind == "health" and s.id then spot = spot or s end end
  engine.set_pos(G.player, spot.x, 1.2, spot.z)
end)
until_(function() return H.player.hp > 40 end, 2, "a health pickup heals (" .. "40 -> 90)")

-- ---- mods -------------------------------------------------------------------
local sandbox
engine.on("sandbox_report", function(r) sandbox = r end)
after(0.2, function()
  local mission = require "lib.mission"
  local taxi
  for _, d in ipairs(mission.defs) do if d.title == "Taxi Driver" then taxi = d end end
  check(taxi ~= nil, "the taxi mod registered its mission")
  engine.load_mod("test/sandbox_probe")
  check(sandbox ~= nil, "hostile probe mod ran")
  for _, r in ipairs(sandbox) do
    check(not r.blocked == (r.expect_ok == true), (r.expect_ok and "mods can use " or "sandbox blocks ") .. r.name)
  end
end)

-- ---- day and night ------------------------------------------------------------
after(0.5, function()
  check(busts == 1, "no extra busts while escaping")
  local daynight = require "lib.daynight"
  local h0 = daynight.hour
  daynight.set_hour(23)
  check(daynight.glow == 1, "night: lights and windows on (glow = 1)")
  local lamps = #engine.find("lamp")
  check(engine.stats().lights >= lamps + 10, string.format("%d lights (lamps %d + headlights)", engine.stats().lights, lamps))
  daynight.set_hour(12)
  check(daynight.glow == 0, "noon: glow off")
  daynight.set_hour(18.1)
  check(daynight.glow > 0.2 and daynight.glow < 1, string.format("dusk blends (glow %.2f)", daynight.glow))
  check(math.abs(daynight.hour - 18.1) < 1e-6 and h0 ~= nil, "clock reads " .. daynight.clock())
end)
after(0.5, function()
  print("AUTOPLAY PASSED; running garage checks")
  require "test.garage"
end)

engine.on("tick", function()
  local now = engine.time()
  t0 = t0 or now
  step_start = step_start or now
  local s = steps[step_i]
  if not s then return end
  local fire = (s.at and now - t0 >= s.at) or (s.after and now - step_start >= s.after)
  if s.pred then
    if s.pred() then
      check(true, s.what)
      fire = true
    elseif now - step_start > s.timeout then
      step_i = step_i + 1
      check(false, s.what .. string.format(" (timed out after %ds)", s.timeout))
    end
  end
  if fire then
    step_i, step_start = step_i + 1, now
    if s.fn then s.fn() end
  end
end)
