-- Touch controls drive the game like a pad: a stick under the left thumb,
-- buttons on the right that change with what you're doing, a drag to look,
-- and pause with the menu's own buttons. TOUCH_TEST=1 auto game --headless 600
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local touch = require "lib.touch"
local vehicle = require "lib.vehicle"

local function check(ok, what)
  if not ok then engine.quit(); error("TOUCH TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local seen = {}
engine.on("key", function(k, down) if down then seen[k] = true end end)
local function t(phase, id, x, y) engine.emit("touch", phase, id, x, y) end
local function tap(label)
  local x, y = touch.button_center(label)
  check(x ~= nil, "there is a " .. label .. " button")
  t("start", 9, x, y)
  t("end", 9, x, y)
end

local steps, frame, car = {}, 0, nil
local function at(n, fn) steps[n] = fn end

at(5, function()
  check(not touch.active and input.move() == 0, "no touch controls before the screen is touched")
  t("start", 1, 200, 500)
  t("move", 1, 200, 400) -- thumb pushed up
  local f, r = input.move()
  check(touch.active and f > 0.6 and math.abs(r) < 0.05, string.format("left thumb up walks forward (%.2f, %.2f)", f, r))
  t("move", 1, 300, 500)
  f, r = input.move()
  check(r > 0.6 and math.abs(f) < 0.05, string.format("and right is right (%.2f, %.2f)", f, r))
  t("end", 1, 300, 500)
  check(input.move() == 0, "letting go stops")
end)

at(10, function()
  local x, y = touch.button_center("JUMP")
  t("start", 2, x, y)
  check(input.jumping() and seen.pad_a and seen.space, "holding JUMP jumps (pad_a, the jump key)")
  t("end", 2, x, y)
  check(not input.jumping(), "and letting go stops")
  t("start", 3, 900, 300)
  t("move", 3, 1000, 250)
  local lx, ly = input.look()
  check(lx ~= 0 and ly ~= 0, string.format("dragging on the right turns the camera (%.2f, %.2f)", lx, ly))
  t("cancel", 3, 1000, 250)
  check(select(1, input.look()) == 0, "a cancelled touch lets go")
end)

at(15, function()
  local px, _, pz = engine.pos(G.player)
  car = vehicle.spawn(px + 3, pz, 0, 2)
end)
at(30, function()
  tap("CAR")
end)
at(40, function()
  check(G.vehicle == car, "CAR gets into the car next to you")
  check(touch.button_center("GAS") and not touch.button_center("JUMP"), "in a car the buttons are the car's")
  local x, y = touch.button_center("GAS")
  t("start", 4, x, y)
  local sx, sy = touch.button_center("DRIFT")
  t("start", 5, sx, sy)
  local throttle, _, handbrake = input.drive()
  check(throttle == 1 and handbrake, "GAS and DRIFT at once: full throttle, handbrake on")
  t("end", 4, x, y)
  t("end", 5, sx, sy)
  throttle, _, handbrake = input.drive()
  check(throttle == 0 and not handbrake, "both let go")
  tap("EXIT")
end)
at(50, function()
  check(G.player and not G.vehicle, "EXIT gets out")
  tap("II")
end)
-- A tap in the middle of item `label`'s row.
local function tap_row(label)
  local menu = require "lib.menu"
  for i, r in pairs(menu.layout().rows) do
    if menu.items()[i].label == label then
      local x, y = r.x + r.w / 2, r.y + r.h / 2
      t("start", 8, x, y); t("end", 8, x, y)
      return
    end
  end
  check(false, "the menu shows " .. label)
end

at(55, function()
  local menu = require "lib.menu"
  check(engine.paused() and touch.button_center("BACK") and not touch.button_center("UP"), "II pauses, and the menu has BACK")
  local labels = {}
  for _, item in ipairs(menu.items()) do labels[item.label] = true end
  check(not labels["QUIT GAME"], "no QUIT GAME on a phone")
  tap_row("SETTINGS")
  check(menu.page == "settings", "tapping SETTINGS opens it")
  tap("BACK")
  check(menu.page == "main", "BACK goes back")
  tap_row("MAP")
  check(menu.page == "map" and touch.button_center("+"), "tapping MAP opens it, with + and - to zoom")
  local mv = require "lib.map_viewer"
  local zoom, px = mv.zoom, mv.pan_x
  tap("+")
  check(mv.zoom > zoom, "+ zooms in")
  t("start", 8, 400, 300); t("move", 8, 460, 300); t("move", 8, 520, 300); t("end", 8, 520, 300)
  check(mv.pan_x < px, "a drag pans the map")
  tap("BACK")
  check(menu.page == "main", "BACK leaves the map")
  tap("BACK")
end)
at(60, function()
  check(not engine.paused(), "BACK closes the menu")
  print("TOUCH TEST PASSED")
  engine.quit()
end)

engine.on("frame", function()
  frame = frame + 1
  if steps[frame] then steps[frame]() end
end)
