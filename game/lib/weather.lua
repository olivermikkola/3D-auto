-- Weather: clear, cloudy or rain, changing every three hours of game time
-- (six real minutes). Clouds grey the sky and dim the sun (no shadows when
-- it's overcast); rain falls on the screen, hisses, pulls the fog in, and
-- wets the roads, which then grip less (lib/vehicle) and dry slowly.
-- The sequence is fixed by the seed, and the first three hours of a game
-- are always clear. WEATHER=clear|cloudy|rain|storm holds one (pictures,
-- tests); the WEATHER setting off keeps it clear.
local U = require "lib.util"

local W = {
  SLOT = 3,         -- hours of game time per spell of weather
  CHANGE = 40,      -- seconds a change takes
  DRY = 150,        -- seconds wet roads take to dry
  cloud = 0, rain = 0, wet = 0,
  kind = "clear", spells = 0,
}
-- What each kind is: cloud cover and rain, 0-1.
W.KINDS = {
  clear = {cloud = 0, rain = 0},
  cloudy = {cloud = 0.75, rain = 0},
  rain = {cloud = 0.9, rain = 0.55},
  storm = {cloud = 1, rain = 1},
}
-- How likely each is when the weather turns (out of 100).
local ODDS = {{"clear", 42}, {"cloudy", 30}, {"rain", 20}, {"storm", 8}}

local held = os.getenv("WEATHER")
assert(not held or W.KINDS[held], "WEATHER must be clear, cloudy, rain or storm")
local seed = math.tointeger(tonumber(os.getenv("SEED") or "")) or 1337
local slot, base_fog, voice = nil, nil, nil

-- The weather of spell n (0 is the start of a game: clear).
function W.pick(n)
  if n == 0 then return "clear" end
  local s = (seed * 7919 + n * 104729) & 0x7fffffff
  s = (s * 1103515245 + 12345) & 0x7fffffff
  local r = s % 100
  for _, o in ipairs(ODDS) do
    if r < o[2] then return o[1] end
    r = r - o[2]
  end
  return "clear"
end

local function enabled()
  local ok, settings = pcall(require, "lib.settings")
  return not ok or settings.get("weather") ~= false
end

function W.target()
  if held then return W.KINDS[held] end
  return enabled() and W.KINDS[W.kind] or W.KINDS.clear
end

-- Set now, without the slow change (a new game, pictures, tests).
function W.set(kind)
  W.kind = kind
  local t = W.target()
  W.cloud, W.rain, W.wet = t.cloud, t.rain, math.min(1, t.rain * 1.6)
  W.apply()
end

-- ---- what it looks like --------------------------------------------------------------

local function grey(c, amount, dim)
  local l = c[1] * 0.3 + c[2] * 0.55 + c[3] * 0.15
  local g = {l * 0.97, l, l * 1.04}
  return {U.lerp(c[1], g[1], amount) * dim, U.lerp(c[2], g[2], amount) * dim, U.lerp(c[3], g[3], amount) * dim}
end

-- A day/night palette under this much cloud (lib/daynight calls it).
function W.tint(p)
  local c = W.cloud
  if c <= 0.001 then return p end
  local out = {}
  for k, v in pairs(p) do out[k] = v end
  out.sky = grey(p.sky, 0.8 * c, 1 - 0.25 * c)
  out.top = grey(p.top, 0.85 * c, 1 - 0.2 * c)
  out.sun = grey(p.sun, 0.5 * c, 1 - 0.7 * c)
  out.ambient = grey(p.ambient, 0.4 * c, 1 - 0.05 * c)
  return out
end

-- The map's fog distances at the chosen view distance (main.lua).
function W.base_fog(a, b)
  base_fog = {a, b}
  W.apply()
end

function W.fog()
  if not base_fog then return nil end
  local k = 1 - 0.5 * W.rain - 0.1 * W.cloud
  return base_fog[1] * k, base_fog[2] * k
end

local shadows_on
function W.apply()
  local a, b = W.fog()
  if a then engine.fog(a, b) end
  local ok, settings = pcall(require, "lib.settings")
  local want = (not ok or settings.get("shadows") ~= false) and W.cloud < 0.6
  if want ~= shadows_on then
    shadows_on = want
    engine.lighting{shadows = want}
  end
end

-- ---- rain on the screen, and its sound ------------------------------------------------

-- Fixed random numbers per streak (an integer hash, so neighbours don't
-- line up), worked out once.
local streaks = {}
local function h(i, k)
  local x = (i * 0x9E3779B1 + k * 0x85EBCA77) & 0xffffffff
  x = x ~ (x >> 15); x = (x * 0x2C1B3C6D) & 0xffffffff
  x = x ~ (x >> 12); x = (x * 0x297A2D39) & 0xffffffff
  x = x ~ (x >> 15)
  return (x & 0xffffff) / 0xffffff
end
local function streak(i)
  local s = streaks[i]
  if not s then
    s = {1.1 + h(i, 1) * 0.8, h(i, 2), h(i, 3), 14 + h(i, 4) * 16}
    streaks[i] = s
  end
  return s
end

-- Under a roof, a bridge or in a tunnel, no rain falls past the camera:
-- 1 in the open, 0 under cover (it fades between the two).
W.open = 1
local function open_sky(dt)
  local x, y, z = engine.camera_pos()
  local want = engine.raycast(x, y + 0.3, z, 0, 1, 0, 40) and 0 or 1
  W.open = W.open + U.clamp(want - W.open, -dt * 3, dt * 3)
end

-- Drawn by the HUD before anything of its own, so the rain is under it.
function W.draw()
  if W.rain * W.open < 0.02 then return end
  local w, sh = engine.screen()
  local t, n = engine.time(), math.floor(260 * W.rain * W.open)
  local s = sh / 720
  local a = 0.18 + 0.2 * W.rain
  for i = 1, n do
    local st = streak(i)                          -- speed in screens a second, place, length
    local y = ((st[2] + t * st[1]) % 1.2 - 0.1) * sh
    local x = (st[3] * w + y * 0.12) % w         -- leaning a little in the wind
    engine.rect(x, y, math.max(1, 1.4 * s), st[4] * s, 0.78, 0.82, 0.9, a)
  end
end

local function sound()
  if not voice then
    engine.synth("rain", {wave = "noise", freq = 9000, dur = 2, attack = 0, release = 0, volume = 0.5, lowpass = 0.45})
    voice = engine.play("rain", {loop = true, volume = 0, ui = true})
  end
  engine.set_voice(voice, {volume = 0.5 * W.rain * (0.5 + 0.5 * W.open)})
end

-- ---- the weather changing -------------------------------------------------------------

engine.on("tick", function(dt)
  local D = package.loaded["lib.daynight"]
  if not D then return end
  local s = math.floor(D.hour / W.SLOT)
  if slot == nil then slot = s
  elseif s ~= slot then
    slot, W.spells = s, W.spells + 1
    local was = W.kind
    W.kind = W.pick(W.spells)
    if W.kind ~= was then engine.emit("weather", W.kind, was) end
  end
  local t, step = W.target(), dt / W.CHANGE
  local c0, r0 = W.cloud, W.rain
  W.cloud = W.cloud + U.clamp(t.cloud - W.cloud, -step, step)
  -- Rain waits for the clouds, and stops before they go.
  local rain_to = W.cloud >= t.cloud - 0.1 and t.rain or 0
  W.rain = W.rain + U.clamp(rain_to - W.rain, -step, step)
  -- Roads wet through in 20 s of rain (a drizzle wets them less), and dry slowly.
  local wet_to = math.min(1, W.rain * 1.6)
  if W.wet < wet_to then W.wet = math.min(wet_to, W.wet + dt / 20)
  else W.wet = math.max(wet_to, W.wet - dt / W.DRY) end
  if W.cloud ~= c0 or W.rain ~= r0 then W.apply() end
  if W.rain > 0 then open_sky(dt) end
  if W.rain > 0 or voice then sound() end
end)

-- How well tyres grip, 1 on dry roads, less on wet ones.
function W.grip() return 1 - 0.3 * W.wet end

engine.on("init", function()
  if held then W.set(held) end
  local ok, settings = pcall(require, "lib.settings")
  if ok then
    settings.watch("weather", function() W.apply() end)
    -- The setting turns shadows on by itself; whether clouds allow them is ours.
    settings.watch("shadows", function() shadows_on = nil; W.apply() end)
  end
end)

return W
