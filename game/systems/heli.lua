-- The police helicopter: from four stars up it flies in and hangs over you,
-- 40 m up, its searchlight on you at night. It sees you wherever the sky
-- does, so the cops keep their sighting; under a roof, a bridge or in a
-- tunnel it loses you. Back under four stars it flies off.
local G = require "lib.state"
local U = require "lib.util"
local wanted = require "lib.wanted"

local Hc = {STARS = 4, HEIGHT = 40, SPEED = 26, SIGHT = 110}
local heli, rotor, light, voice
local leaving = false

function Hc.build()
  local blue, white, dark, glass = {0.08, 0.14, 0.4}, {0.92, 0.92, 0.95}, {0.12, 0.12, 0.14}, {0.15, 0.22, 0.3}
  engine.mesh("heli", {
    {mesh = "cube", pos = {0, 0, 0.3}, size = {2.2, 1.8, 4.4}, color = blue},
    {mesh = "cube", pos = {0, -0.25, 0.3}, size = {2.24, 0.5, 4.2}, color = white},
    {mesh = "cube", pos = {0, 0.25, 2.2}, size = {1.9, 1.0, 0.9}, color = glass},
    {mesh = "cube", pos = {0, 0.4, -4.0}, size = {0.45, 0.45, 4.2}, color = blue},
    {mesh = "cube", pos = {0, 1.0, -5.9}, size = {0.12, 1.3, 0.8}, color = blue},
    {mesh = "cube", pos = {0.9, -1.15, 0.3}, size = {0.12, 0.12, 3.6}, color = dark},
    {mesh = "cube", pos = {-0.9, -1.15, 0.3}, size = {0.12, 0.12, 3.6}, color = dark},
    {mesh = "cube", pos = {0, 1.05, 0.3}, size = {0.5, 0.3, 0.5}, color = dark},
    {mesh = "cube", pos = {0, -0.95, 1.8}, size = {0.4, 0.3, 0.4}, color = {1, 1, 0.9}, emissive = 1},
    -- Navigation lights: red to port, green to starboard, white on the tail.
    {mesh = "cube", pos = {-1.15, 0.1, 0.3}, size = {0.12, 0.18, 0.18}, color = {1, 0.1, 0.1}, emissive = 1},
    {mesh = "cube", pos = {1.15, 0.1, 0.3}, size = {0.12, 0.18, 0.18}, color = {0.1, 1, 0.2}, emissive = 1},
    {mesh = "cube", pos = {0, 1.7, -5.9}, size = {0.16, 0.16, 0.16}, color = {1, 1, 1}, emissive = 1},
  })
  engine.mesh("rotor", {
    {mesh = "cube", size = {0.3, 0.05, 11}, color = {0.15, 0.15, 0.15}},
    {mesh = "cube", size = {11, 0.05, 0.3}, color = {0.15, 0.15, 0.15}},
  })
  engine.synth("rotor", {wave = "saw", freq = 21, dur = 1, loop = true, volume = 0.55, lowpass = 0.25})
end

local function despawn()
  if heli then engine.despawn(heli) end
  if rotor then engine.despawn(rotor) end
  if light then engine.remove_light(light) end
  if voice then engine.stop(voice) end
  heli, rotor, light, voice, leaving = nil, nil, nil, nil, false
end

-- Is the sky open above (x, y, z)? Not under a roof, a bridge or in a
-- tunnel (the player's own car doesn't count: start above its roof).
local function open_above(x, y, z)
  return engine.raycast(x, y + 2.6, z, 0, 1, 0, 60) == nil
end

-- Does the helicopter see the player right now?
function Hc.sees()
  if not heli or leaving then return false end
  local px, py, pz = U.player_pos()
  if not px then return false end
  local x, _, z = engine.pos(heli)
  return U.dist2d(x, z, px, pz) < Hc.SIGHT and open_above(px, py, pz)
end

function Hc.active() return heli ~= nil and not leaving end
function Hc.id() return heli end

local function arrive(px, pz)
  -- From 300 m off, upwind of nowhere in particular: the side you face away from.
  local yaw = U.player_yaw() or 0
  local fx, fz = U.forward(yaw)
  local x, z = px - fx * 300, pz - fz * 300
  local y = U.ground(x, z) + Hc.HEIGHT
  heli = engine.spawn{mesh = "heli", pos = {x, y, z}, scale = 1, tag = "heli"}
  rotor = engine.spawn{mesh = "rotor", pos = {x, y + 1.3, z}, scale = 1}
  light = engine.light{pos = {x, y - 1, z}, dir = {0, -1, 0}, cone = 12, radius = 80, intensity = 3, color = {0.95, 0.97, 1}}
  voice = engine.play("rotor", {loop = true, follow = heli, volume = 1.2})
  U.message("POLICE HELICOPTER", 2)
  engine.emit("heli")
end

engine.on("tick", function(dt)
  local px, py, pz = U.player_pos()
  local want = wanted.stars() >= Hc.STARS and px and not G.dead
  if want and not heli then arrive(px, pz) end
  if not heli then return end
  if not want then leaving = true end
  local x, y, z = engine.pos(heli)
  local tx, tz, ty
  if leaving then
    -- Off the way it's facing, climbing.
    local fx, fz = U.forward(engine.yaw(heli))
    tx, tz, ty = x + fx * 50, z + fz * 50, y + 5
    if not px or U.dist2d(x, z, px, pz) > 400 then return despawn() end
  else
    -- A slow circle 12 m round the player, a little behind where they go.
    local t = engine.time() * 0.25
    tx, tz = px + math.cos(t) * 12, pz + math.sin(t) * 12
    ty = math.max(U.ground(x, z), py or 0) + Hc.HEIGHT
  end
  local dx, dz = tx - x, tz - z
  local d = math.sqrt(dx * dx + dz * dz)
  local step = math.min(d, Hc.SPEED * dt)
  if d > 0.01 then
    x, z = x + dx / d * step, z + dz / d * step
    if d > 8 then engine.set_yaw(heli, math.atan(dx, dz)) end
  end
  y = y + U.clamp(ty - y, -6 * dt, 6 * dt)
  engine.set_pos(heli, x, y, z)
end)

engine.on("frame", function()
  if not heli then return end
  local x, y, z = engine.pos(heli)
  engine.set_pos(rotor, x, y + 1.3, z)
  engine.set_yaw(rotor, engine.time() * 25)
  -- The searchlight on the player (or straight down while leaving).
  local px, py, pz = U.player_pos()
  local dx, dy, dz = 0, -1, 0
  if px and not leaving then dx, dy, dz = px - x, py - y, pz - z end
  engine.set_light(light, {pos = {x, y - 1.2, z}, dir = {dx, dy, dz}})
end)

engine.on("minimap", function(map)
  if not heli then return end
  local x, _, z = engine.pos(heli)
  local mx, my = map(x, z)
  local on = math.floor(engine.time() * 4) % 2 == 0
  engine.rect(mx - 3, my - 3, 6, 6, on and 1 or 0.3, on and 1 or 0.3, 1, 1)
end)

-- Busted or wasted: gone with the rest of them.
engine.on("busted", despawn)
engine.on("respawned", despawn)

return Hc
