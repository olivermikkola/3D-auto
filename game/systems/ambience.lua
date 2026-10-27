-- Sounds of the place, not of anything you do: Turku Cathedral striking
-- the hours over the centre, and gulls over the water.
--
-- The mixer fades a voice with its position as 1 / (1 + (d / 12)²), right
-- for a car but gone in 50 m; a bell is heard across town. So the bells
-- play unplaced, at a volume this file works out from the distance.
local city = require "lib.city"
local daynight = require "lib.daynight"
local U = require "lib.util"

local A = {}

A.CATHEDRAL = {428, -104} -- the tower (as systems/aurajoki's)
A.BELL_REACH = 1400       -- m: past this the bells are lost in the town
A.STRIKE_GAP = 1.6        -- s between strikes
A.QUIET = {23, 6}         -- no bells from 23:00 to 06:00 (inclusive start, exclusive end)
A.GULL_HOURS = {5, 21}    -- gulls about from dawn to dusk
A.GULL_EVERY = {6, 18}    -- s between calls, when there is water near
A.GULL_LOOK = 45          -- m round the camera to look for water

local function turku()
  local map = city.map()
  return map and (map.id == "turku" or map.name == "Turku")
end

function A.build()
  -- A big bell: the strike, and its hum an octave up dying away under it.
  engine.synth("bell_strike", {wave = "sine", freq = 147, dur = 0.08, attack = 0.002, release = 3.2, volume = 0.7})
  engine.synth("bell_hum", {wave = "triangle", freq = 294, dur = 0.05, attack = 0.01, release = 2.4, volume = 0.25, lowpass = 0.5})
  -- The noon chime before the twelve strikes.
  engine.synth("cathedral_bell", {wave = "sine", notes = {262, 330, 392, 523}, note_len = 0.45, attack = 0.01, release = 1.8, volume = 0.6})
  -- A herring gull's "kyow": up, a catch, and down.
  engine.synth("gull", {wave = "triangle", notes = {1250, 1580, 1420, 1050}, note_len = 0.07, attack = 0.01, release = 0.12,
                        volume = 0.35, lowpass = 0.7})
  engine.synth("gull_short", {wave = "triangle", freq = 1500, freq_end = 980, dur = 0.16, attack = 0.01, release = 0.08,
                              volume = 0.3, lowpass = 0.7})
end

-- How loud the bells are d m from the tower (0 past A.BELL_REACH).
function A.bell_volume(d)
  if d >= A.BELL_REACH then return 0 end
  return 0.55 / (1 + (d / 400) ^ 2) * (1 - d / A.BELL_REACH)
end

-- How many strikes at hour h (0-23): the hour on a twelve-hour dial, none
-- in the quiet hours.
function A.strikes(h)
  if h >= A.QUIET[1] or h < A.QUIET[2] then return 0 end
  local n = h % 12
  return n == 0 and 12 or n
end

-- Its own random numbers: a gull mustn't move the game's math.random
-- sequence, which seeds traffic and the tests' runs.
local seed = 12345
local function rnd()
  seed = (seed * 1103515245 + 12345) & 0x7fffffff
  return seed / 0x80000000
end

local queue, last_hour, next_gull, t = {}, nil, 2, 0
A.played = {bell = 0, gull = 0} -- for tests

local function strike(sound)
  local x, _, z = engine.camera_pos()
  local v = A.bell_volume(U.dist2d(x, z, A.CATHEDRAL[1], A.CATHEDRAL[2]))
  A.played.bell = A.played.bell + 1
  if v <= 0.005 then return end
  if sound then return engine.play(sound, {volume = v}) end
  engine.play("bell_strike", {volume = v})
  engine.play("bell_hum", {volume = v})
end

-- A point on the water within reach of the camera, or nil.
local function water_near(x, z)
  local roadnet = require "lib.roadnet"
  for _ = 1, 6 do
    local a, r = rnd() * 2 * math.pi, 10 + rnd() * A.GULL_LOOK
    local wx, wz = x + math.cos(a) * r, z + math.sin(a) * r
    if roadnet.water_at(wx, wz) then return wx, wz end
  end
end

local function gulls(dt)
  next_gull = next_gull - dt
  if next_gull > 0 then return end
  next_gull = A.GULL_EVERY[1] + rnd() * (A.GULL_EVERY[2] - A.GULL_EVERY[1])
  local h = daynight.hour
  if h < A.GULL_HOURS[1] or h >= A.GULL_HOURS[2] then return end
  local weather = package.loaded["lib.weather"]
  if weather and (weather.rain or 0) > 0.5 then return end -- they sit out a storm
  local x, y, z = engine.camera_pos()
  local wx, wz = water_near(x, z)
  if not wx then return end
  A.played.gull = A.played.gull + 1
  engine.play(rnd() < 0.6 and "gull" or "gull_short",
              {pos = {wx, y + 8 + rnd() * 10, wz}, volume = 0.8, pitch = 0.9 + rnd() * 0.2})
  if rnd() < 0.35 then next_gull = 0.4 + rnd() * 0.5 end -- another answers
end

function A.tick(dt)
  t = t + dt
  local hour = math.floor(daynight.hour)
  if last_hour and hour ~= last_hour then
    local at = t
    if hour == 12 then -- noon: the chime first
      queue[#queue + 1] = {at, "cathedral_bell"}
      at = at + 2.6
    end
    for k = 1, A.strikes(hour) do queue[#queue + 1] = {at + (k - 1) * A.STRIKE_GAP} end
  end
  last_hour = hour
  while queue[1] and queue[1][1] <= t do
    strike(table.remove(queue, 1)[2])
  end
  gulls(dt)
end

engine.on("init", function()
  if not turku() then return end
  A.build()
  engine.on("tick", function(dt) A.tick(dt or 1 / 60) end)
end)

return A
