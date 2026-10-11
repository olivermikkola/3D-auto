-- Cheap effects: particles (no physics bodies, moved here), bullet tracers,
-- muzzle flashes, fire, smoke and explosions. Everything self-destructs.
local FX = {live = {}}
local MAX = 260

local function add(e)
  if #FX.live >= MAX then
    local old = table.remove(FX.live, 1)
    engine.despawn(old.id)
  end
  FX.live[#FX.live + 1] = e
end

-- n bits flying out of (x, y, z).
function FX.burst(x, y, z, n, color, speed, life, size, glow, gravity)
  for _ = 1, n do
    local a, b = math.random() * math.pi * 2, math.random() * 0.9
    local s = speed * (0.4 + math.random() * 0.6)
    local id = engine.spawn{mesh = "cube", pos = {x, y, z}, size = size or 0.12, color = color, glow = glow or 0}
    add{id = id, vx = math.cos(a) * math.cos(b) * s, vy = math.sin(b) * s + speed * 0.3, vz = math.sin(a) * math.cos(b) * s,
        die = engine.time() + life * (0.6 + math.random() * 0.4), g = gravity or -18}
  end
end

-- A drifting puff that grows (smoke) or rises and shrinks (fire).
function FX.puff(x, y, z, color, size, rise, life, glow)
  local id = engine.spawn{mesh = "cube", pos = {x, y, z}, size = size, yaw = math.random() * 6, color = color, glow = glow or 0}
  add{id = id, vx = (math.random() - 0.5), vy = rise, vz = (math.random() - 0.5), g = 0, die = engine.time() + life,
      grow = glow and -0.8 or 1.2, s = size}
end

-- A thin glowing streak from a to b, gone in a blink.
function FX.tracer(ax, ay, az, bx, by, bz)
  local dx, dy, dz = bx - ax, by - ay, bz - az
  local len = math.sqrt(dx * dx + dy * dy + dz * dz)
  if len < 0.1 then return end
  local id = engine.spawn{mesh = "cube", pos = {(ax + bx) / 2, (ay + by) / 2, (az + bz) / 2}, size = {0.03, 0.03, len},
                          color = {1, 0.9, 0.5, 0.8}, glow = 1.5}
  engine.orient(id, math.atan(dx, dz), -math.asin(dy / len))
  add{id = id, vx = 0, vy = 0, vz = 0, g = 0, die = engine.time() + 0.05}
end

function FX.flash(x, y, z, size)
  local id = engine.spawn{mesh = "sphere", pos = {x, y, z}, size = size or 0.35, color = {1, 0.85, 0.4}, glow = 2}
  add{id = id, vx = 0, vy = 0, vz = 0, g = 0, die = engine.time() + 0.05}
  local l = engine.light{pos = {x, y, z}, radius = 10, intensity = 3, color = {1, 0.8, 0.4}}
  add{light = l, die = engine.time() + 0.06}
end

function FX.explosion(x, y, z)
  for k = 1, 7 do
    local s = 2 + math.random() * 2
    local id = engine.spawn{mesh = "sphere", pos = {x + (math.random() - 0.5) * 3, y + math.random() * 2, z + (math.random() - 0.5) * 3},
                            size = s, color = {1, 0.45 + math.random() * 0.3, 0.1, 0.85}, glow = 2.5}
    add{id = id, vx = 0, vy = 2 + k * 0.3, vz = 0, g = 0, die = engine.time() + 0.5 + math.random() * 0.4, grow = 3, s = s}
  end
  FX.burst(x, y + 1, z, 24, {0.15, 0.13, 0.12}, 14, 1.6, 0.25)
  FX.burst(x, y + 1, z, 16, {1, 0.6, 0.2}, 10, 0.8, 0.15, 2)
  for _ = 1, 8 do FX.puff(x + (math.random() - 0.5) * 4, y + 1, z + (math.random() - 0.5) * 4, {0.2, 0.2, 0.2, 0.7}, 1.5, 3, 3) end
  local l = engine.light{pos = {x, y + 2, z}, radius = 30, intensity = 6, color = {1, 0.6, 0.25}}
  add{light = l, die = engine.time() + 0.6}
end

engine.on("frame", function(dt)
  local now = engine.time()
  local keep = {}
  for _, e in ipairs(FX.live) do
    if now >= e.die then
      if e.id then engine.despawn(e.id) end
      if e.light then engine.remove_light(e.light) end
    else
      if e.id then
        e.vy = e.vy + e.g * dt
        local x, y, z = engine.pos(e.id)
        if x then
          y = y + e.vy * dt
          if y < 0.06 and e.g ~= 0 then y, e.vy, e.vx, e.vz = 0.06, 0, e.vx * 0.5, e.vz * 0.5 end
          engine.set_pos(e.id, x + e.vx * dt, y, z + e.vz * dt)
          if e.grow then
            e.s = math.max(0.05, e.s + e.grow * dt)
            engine.set_scale(e.id, e.s)
          end
        end
      end
      keep[#keep + 1] = e
    end
  end
  FX.live = keep
end)

return FX
