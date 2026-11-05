-- EduCity (systems/educity.lua): in by the door on Joukahaisenkatu, the floors
-- hold you (the foyer, down the Stairway of Skills, the restaurant), coffee
-- and lunch, the hackathon's pizza, out again, and the cops lose you inside.
-- EDUCITY_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local health = require "lib.health"
local wanted = require "lib.wanted"
local E = require "systems.educity"

local log = {}
local function check(ok, what)
  print(string.format("EDUCITY: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
end
local function finish()
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("EDUCITY: %d checks, %d failed", #log, bad))
  if bad == 0 then print("ALL EDUCITY CHECKS PASSED") end
  engine.quit()
end

-- Put the player at (a, c) inside, a little over the floor, and see where
-- they stand after a second: on the floor, not through it.
local function stand(a, c)
  local x, z = E.xz(a, c)
  engine.set_pos(G.player, x, E.floor_at(a, c) + 1.2, z)
  engine.set_vel(G.player, 0, 0, 0)
end
local function on_floor(a, c, what)
  local x, y, z = engine.pos(G.player)
  local fa, fc = E.ac(x, z)
  local want = E.floor_at(a, c)
  check(math.abs(fa - a) < 1.5 and math.abs(fc - c) < 1.5 and y > want - 0.3 and y < want + 1.6,
        string.format("%s: stands at y %.2f, floor %.2f (a %.1f c %.1f)", what, y, want, fa, fc))
end
local function buy(i, what)
  local s = E.shops[i]
  engine.set_pos(G.player, s.x, s.y + 1.0, s.z)
  engine.set_vel(G.player, 0, 0, 0)
  health.player.hp = 40
  local cash, hp = G.cash, health.player.hp
  check(E.current_shop() == s, what .. ": at the counter")
  engine.emit("key", "r", true)
  check(G.cash == cash - s.price and health.player.hp > hp,
        string.format("%s: $%d -> $%d, %d -> %d HP", what, cash, G.cash, hp, health.player.hp))
end

local step, t = 0, 0
engine.on("tick", function(dt)
  if engine.ticks() < 20 or not G.player or G.vehicle then return end
  t = t + dt
  local d = E.DOOR
  if step == 0 then
    check(E.built and #E.shops == 3, "EduCity built, three counters")
    G.cash = 100
    health.player.hp = 40
    engine.set_layer(G.player, 0)
    engine.view_layer(0)
    -- walk at the door from the pavement, a few metres out
    local x, z = E.xz(d.a, d.c_out - 4)
    engine.set_pos(G.player, x, d.y + 1.0, z)
    step, t = 1, 0
  elseif step == 1 then
    -- walking in: the player is pushed towards the door, as if walking
    local x, _, z = engine.pos(G.player)
    if (engine.layer(G.player) or 0) == E.LAYER then
      check(engine.view_layer() == E.LAYER, "walked in by the door: inside, the view is the atrium's")
      local a, c = E.ac(x, z)
      check(c > 1 and c < 4 and math.abs(a) < 2, string.format("in the foyer by the door (a %.1f c %.1f)", a, c))
      step, t = 2, 0
    elseif t > 8 then
      check(false, "didn't get in by walking at the door")
      return finish()
    else
      local dx, dz = d.out_x - x, d.out_z - z
      local l = math.max(0.1, math.sqrt(dx * dx + dz * dz))
      local _, vy = engine.vel(G.player)
      engine.set_vel(G.player, dx / l * 3, vy, dz / l * 3)
    end
  elseif step == 2 and t > 1.0 then
    on_floor(0, 2.6, "foyer")
    stand(-10, 13)
    step, t = 3, 0
  elseif step == 3 and t > 1.2 then
    on_floor(-10, 13, "half way down the Stairway of Skills")
    stand(-12, 7)
    step, t = 4, 0
  elseif step == 4 then
    -- walk down the stairs from the foyer to the restaurant
    local x, y, z = engine.pos(G.player)
    local a, c = E.ac(x, z)
    if c > 22 then
      on_floor(a, c, "walked down the Stairway of Skills to the restaurant")
      step, t = 45, 0
    elseif t > 12 then
      check(false, string.format("didn't walk down the stairs (a %.1f c %.1f y %.2f)", a, c, y))
      step, t = 45, 0
    else
      local _, vy = engine.vel(G.player)
      local x1, z1 = E.xz(a, c + 1)
      engine.set_vel(G.player, (x1 - x) * 3, vy, (z1 - z) * 3)
    end
  elseif step == 45 then
    stand(14, 21.5)
    step, t = 5, 0
    stand(14, 21.5)
    step, t = 5, 0
  elseif step == 5 and t > 1.2 then
    on_floor(14, 21.5, "the hackathon's floor")
    buy(1, "coffee in the foyer")
    buy(2, "lunch in the restaurant")
    buy(3, "the hackathon's pizza")
    -- and out: to the door from inside
    engine.set_pos(G.player, d.in_x, d.y + 1.0, d.in_z)
    step, t = 6, 0
  elseif step == 6 then
    if (engine.layer(G.player) or 0) == 0 then
      local x, _, z = engine.pos(G.player)
      check(U.dist2d(x, z, d.out_x, d.out_z) < 2, "out on Joukahaisenkatu's pavement")
      wanted.set(2)
      engine.set_pos(G.player, d.out_x, d.y + 1.0, d.out_z)
      step, t = 7, 0
    elseif t > 8 then
      check(false, "didn't get out by the door")
      return finish()
    else
      local x, _, z = engine.pos(G.player)
      local tx, tz = E.xz(d.a, 0.5)
      local dx, dz = tx - x, tz - z
      local l = math.max(0.1, math.sqrt(dx * dx + dz * dz))
      local _, vy = engine.vel(G.player)
      engine.set_vel(G.player, dx / l * 3, vy, dz / l * 3)
    end
  elseif step == 7 then
    if (engine.layer(G.player) or 0) == E.LAYER then
      check(wanted.hiding == true and not wanted.seen, "in again with two stars: the cops lost sight")
      return finish()
    elseif t > 5 then
      check(false, "didn't get back in while wanted")
      return finish()
    end
  end
end)
