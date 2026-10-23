-- Missions are coroutines. A mission file returns a table:
--
--   return {
--     title = "Name", start = {x, z}, reward = 500,
--     after = "04_getaway",   -- optional: locked until that mission is passed
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
-- time fails it. Everything spawned through m:spawn/m:marker is cleaned up,
-- handlers added with m:on are removed, and m:defer(fn) runs fn at the end
-- whether the mission passed or failed.
local G = require "lib.state"
local U = require "lib.util"

local M = {defs = {}}
G.markers = {}

local Mission = {}
Mission.__index = Mission

function Mission:say(text) self.objective = text end
-- " on <street>" for a spot on a named street, for objectives; "" if not.
function Mission:on_street(x, z)
  local s = require("lib.city").street(x, z)
  return s and (" on " .. s) or ""
end
function Mission:timer(seconds) self.deadline = engine.time() + seconds end
function Mission:clear_timer() self.deadline = nil end
function Mission:fail(reason) coroutine.yield("fail", reason) end
function Mission:in_car() return G.vehicle ~= nil end
-- In that vehicle (the one the mission gave you), not just any.
function Mission:in_vehicle(id) return id ~= nil and G.vehicle == id end
function Mission:wanted(stars) require("lib.wanted").set(stars) end
function Mission:stars() return require("lib.wanted").stars() end

function Mission:on(ev, fn)
  engine.on(ev, fn)
  self:defer(function() engine.off(ev, fn) end)
end

function Mission:defer(fn) self.cleanup[#self.cleanup + 1] = fn end

-- Spawn t (a table, as engine.spawn takes) or take on an entity already
-- spawned (a vehicle from vehicle.spawn): either way it goes when the
-- mission ends.
function Mission:spawn(t)
  local id = type(t) == "table" and engine.spawn(t) or t
  self.owned[#self.owned + 1] = id
  return id
end

-- A glowing column; returns its entity id.
function Mission:marker(x, z, color)
  color = color or {1, 0.85, 0.1}
  local id = self:spawn{mesh = "marker", pos = {x, 2.5 + U.ground(x, z), z}, scale = 5, color = {color[1], color[2], color[3], 0.35}}
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
  -- (Not the vehicle you're in: the bus, the Pasi or the boat stays in town
  -- with you in it, as an ordinary vehicle.)
  for _, id in ipairs(m.owned) do
    if id ~= G.vehicle and engine.exists(id) then engine.despawn(id) end
  end
  for _, fn in ipairs(m.cleanup) do fn() end
  G.mission = nil
  if passed then
    G.cash = G.cash + (m.def.reward or 0)
    m.def.passed = true
    U.message("MISSION PASSED", 4)
    if m.def.reward then U.message(string.format("+$%d", m.def.reward), 4) end
    for _, def in ipairs(M.defs) do
      if def.after == m.def.id and not def.passed then U.message("NEW MISSION: " .. def.title:upper(), 5) end
    end
    engine.emit("mission_passed", m.def)
  else
    U.message("MISSION FAILED", 4)
    if reason then U.message(reason, 4) end
    engine.emit("mission_failed", m.def, reason)
  end
  M.show_start_markers()
end

-- Getting busted or wasted ends whatever you were doing.
engine.on("busted", function()
  if G.mission then finish(G.mission, false, "BUSTED") end
end)
engine.on("wasted", function()
  if G.mission then finish(G.mission, false, "WASTED") end
end)

function M.start(def)
  M.hide_start_markers()
  local m = setmetatable({def = def, owned = {}, cleanup = {}}, Mission)
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

-- A mission with `after` waits for that one to be passed.
function M.unlocked(def)
  return def.after == nil or (G.passed or {})[def.after] == true
end

function M.show_start_markers()
  M.hide_start_markers()
  for _, def in ipairs(M.defs) do
    if M.unlocked(def) then
      local c = def.passed and {0.3, 1, 0.3} or {1, 0.85, 0.1}
      def.marker = engine.spawn{mesh = "marker", pos = {def.start[1], 1.5 + U.ground(def.start[1], def.start[2]), def.start[2]}, scale = {2.5, 3, 2.5}, color = {c[1], c[2], c[3], 0.45}}
      G.markers[#G.markers + 1] = {id = def.marker, color = c}
    end
  end
end

function M.hide_start_markers()
  for _, def in ipairs(M.defs) do
    if def.marker then engine.despawn(def.marker) end
    def.marker = nil
  end
  prune_markers()
end

-- Add a mission. Mods call this; the game's own missions come from load_all.
function M.register(def)
  assert(type(def) == "table" and def.title and def.start and def.run, "a mission needs title, start and run")
  def.id = def.id or def.title
  if G.passed[def.id] then def.passed = true end
  M.defs[#M.defs + 1] = def
  if M.ready then M.show_start_markers() end
end

function M.all() return M.defs end

-- Every .lua file in the directory is a mission. Drop one in, press F5.
function M.load_all(dir)
  -- A unit cylinder that glows at night.
  engine.mesh("marker", {{mesh = "cylinder", emissive = 1}})
  for _, f in ipairs(engine.files(dir)) do
    local name = f:match("^(.+)%.lua$")
    if name then
      local def = require(dir .. "." .. name)
      -- A mission returns false when the map lacks a place it needs.
      if type(def) == "table" then
        def.id = name
        M.register(def)
      else
        print("mission " .. name .. " is not on this map")
      end
    end
  end
  M.ready = true
  M.show_start_markers()
  print(string.format("loaded %d missions", #M.defs))
end

return M
