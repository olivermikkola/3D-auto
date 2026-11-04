-- Test probe for Turun Kauppahalli (systems/kauppahalli.lua)
-- KAUPPAHALLI_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local health = require "lib.health"
local wanted = require "lib.wanted"
local Kh = require "systems.kauppahalli"

local log = {}
local function check(ok, what)
  print(string.format("KAUPPAHALLI: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
end

local function finish()
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("KAUPPAHALLI: %d checks, %d failed", #log, bad))
  assert(bad == 0, "Turun Kauppahalli test failed")
  print("ALL KAUPPAHALLI CHECKS PASSED")
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
    check(Kh.built, "Kauppahalli system is built")
    check(#Kh.stalls >= 10, string.format("registered %d market stalls", #Kh.stalls))

    -- Prepare player state: $100 cash, 50 HP
    G.cash = initial_cash
    health.player.hp = initial_hp

    -- Position player on Eerikinkatu right outside the north entrance door
    local d1 = Kh.DOORS.eerikinkatu
    engine.set_pos(G.player, d1.out_x + 0.3, d1.y + 0.9, d1.out_z + 0.3)
    engine.set_vel(G.player, 0, 0, 0)
    engine.set_layer(G.player, 0)
    engine.view_layer(0)

    check((engine.layer(G.player) or 0) == 0, "player starts on street in layer 0")
    step, t = 1, 0

  elseif step == 1 then
    -- Move player through Eerikinkatu door
    local d1 = Kh.DOORS.eerikinkatu
    engine.set_pos(G.player, d1.out_x, d1.y + 0.9, d1.out_z)

    -- Tick logic in kauppahalli.lua will detect proximity and transition to Layer 1
    if cur_layer == 1 then
      check(cur_layer == 1, "player entered Kauppahalli: layer is 1")
      check(engine.view_layer() == 1, "view_layer is 1")

      local along, across = Kh.hall_ac(px, pz)
      check(along < -50, string.format("inside north end of hall (along=%.1f)", along))
      check(math.abs(across) < 2.0, string.format("standing in central aisle (across=%.1f)", across))

      -- Move along aisle towards Kahvila Halli (along ~ -45, across ~ 1.5)
      local st = Kh.stalls[1] -- Kahvila Halli
      engine.set_pos(G.player, st.x, 4.80 + 0.9, st.z)
      step, t = 2, 0
    elseif t > 5 then
      check(false, "failed to transition through Eerikinkatu door")
      return finish()
    end

  elseif step == 2 then
    -- Verify stall proximity detection
    local st = Kh.current_stall()
    check(st ~= nil, "detected nearby stall")
    if st then
      check(st.name == "KAHVILA HALLI", "nearest stall is Kahvila Halli")
      check(st.price == 5, "price is $5")

      -- Interact: press 'r' to buy coffee and bun
      local prev_hp = health.player.hp
      local prev_cash = G.cash

      -- Simulate key interaction directly
      engine.emit("key", "r", true)

      check(G.cash == prev_cash - 5, string.format("cash deducted from %d to %d", prev_cash, G.cash))
      check(health.player.hp > prev_hp, string.format("health restored from %d to %d", prev_hp, health.player.hp))
    end

    -- Walk through the hall all the way to Linnankatu exit door (along = 54.0)
    local d2 = Kh.DOORS.linnankatu
    engine.set_pos(G.player, d2.in_x, 4.80 + 0.9, d2.in_z)
    step, t = 3, 0

  elseif step == 3 then
    -- Step through Linnankatu door out onto street
    local d2 = Kh.DOORS.linnankatu
    -- Move player right onto exit trigger
    engine.set_pos(G.player, d2.in_x, 4.80 + 0.9, d2.in_z)

    if cur_layer == 0 then
      check(cur_layer == 0, "player exited Kauppahalli onto Linnankatu: layer is 0")
      check(engine.view_layer() == 0, "view_layer is 0")

      local dist = U.dist2d(px, pz, d2.out_x, d2.out_z)
      check(dist < 2.0, string.format("standing outside on Linnankatu sidewalk (dist=%.2f)", dist))

      -- Test 4: Wanted evasion test
      wanted.set(2)
      check(wanted.stars() == 2, "set wanted level to 2 stars")

      -- Step back into Kauppahalli from Linnankatu
      engine.set_pos(G.player, d2.out_x, d2.y + 0.9, d2.out_z)
      step, t = 4, 0
    elseif t > 5 then
      check(false, "failed to transition out through Linnankatu door")
      return finish()
    end

  elseif step == 4 then
    if cur_layer == 1 then
      check(cur_layer == 1, "entered Kauppahalli while wanted")
      check(wanted.hiding == true, "wanted.hiding is true (police lost sight)")
      return finish()
    elseif t > 5 then
      check(false, "failed to re-enter Kauppahalli while wanted")
      return finish()
    end
  end
end)
