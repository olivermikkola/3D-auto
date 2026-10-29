-- The pause menu. Esc (or minimizing the window) pauses the game: no ticks,
-- so physics, timers and game sounds stop. While paused, input arrives as
-- "menu_key" events, which only this menu listens to.
--
-- Keyboard: up/down (or W/S) to choose, left/right (or A/D) to change a
-- setting, Enter or Space to pick, Esc to go back. The mouse works too, and
-- on a phone a tap picks a row and a drag scrolls a page that doesn't fit.
--
-- Other systems add pages (shops do) with menu.add_page and open them with
-- menu.show(name). An item is {label, act = fn} and may have value = fn
-- returning the text (and an optional {r,g,b}) shown on its right.
local settings = require "lib.settings"
local map_viewer = require "lib.map_viewer"

local M = {open = false, page = "main", sel = 1}

local pages = {
  main = {
    title = "PAUSED",
    items = {
      {label = "RESUME", act = function() M.close() end},
      {label = "SETTINGS", act = function() M.go("settings") end},
      {label = "MAP", act = function() M.go("map") end},
      {label = "CITY", act = function() M.go("city") end, value = function() return string.upper(require("lib.city").map().name) end},
      {label = "CREDITS", act = function() M.go("credits") end},
      {label = "QUIT GAME", act = function() engine.quit() end, desktop = true},
    },
  },
  -- Whose data the cities are made of, as their licences ask (game/maps/LICENSE).
  credits = {title = "CREDITS", back = "main", items = {
    {label = "MAP DATA (C) OPENSTREETMAP"},
    {label = "CONTRIBUTORS, ODBL 1.0"},
    {label = "TERRAIN: CONTAINS DATA FROM"},
    {label = "THE NATIONAL LAND SURVEY OF"},
    {label = "FINLAND (MAANMITTAUSLAITOS)"},
    {label = "2026, CC BY 4.0"},
    {label = "TURKU AERIAL PHOTO 2022 AND"},
    {label = "CITY MODEL (KAUPUNKITIETOMALLI)"},
    {label = "(C) TURUN KAUPUNKI, CC BY 4.0"},
    {label = "CITY MAPS (C) OLIVER MIKKOLA"},
    {label = "CC BY-NC 4.0"},
    {label = "GAME AND ENGINE: MIT LICENSE"},
    {label = "BACK", act = function() M.go("main") end},
  }},
  map = {title = "MAP", back = "main", items = {}},
  city = {title = "CITY", back = "main", items = {}},
  settings = {title = "SETTINGS", back = "main", items = {}},
}
for _, s in ipairs(settings.list) do
  table.insert(pages.settings.items, {label = s.label, setting = s.key})
end
table.insert(pages.settings.items, {label = "RESET TO DEFAULTS", act = function() settings.reset() end})
table.insert(pages.settings.items, {label = "BACK", act = function() M.go("main") end})
-- Picking another city starts the game afresh there; cash and missions carry over.
for _, m in ipairs(require("lib.city").MAPS) do
  table.insert(pages.city.items, {label = m[2], act = function()
    local city = require "lib.city"
    if (city.map().id or "") == m[1] then return M.close() end
    city.choose(m[1])
  end, value = function()
    if (require("lib.city").map().id or "") == m[1] then return "HERE", {1, 0.85, 0.2} end
    return ""
  end})
end
table.insert(pages.city.items, {label = "BACK", act = function() M.go("main") end})

local function click() engine.play("ui_click", {ui = true}) end

engine.on("init", function()
  engine.synth("ui_click", {wave = "square", freq = 900, freq_end = 700, dur = 0.04, release = 0.03, volume = 0.18, lowpass = 0.5})
end)

-- A phone has no quitting a game: items marked desktop are left out on touch.
function M.items()
  local items = pages[M.page].items
  if not require("lib.touch").active then return items end
  local out = {}
  for _, item in ipairs(items) do
    if not item.desktop then out[#out + 1] = item end
  end
  return out
end

function M.add_page(name, page) pages[name] = page end

function M.go(page)
  M.page, M.sel, M.top = page, 1, 1
  if page == "map" then map_viewer.init() end
end

function M.show(page)
  if M.open then return end
  M.open, M.page, M.sel, M.top = true, type(page) == "string" and page or "main", 1, 1
  if M.page == "map" then map_viewer.init() end
  engine.pause(true)
  engine.grab_mouse(false)
  click()
end

function M.close()
  if not M.open then return end
  M.open = false
  engine.pause(false)
  if not require("lib.touch").active then engine.grab_mouse(true) end -- no mouse to grab on a phone
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
local W, ROW, TOP, FOOT = 420, 34, 74, 46

-- How many rows fit on the screen. A longer page (settings on a phone held
-- sideways) shows rows M.top onwards and scrolls to keep the selected one in.
local function fit(h, n) return math.max(1, math.min(n, math.floor((h - 16 - TOP - FOOT) / ROW))) end

-- Screen rectangles of the panel and each shown row (by item number), for
-- drawing and clicking.
function M.layout()
  local w, h = engine.screen()
  local items = M.items()
  local n = fit(h, #items)
  M.sel = math.max(1, math.min(M.sel, #items))
  if M.sel < M.top then M.top = M.sel elseif M.sel > M.top + n - 1 then M.top = M.sel - n + 1 end
  M.top = math.max(1, math.min(M.top, #items - n + 1))
  local pw, ph = math.min(W, w - 16), TOP + n * ROW + FOOT
  local x, y = (w - pw) / 2, math.max(8, (h - ph) / 2)
  local rows = {}
  for i = M.top, M.top + n - 1 do
    rows[i] = {x = x + 14, y = y + TOP + (i - M.top) * ROW, w = pw - 28, h = ROW - 4}
  end
  return {x = x, y = y, w = pw, h = ph, rows = rows, first = M.top, last = M.top + n - 1, count = #items}
end

-- Scroll a page that doesn't fit by d rows; the selection stays on screen.
function M.scroll(d)
  local L = M.layout()
  local n = L.last - L.first + 1
  M.top = math.max(1, math.min(M.top + d, L.count - n + 1))
  M.sel = math.max(M.top, math.min(M.sel, M.top + n - 1))
end

function M.row_height() return ROW end

function M.row_at(px, py)
  for i, r in pairs(M.layout().rows) do
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
  if M.page == "map" then
    map_viewer.draw(sw, sh)
    require("lib.touch").draw()
    return
  end

  engine.rect(0, 0, sw, sh, 0, 0, 0, 0.45)
  local L = M.layout()
  engine.rect(L.x, L.y, L.w, L.h, 0.05, 0.06, 0.08, 0.9)
  engine.rect(L.x, L.y, L.w, 4, 1, 0.85, 0.2, 1)
  local title = pages[M.page].title
  if type(title) == "function" then title = title() end
  engine.text(title, L.x + 24, L.y + 26, 24, 1, 0.85, 0.2, 1)
  local items = M.items()
  for i = L.first, L.last do
    local item, r, on = items[i], L.rows[i], i == M.sel
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
  -- More rows above or below.
  -- More rows above or below: a small arrow (the font has no ^).
  local function arrow(cx, cy, up)
    for k = 0, 4 do
      local half = up and k or 4 - k
      engine.rect(cx - half - 1, cy + k * 2, 2 * half + 2, 2, 1, 0.85, 0.2, 1)
    end
  end
  if L.first > 1 then arrow(L.x + L.w - 26, L.y + TOP - 16, true) end
  if L.last < L.count then arrow(L.x + L.w - 26, L.y + L.h - FOOT + 6, false) end
  local hint = "ARROWS/WASD CHOOSE  ENTER PICK  ESC BACK"
  if require("lib.touch").active then hint = (L.last < L.count or L.first > 1) and "TAP TO PICK  DRAG TO SCROLL" or "TAP TO PICK" end
  engine.text(hint, L.x + 24, L.y + L.h - 26, 10, 0.6, 0.6, 0.6, 1)
  require("lib.touch").draw()
end)

-- ---- input ----------------------------------------------------------------------
local nav = {up = -1, w = -1, down = 1, s = 1}
local adjust = {left = -1, a = -1, right = 1, d = 1}

engine.on("key", function(k, down)
  if k == "escape" and down then M.show() end
  if k == "m" and down then
    if M.open and M.page == "map" then M.close()
    else M.show("map") end
  end
end)

engine.on("minimized", M.show)

-- Left alone, the game pauses itself: no key, button, stick or tap for
-- IDLE_PAUSE seconds of play opens this menu, and paused it hardly uses the
-- machine (one left running for a Moonlight session kept Turku going for
-- nine hours on three quarters of a core). Not in a headless run, where a
-- probe drives with nobody at the controls; only frames count, and they stop
-- while paused.
M.IDLE_PAUSE = tonumber(os.getenv("IDLE_PAUSE") or "") or 180
local idle = 0
local function touched() idle = 0 end
engine.on("key", touched)
engine.on("touch", touched)
engine.on("frame", function(dt)
  if M.open or engine.paused() or engine.headless() then idle = 0 return end
  local p = engine.pad()
  if p then
    for _, k in ipairs{"lx", "ly", "rx", "ry", "lt", "rt"} do
      if math.abs(p[k] or 0) > 0.2 then idle = 0 break end
    end
  end
  local mx, my = engine.mouse()
  if mx and (mx ~= 0 or my ~= 0) then idle = 0 end
  idle = idle + dt
  if idle >= M.IDLE_PAUSE then
    idle = 0
    M.show("main")
  end
end)

-- A click or a tap at x, y: a row, or on the map the BACK corner or the map.
-- The map gets the touch's own point (V.touch), not the mouse cursor.
function M.tap(px, py, touch)
  if not M.open then return end
  if M.page ~= "map" then return M.click(px, py) end
  local sw = engine.screen()
  if px >= sw - 120 and py <= 45 then
    M.back()
    click()
  elseif touch then
    map_viewer.tap(px, py)
  else
    map_viewer.mouse_down(px, py)
  end
end

engine.on("menu_key", function(k, down)
  if not down or not M.open then return end
  if M.page == "map" then
    if k == "escape" or k == "m" then
      M.back()
      click()
    elseif k == "mouse1" then
      M.tap(engine.cursor())
    else
      map_viewer.key(k)
    end
    return
  end

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
