-- Progress that survives quitting: cash, missions passed, personal bests,
-- ammo, and the car you bought.
-- It's the "progress" save (see engine.save), written a couple of seconds
-- after anything changes and again when the game closes or reloads.
-- Tab shows it; holding Backspace on that screen starts over.
local G = require "lib.state"
local U = require "lib.util"

local M = {}
local KEY, DELAY, RESET_HOLD = "progress", 2, 3

local AMMO = {pistol = 36, smg = 0} -- what a new game starts with

local function blank()
  return {cash = 0, missions = {}, stats = {stunts = 0, best_air = 0, best_flips = 0, busted = 0, wasted = 0},
          ammo = {pistol = AMMO.pistol, smg = AMMO.smg}, car = nil}
end

-- Keep only what we recognise, so a hand-edited save can't break the game.
local function clean(t)
  local p = blank()
  if type(t) ~= "table" then return p end
  if type(t.cash) == "number" then p.cash = math.tointeger(math.floor(U.clamp(t.cash, 0, 1e9))) end
  if type(t.missions) == "table" then
    for id, done in pairs(t.missions) do
      if type(id) == "string" and done == true then p.missions[id] = true end
    end
  end
  if type(t.stats) == "table" then
    for k in pairs(p.stats) do
      local v = t.stats[k]
      if type(v) == "number" and v >= 0 and v < 1e9 then p.stats[k] = v end
    end
  end
  if type(t.ammo) == "table" then
    for k in pairs(p.ammo) do
      local v = t.ammo[k]
      if type(v) == "number" then p.ammo[k] = math.tointeger(math.floor(U.clamp(v, 0, 9999))) end
    end
  end
  local colors = #require("lib.prefabs").car_colors
  if type(t.car) == "table" and math.type(t.car.color) == "integer" and t.car.color >= 1 and t.car.color <= colors then
    p.car = {color = t.car.color}
  end
  return p
end

local data, err = engine.load(KEY)
M.load_error = err
if err then print("progress: " .. err) end
local p = clean(data)
G.cash, G.passed, G.stats, G.owned_car = p.cash, p.missions, p.stats, p.car
-- systems.weapons sets the starting ammo when it loads; ours replaces it once everything has.
local loaded_ammo = p.ammo
engine.on("init", function() G.ammo.pistol, G.ammo.smg = loaded_ammo.pistol, loaded_ammo.smg end)

local saved_cash, saved_pistol, saved_smg, dirty, due = G.cash, p.ammo.pistol, p.ammo.smg, false, nil

-- Something not tracked automatically changed (a purchase, say): save soon.
function M.touch() dirty = true end

function M.save()
  local ammo = G.ammo or loaded_ammo
  local ok, e = engine.save(KEY, {version = 1, cash = G.cash, missions = G.passed, stats = G.stats,
                                  ammo = {pistol = ammo.pistol, smg = ammo.smg}, car = G.owned_car})
  saved_cash, saved_pistol, saved_smg, dirty, due = G.cash, ammo.pistol, ammo.smg, false, nil
  if not ok then
    print("progress: " .. e)
    U.message("COULDN'T SAVE PROGRESS", 3)
  end
  return ok
end

local function changed()
  local ammo = G.ammo or loaded_ammo
  return dirty or G.cash ~= saved_cash or ammo.pistol ~= saved_pistol or ammo.smg ~= saved_smg
end

-- Forget everything: back to a new game.
function M.reset()
  local fresh = blank()
  G.cash, G.passed, G.stats, G.owned_car = fresh.cash, fresh.missions, fresh.stats, nil
  if G.ammo then G.ammo.pistol, G.ammo.smg = fresh.ammo.pistol, fresh.ammo.smg end
  local mission = require "lib.mission"
  for _, def in ipairs(mission.defs) do def.passed = nil end
  if not G.mission then mission.show_start_markers() end
  M.save()
  U.message("PROGRESS RESET", 3)
end

engine.on("init", function()
  if M.load_error then U.message("SAVE WAS UNREADABLE, STARTING FRESH", 5) end
end)

engine.on("mission_passed", function(def)
  G.passed[def.id] = true
  dirty = true
end)
engine.on("stunt", function(air, _, flips)
  local s = G.stats
  s.stunts = s.stunts + 1
  s.best_air = math.max(s.best_air, math.floor(air * 10 + 0.5) / 10)
  s.best_flips = math.max(s.best_flips, math.floor(flips))
  dirty = true
end)
engine.on("busted", function() G.stats.busted = G.stats.busted + 1; dirty = true end)
engine.on("wasted", function() G.stats.wasted = G.stats.wasted + 1; dirty = true end)

engine.on("tick", function()
  if not changed() then return end
  due = due or engine.time() + DELAY
  if engine.time() >= due then M.save() end
end)

engine.on("quit", function()
  if changed() then M.save() end
end)

-- ---- the Tab screen ---------------------------------------------------------
local shown, hold = false, 0

engine.on("key", function(k, down)
  if k == "tab" and down then shown, hold = not shown, 0 end
end)

engine.on("frame", function(dt)
  if not shown or engine.paused() then return end
  hold = engine.key("backspace") and hold + dt or 0
  if hold >= RESET_HOLD then
    hold, shown = 0, false
    return M.reset()
  end

  local defs = require("lib.mission").defs
  local done = 0
  for _, def in ipairs(defs) do if G.passed[def.id] then done = done + 1 end end
  local s = G.stats
  local rows = {
    {"CASH", string.format("$%d", G.cash)},
    {"MISSIONS", string.format("%d / %d", done, #defs)},
    {"STUNTS", tostring(s.stunts)},
    {"BEST AIRTIME", string.format("%.1f S", s.best_air)},
    {"MOST FLIPS", tostring(s.best_flips)},
    {"BUSTED", tostring(s.busted)},
    {"WASTED", tostring(s.wasted)},
  }
  local w, h = engine.screen()
  local pw, ph = 340, 130 + #rows * 26
  local x, y = (w - pw) / 2, (h - ph) / 2
  engine.rect(x, y, pw, ph, 0, 0, 0, 0.7)
  engine.text("PROGRESS", x + 20, y + 18, 20, 1, 0.85, 0.2, 1)
  for i, r in ipairs(rows) do
    local ry = y + 30 + i * 26
    engine.text(r[1], x + 20, ry, 14, 0.8, 0.8, 0.8, 1)
    engine.text(r[2], x + pw - 20 - engine.text_width(r[2], 14), ry, 14, 1, 1, 1, 1)
  end
  local foot = hold > 0 and string.format("STARTING OVER IN %.1f...", RESET_HOLD - hold) or "SAVED AUTOMATICALLY\nHOLD BACKSPACE TO START OVER"
  engine.text(foot, x + 20, y + ph - 44, 10, hold > 0 and 1 or 0.6, hold > 0 and 0.4 or 0.6, hold > 0 and 0.4 or 0.6, 1)
end)

return M
