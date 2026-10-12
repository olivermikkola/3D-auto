-- Heads-up display: cash, speed, mission text, minimap, big messages.
local G = require "lib.state"
local U = require "lib.util"
local settings = require "lib.settings"

local M = {}

local function shadow_text(s, x, y, size, r, g, b)
  engine.text(s, x + 2, y + 2, size, 0, 0, 0, 0.6)
  engine.text(s, x, y, size, r, g, b, 1)
end

local function centered(s, y, size, r, g, b)
  local w = engine.screen()
  shadow_text(s, (w - engine.text_width(s, size)) / 2, y, size, r, g, b)
end

local function bar(x, y, bw, bh, frac, r, g, b)
  engine.rect(x - 2, y - 2, bw + 4, bh + 4, 0, 0, 0, 0.6)
  engine.rect(x, y, bw * math.max(0, math.min(1, frac)), bh, r, g, b, 0.95)
end

-- The map's static part (water, blocks, park, roads) as rects in 0..1 map
-- coordinates, worked out once per city.
local base, base_city
local COLORS = {
  downtown = {0.62, 0.62, 0.6}, residential = {0.7, 0.62, 0.52}, industrial = {0.62, 0.5, 0.38},
  park = {0.36, 0.58, 0.3}, road = {0.25, 0.25, 0.27}, land = {0.3, 0.42, 0.26}, water = {0.18, 0.32, 0.55},
}
local function map_base(L)
  if base_city == L then return base end
  local city = require "lib.city"
  local rects = {}
  local function add(x0, z0, x1, z1, c)
    rects[#rects + 1] = {(x0 + L.sx / 2) / L.sx, (z0 + L.sz / 2) / L.sz, (x1 - x0) / L.sx, (z1 - z0) / L.sz, c}
  end
  if L.network then
    -- Land, then rivers and roads as chains of dots, so curves show.
    add(-L.sx / 2, -L.sz / 2, L.sx / 2, L.sz / 2, COLORS.land)
    local function dots(pts, w, c)
      for i = 2, #pts do
        local ax, az, bx, bz = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
        local n = math.max(1, math.floor(U.dist2d(ax, az, bx, bz) / 6))
        for k = 0, n do
          local x, z = ax + (bx - ax) * k / n, az + (bz - az) * k / n
          add(x - w / 2, z - w / 2, x + w / 2, z + w / 2, c)
        end
      end
    end
    for _, river in ipairs(city.map().rivers or {}) do dots(river, (river.width or 10) * 1.6, COLORS.water) end
    for _, e in ipairs(require("lib.roadnet").net().edges) do dots(e.pts, math.max(9, e.width * 1.3), COLORS.road) end
    base, base_city = rects, L
    return rects
  end
  local A, S = L.avenue / 2, L.street / 2
  for _, j in ipairs(city.junctions()) do
    local x, z = city.pos(j)
    add(x - A, z - S, x + A, z + S, COLORS.road)
  end
  for _, r in ipairs(city.roads()) do
    local ax, az = city.pos(r[1])
    local bx, bz = city.pos(r[2])
    add(math.min(ax, bx) - A, math.min(az, bz) - S, math.max(ax, bx) + A, math.max(az, bz) + S, COLORS.road)
  end
  for i = 0, L.NX - 1 do
    for j = 0, L.NZ - 1 do
      local c = COLORS[city.district(i, j)]
      if c and city.district(i, j) ~= "park" then
        local x, z = city.block_center(i, j)
        add(x - L.bx / 2, z - L.bz / 2, x + L.bx / 2, z + L.bz / 2, c)
      end
    end
  end
  local P = L.park_area
  if P then
    add(P.x0, P.z0, P.x1, P.z1, COLORS.park)
    add(P.x0, P.transverse - S, P.x1, P.transverse + S, COLORS.road)
  end
  base, base_city = rects, L
  return rects
end

-- A town too big to show whole gets a radar instead: RADAR meters each way
-- round the player. Its static part is world-space rects, bucketed in
-- CELL-meter squares so a frame only looks at the ones in view.
local RADAR, CELL = 400, 100
local radar_base, radar_city
local stamp = 0
local function radar_rects(L)
  if radar_city == L then return radar_base end
  local cells = {}
  local function add(x0, z0, x1, z1, c)
    local r = {x0, z0, x1, z1, c}
    for i = math.floor(x0 / CELL), math.floor(x1 / CELL) do
      for j = math.floor(z0 / CELL), math.floor(z1 / CELL) do
        local k = i * 100003 + j
        cells[k] = cells[k] or {}
        table.insert(cells[k], r)
      end
    end
  end
  local city = require "lib.city"
  for _, st in ipairs((city.map().cover or {}).water or {}) do add(st[1], st[2], st[3], st[4], COLORS.water) end
  for _, e in ipairs(require("lib.roadnet").net().edges) do
    local w = math.max(8, e.width * 1.2)
    for i = 2, #e.pts do
      local ax, az, bx, bz = e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]
      local n = math.max(1, math.floor(U.dist2d(ax, az, bx, bz) / (w * 0.6)))
      for k = 0, n do
        local x, z = ax + (bx - ax) * k / n, az + (bz - az) * k / n
        add(x - w / 2, z - w / 2, x + w / 2, z + w / 2, COLORS.road)
      end
    end
  end
  radar_base, radar_city = cells, L
  return cells
end

local function radar(sw, sh, L)
  local px, _, pz = U.player_pos()
  if not px then return end
  local S = math.floor(math.min(230, sh * 0.3))
  local x0, y0 = sw - S - 20, sh - S - 20
  local k = S / (2 * RADAR)
  -- Anything off the radar is pinned to its edge, so blips still point the way.
  local function map(wx, wz)
    local u = math.max(-RADAR, math.min(RADAR, wx - px))
    local v = math.max(-RADAR, math.min(RADAR, wz - pz))
    return x0 + (u + RADAR) * k, y0 + (v + RADAR) * k
  end
  engine.rect(x0 - 4, y0 - 4, S + 8, S + 8, 0, 0, 0, 0.55)
  engine.rect(x0, y0, S, S, COLORS.land[1], COLORS.land[2], COLORS.land[3], 0.9)
  -- Rects span several cells; each is drawn once a frame, marked with the
  -- frame's stamp (no table a frame for the garbage collector).
  local cells = radar_rects(L)
  stamp = stamp + 1
  for i = math.floor((px - RADAR) / CELL), math.floor((px + RADAR) / CELL) do
    for j = math.floor((pz - RADAR) / CELL), math.floor((pz + RADAR) / CELL) do
      for _, r in ipairs(cells[i * 100003 + j] or {}) do
        if r[6] ~= stamp then
          r[6] = stamp
          local a = math.max(r[1], px - RADAR)
          local b = math.max(r[2], pz - RADAR)
          local c = math.min(r[3], px + RADAR)
          local d = math.min(r[4], pz + RADAR)
          if c > a and d > b then
            local col = r[5]
            engine.rect(x0 + (a - px + RADAR) * k, y0 + (b - pz + RADAR) * k, (c - a) * k, (d - b) * k, col[1], col[2], col[3], 0.9)
          end
        end
      end
    end
  end
  for _, id in ipairs(engine.find("car")) do
    local x, _, z = engine.pos(id)
    if math.abs(x - px) < RADAR and math.abs(z - pz) < RADAR then
      local bx, by = map(x, z)
      engine.rect(bx - 1.5, by - 1.5, 3, 3, 0.4, 0.6, 1.0, 1)
    end
  end
  for _, m in ipairs(G.markers or {}) do
    if engine.exists(m.id) then
      local x, _, z = engine.pos(m.id)
      local bx, by = map(x, z)
      engine.rect(bx - 3, by - 3, 6, 6, m.color[1], m.color[2], m.color[3], 1)
    end
  end
  for _, lm in ipairs(L.labels or {}) do
    if math.abs(lm.x - px) < RADAR and math.abs(lm.z - pz) < RADAR then
      local bx, by = map(lm.x, lm.z)
      engine.rect(bx - 4, by - 4, 8, 8, 1, 1, 1, 1)
      engine.text(lm.letter, bx + 6, by - 6, 10, 1, 1, 1, 1)
    end
  end
  engine.emit("minimap", map)
  engine.rect(x0 + S / 2 - 3, y0 + S / 2 - 3, 6, 6, 1, 1, 1, 1)
end

local function minimap(sw, sh)
  local L = G.city
  if not L then return end
  if L.network and math.max(L.sx, L.sz) > 2 * RADAR * 2.5 then return radar(sw, sh, L) end
  -- The island is tall and thin, so the map is too; it scales with the window.
  local H = math.floor(math.min(230, sh * 0.3))
  local W = math.floor(H * L.sx / L.sz)
  local x0, y0 = sw - W - 20, sh - H - 20
  local function map(wx, wz) return x0 + (wx + L.sx / 2) / L.sx * W, y0 + (wz + L.sz / 2) / L.sz * H end
  engine.rect(x0 - 4, y0 - 4, W + 8, H + 8, 0, 0, 0, 0.55)
  engine.rect(x0, y0, W, H, 0.18, 0.32, 0.55, 0.85)
  for _, r in ipairs(map_base(L)) do
    local c = r[5]
    engine.rect(x0 + r[1] * W, y0 + r[2] * H, r[3] * W, r[4] * H, c[1], c[2], c[3], 0.9)
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
  for _, lm in ipairs(L.labels or {}) do
    local px, py = map(lm.x, lm.z)
    engine.rect(px - 4, py - 4, 8, 8, 1, 1, 1, 1)
    engine.text(lm.letter, px + 6, py - 6, 10, 1, 1, 1, 1)
  end
  for _, lm in ipairs(L.landmarks or {}) do
    local px, py = map(lm.x, lm.z)
    engine.rect(px - 4, py - 4, 8, 8, 1, 1, 1, 1)
    engine.text(lm.letter, px + 6, py - 6, 10, 1, 1, 1, 1)
  end
  engine.emit("minimap", map) -- other systems add blips
  local x, _, z = U.player_pos()
  if x then
    local px, py = map(x, z)
    engine.rect(px - 3, py - 3, 6, 6, 1, 1, 1, 1)
  end
end

engine.on("key", function(k, down) if k == "f1" and down then settings.set("help", not settings.get("help")) end end)

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

  local H = require "lib.health"
  if G.vehicle and engine.exists(G.vehicle) then
    local kmh = math.abs(require("lib.vehicle").speed(G.vehicle)) * 3.6
    shadow_text(string.format("%3d KM/H", math.floor(kmh)), 20, h - 50, 28, 1, 1, 1)
    -- Car condition.
    local hp = H.get(G.vehicle) or H.VEHICLE_HP
    bar(20, h - 92, 160, 8, hp / H.VEHICLE_HP, 1, 0.6, 0.1)
  end

  -- Health.
  bar(20, h - 76, 160, 10, H.player.hp / H.player.max, 0.9, 0.15, 0.15)

  -- Weapon, ammo and crosshair (on foot).
  local W = require "systems.weapons"
  local def = W.defs[G.weapon]
  local label = def.name .. (def.melee and "" or string.format("  %d", G.ammo[G.weapon] or 0))
  shadow_text(label, w - 20 - engine.text_width(label, 16), h - math.min(230, h * 0.3) - 55, 16, 1, 1, 1)
  if G.player and not def.melee then
    local cx, cy = w / 2, h / 2
    for _, r in ipairs{{-9, -1, 6, 2}, {3, -1, 6, 2}, {-1, -9, 2, 6}, {-1, 3, 2, 6}} do
      engine.rect(cx + r[1], cy + r[2], r[3], r[4], 1, 1, 1, 0.85)
    end
  end

  -- Wasted: fade to dark red.
  if G.dead then
    local t = math.min(1, (engine.time() - G.dead) / 2)
    engine.rect(0, 0, w, h, 0.25, 0, 0, 0.6 * t)
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

  if settings.get("help") then
    local lines = require("lib.input").connected() and
      "L STICK MOVE/STEER  R STICK CAMERA  RT ACCELERATE/FIRE  LT BRAKE\nA JUMP/HANDBRAKE  B RUN/HORN  Y ENTER/EXIT CAR  X SHOPS\nLB/RB WEAPONS  BACK PROGRESS  START PAUSE/SETTINGS\nYELLOW MARKERS: MISSIONS  ORANGE RAMPS: STUNT PARK\nF1 HIDE HELP" or "WASD MOVE/DRIVE  SHIFT RUN  SPACE JUMP/HANDBRAKE\nE ENTER/EXIT CAR  H HORN  MOUSE/ARROWS CAMERA\nCLICK/F FIRE  1/2/3/Q WEAPONS\nYELLOW MARKERS: MISSIONS  ORANGE RAMPS: STUNT PARK\nTAB PROGRESS  N SKIP 3 HOURS  F5 RELOAD  F1 HIDE HELP  ESC PAUSE/SETTINGS"
    engine.rect(14, 14, engine.text_width(lines, 12) + 16, 93, 0, 0, 0, 0.45)
    engine.text(lines, 22, 22, 12, 0.9, 0.9, 0.9, 1)
  end
  local st = engine.stats()
  engine.text(string.format("%d ENTITIES", st.entities), 20, h - 18, 10, 1, 1, 1, 0.5)
end)

return M
