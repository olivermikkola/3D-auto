-- Gamepad controls, with a fake pad: the engine reports sticks and triggers
-- through engine.pad() and buttons as "pad_*" keys, so a test can stand in
-- for both. PAD_TEST=1 auto game --headless 3000
local G = require "lib.state"
local U = require "lib.util"
local vehicle = require "lib.vehicle"
local menu = require "lib.menu"
local input = require "lib.input"
local city = require "lib.city"

local function check(ok, what)
  if not ok then engine.quit(); error("PAD TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

check(engine.pad() == nil and not input.connected(), "headless runs have no gamepad")

local pad = {name = "Test Pad", lx = 0, ly = 0, rx = 0, ry = 0, lt = 0, rt = 0}
local held = {}
engine.pad = function() return pad end
engine.key = function(k) return held[k] == true end
-- What the engine does for a button: hold it, then send the key event.
local function button(name, down)
  held[name] = down or nil
  engine.emit(engine.paused() and "menu_key" or "key", name, down)
end
local function tap(name) button(name, true) button(name, false) end
local function hspeed(id) local vx, _, vz = engine.vel(id) return math.sqrt(vx * vx + vz * vz) end

local seen = {}
engine.on("key", function(k, down) if down then seen[k] = (seen[k] or 0) + 1 end end)

-- Steps fire at frame counts; frames keep coming while the menu pauses ticks.
local steps, yaw0, car = {}, nil, nil
local function at(n, fn) steps[n] = fn end

at(30, function()
  check(input.connected(), "a pad is connected")
  pad.ly = 1
end)
at(90, function()
  check(math.abs(hspeed(G.player) - 5) < 0.5, string.format("stick fully forward walks (%.1f m/s)", hspeed(G.player)))
  pad.ly = 0.5
end)
at(120, function()
  local v = hspeed(G.player)
  check(v > 1 and v < 3, string.format("half a push walks slower (%.1f m/s)", v))
  pad.ly = 1
  held.pad_b = true
end)
at(150, function()
  check(math.abs(hspeed(G.player) - 10) < 0.8, string.format("B runs (%.1f m/s)", hspeed(G.player)))
  held.pad_b, pad.ly = nil, 0
  button("pad_a", true)
end)
at(156, function()
  local _, vy = engine.vel(G.player)
  check(vy > 2 and (seen.space or 0) == 1, "A jumps (and plays the jump sound)")
  button("pad_a", false)
  yaw0 = G.cam_yaw
  pad.rx = 1
end)
at(186, function()
  check(G.cam_yaw < yaw0 - 0.5, string.format("right stick turns the camera (%.2f rad)", yaw0 - G.cam_yaw))
  pad.rx = 0
  local ammo = G.ammo.pistol
  G.weapon = "pistol"
  pad.rt = 1
  button("pad_rt", true)
  check(G.ammo.pistol == ammo - 1, "RT fires on foot")
  pad.rt = 0
  button("pad_rt", false)
  tap("pad_rb")
  check(G.weapon == "fists", "RB: next weapon you have (no SMG ammo, so fists)")
  tap("pad_lb")
  check(G.weapon == "pistol", "LB: back the other way")
  -- Walk up to a parked car and get in with Y.
  local lx, lz = city.block_center(G.city.lot[1], G.city.lot[2])
  engine.set_pos(G.player, lx - 8 - 2.5, 1.2, lz)
end)
at(200, function()
  tap("pad_y")
  check(G.vehicle ~= nil, "Y gets in the nearest car")
  car = G.vehicle
  engine.orient(car, 0) -- face south, into the open half of the lot
  pad.rt = 1
end)
at(260, function()
  check(vehicle.speed(car) > 8, string.format("RT accelerates (%.1f m/s)", vehicle.speed(car)))
  pad.rt = 0
  yaw0 = engine.yaw(car)
  pad.lx = 1
end)
at(275, function()
  local stick = U.angle_diff(yaw0, engine.yaw(car))
  pad.lx = 0
  check(math.abs(stick) > 0.05, string.format("left stick steers (%.2f rad)", stick))
  -- The same as holding D?
  yaw0 = engine.yaw(car)
  held.d = true
  steps.keyboard = stick
end)
at(290, function()
  held.d = nil
  local keys = U.angle_diff(yaw0, engine.yaw(car))
  check(keys * steps.keyboard > 0, "stick right turns the same way as D")
  pad.lt = 1
end)
at(350, function()
  check(vehicle.speed(car) < 0, string.format("LT brakes, then reverses (%.1f m/s)", vehicle.speed(car)))
  pad.lt = 0
  local horns = seen.h or 0
  tap("pad_b")
  check((seen.h or 0) == horns + 1, "B honks in a car")
  local fired = G.ammo.pistol
  button("pad_rt", true)
  button("pad_rt", false)
  check(G.ammo.pistol == fired, "RT in a car doesn't fire")
  tap("pad_back")
  check((seen.tab or 0) == 1, "Back opens the progress screen")
  tap("pad_back")
  tap("pad_start")
  check(menu.open and engine.paused(), "Start pauses")
end)
at(360, function()
  tap("pad_down")
  check(menu.sel == 2, "D-pad moves through the menu")
  tap("pad_a")
  check(menu.page == "settings", "A picks")
  pad.ly = -1
end)
at(362, function()
  pad.ly = 0
  check(menu.sel == 2, "the left stick moves the selection too")
end)
at(364, function()
  pad.ly = -1
end)
at(366, function()
  pad.ly = 0
  check(menu.sel == 3, "once per push")
  tap("pad_b")
  check(menu.page == "main", "B goes back")
  tap("pad_start")
  check(not menu.open and not engine.paused(), "Start resumes")
  tap("pad_y")
  check(G.player and not G.vehicle, "Y gets out")
  engine.emit("pad_disconnected", "Test Pad")
  check(menu.open, "pulling the controller out pauses the game")
  print("PAD TEST PASSED")
  engine.quit()
end)

local n = 0
engine.on("frame", function()
  n = n + 1
  if steps[n] then steps[n]() end
end)
