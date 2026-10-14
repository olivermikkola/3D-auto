-- Day/night cycle: moves the sun (or moon), blends sky and light palettes,
-- and sets `glow`, which turns on emissive surfaces and every light.
-- A full day takes DAY_LENGTH real seconds. Press N to skip ahead 3 hours.
local U = require "lib.util"

local D = {hour = 16.5, DAY_LENGTH = 8 * 60}

local function lerp3(a, b, t) return {U.lerp(a[1], b[1], t), U.lerp(a[2], b[2], t), U.lerp(a[3], b[3], t)} end

local PALETTES = {
  night = {sky = {0.03, 0.05, 0.10}, top = {0.0, 0.01, 0.04}, sun = {0.10, 0.12, 0.20}, ambient = {0.07, 0.08, 0.14}, ground = {0.02, 0.02, 0.03}, glow = 1},
  dusk = {sky = {0.95, 0.52, 0.30}, top = {0.22, 0.27, 0.52}, sun = {1.0, 0.55, 0.28}, ambient = {0.34, 0.30, 0.36}, ground = {0.10, 0.08, 0.08}, glow = 0.45},
  day = {sky = {0.68, 0.79, 0.90}, top = {0.30, 0.50, 0.85}, sun = {0.95, 0.88, 0.76}, ambient = {0.42, 0.45, 0.52}, ground = {0.13, 0.12, 0.11}, glow = 0},
}

local function blend(a, b, t)
  local out = {}
  for k, v in pairs(a) do out[k] = type(v) == "table" and lerp3(v, b[k], t) or U.lerp(v, b[k], t) end
  return out
end

-- Sun elevation (-1..1) for an hour of the day: up at 6, peak at 12, down at 18.
function D.elevation(hour) return math.sin((hour - 6) / 12 * math.pi) end

function D.palette(hour)
  local e = D.elevation(hour)
  local P = PALETTES
  if e > 0.3 then return P.day end
  if e > 0 then return blend(P.dusk, P.day, e / 0.3) end
  if e > -0.15 then return blend(P.night, P.dusk, (e + 0.15) / 0.15) end
  return P.night
end

function D.apply()
  local e = D.elevation(D.hour)
  local a = (D.hour - 6) / 12 * math.pi
  -- Sun arcs east to west, tilted south; at night the moon takes over.
  local sun = e > -0.05 and {math.cos(a) * 0.8, math.max(e, 0.06), 0.35} or {0.35, 0.75, -0.45}
  local p = D.palette(D.hour)
  engine.lighting{sky = p.sky, sky_top = p.top, sun = sun, sun_color = p.sun, ambient = p.ambient, ground = p.ground, glow = p.glow}
  D.glow = p.glow
end

function D.set_hour(h)
  D.hour = h % 24
  D.apply()
end

function D.clock() return string.format("%02d:%02d", math.floor(D.hour), math.floor(D.hour % 1 * 60)) end

-- Street lamps light pools on the ground once it gets dark.
function D.light_lamps()
  for _, id in ipairs(engine.find("lamp")) do
    engine.light{follow = id, pos = {0, 4.8, 1.15}, dir = {0, -1, 0}, cone = 60, radius = 13, intensity = 1.6, color = {1, 0.82, 0.55}}
  end
end

engine.on("tick", function(dt)
  local prev_h = math.floor(D.hour)
  local next_h = D.hour + dt * 24 / D.DAY_LENGTH
  D.set_hour(next_h)
  if prev_h ~= math.floor(D.hour) and math.floor(D.hour) == 12 then
    engine.play("cathedral_bell", {pos = {380, 25, -90}, volume = 0.8})
  end
end)
engine.on("key", function(k, down) if k == "n" and down then D.set_hour(D.hour + 3) end end)

return D
