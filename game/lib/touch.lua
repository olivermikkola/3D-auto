-- Touch controls, for phones and tablets: a virtual gamepad. Nothing shows
-- until the screen is first touched. Then
--
--   left thumb       a stick wherever it lands: walk, or steer and drive
--   right side       buttons for what you're doing; drag elsewhere to look
--   top middle       pause; in the menus a tap picks a row, a drag scrolls a
--                    long page, and on the map a drag pans and a tap sets a
--                    waypoint (BACK, and + and - to zoom it)
--
-- The buttons are the pad's (pad_a, pad_rt...), pressed the way the engine
-- presses a real pad's, and input.lua adds the sticks and triggers to a
-- real pad's, so the rest of the game needs to know nothing about touch.
local G = require "lib.state"

local M = {active = false}
local touches = {} -- id -> {role = "move"|"look"|"button", x0, y0, x, y, button}
local held = {}    -- pad button name -> how many touches hold it
local axes = {lx = 0, ly = 0, rx = 0, ry = 0, lt = 0, rt = 0}

-- Buttons by what you're doing: label, pad button, column and row from the
-- bottom right corner, and the trigger they also pull all the way.
local SETS = {
  foot = {
    {"FIRE", "pad_rt", 0, 0, "rt"}, {"JUMP", "pad_a", 1, 0}, {"RUN", "pad_b", 2, 0},
    {"CAR", "pad_y", 0, 1}, {"USE", "pad_x", 1, 1}, {"GUN", "pad_rb", 2, 1},
  },
  car = {
    {"GAS", "pad_rt", 0, 0, "rt"}, {"BRAKE", "pad_lt", 1, 0, "lt"}, {"DRIFT", "pad_a", 2, 0},
    {"EXIT", "pad_y", 0, 1}, {"HORN", "pad_b", 1, 1},
  },
  menu = {
    {"BACK", "pad_b", 0, 0},
  },
  map = {
    {"BACK", "pad_b", 0, 0}, {"+", "pad_rb", 0, 1}, {"-", "pad_lb", 0, 2},
  },
}
local PAUSE = {"II", "pad_start"}

local function mode()
  if engine.paused() then
    local menu = package.loaded["lib.menu"]
    return menu and menu.open and menu.page == "map" and "map" or "menu"
  end
  return G.vehicle and "car" or "foot"
end

-- Sizes follow the screen: u is a tenth of its shorter side.
local function layout()
  local w, h = engine.screen()
  local u = math.min(w, h) / 10
  return w, h, u, 1.6 * u -- screen, unit, button size (about a thumb)
end

-- Where button b of the current set is: x, y, w, h.
local function rect(b)
  local w, h, u, s = layout()
  local gap = 0.25 * u
  return w - (b[3] + 1) * (s + gap) - u * 0.4, h - (b[4] + 1) * (s + gap) - u * 0.4, s, s
end
local function pause_rect()
  local w, _, u = layout()
  return w / 2 - 0.55 * u, 0.3 * u, 1.1 * u, 1.1 * u -- top middle, clear of the cash and the map
end

local function inside(x, y, rx, ry, rw, rh) return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh end

local function button_at(x, y)
  if inside(x, y, pause_rect()) then return PAUSE end
  for _, b in ipairs(SETS[mode()]) do
    if inside(x, y, rect(b)) then return b end
  end
end

-- The same as a real pad's button: held, then the key event.
local function press(name, down)
  local before = held[name] or 0
  local n = math.max(0, before + (down and 1 or -1))
  held[name] = n > 0 and n or nil
  if (down and before == 0) or (not down and before > 0 and n == 0) then
    engine.emit(engine.paused() and "menu_key" or "key", name, down)
  end
end

local function stick(t)
  local _, _, u = layout()
  local r = 1.2 * u
  local dx, dy = (t.x - t.x0) / r, (t.y - t.y0) / r
  local len = math.sqrt(dx * dx + dy * dy)
  if len > 1 then dx, dy = dx / len, dy / len end
  return dx, -dy -- up the screen is forward, like a stick pushed up
end

local function update_axes()
  axes.lx, axes.ly, axes.rx, axes.ry, axes.lt, axes.rt = 0, 0, 0, 0, 0, 0
  for _, t in pairs(touches) do
    if t.role == "move" then axes.lx, axes.ly = stick(t)
    elseif t.role == "look" then axes.rx, axes.ry = stick(t)
    elseif t.role == "button" and t.button[5] then axes[t.button[5]] = 1 end
  end
end

local function release(id)
  local t = touches[id]
  if not t then return end
  touches[id] = nil
  if t.role == "button" then press(t.button[2], false) end
  update_axes()
end

function M.release_all()
  for id in pairs(touches) do release(id) end
end

-- A finger moving in a menu: past a few pixels it's a drag, not a tap. On the
-- map it pans; on a page too long for the screen each row's height scrolls.
local function menu_drag(t, x, y)
  local menu = require "lib.menu"
  if math.abs(x - t.x0) + math.abs(y - t.y0) > 12 then t.dragged = true end
  if not t.dragged then return end
  if menu.page == "map" then
    require("lib.map_viewer").pan_by(x - t.x, y - t.y)
  else
    t.dy = t.dy + (y - t.y)
    local row = menu.row_height()
    while t.dy >= row do menu.scroll(-1); t.dy = t.dy - row end
    while t.dy <= -row do menu.scroll(1); t.dy = t.dy + row end
  end
end

engine.on("touch", function(phase, id, x, y)
  M.active = true
  if phase == "start" then
    release(id)
    local b = button_at(x, y)
    local w = engine.screen()
    local t = {x0 = x, y0 = y, x = x, y = y}
    if b then t.role, t.button = "button", b
    elseif engine.paused() then t.role, t.dy = "menu", 0 -- a tap or a drag, decided when it ends
    elseif x < w * 0.45 then t.role = "move"
    else t.role = "look" end
    touches[id] = t
    if b then press(b[2], true) end
  elseif phase == "move" then
    local t = touches[id]
    if t then
      if t.role == "menu" then menu_drag(t, x, y) end
      t.x, t.y = x, y
    end
  else -- end, cancel
    local t = touches[id]
    if t and t.role == "menu" and phase == "end" and not t.dragged then
      local menu = require "lib.menu"
      menu.tap(x, y, true)
    end
    release(id)
  end
  update_axes()
end)

-- The page losing focus can swallow the touchend: let go of everything.
engine.on("minimized", M.release_all)

-- A real pad's sticks and triggers plus the touch ones, or nil if neither.
function M.merge(pad)
  if not M.active then return pad end
  local out = {name = pad and pad.name or "Touch"}
  for k, v in pairs(axes) do
    out[k] = math.max(-1, math.min(1, (pad and pad[k] or 0) + v))
  end
  return out
end

-- The middle of the button labelled `label` in the current set (tests use it).
function M.button_center(label)
  local all = {PAUSE}
  for _, b in ipairs(SETS[mode()]) do all[#all + 1] = b end
  for _, b in ipairs(all) do
    if b[1] == label then
      local x, y, w, h
      if b == PAUSE then x, y, w, h = pause_rect() else x, y, w, h = rect(b) end
      return x + w / 2, y + h / 2
    end
  end
end

function M.held(name) return held[name] ~= nil end
function M.holding() return next(touches) ~= nil end

-- ---- drawing -----------------------------------------------------------------------
local function draw_button(b, x, y, w, h)
  local on = held[b[2]]
  if on then engine.rect(x, y, w, h, 1, 0.85, 0.3, 0.55) else engine.rect(x, y, w, h, 0.1, 0.1, 0.12, 0.55) end
  local size = math.max(11, math.floor(h * 0.24))
  engine.text(b[1], x + (w - engine.text_width(b[1], size)) / 2, y + (h - size) / 2, size, 1, 1, 1, on and 1 or 0.85)
end

-- The buttons and sticks. While a menu is open the menu draws them after
-- itself, so they stay on top (the map covers the whole screen).
function M.draw()
  if not M.active then return end
  for _, b in ipairs(SETS[mode()]) do draw_button(b, rect(b)) end
  draw_button(PAUSE, pause_rect())
  -- The sticks where the thumbs are.
  local _, _, u = layout()
  for _, t in pairs(touches) do
    if t.role == "move" or t.role == "look" then
      local r = 1.2 * u
      engine.rect(t.x0 - r, t.y0 - r, 2 * r, 2 * r, 1, 1, 1, 0.12)
      local dx, dy = stick(t)
      engine.rect(t.x0 + dx * r - 0.4 * u, t.y0 - dy * r - 0.4 * u, 0.8 * u, 0.8 * u, 1, 1, 1, 0.4)
    end
  end
end

engine.on("frame", function()
  local menu = package.loaded["lib.menu"]
  if not (menu and menu.open) then M.draw() end
end)

return M
