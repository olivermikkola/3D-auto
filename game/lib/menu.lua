-- The pause menu. Esc (or minimizing the window) pauses the game: no ticks,
-- so physics, timers and game sounds stop. While paused, input arrives as
-- "menu_key" events, which only this menu listens to.
--
-- Keyboard: up/down (or W/S) to choose, left/right (or A/D) to change a
-- setting, Enter or Space to pick, Esc to go back. The mouse works too.
--
-- Other systems add pages (shops do) with menu.add_page and open them with
-- menu.show(name). An item is {label, act = fn} and may have value = fn
-- returning the text (and an optional {r,g,b}) shown on its right.
local settings = require "lib.settings"

local M = {open = false, page = "main", sel = 1}

local pages = {
  main = {
    title = "PAUSED",
    items = {
      {label = "RESUME", act = function() M.close() end},
      {label = "SETTINGS", act = function() M.go("settings") end},
      {label = "QUIT GAME", act = function() engine.quit() end},
    },
  },
  settings = {title = "SETTINGS", back = "main", items = {}},
}
for _, s in ipairs(settings.list) do
  table.insert(pages.settings.items, {label = s.label, setting = s.key})
end
table.insert(pages.settings.items, {label = "RESET TO DEFAULTS", act = function() settings.reset() end})
table.insert(pages.settings.items, {label = "BACK", act = function() M.go("main") end})

local function click() engine.play("ui_click", {ui = true}) end

engine.on("init", function()
  engine.synth("ui_click", {wave = "square", freq = 900, freq_end = 700, dur = 0.04, release = 0.03, volume = 0.18, lowpass = 0.5})
end)

function M.items() return pages[M.page].items end

function M.add_page(name, page) pages[name] = page end

function M.go(page)
  M.page, M.sel = page, 1
end

function M.show(page)
  if M.open then return end
  M.open, M.page, M.sel = true, type(page) == "string" and page or "main", 1
  engine.pause(true)
  engine.grab_mouse(false)
  click()
end

function M.close()
  if not M.open then return end
  M.open = false
  engine.pause(false)
  engine.grab_mouse(true)
  click()
end

function M.back()
  local back = pages[M.page].back
  if back then M.go(back) else M.close() end
end

function M.move(d)
  local n = #M.items()
  M.sel = (M.sel - 1 + d) % n + 1
end

-- Activate the selected item, or step its setting (dir = -1 / 1).
function M.press(dir)
  local item = M.items()[M.sel]
  if item.setting then
    settings.nudge(item.setting, dir or 1)
  elseif item.act and not dir then
    item.act()
  else
    return
  end
  click()
end

-- ---- layout and drawing -------------------------------------------------------
local W, ROW, TOP = 420, 34, 74

-- Screen rectangles of the panel and each row, for drawing and clicking.
function M.layout()
  local w, h = engine.screen()
  local items = M.items()
  local ph = TOP + #items * ROW + 46
  local x, y = (w - W) / 2, (h - ph) / 2
  local rows = {}
  for i = 1, #items do rows[i] = {x = x + 14, y = y + TOP + (i - 1) * ROW, w = W - 28, h = ROW - 4} end
  return {x = x, y = y, w = W, h = ph, rows = rows}
end

function M.row_at(px, py)
  for i, r in ipairs(M.layout().rows) do
    if px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h then return i, r end
  end
end

-- A click picks a row. On a setting, clicking the "<" side of its value
-- lowers it and anywhere else raises it (or flips a switch).
function M.click(px, py)
  local i, r = M.row_at(px, py)
  if not i then return end
  M.sel = i
  local item = M.items()[i]
  if item.setting then
    local right = r.x + r.w
    M.press(px >= right - 130 and px < right - 65 and -1 or 1)
  else
    M.press()
  end
end

local last_cursor
engine.on("frame", function()
  if not M.open then return end
  -- Hovering selects, but only when the mouse actually moves.
  local cx, cy = engine.cursor()
  if last_cursor and (cx ~= last_cursor[1] or cy ~= last_cursor[2]) then
    M.sel = M.row_at(cx, cy) or M.sel
  end
  last_cursor = {cx, cy}

  local sw, sh = engine.screen()
  engine.rect(0, 0, sw, sh, 0, 0, 0, 0.45)
  local L = M.layout()
  engine.rect(L.x, L.y, L.w, L.h, 0.05, 0.06, 0.08, 0.9)
  engine.rect(L.x, L.y, L.w, 4, 1, 0.85, 0.2, 1)
  local title = pages[M.page].title
  if type(title) == "function" then title = title() end
  engine.text(title, L.x + 24, L.y + 26, 24, 1, 0.85, 0.2, 1)
  for i, item in ipairs(M.items()) do
    local r, on = L.rows[i], i == M.sel
    if on then engine.rect(r.x, r.y, r.w, r.h, 1, 0.85, 0.2, 0.18) end
    local c = on and 1 or 0.75
    engine.text(item.label, r.x + 12, r.y + 10, 14, c, c, c, 1)
    if item.setting then
      local v = settings.text(item.setting)
      local right = r.x + r.w - 12
      engine.text(v, right - 65 - engine.text_width(v, 14) / 2, r.y + 10, 14, 1, 1, 1, 1)
      if on then
        engine.text("<", right - 118, r.y + 10, 14, 1, 0.85, 0.2, 1)
        engine.text(">", right - engine.text_width(">", 14), r.y + 10, 14, 1, 0.85, 0.2, 1)
      end
    elseif item.value then
      local v, col = item.value()
      col = col or {1, 1, 1}
      engine.text(v, r.x + r.w - 12 - engine.text_width(v, 14), r.y + 10, 14, col[1], col[2], col[3], 1)
    end
  end
  engine.text("ARROWS/WASD CHOOSE  ENTER PICK  ESC BACK", L.x + 24, L.y + L.h - 26, 10, 0.6, 0.6, 0.6, 1)
end)

-- ---- input ----------------------------------------------------------------------
local nav = {up = -1, w = -1, down = 1, s = 1}
local adjust = {left = -1, a = -1, right = 1, d = 1}

engine.on("key", function(k, down)
  if k == "escape" and down then M.show() end
end)

engine.on("minimized", M.show)

engine.on("menu_key", function(k, down)
  if not down or not M.open then return end
  if k == "escape" then
    M.back()
    if M.open then click() end
  elseif nav[k] then M.move(nav[k]); click()
  elseif adjust[k] then M.press(adjust[k])
  elseif k == "enter" or k == "space" then M.press()
  elseif k == "mouse1" then M.click(engine.cursor())
  end
end)

return M
