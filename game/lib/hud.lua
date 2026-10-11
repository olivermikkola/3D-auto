-- Heads-up display: cash, speed, mission text, minimap, big messages.
local G = require "lib.state"
local U = require "lib.util"

local M = {}
local show_help = true

local function shadow_text(s, x, y, size, r, g, b)
  engine.text(s, x + 2, y + 2, size, 0, 0, 0, 0.6)
  engine.text(s, x, y, size, r, g, b, 1)
end

local function centered(s, y, size, r, g, b)
  local w = engine.screen()
  shadow_text(s, (w - engine.text_width(s, size)) / 2, y, size, r, g, b)
end

local function minimap(sw, sh)
  local L = G.city
  if not L then return end
  local S, half = 180, L.size / 2
  local x0, y0 = sw - S - 20, sh - S - 20
  local function map(wx, wz) return x0 + (wx + half) / L.size * S, y0 + (wz + half) / L.size * S end
  engine.rect(x0 - 4, y0 - 4, S + 8, S + 8, 0, 0, 0, 0.55)
  engine.rect(x0, y0, S, S, 0.62, 0.62, 0.6, 0.85)
  local rw = L.road / L.size * S
  for k = 0, L.N do
    local a = map(L.origin + k * L.P, 0)
    engine.rect(a - rw / 2, y0, rw, S, 0.25, 0.25, 0.27, 0.95)
    local _, b = map(0, L.origin + k * L.P)
    engine.rect(x0, b - rw / 2, S, rw, 0.25, 0.25, 0.27, 0.95)
  end
  for _, id in ipairs(engine.find("car")) do
    local x, _, z = engine.pos(id)
    local px, py = map(x, z)
    engine.rect(px - 1.5, py - 1.5, 3, 3, 0.4, 0.6, 1.0, 1)
  end
  for _, m in ipairs(G.markers or {}) do
    if engine.exists(m.id) then
      local x, _, z = engine.pos(m.id)
      local px, py = map(x, z)
      engine.rect(px - 3, py - 3, 6, 6, m.color[1], m.color[2], m.color[3], 1)
    end
  end
  engine.emit("minimap", map) -- other systems add blips
  local x, _, z = U.player_pos()
  if x then
    local px, py = map(x, z)
    engine.rect(px - 3, py - 3, 6, 6, 1, 1, 1, 1)
  end
end

engine.on("key", function(k, down) if k == "f1" and down then show_help = not show_help end end)

engine.on("frame", function(dt)
  local w, h = engine.screen()
  shadow_text(string.format("$%d", G.cash), w - 20 - engine.text_width(string.format("$%d", G.cash), 28), 20, 28, 0.4, 0.9, 0.4)

  -- Clock, under the cash.
  local clock = require("lib.daynight").clock()
  shadow_text(clock, w - 20 - engine.text_width(clock, 14), 92, 14, 0.85, 0.85, 0.85)

  -- Wanted stars; they blink while the cops can't see you.
  local stars = require("lib.wanted")
  if stars.stars() > 0 then
    local show = stars.seen or math.floor(engine.time() * 3) % 2 == 0
    for k = 1, 5 do
      local lit = k <= stars.stars() and show
      local x = w - 20 - (6 - k) * 26
      shadow_text("*", x, 58, 28, lit and 1 or 0.3, lit and 0.85 or 0.3, lit and 0.2 or 0.3)
    end
  end

  if G.vehicle and engine.exists(G.vehicle) then
    local kmh = math.abs(require("lib.vehicle").speed(G.vehicle)) * 3.6
    shadow_text(string.format("%3d KM/H", math.floor(kmh)), 20, h - 50, 28, 1, 1, 1)
  end

  local m = G.mission
  if m then
    if m.objective then centered(m.objective, 110, 18, 1, 0.9, 0.5) end
    if m.deadline then
      local left = math.max(0, m.deadline - engine.time())
      centered(string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)), 140, 24, 1, left < 10 and 0.3 or 1, left < 10 and 0.3 or 1)
    end
  end

  -- Big messages, newest last.
  local now, y, keep = engine.time(), h * 0.35, {}
  for _, msg in ipairs(G.messages) do
    if msg.till > now then
      keep[#keep + 1] = msg
      centered(msg.text, y, 30, 1, 0.85, 0.2)
      y = y + 44
    end
  end
  G.messages = keep

  minimap(w, h)

  if show_help then
    local lines = "WASD MOVE/DRIVE  SHIFT RUN  SPACE JUMP/HANDBRAKE\nE ENTER/EXIT CAR  H HORN  MOUSE/ARROWS CAMERA\nYELLOW MARKERS: MISSIONS  ORANGE RAMPS: STUNT PARK\nN SKIP 3 HOURS  F5 RELOAD SCRIPTS  F1 HIDE HELP  ESC FREE MOUSE"
    engine.rect(14, 14, engine.text_width(lines, 12) + 16, 76, 0, 0, 0, 0.45)
    engine.text(lines, 22, 22, 12, 0.9, 0.9, 0.9, 1)
  end
  local st = engine.stats()
  engine.text(string.format("%d ENTITIES", st.entities), 20, h - 18, 10, 1, 1, 1, 0.5)
end)

return M
