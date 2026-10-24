-- Keyboard and gamepad, merged. Movement, driving and the camera read the
-- analog values here; pad buttons are mapped onto the keyboard actions the
-- rest of the game already listens for, so nothing else needs to know.
--
--   left stick  move / steer         right stick  camera
--   RT          accelerate / fire    LT           brake, reverse
--   A           jump / handbrake     B            run / horn
--   Y           enter or leave a car X            use (shops, garage)
--   LB / RB     weapon               Back         progress   Start  pause
--   D-pad and A/B in menus
local G = require "lib.state"
local touch = require "lib.touch"

local M = {}
M.DEAD = 0.2 -- stick dead zone

-- Touch buttons and sticks count as the pad's (lib/touch.lua).
local function key(k) return engine.key(k) or touch.held(k) end
local function pad() return touch.merge(engine.pad()) end

-- Stick value with the dead zone removed and the rest rescaled to 0..1.
local function axis(v)
  local a = math.abs(v or 0)
  if a < M.DEAD then return 0 end
  return (v > 0 and 1 or -1) * math.min(1, (a - M.DEAD) / (1 - M.DEAD))
end
M.axis = axis

local function clamp(v) return math.max(-1, math.min(1, v)) end

-- On foot: forward and right, each -1..1.
function M.move()
  local f = (key("w") and 1 or 0) - (key("s") and 1 or 0)
  local r = (key("d") and 1 or 0) - (key("a") and 1 or 0)
  local p = pad()
  if p then f, r = f + axis(p.ly), r + axis(p.lx) end
  return clamp(f), clamp(r)
end

function M.running() return key("shift") or key("pad_b") end
function M.jumping() return key("space") or key("pad_a") end

-- Driving: throttle -1..1, steer -1..1 (positive = left), handbrake.
function M.drive()
  local throttle = (key("w") and 1 or 0) - (key("s") and 1 or 0)
  local steer = (key("a") and 1 or 0) - (key("d") and 1 or 0)
  local p = pad()
  if p then
    throttle = throttle + (p.rt or 0) - (p.lt or 0)
    steer = steer - axis(p.lx)
  end
  return clamp(throttle), clamp(steer), key("space") or key("pad_a")
end

-- Camera turn rates from the right stick (and arrow keys), -1..1.
function M.look()
  local x = (key("left") and 1 or 0) - (key("right") and 1 or 0)
  local y = (key("up") and 1 or 0) - (key("down") and 1 or 0)
  local p = pad()
  if p then x, y = x - axis(p.rx), y - axis(p.ry) end
  return clamp(x), clamp(y)
end

function M.connected() return engine.pad() ~= nil end

-- ---- buttons -> the keys the game already understands -------------------------
-- RT fires only on foot (in a car it's the accelerator); B is the horn in a car.
local function game_key(k, down)
  if k == "pad_a" then return "space" -- the jump sound; jumping itself is polled
  elseif k == "pad_y" then return "e"
  elseif k == "pad_x" then return "r"
  elseif k == "pad_rb" then return "q"
  elseif k == "pad_lb" then return "q_back"
  elseif k == "pad_back" then return "tab"
  elseif k == "pad_start" then return "escape"
  elseif k == "pad_b" and (G.vehicle or not down) then return "h"
  elseif k == "pad_rt" and (G.player or not down) then return "f"
  end
end

local MENU = {pad_a = "enter", pad_b = "escape", pad_start = "escape", pad_up = "up", pad_down = "down",
              pad_left = "left", pad_right = "right", pad_x = "backspace", pad_y = "y",
              pad_rb = "=", pad_lb = "-"} -- the shoulders zoom the map

engine.on("key", function(k, down)
  local mapped = k:sub(1, 4) == "pad_" and game_key(k, down)
  if mapped then engine.emit("key", mapped, down) end
end)

engine.on("menu_key", function(k, down)
  local mapped = MENU[k]
  if mapped then engine.emit("menu_key", mapped, down) end
end)

-- Moving the left stick in a menu also moves the selection, once per push.
local stick_held = false
engine.on("frame", function()
  if not engine.paused() then stick_held = false return end
  local p = pad()
  local y = p and axis(p.ly) or 0
  if math.abs(y) < 0.5 then stick_held = false
  elseif not stick_held then
    stick_held = true
    engine.emit("menu_key", y > 0 and "up" or "down", true)
  end
end)

engine.on("pad_connected", function(name)
  require("lib.util").message("CONTROLLER CONNECTED", 3)
  print("controller: " .. name)
end)
engine.on("pad_disconnected", function()
  require("lib.util").message("CONTROLLER DISCONNECTED", 3)
  if G.vehicle or G.player then require("lib.menu").show() end
end)

return M
