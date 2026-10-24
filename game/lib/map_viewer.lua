-- Fullscreen interactive vector map viewer for pause menu and navigation.
local U = require "lib.util"
local G = require "lib.state"
local city = require "lib.city"
local gps = require "lib.gps"

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
  elseif k == "space" or k == "y" then V.recenter()
  elseif k == "enter" then V.toggle_waypoint(V.pan_x, V.pan_z) -- at the crosshair
  elseif k == "backspace" then gps.clear_waypoint()
  end
end

-- The world point under screen point (sx, sy), as drawn last.
local view = {x = 20, y = 64, w = 920, h = 424}
function V.to_world(sx, sy)
  return V.pan_x + (sx - view.x - view.w / 2) / V.zoom, V.pan_z + (sy - view.y - view.h / 2) / V.zoom
end

-- A waypoint at (x, z) for the GPS; on (or right by) the one there is, off.
function V.toggle_waypoint(x, z)
  local w = gps.waypoint
  if w and U.dist2d(w.x, w.z, x, z) * V.zoom < 14 then
    gps.clear_waypoint()
  else
    gps.set_waypoint(x, z)
  end
end

function V.mouse_down(x, y)
  V.dragging = true
  V.drag_start_x = x
  V.drag_start_y = y
  V.drag_pan_x = V.pan_x
  V.drag_pan_z = V.pan_z
end

-- Touch: a finger dragged d pixels pans the map with it, and a tap (the
-- touch never moved far) sets or clears a waypoint there.
function V.pan_by(dx, dy)
  V.pan_x = V.pan_x - dx / math.max(0.01, V.zoom)
  V.pan_z = V.pan_z - dy / math.max(0.01, V.zoom)
end
function V.tap(x, y) V.toggle_waypoint(V.to_world(x, y)) end

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
      -- A click, not a drag: a waypoint there.
      if math.abs(cx - V.drag_start_x) + math.abs(cy - V.drag_start_y) < 5 then
        V.pan_x, V.pan_z = V.drag_pan_x, V.drag_pan_z
        V.toggle_waypoint(V.to_world(cx, cy))
      end
    end
  end
end

function V.draw(sw, sh)
  sw, sh = sw or 960, sh or 540
  V.frame()
  local cur_map = city.map()
  local L = G.city

  -- 1. Fullscreen dark backdrop
  engine.rect(0, 0, sw, sh, COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 0.98)

  -- 2. Top Header
  engine.rect(0, 0, sw, 52, 0.08, 0.09, 0.12, 1)
  engine.rect(0, 52, sw, 2, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
  local title = string.upper(cur_map.name or "CITY") .. " - MAP" -- (the font has no dashes but -)
  engine.text(title, 24, 16, 20, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

  -- Top right: current street / area or back button
  local px, py, pz = U.player_pos()
  if px then
    local street, area
    if L and L.network then
      street, area = require("lib.roadnet").where(px, pz)
    end
    local loc_str = street and (street .. (area and (" (" .. area .. ")") or "")) or area or ""
    local tw = engine.text_width(string.upper(loc_str), 12)
    engine.text(string.upper(loc_str), sw - 140 - tw, 20, 12, 0.8, 0.82, 0.85, 1)
  end

  engine.rect(sw - 110, 12, 88, 28, 0.15, 0.18, 0.22, 1)
  engine.text("ESC: BACK", sw - 98, 19, 12, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

  -- 3. Viewport setup
  local vx, vy = 20, 64
  local vw, vh = sw - 40, sh - 116
  view.x, view.y, view.w, view.h = vx, vy, vw, vh
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

  -- The GPS route and the waypoint.
  gps.update()
  local dots, col = gps.dots()
  local ds = math.max(3, math.min(6, 10 * V.zoom))
  for i = 1, dots and #dots or 0, 2 do
    local dx, dy = to_screen(dots[i], dots[i + 1])
    if dx >= vx and dx + ds <= vx + vw and dy >= vy and dy + ds <= vy + vh then
      engine.rect(dx - ds / 2, dy - ds / 2, ds, ds, col[1], col[2], col[3], 0.95)
    end
  end
  local w = gps.waypoint
  if w then
    local wx, wy = to_screen(w.x, w.z)
    if in_view(wx, wy, 0) then
      engine.rect(wx - 8, wy - 8, 16, 16, 0, 0, 0, 0.9)
      engine.rect(wx - 6, wy - 6, 12, 12, w.color[1], w.color[2], w.color[3], 1)
      local left = gps.left()
      local label = left and (left < 1000 and string.format("%d M", math.floor(left / 10 + 0.5) * 10)
        or string.format("%.1f KM", left / 1000)) or "WAYPOINT"
      engine.text(label, wx + 11, wy - 5, 11, w.color[1], w.color[2], w.color[3], 1)
    end
  end
  -- The crosshair (Enter puts a waypoint under it).
  local chx, chy = vx + vw / 2, vy + vh / 2
  engine.rect(chx - 9, chy - 1, 6, 2, 1, 1, 1, 0.7)
  engine.rect(chx + 3, chy - 1, 6, 2, 1, 1, 1, 0.7)
  engine.rect(chx - 1, chy - 9, 2, 6, 1, 1, 1, 0.7)
  engine.rect(chx - 1, chy + 3, 2, 6, 1, 1, 1, 0.7)

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
  local help = require("lib.touch").active and "DRAG: PAN    TAP: WAYPOINT (TAP IT AGAIN TO CLEAR)"
    or require("lib.input").connected() and "D-PAD: PAN    A: WAYPOINT    X: CLEAR IT    Y: RECENTER    B: RETURN"
    or "DRAG/WASD: PAN   +/-: ZOOM   CLICK/ENTER: WAYPOINT   BACKSPACE: CLEAR   SPACE: RECENTER   ESC: BACK"
  engine.text(help, 24, sh - 30, 11, 0.75, 0.75, 0.75, 1)
  local zoom_pct = string.format("ZOOM: %d%%", math.floor(V.zoom / 0.35 * 100))
  engine.text(zoom_pct, sw - 24 - engine.text_width(zoom_pct, 11), sh - 30, 11, COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
end

return V
