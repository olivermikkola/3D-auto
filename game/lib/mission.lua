-- Missions are coroutines. A mission file returns a table:
--
--   return {
--     title = "Name", start = {x, z}, reward = 500,
--     run = function(m)
--       m:say("Get in a car")
--       m:wait(function() return m:in_car() end)
--       local goal = m:marker(100, -40)
--       m:timer(60)
--       m:wait(function() return m:near(goal, 6) end)
--     end,
--   }
--
-- Returning from run() passes the mission; m:fail(reason) or running out of
-- time fails it. Everything spawned through m:spawn/m:marker is cleaned up.
local G = require "lib.state"
local U = require "lib.util"

local M = {defs = {}}
G.markers = {}

local Mission = {}
Mission.__index = Mission

function Mission:say(text) self.objective = text end
function Mission:timer(seconds) self.deadline = engine.time() + seconds end
function Mission:clear_timer() self.deadline = nil end
function Mission:fail(reason) coroutine.yield("fail", reason) end
function Mission:in_car() return G.vehicle ~= nil end
function Mission:wanted(stars) require("lib.wanted").set(stars) end
function Mission:stars() return require("lib.wanted").stars() end

function Mission:spawn(t)
  local id = engine.spawn(t)
  self.owned[#self.owned + 1] = id
  return id
end

-- A glowing column; returns its entity id.
function Mission:marker(x, z, color)
  color = color or {1, 0.85, 0.1}
  local id = self:spawn{mesh = "cylinder", pos = {x, 2.5, z}, size = {5, 5, 5}, color = {color[1], color[2], color[3], 0.35}}
  G.markers[#G.markers + 1] = {id = id, color = color}
  return id
end

function Mission:remove(id)
  engine.despawn(id)
end

function Mission:near(id, radius)
  local x, _, z = U.player_pos()
  local mx, _, mz = engine.pos(id)
  return x and mx and U.dist2d(x, z, mx, mz) <= radius
end

-- Block until pred() is true. The deadline is enforced while waiting.
function Mission:wait(pred)
  while not pred() do coroutine.yield() end
end

function Mission:sleep(seconds)
  local t = engine.time() + seconds
  self:wait(function() return engine.time() >= t end)
end

local function prune_markers()
  local keep = {}
  for _, m in ipairs(G.markers) do if engine.exists(m.id) then keep[#keep + 1] = m end end
  G.markers = keep
end

local function finish(m, passed, reason)
  for _, id in ipairs(m.owned) do engine.despawn(id) end
  G.mission = nil
  if passed then
    G.cash = G.cash + (m.def.reward or 0)
    m.def.passed = true
    U.message("MISSION PASSED", 4)
    if m.def.reward then U.message(string.format("+$%d", m.def.reward), 4) end
    engine.emit("mission_passed", m.def)
  else
    U.message("MISSION FAILED", 4)
    if reason then U.message(reason, 4) end
    engine.emit("mission_failed", m.def, reason)
  end
  M.show_start_markers()
end

-- Getting busted ends whatever you were doing.
engine.on("busted", function()
  if G.mission then finish(G.mission, false, "BUSTED") end
end)

function M.start(def)
  M.hide_start_markers()
  local m = setmetatable({def = def, owned = {}}, Mission)
  m.co = coroutine.create(function() def.run(m) return "pass" end)
  G.mission = m
  U.message(def.title:upper(), 3)
  engine.emit("mission_started", def)
end

engine.on("tick", function()
  local m = G.mission
  if not m then
    -- Walk or drive into a start marker to begin.
    for _, def in ipairs(M.defs) do
      if def.marker and engine.exists(def.marker) then
        local x, _, z = U.player_pos()
        if x and U.dist2d(x, z, def.start[1], def.start[2]) < 3 then return M.start(def) end
      end
    end
    return
  end
  if m.deadline and engine.time() > m.deadline then return finish(m, false, "OUT OF TIME") end
  local ok, status, reason = coroutine.resume(m.co)
  if not ok then
    finish(m, false, "SCRIPT ERROR")
    error(debug.traceback(m.co, status), 0)
  elseif status == "pass" then finish(m, true)
  elseif status == "fail" then finish(m, false, reason) end
  prune_markers()
end)

function M.show_start_markers()
  for _, def in ipairs(M.defs) do
    local c = def.passed and {0.3, 1, 0.3} or {1, 0.85, 0.1}
    def.marker = engine.spawn{mesh = "cylinder", pos = {def.start[1], 1.5, def.start[2]}, size = {2.5, 3, 2.5}, color = {c[1], c[2], c[3], 0.45}}
    G.markers[#G.markers + 1] = {id = def.marker, color = c}
  end
end

function M.hide_start_markers()
  for _, def in ipairs(M.defs) do
    if def.marker then engine.despawn(def.marker) end
    def.marker = nil
  end
  prune_markers()
end

-- Every .lua file in the directory is a mission. Drop one in, press F5.
function M.load_all(dir)
  for _, f in ipairs(engine.files(dir)) do
    local name = f:match("^(.+)%.lua$")
    if name then
      local def = require(dir .. "." .. name)
      def.id = name
      M.defs[#M.defs + 1] = def
    end
  end
  M.show_start_markers()
  print(string.format("loaded %d missions", #M.defs))
end

return M
