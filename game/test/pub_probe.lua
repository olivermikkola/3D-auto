-- Test probe for Uusi Apteekki pub (systems/pub.lua)
-- PUB_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local health = require "lib.health"
local wanted = require "lib.wanted"
local Pub = require "systems.pub"

local log = {}
local function check(ok, what)
  print(string.format("PUB: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
end

local function finish()
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("PUB: %d checks, %d failed", #log, bad))
  assert(bad == 0, "Uusi Apteekki pub test failed")
  print("ALL PUB CHECKS PASSED")
  engine.quit()
end

local step, t = 0, 0
local initial_cash = 100
local initial_hp = 50

engine.on("tick", function(dt)
  if engine.ticks() < 20 or not G.player or G.vehicle then return end
  t = t + dt

  local px, py, pz = engine.pos(G.player)
  local cur_layer = engine.layer(G.player) or 0

  if step == 0 then
    -- Verify build
    check(Pub.built, "Uusi Apteekki pub system is built")

    -- Prepare player state: $100 cash, 50 HP
    G.cash = initial_cash
    health.player.hp = initial_hp

    -- Position player on Kaskenkatu right in front of the door
    local out_x, out_z = Pub.pub_xz(6.6, 0)
    engine.set_pos(G.player, out_x, 12.68 + 0.9, out_z)
    engine.set_vel(G.player, 0, 0, 0)
    engine.set_layer(G.player, 0)
    engine.view_layer(0)

    check((engine.layer(G.player) or 0) == 0, "player starts on Kaskenkatu in layer 0")
    step, t = 1, 0

  elseif step == 1 then
    -- Walk player into pub doorway
    local in_x, in_z = Pub.pub_xz(4.8, 0)
    local out_x, out_z = Pub.pub_xz(6.6, 0)
    engine.set_pos(G.player, out_x, 12.68 + 0.9, out_z)

    if cur_layer == 1 then
      check(cur_layer == 1, "player entered Uusi Apteekki: layer is 1")
      check(engine.view_layer() == 1, "view_layer is 1")

      -- Move to the bar counter
      local bar_x, bar_z = Pub.pub_xz(-1.2, -1.2)
      engine.set_pos(G.player, bar_x, 12.68 + 0.9, bar_z)
      step, t = 2, 0
    elseif t > 5 then
      check(false, "failed to transition into pub through door")
      return finish()
    end

  elseif step == 2 then
    -- Verify bar counter interaction
    local kind = Pub.current_interaction()
    check(kind == "bar", string.format("detected interaction zone: %s", tostring(kind)))

    local prev_hp = health.player.hp
    local prev_cash = G.cash

    -- Buy beer (press R)
    engine.emit("key", "r", true)

    check(G.cash == prev_cash - 7, string.format("cash deducted for beer from %d to %d", prev_cash, G.cash))
    check(health.player.hp > prev_hp, string.format("health restored from %d to %d", prev_hp, health.player.hp))

    -- Move to dartboard area
    local dart_x, dart_z = Pub.pub_xz(-1.0, 2.8)
    engine.set_pos(G.player, dart_x, 12.68 + 0.9, dart_z)
    step, t = 3, 0

  elseif step == 3 then
    -- Verify dartboard interaction
    local kind = Pub.current_interaction()
    check(kind == "darts", string.format("detected interaction zone: %s", tostring(kind)))

    local dart_thrown = false
    local handle = engine.on("pub_darts", function(score)
      dart_thrown = true
      check(score > 0, string.format("threw dart, score: %d", score))
    end)

    engine.emit("key", "r", true)
    check(dart_thrown, "darts minigame executed successfully")

    -- Move to exit door
    local in_x, in_z = Pub.pub_xz(4.8, 0)
    engine.set_pos(G.player, in_x, 12.68 + 0.9, in_z)
    step, t = 4, 0

  elseif step == 4 then
    if cur_layer == 0 then
      check(cur_layer == 0, "exited pub back onto Kaskenkatu: layer is 0")
      check(engine.view_layer() == 0, "view_layer is 0")

      -- Test police evasion
      wanted.set(1)
      check(wanted.stars() == 1, "wanted at 1 star")

      -- Step back into pub to lay low
      local out_x, out_z = Pub.pub_xz(6.6, 0)
      engine.set_pos(G.player, out_x, 12.68 + 0.9, out_z)
      step, t = 5, 0
    elseif t > 5 then
      check(false, "failed to transition out through pub door")
      return finish()
    end

  elseif step == 5 then
    if cur_layer == 1 then
      check(cur_layer == 1, "re-entered pub while wanted")
      check(wanted.hiding == true, "police lost sight (wanted.hiding is true)")
      return finish()
    elseif t > 5 then
      check(false, "failed to re-enter pub while wanted")
      return finish()
    end
  end
end)
