-- The pause menu and settings, across a restart. CI runs:
--   MENU_TEST=1 auto game --headless 900 --save-dir DIR   pause, change settings, quit from the menu
--   MENU_TEST=2 ...                                       settings came back; reset; minimize pauses;
--                                                         pick another city, and the game restarts there
-- Steps count frames, not ticks: frames keep coming while the game is paused.
local G = require "lib.state"
local U = require "lib.util"
local menu = require "lib.menu"
local settings = require "lib.settings"
local phase = tonumber(os.getenv("MENU_TEST"))

local function check(ok, what)
  if not ok then engine.quit(); error("MENU TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end
local function key(k) engine.emit(menu.open and "menu_key" or "key", k, true) end
local function select(label)
  for i, item in ipairs(menu.items()) do if item.label == label then menu.sel = i return end end
  error("no menu item " .. label)
end
local function center(label)
  for i, item in ipairs(menu.items()) do
    if item.label == label then
      local r = menu.layout().rows[i]
      return r.x + 20, r.y + r.h / 2
    end
  end
end

local steps, frozen = {}, nil

if phase == 1 then
  steps[30] = function()
    check(not engine.paused() and settings.get("volume") == 70, "starts unpaused with default settings")
    local hud = require "lib.hud"
    check(hud.help_shown() and not engine.load("help_seen"), "the very first start shows the controls")
    key("f1")
    check(not hud.help_shown() and settings.get("help_on") == false and engine.load("help_seen"), "F1 hides them, for good")
    local x, y, z = U.player_pos()
    frozen = {ticks = engine.ticks(), time = engine.time(), pos = {x, y, z}}
    key("escape")
    check(menu.open and engine.paused() and menu.page == "main", "Esc opens the pause menu and pauses")
    check(engine.stats().voices > 0, "the menu click is playing (a ui sound)")
  end
  steps[90] = function()
    local x, y, z = U.player_pos()
    check(engine.ticks() == frozen.ticks and engine.time() == frozen.time, "no ticks while paused (60 frames later)")
    check(x == frozen.pos[1] and y == frozen.pos[2] and z == frozen.pos[3], "the world holds still")
    -- Mouse: click SETTINGS.
    menu.click(center("SETTINGS"))
    check(menu.page == "settings", "clicking SETTINGS opens the settings page")
    -- Keyboard: volume up, sensitivity to its floor, flip invert, wider FOV, help on.
    key("right")
    check(settings.get("volume") == 80 and math.abs(engine.volume() - 0.8) < 1e-6, "right raises the volume and applies it")
    key("down")
    for _ = 1, 12 do key("left") end
    check(settings.get("sensitivity") == 1, "sensitivity stops at its minimum")
    key("s")
    key("enter")
    check(settings.get("invert_y") == true, "enter flips invert-Y")
    key("down")
    key("d")
    check(settings.get("fov") == 75, "D widens the field of view")
    select("HELP OVERLAY")
    local _, r = menu.row_at(center("HELP OVERLAY"))
    menu.click(r.x + r.w - 100, r.y + 5)
    check(settings.get("help_on") == true, "clicking a switch flips it")
    menu.click(r.x + r.w - 100, r.y + 5)
    menu.click(r.x + r.w - 100, r.y + 5)
    check(settings.get("help_on") == true, "and flips it back each click")
    local saved = engine.load("settings")
    check(saved and saved.volume == 80 and saved.fov == 75 and saved.invert_y == true, "settings save as they change")
    key("escape")
    check(menu.page == "main" and engine.paused(), "Esc goes back a page")
    key("escape")
    check(not menu.open and not engine.paused(), "Esc again resumes")
  end
  steps[150] = function()
    check(engine.ticks() > frozen.ticks + 30, "ticks run again after resuming")
    engine.emit("menu_key", "enter", true)
    check(not menu.open and not engine.paused(), "menu keys do nothing while the menu is closed")
    key("escape")
    select("QUIT GAME")
    G.cash = 123 -- progress must still save when quitting from the menu
    print("MENU TEST PHASE 1 PASSED")
    key("enter")
  end
elseif phase == 2 and engine.load("menu_test_city") then
  -- After picking another city in the menu (below): the game came back
  -- there, though it was started with MAP=<the old one>.
  steps[2] = function()
    local want = engine.load("menu_test_city")
    check(require("lib.city").map().id == want, "picking " .. want .. " under CITY takes you there, whatever MAP says")
    engine.save("menu_test_city", nil)
    print("MENU TEST PASSED")
    engine.quit()
  end
elseif phase == 2 then
  steps[2] = function()
    check(settings.get("volume") == 80 and math.abs(engine.volume() - 0.8) < 1e-6, "volume survives a restart and is applied")
    check(settings.get("sensitivity") == 1 and settings.get("invert_y") == true, "mouse settings survive a restart")
    check(settings.get("fov") == 75 and settings.get("help_on") == true, "FOV and help overlay survive a restart")
    settings.set("help_on", false)
    check(not require("lib.hud").help_shown(), "no controls on later starts unless asked for")
    engine.emit("key", "f1", true)
    check(require("lib.hud").help_shown() and settings.get("help_on") == true, "F1 brings them back, and keeps them")
    check(G.cash == 123, "quitting from the menu saved progress")
    engine.emit("minimized")
    check(menu.open and engine.paused(), "minimizing the window pauses")
    menu.click(center("SETTINGS"))
    select("SHADOWS")
    key("enter")
    select("VIEW DISTANCE")
    key("left")
    check(settings.get("shadows") == false and settings.get("view") == 90, "shadows switch off and the view shortens")
    select("RESET TO DEFAULTS")
    key("enter")
    check(settings.get("volume") == 70 and settings.get("invert_y") == false and settings.get("help_on") == false, "reset restores defaults")
    check(settings.get("shadows") == true and settings.get("view") == 100, "including shadows and view distance")
    check(engine.load("settings").volume == 70, "and saves them")
    select("BACK")
    key("space")
    select("RESUME")
    key("enter")
    check(not engine.paused(), "RESUME resumes")
    -- Another city, picked in the menu: the game starts afresh there.
    local city = require "lib.city"
    local want = city.map().id == "harbor" and "manhattan" or "harbor"
    engine.save("menu_test_city", want)
    key("escape")
    select("CITY")
    key("enter")
    check(menu.page == "city", "CITY lists the cities")
    select(want == "harbor" and "HARBOR" or "MANHATTAN")
    key("enter")
  end
end

local n = 0
engine.on("frame", function()
  n = n + 1
  if steps[n] then steps[n]() end
end)
