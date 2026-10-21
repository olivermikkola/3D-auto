-- The later missions and the order they unlock in, played by teleporting.
-- MISSION_TEST=1 auto game --headless 6000
local G = require "lib.state"
local U = require "lib.util"
local H = require "lib.health"
local mission = require "lib.mission"
local city = require "lib.city"
local wanted = require "lib.wanted"
local traffic = require "systems.traffic"

local held = {}
engine.key = function(k) return held[k] == true end
local function check(ok, what)
  if not ok then engine.quit(); error("MISSION TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local function def_of(id)
  for _, d in ipairs(mission.defs) do if d.id == id then return d end end
end

-- The script runs as a coroutine, one tick per yield.
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

-- Stand (or park the car you're in) at x, z, stopped.
local function go(x, z)
  local id = G.vehicle or G.player
  engine.set_pos(id, x, (G.vehicle and 0.8 or 1.2) + U.ground(x, z), z)
  engine.set_vel(id, 0, 0, 0)
  engine.set_angvel(id, 0, 0, 0)
end

local function start(id)
  local d = def_of(id)
  check(d and d.marker and engine.exists(d.marker), d.title .. " has a start marker")
  go(d.start[1], d.start[2])
  wait(function() return G.mission and G.mission.def == d end, 2, d.title .. " starts at its marker")
  sleep(0.1) -- let its script run up to its first wait
  return G.mission
end

local function pass(id)
  local d = def_of(id)
  G.passed[id] = true
  d.passed = true
  mission.show_start_markers()
end

local function script()
  sleep(0.5)
  for _, id in ipairs{"05_cargo", "06_takedown", "07_smuggler"} do
    check(def_of(id) and def_of(id).marker == nil, id .. " is locked in a new game")
  end
  check(def_of("01_joyride").marker ~= nil, "the first missions are open")
  -- Stepping into a marker starts the first mission listed there, so two
  -- starts on one spot would leave the later one impossible to play.
  local defs = mission.defs
  for i = 1, #defs do
    for j = i + 1, #defs do
      local a, b = defs[i].start, defs[j].start
      local d = U.dist2d(a[1], a[2], b[1], b[2])
      check(d >= 8, string.format("%s and %s start %.0f m apart", defs[i].title, defs[j].title, d))
    end
  end
  pass("04_getaway")
  check(def_of("05_cargo").marker ~= nil and def_of("06_takedown").marker == nil,
        "passing Getaway unlocks Fragile Cargo, and only that")

  -- ---- Fragile Cargo: a hard knock fails it ---------------------------------
  local m = start("05_cargo")
  local px, _, pz = engine.pos(m.car)
  engine.set_pos(G.player, px, 1.2 + U.ground(px, pz - 3.5), pz - 3.5)
  engine.emit("key", "e", true)
  wait(function() return G.vehicle == m.car end, 1, "got into the cargo car")
  H.damage(m.car, 45)
  wait(function() return G.mission == nil end, 1, "a ruined cargo ends the mission")
  check(not def_of("05_cargo").passed and G.cash == 0, "and it doesn't pay")

  -- ...and a careful delivery passes, unlocking Takedown.
  engine.emit("key", "e", true) -- out of the dented one
  wait(function() return G.vehicle == nil end, 1, "got out of the dented car")
  m = start("05_cargo")
  px, _, pz = engine.pos(m.car)
  engine.set_pos(G.player, px, 1.2 + U.ground(px, pz - 3.5), pz - 3.5)
  engine.emit("key", "e", true)
  wait(function() return G.vehicle == m.car end, 1, "got into the second cargo car")
  wait(function() return m.goal end, 1, "the drop is picked")
  go(m.goal[1], m.goal[2])
  wait(function() return G.mission == nil end, 2, "delivering the cargo ends the mission")
  check(def_of("05_cargo").passed and G.cash == 900, "Fragile Cargo pays $900 (cash " .. G.cash .. ")")
  check(def_of("06_takedown").marker ~= nil, "and unlocks Takedown")

  -- ---- Takedown: the target drives, runs when hit, and pays when it blows --
  engine.emit("key", "e", true)
  m = start("06_takedown")
  local tx, _, tz = engine.pos(m.target)
  check(traffic.cars[m.target] and traffic.cars[m.target].keep, "the target drives with traffic and isn't recycled")
  sleep(2)
  local nx, _, nz = engine.pos(m.target)
  check((nx - tx) ^ 2 + (nz - tz) ^ 2 > 4, "the target drives off")
  H.damage(m.target, 20)
  check(traffic.cars[m.target].cruise, "hitting the target makes it run")
  H.damage(m.target, 500)
  wait(function() return G.mission == nil end, 6, "the target burns and explodes")
  check(def_of("06_takedown").passed and G.cash == 2400, "Takedown pays $1500 (cash " .. G.cash .. ")")

  -- ---- Smuggler's Run: heat rises per package; the drop waits for zero stars
  m = start("07_smuggler")
  for i, n in ipairs(city.route("smuggle")) do
    go(n[1], n[2])
    wait(function() return m.objective and m.objective:find(i < 4 and tostring(i + 1) .. " of" or "drop") end, 1,
         "package " .. i .. " picked up")
    check(wanted.stars() == math.min(3, i - 1), string.format("%d star(s) after package %d", wanted.stars(), i))
  end
  go(city.place("smuggle_drop"))
  sleep(0.5)
  check(G.mission == m, "the drop waits while you're wanted")
  wanted.set(0)
  wait(function() return G.mission == nil end, 1, "the drop completes once the heat is gone")
  check(def_of("07_smuggler").passed and G.cash == 4400, "Smuggler's Run pays $2000 (cash " .. G.cash .. ")")

  print("MISSION TEST PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
