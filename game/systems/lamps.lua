-- Street lamps give way, as in GTA: a car or bus meeting one at speed
-- goes through (the physics lets it, see Body::breaks_at), and the post
-- is swapped for a loose one that topples the way the car was going.
-- Slower than BREAKS_AT it's a solid post; people never knock one over.
local U = require "lib.util"
local FX = require "lib.fx"

local L = {BREAKS_AT = 6, down = {}, MAX_DOWN = 24}
local POLE = 5.0 -- the post's height; a lamp's position is its foot

-- What hitting a lamp costs the car: a quarter of its speed.
local KEEP = 0.75

function L.knock(lamp, car)
  local x, y, z = engine.pos(lamp)
  local qx, qy, qz, qw = engine.rot(lamp)
  local vx, vy, vz = engine.vel(car)
  engine.despawn(lamp)
  local pole = engine.spawn{mesh = "lamp_down", pos = {x, y + POLE / 2, z}, size = {0.3, POLE, 0.3},
                            body = "dynamic", mass = 90, friction = 0.8, tag = "lamp_down"}
  engine.set_rot(pole, qx, qy, qz, qw)
  -- It goes off the car's front corner, out of its way: forward and to
  -- the side the post was on (the near side if it was dead ahead).
  local s = math.max(math.sqrt(vx * vx + vz * vz), 0.1)
  local fx, fz = vx / s, vz / s
  local cx, _, cz = engine.pos(car)
  local rx, rz = -fz, fx
  local side = (x - cx) * rx + (z - cz) * rz >= 0 and 1 or -1
  local dx, dz = fx * 0.3 + rx * side, fz * 0.3 + rz * side
  local n = math.sqrt(dx * dx + dz * dz)
  dx, dz = dx / n, dz / n
  -- Tip over that way: the top swings along (dx, dz).
  local spin = math.min(1.5 + s / 6, 5)
  engine.set_angvel(pole, dz * spin, 0, -dx * spin)
  engine.set_vel(pole, vx * 0.4 + dx * 6, 1.5, vz * 0.4 + dz * 6)
  engine.set_vel(car, vx * KEEP, vy, vz * KEEP)
  engine.play("thud", {pos = {x, y + 1, z}, volume = 1.0, pitch = 0.6})
  FX.burst(x, y + 1, z, 10, {1, 0.85, 0.5}, 4, 0.4, 0.08, 1)
  L.down[#L.down + 1] = {id = pole, t = engine.time()}
  if #L.down > L.MAX_DOWN then
    engine.despawn(table.remove(L.down, 1).id)
  end
  engine.emit("lamp_down", pole, car)
  return pole
end

engine.on("contact", function(a, b, _, broke)
  if not broke then return end
  local lamp, car = a, b
  if engine.tag(lamp) ~= "lamp" then lamp, car = b, a end
  if engine.tag(lamp) == "lamp" and engine.exists(car) then L.knock(lamp, car) end
end)

-- Fallen lamps are cleared away later, once nobody is near.
engine.on("tick", function()
  local now = engine.time()
  local px, _, pz = U.player_pos()
  for i = #L.down, 1, -1 do
    local d = L.down[i]
    local x, _, z = engine.pos(d.id)
    local age = now - d.t
    if not x or (age > 60 and (not px or U.dist2d(x, z, px, pz) > 60)) or age > 240 then
      engine.despawn(d.id)
      table.remove(L.down, i)
    end
  end
end)

return L
