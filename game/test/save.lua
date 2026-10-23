-- Saves, across real restarts. CI runs the game three times on one folder:
--   SAVE_TEST=1 auto game --headless 600 --save-dir DIR   earn progress, quit
--   SAVE_TEST=2 ...                                       it all came back
--   (CI overwrites DIR/progress.lua with garbage)
--   SAVE_TEST=3 ...                                       a bad save starts fresh
local G = require "lib.state"
local progress = require "lib.progress"
local mission = require "lib.mission"
local phase = tonumber(os.getenv("SAVE_TEST"))

local function check(ok, what)
  if not ok then engine.quit(); error("SAVE TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b and math.type(a) == math.type(b) end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Awkward values that must come back exactly, from memory and from disk.
local SAMPLE = {
  int = 42, neg = -7, float = 0.1, whole_float = 3.0, tiny = -2.5e-8, big = 1e300, maxint = math.maxinteger,
  yes = true, no = false, list = {1, "two", {3}}, holes = {[1] = "a", [3] = "c"},
  ["spaced key"] = 1, ["end"] = "keyword key", [10] = "int key", [0.5] = "float key", [true] = "bool key",
  text = "quotes \" ' backslash \\ newline \n tab \t nul \0 bell \a utf8 \u{e9}\u{65e5} raw \255\254",
  nested = {a = {b = {c = {d = {}}}}},
}

local function joyride()
  for _, d in ipairs(mission.defs) do if d.id == "01_joyride" then return d end end
end

local steps = {}

if phase == 1 then
  steps[1] = function()
    check(#engine.saves() == 0, "starts with an empty save folder")
    check(G.cash == 0 and next(G.passed) == nil, "a new game: no cash, no missions")
    check(engine.save("roundtrip", SAMPLE) == true, "engine.save accepts tables, numbers, strings, booleans")
    check(same(engine.load("roundtrip"), SAMPLE), "engine.load returns exactly what was saved")
    check(engine.load("never_saved") == nil, "a missing key loads as nil")
    check(engine.save("scratch", 1) and engine.save("scratch", nil) and engine.load("scratch") == nil, "saving nil deletes a key")
    for _, bad in ipairs{"../escape", "a/b", "", ".hidden", "con", "has space"} do
      check(not pcall(engine.save, bad, 1), "refuses key '" .. bad .. "'")
    end
    local cycle = {}
    cycle.me = cycle
    for what, v in pairs{["a function"] = {print}, ["a cycle"] = cycle, ["infinity"] = {math.huge}, ["NaN"] = {0 / 0},
                         ["1 MB"] = string.rep("x", 1 << 20)} do
      check(not pcall(engine.save, "bad", v), "refuses to save " .. what)
    end
    check(engine.load("bad") == nil, "a refused save writes nothing")

    -- Earn some progress the way the game does.
    G.cash = 777
    G.stats.patients, G.stats.fire_calls, G.stats.suspects_caught = 3, 5, 2
    engine.emit("stunt", 2.46, 10, 1.5)
    engine.emit("mission_passed", joyride())
  end
  steps[180] = function() -- 3 s later: the autosave delay has passed
    local p = engine.load("progress")
    check(p and p.cash == 777 and p.missions["01_joyride"] == true, "progress autosaves a moment after it changes")
    G.cash = 778 -- changed right before quitting: only the quit event can save this
    print("SAVE TEST PHASE 1 PASSED")
    engine.quit()
  end
elseif phase == 2 then
  steps[1] = function()
    check(G.cash == 778, "cash survives a restart, including a change made just before quitting ($" .. G.cash .. ")")
    check(G.passed["01_joyride"] and joyride().passed, "passed missions survive a restart (marker turns green)")
    check(G.stats.stunts == 1 and G.stats.best_air == 2.5 and G.stats.best_flips == 1, "stunt records survive a restart")
    check(G.stats.patients == 3 and G.stats.fire_calls == 5 and G.stats.suspects_caught == 2,
          "job counts survive a restart (they also seed the next call)")
    for k, v in pairs(G.stats) do check(math.type(v) ~= nil, "stat " .. k .. " is a number") end
    check(same(engine.load("roundtrip"), SAMPLE), "every awkward value survives the disk")
    local keys = engine.saves()
    check(#keys == 2 and keys[1] == "progress" and keys[2] == "roundtrip", "engine.saves lists the keys")
    progress.reset()
    check(G.cash == 0 and next(G.passed) == nil and not joyride().passed, "reset starts a new game")
    check(engine.load("progress").cash == 0, "and saves it")
    G.cash = 50
    print("SAVE TEST PHASE 2 PASSED")
    engine.quit()
  end
elseif phase == 3 then
  steps[1] = function()
    check(progress.load_error ~= nil, "an unreadable save is reported: " .. tostring(progress.load_error))
    check(G.cash == 0, "and the game starts fresh instead of crashing")
    check(engine.load("progress") == nil, "the bad file is moved aside, not overwritten")
    G.cash = 5
    check(progress.save() and engine.load("progress").cash == 5, "new progress saves normally")
    print("SAVE TEST PASSED")
    engine.quit()
  end
end

local n = 0
engine.on("tick", function()
  n = n + 1
  if steps[n] then steps[n]() end
end)
