-- Fullscreen interactive vector map viewer for pause menu and navigation.
local U = require "lib.util"
local G = require "lib.state"
local city = require "lib.city"

local V = {
  pan_x = 0,
  pan_z = 0,
  zoom = 0.35,
  inited = false,
  dragging = false,
  drag_start_x = 0,
  drag_start_y = 0,
  drag_pan_x = 0,
  drag_pan_z = 0,
}

local COLORS = {
  bg = {0.05, 0.06, 0.09},
  viewport = {0.12, 0.15, 0.19},
  road = {0.28, 0.30, 0.34},
  arterial = {0.44, 0.46, 0.52},
  water = {0.16, 0.28, 0.36},
  accent = {1.0, 0.85, 0.2},
}

function V.recenter()
  local px, _, pz = U.player_pos()
  local L = G.city
  if px then
    V.pan_x = px
    V.pan_z = pz
  elseif L then
    V.pan_x = L.cx or 0
    V.pan_z = L.cz or 0
  else
    V.pan_x, V.pan_z = 0, 0
  end
end

function V.init()
  V.recenter()
  local L = G.city
  local sw, sh = engine.screen()
  local vw, vh = sw - 40, sh - 116
  if L and L.sx and L.sz then
    V.zoom = math.max(0.12, math.min(1.2, math.min(vw / L.sx, vh / L.sz) * 1.5))
  else
    V.zoom = 0.35
  end
  V.inited = true
end

function V.key(k)
  local speed = 140 / math.max(0.05, V.zoom)
  if k == "w" or k == "up" then V.pan_z = V.pan_z - speed
  elseif k == "s" or k == "down" then V.pan_z = V.pan_z + speed
  elseif k == "a" or k == "left" then V.pan_x = V.pan_x - speed
  elseif k == "d" or k == "right" then V.pan_x = V.pan_x + speed
  elseif k == "=" or k == "+" or k == "e" then V.zoom = math.min(1.8, V.zoom * 1.25)
  elseif k == "-" or k == "_" or k == "q" then V.zoom = math.max(0.04, V.zoom / 1.25)
  elseif k == "space" or k == "enter" then V.recenter()
  end
end

function V.mouse_down(x, y)
  V.dragging = true
  V.drag_start_x = x
  V.drag_start_y = y
  V.drag_pan_x = V.pan_x
  V.drag_pan_z = V.pan_z
end

function V.mouse_up()
  V.dragging = false
end

function V.frame()
  if V.dragging then
    local cx, cy = engine.cursor()
    V.pan_x = V.drag_pan_x - (cx - V.drag_start_x) / math.max(0.01, V.zoom)
    V.pan_z = V.drag_pan_z - (cy - V.drag_start_y) / math.max(0.01, V.zoom)
    if not engine.key("mouse1") then
      V.dragging = false
    end
  end
end

function V.draw(sw, sh)
  V.frame()
  local cur_map = city.map()
  local L = G.city

  -- 1. Fullscreen dark backdrop
  engine.rect(0, 0, sw, sh, COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 0.98)

  -- 2. Top Header
  engine.rect(0, 0, sw, 52, 0.08, 0.09, 0.12, 1)
  engine.rect(0, 52, sw, 2, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
  local title = string.upper(cur_map.name or "CITY") .. " — SATELLITE MAP"
  engine.text(title, 24, 16, 20, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

  -- Top right: current street / area or back button
  local px, py, pz = U.player_pos()
  if px then
    local street, area
    if L and L.network then
      street, area = require("lib.roadnet").where(px, pz)
    end
    local loc_str = (street or "DISTRICT") .. (area and (" (" .. area .. ")") or "")
    local tw = engine.text_width(string.upper(loc_str), 12)
    engine.text(string.upper(loc_str), sw - 140 - tw, 20, 12, 0.8, 0.82, 0.85, 1)
  end

  engine.rect(sw - 110, 12, 88, 28, 0.15, 0.18, 0.22, 1)
  engine.text("ESC: BACK", sw - 98, 19, 12, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

  -- 3. Viewport setup
  local vx, vy = 20, 64
  local vw, vh = sw - 40, sh - 116
  engine.rect(vx, vy, vw, vh, COLORS.viewport[1], COLORS.viewport[2], COLORS.viewport[3], 1)

  local function to_screen(wx, wz)
    local sx = vx + vw / 2 + (wx - V.pan_x) * V.zoom
    local sy = vy + vh / 2 + (wz - V.pan_z) * V.zoom
    return sx, sy
  end

  local function in_view(sx, sy, pad)
    pad = pad or 12
    return sx >= vx - pad and sx <= vx + vw + pad and sy >= vy - pad and sy <= vy + vh + pad
  end

  -- 4. Water areas
  local cover = cur_map.cover
  if cover and cover.water then
    for _, st in ipairs(cover.water) do
      local s1x, s1y = to_screen(st[1], st[2])
      local s2x, s2y = to_screen(st[3], st[4])
      local rx, ry = math.min(s1x, s2x), math.min(s1y, s2y)
      local rw, rh = math.abs(s2x - s1x), math.abs(s2y - s1y)
      local cx = math.max(vx, rx)
      local cy = math.max(vy, ry)
      local cw = math.min(vx + vw, rx + rw) - cx
      local ch = math.min(vy + vh, ry + rh) - cy
      if cw > 0 and ch > 0 then
        engine.rect(cx, cy, cw, ch, COLORS.water[1], COLORS.water[2], COLORS.water[3], 0.95)
      end
    end
  end

  -- 5. Aurajoki River corridor if in Turku
  if cur_map.id == "turku" then
    local river_pts = {
      {450, -320}, {280, -180}, {120, -70}, {-60, 40},
      {-280, 180}, {-520, 340}, {-800, 520}, {-1200, 780}, {-1600, 1050}
    }
    local rsize = math.max(8, 46 * V.zoom)
    for i = 2, #river_pts do
      local p0, p1 = river_pts[i - 1], river_pts[i]
      local ax, ay = to_screen(p0[1], p0[2])
      local bx, by = to_screen(p1[1], p1[2])
      local dist = math.sqrt((bx - ax)^2 + (by - ay)^2)
      local steps = math.max(1, math.floor(dist / 8))
      for k = 0, steps do
        local rx = ax + (bx - ax) * k / steps
        local ry = ay + (by - ay) * k / steps
        if in_view(rx, ry, rsize) then
          local cx = math.max(vx, rx - rsize / 2)
          local cy = math.max(vy, ry - rsize / 2)
          local cw = math.min(vx + vw, rx + rsize / 2) - cx
          local ch = math.min(vy + vh, ry + rsize / 2) - cy
          if cw > 0 and ch > 0 then
            engine.rect(cx, cy, cw, ch, COLORS.water[1], COLORS.water[2], COLORS.water[3], 0.95)
          end
        end
      end
    end
  end

  -- 6. Road network
  if L and L.network then
    local net = require("lib.roadnet").net()
    for _, e in ipairs(net.edges) do
      local rw = math.max(2, (e.width or 12) * V.zoom)
      local is_arterial = (e.width and e.width >= 16) or e.oneway
      local rc = is_arterial and COLORS.arterial or COLORS.road
      for i = 2, #e.pts do
        local p0, p1 = e.pts[i - 1], e.pts[i]
        local ax, ay = to_screen(p0[1], p0[2])
        local bx, by = to_screen(p1[1], p1[2])
        if in_view(ax, ay, 20) or in_view(bx, by, 20) then
          local dist = math.sqrt((bx - ax)^2 + (by - ay)^2)
          local steps = math.max(1, math.floor(dist / math.max(3, rw * 0.7)))
          for k = 0, steps do
            local rx = ax + (bx - ax) * k / steps
            local ry = ay + (by - ay) * k / steps
            if rx >= vx and rx + rw <= vx + vw and ry >= vy and ry + rw <= vy + vh then
              engine.rect(rx - rw / 2, ry - rw / 2, rw, rw, rc[1], rc[2], rc[3], 0.95)
            end
          end
        end
      end
    end
  elseif L then
    local A, S = (L.avenue or 16) / 2, (L.street or 13) / 2
    for _, j in ipairs(city.junctions()) do
      local jx, jz = city.pos(j)
      local sx, sy = to_screen(jx, jz)
      local jw = math.max(3, A * 2 * V.zoom)
      if in_view(sx, sy, 10) then
        engine.rect(sx - jw / 2, sy - jw / 2, jw, jw, COLORS.road[1], COLORS.road[2], COLORS.road[3], 0.95)
      end
    end
    for _, r in ipairs(city.roads()) do
      local ax, az = city.pos(r[1])
      local bx, bz = city.pos(r[2])
      local asx, asy = to_screen(ax, az)
      local bsx, bsy = to_screen(bx, bz)
      local rx, ry = math.min(asx, bsx), math.min(asy, bsy)
      local rw = math.max(math.abs(bsx - asx), math.max(2, A * 2 * V.zoom))
      local rh = math.max(math.abs(bsy - asy), math.max(2, S * 2 * V.zoom))
      if in_view(rx, ry, 20) then
        engine.rect(rx, ry, rw, rh, COLORS.road[1], COLORS.road[2], COLORS.road[3], 0.95)
      end
    end
  end

  -- 7. Ambient Traffic
  for _, id in ipairs(engine.find("car")) do
    local x, _, z = engine.pos(id)
    local cx, cy = to_screen(x, z)
    if in_view(cx, cy, 4) then
      engine.rect(cx - 2, cy - 2, 4, 4, 0.35, 0.65, 0.95, 0.85)
    end
  end

  -- 8. Mission Objectives
  for _, m in ipairs(G.markers or {}) do
    if engine.exists(m.id) then
      local x, _, z = engine.pos(m.id)
      local mx, my = to_screen(x, z)
      if in_view(mx, my, 12) then
        local col = m.color or {0.9, 0.8, 0.2}
        engine.rect(mx - 6, my - 6, 12, 12, col[1], col[2], col[3], 1)
        engine.rect(mx - 8, my - 8, 16, 2, col[1], col[2], col[3], 0.8)
      end
    end
  end

  -- 9. Landmarks and Labels
  if L then
    for _, lm in ipairs(L.labels or {}) do
      local lx, ly = to_screen(lm.x, lm.z)
      if in_view(lx, ly, 30) then
        engine.rect(lx - 5, ly - 5, 10, 10, 1, 1, 1, 1)
        engine.text(lm.letter or "*", lx - 3, ly - 5, 10, 0.1, 0.1, 0.1, 1)
        engine.text(lm.name, lx + 9, ly - 5, 11, 0.95, 0.95, 0.95, 1)
      end
    end
    for _, lm in ipairs(L.landmarks or {}) do
      local lx, ly = to_screen(lm.x, lm.z)
      if in_view(lx, ly, 30) then
        engine.rect(lx - 5, ly - 5, 10, 10, 1, 1, 1, 1)
        engine.text(lm.letter or "*", lx - 3, ly - 5, 10, 0.1, 0.1, 0.1, 1)
        engine.text(lm.name, lx + 9, ly - 5, 11, 0.95, 0.95, 0.95, 1)
      end
    end
  end

  -- 10. Player Icon & Heading
  if px then
    local psx, psy = to_screen(px, pz)
    if in_view(psx, psy, 12) then
      engine.rect(psx - 6, psy - 6, 12, 12, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
      engine.rect(psx - 4, psy - 4, 8, 8, 0.1, 0.1, 0.1, 1)
      local yaw = U.player_yaw()
      if yaw then
        local fx, fz = U.forward(yaw)
        engine.rect(psx + fx * 12 - 2, psy + fz * 12 - 2, 4, 4, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
      end
      engine.text("YOU", psx + 10, psy - 5, 11, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    end
  end

  -- Viewport Outer Border
  engine.rect(vx, vy, vw, 2, 0.35, 0.40, 0.48, 1)
  engine.rect(vx, vy + vh - 2, vw, 2, 0.35, 0.40, 0.48, 1)
  engine.rect(vx, vy, 2, vh, 0.35, 0.40, 0.48, 1)
  engine.rect(vx + vw - 2, vy, 2, vh, 0.35, 0.40, 0.48, 1)

  -- 11. Bottom Controls Footer
  engine.rect(0, sh - 48, sw, 48, 0.08, 0.09, 0.12, 1)
  engine.rect(0, sh - 48, sw, 1, 0.20, 0.25, 0.30, 1)
  engine.text("WASD / ARROWS: PAN    +/-: ZOOM    SPACE: RECENTER    ESC: RETURN", 24, sh - 30, 11, 0.75, 0.75, 0.75, 1)
  local zoom_pct = string.format("ZOOM: %d%%", math.floor(V.zoom / 0.35 * 100))
  engine.text(zoom_pct, sw - 24 - engine.text_width(zoom_pct, 11), sh - 30, 11, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
end

return V
