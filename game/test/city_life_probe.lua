-- Probe checking City Life (Wave 4): Kauppatori Torikahvilateltta and Aurajoki Riverboats
-- CITY_LIFE_TEST=1 auto game --headless 1000  (MAP=turku)

local G = require "lib.state"
local U = require "lib.util"
local daynight = require "lib.daynight"
local health = require "lib.health"
local city_life = require "systems.city_life"

local function check(ok, what)
  if not ok then
    engine.quit()
    error("CITY_LIFE TEST FAILED: " .. tostring(what), 0)
  end
  print("  ok  " .. tostring(what))
end

local function wait(pred, timeout, what)
  local t = engine.time() + timeout
  while not pred() do
    if engine.time() > t then check(false, what .. " (timed out)") end
    coroutine.yield()
  end
end

local function sleep(s)
  local t = engine.time() + s
  wait(function() return engine.time() >= t end, s + 1, "sleep")
end

local function move_player(x, y, z)
  local id = G.vehicle or G.player
  if not id or not engine.exists(id) then return end
  engine.set_pos(id, x, y, z)
  engine.set_vel(id, 0, 0, 0)
end

local function script()
  sleep(0.5)

  -- 1. Structural Checks: Torikahvila on Kauppatori
  check(city_life.torikahvila ~= nil, "Torikahvila structure built")
  local tk = city_life.torikahvila
  check(engine.exists(tk.id), "Torikahvila tent entity exists in engine")
  print(string.format("  ok  Torikahvila located at (%.1f, %.1f, %.1f)", tk.pos[1], tk.pos[2], tk.pos[3]))

  -- 2. Flagship Riverboats
  check(#city_life.boats == 3, string.format("3 flagship riverboats built, got %d", #city_life.boats))
  for _, boat in ipairs(city_life.boats) do
    local spec = boat.spec
    check(spec.name == "SVARTE RUDOLF" or spec.name == "DONNA" or spec.name == "MAJLAND", "Flagship boat: " .. spec.name)
    local d_gang = U.dist2d(boat.quay_pos[1], boat.quay_pos[2], boat.gate_pos[1], boat.gate_pos[2])
    check(d_gang >= 1.0 and d_gang <= 15.0, string.format("%s gangway span %.1fm", spec.name, d_gang))
  end

  -- 3. Kauppatori Daytime Test (Hour = 10:00)
  daynight.set_hour(10)
  sleep(0.5)
  G.cash = 100
  health.player.hp = 50
  local hp_before = health.player.hp

  -- Move player to Torikahvila serving counter
  move_player(tk.counter_x, tk.counter_y + 1.2, tk.counter_z + 0.8)
  sleep(0.5)

  local act = city_life.current_interaction()
  check(act ~= nil, "Interaction detected at Torikahvila counter")
  check(act.kind == "torikahvila", "Interaction is torikahvila")
  check(act.open == true, "Torikahvila is open at 10:00")

  -- Purchase Coffee & Possumunkki via 'r'
  engine.emit("key", "r", true)
  sleep(0.2)
  check(G.cash == 95, string.format("Cash deducted ($5), cash is now $%d", G.cash))
  check(health.player.hp > hp_before, string.format("Player healed from %d to %d HP", hp_before, health.player.hp))

  -- Purchase Lihapiirakka via 'e'
  local hp_before2 = health.player.hp
  engine.emit("key", "e", true)
  sleep(0.2)
  check(G.cash == 89, string.format("Cash deducted ($6), cash is now $%d", G.cash))
  check(health.player.hp >= hp_before2, "Player healed with Lihapiirakka")

  -- 4. Torikahvila Closing Time (Hour = 22:00)
  daynight.set_hour(22)
  sleep(0.5)
  local act_night = city_life.current_interaction()
  check(act_night ~= nil and act_night.open == false, "Torikahvila is closed at night (22:00)")

  -- 5. Riverboat Evening Life: Svarte Rudolf
  local rudolf = nil
  for _, b in ipairs(city_life.boats) do
    if b.spec.key == "rudolf" then rudolf = b end
  end
  check(rudolf ~= nil, "Svarte Rudolf found")

  -- Walk onto Svarte Rudolf gangway and deck
  move_player(rudolf.gangway_pos[1], rudolf.gangway_pos[2] + 1.2, rudolf.gangway_pos[3])
  sleep(0.5)
  local px, py, pz = engine.pos(G.player)
  check(py >= 1.0, string.format("Player safely on Svarte Rudolf gangway, y=%.2f", py))

  -- Move to Svarte Rudolf bar counter
  move_player(rudolf.bar_pos[1], rudolf.bar_pos[2] + 1.2, rudolf.bar_pos[3])
  sleep(0.5)

  local b_act = city_life.current_interaction()
  check(b_act ~= nil, "Interaction detected at Svarte Rudolf bar counter")
  check(b_act.kind == "riverboat_bar", "Interaction is riverboat_bar")
  check(b_act.open == true, "Riverboat bar is open at 22:00")

  -- Order Aura-olut ($6, +25 HP) via 'r'
  health.player.hp = 50
  local hp_before_beer = health.player.hp
  local cash_before_beer = G.cash
  engine.emit("key", "r", true)
  sleep(0.2)
  check(G.cash == cash_before_beer - 6, string.format("Aura-olut ordered (-$6), cash is now $%d", G.cash))
  check(health.player.hp > hp_before_beer, string.format("Player healed from %d to %d HP", hp_before_beer, health.player.hp))

  -- 6. Riverboat: Donna
  local donna = nil
  for _, b in ipairs(city_life.boats) do
    if b.spec.key == "donna" then donna = b end
  end
  check(donna ~= nil, "Donna found")
  move_player(donna.bar_pos[1], donna.bar_pos[2] + 1.2, donna.bar_pos[3])
  sleep(0.5)
  local d_act = city_life.current_interaction()
  check(d_act ~= nil and d_act.kind == "riverboat_bar", "Donna deck bar active")
  engine.emit("key", "r", true)
  sleep(0.2)
  check(G.cash == cash_before_beer - 6 - 7, "Donna Special ordered (-$7)")

  -- 7. Riverboat: Majland
  local majland = nil
  for _, b in ipairs(city_life.boats) do
    if b.spec.key == "majland" then majland = b end
  end
  check(majland ~= nil, "Majland found")
  move_player(majland.bar_pos[1], majland.bar_pos[2] + 1.2, majland.bar_pos[3])
  sleep(0.5)
  local m_act = city_life.current_interaction()
  check(m_act ~= nil and m_act.kind == "riverboat_bar", "Majland deck bar active")
  engine.emit("key", "r", true)
  sleep(0.2)
  check(G.cash == cash_before_beer - 6 - 7 - 6, "Majland-IPA ordered (-$6)")

  -- 8. Daytime closing for riverboat bar (Hour = 10:00)
  daynight.set_hour(10)
  sleep(0.5)
  local m_day_act = city_life.current_interaction()
  check(m_day_act ~= nil and m_day_act.open == false, "Riverboat bar closed at 10:00")

  print("ALL CITY LIFE CHECKS PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then
    engine.quit()
    error(err, 0)
  end
end)
