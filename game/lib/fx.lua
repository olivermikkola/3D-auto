-- Cheap effects: particles (no physics bodies, moved here), bullet tracers,
-- muzzle flashes, fire, smoke and explosions. Everything self-destructs.
local FX = {live = {}}
local MAX = 260

local function add(e)
  if #FX.live >= MAX then
    local old = table.remove(FX.live, 1)
    if old.id then engine.despawn(old.id) end
    if old.light then engine.remove_light(old.light) end
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

-- A fireball: flashes white-hot, swells, cools through orange to a dark
-- red and shrinks away in about half a second. Smoke stays behind.
local HOT, WARM, COOL = {1, 0.95, 0.75}, {1, 0.5, 0.1}, {0.3, 0.08, 0.04}
local function mix(a, b, t) return a + (b - a) * t end
local function fire_color(p)
  local a, b, t = HOT, WARM, p / 0.35
  if p > 0.35 then a, b, t = WARM, COOL, (p - 0.35) / 0.65 end
  return mix(a[1], b[1], t), mix(a[2], b[2], t), mix(a[3], b[3], t)
end

function FX.explosion(x, y, z)
  local now = engine.time()
  for k = 1, 5 do
    local s = 1.2 + math.random() * 1.0
    local px, py, pz = x + (math.random() - 0.5) * 2.4, y + 0.3 + math.random() * 1.2, z + (math.random() - 0.5) * 2.4
    local id = engine.spawn{mesh = "sphere", pos = {px, py, pz}, size = s, color = {HOT[1], HOT[2], HOT[3], 0.95}, glow = 1.6}
    add{id = id, vx = 0, vy = 1 + k * 0.3, vz = 0, g = 0, born = now, life = 0.4 + math.random() * 0.2, fire = s}
  end
  FX.burst(x, y + 1, z, 20, {0.12, 0.11, 0.1}, 12, 1.4, 0.22)
  FX.burst(x, y + 1, z, 14, {1, 0.6, 0.2}, 10, 0.5, 0.12, 2)
  for _ = 1, 7 do
    local id = engine.spawn{mesh = "sphere", pos = {x + (math.random() - 0.5) * 3, y + 0.8, z + (math.random() - 0.5) * 3},
                            size = 1.2, color = {0.13, 0.12, 0.12, 0.6}}
    add{id = id, vx = (math.random() - 0.5), vy = 1.6 + math.random(), vz = (math.random() - 0.5), g = 0,
        born = now, life = 2 + math.random(), smoke = 1.2, delay = 0.15}
  end
  local l = engine.light{pos = {x, y + 2, z}, radius = 24, intensity = 4, color = {1, 0.6, 0.25}}
  add{light = l, born = now, life = 0.45, flash = 4, die = now + 0.45}
end

engine.on("frame", function(dt)
  local now = engine.time()
  local keep = {}
  for _, e in ipairs(FX.live) do
    if e.life and not e.die then e.die = e.born + e.life end
    if now >= e.die then
      if e.id then engine.despawn(e.id) end
      if e.light then engine.remove_light(e.light) end
    else
      if e.flash then
        engine.set_light(e.light, {intensity = e.flash * (1 - (now - e.born) / e.life)})
      end
      if e.id then
        e.vy = e.vy + e.g * dt
        local x, y, z = engine.pos(e.id)
        if x then
          y = y + e.vy * dt
          e.floor = e.floor or require("lib.util").ground(x, z) + 0.06
          if y < e.floor and e.g ~= 0 then y, e.vy, e.vx, e.vz = e.floor, 0, e.vx * 0.5, e.vz * 0.5 end
          engine.set_pos(e.id, x + e.vx * dt, y, z + e.vz * dt)
          if e.grow then
            e.s = math.max(0.05, e.s + e.grow * dt)
            engine.set_scale(e.id, e.s)
          end
          local p = e.life and (now - e.born) / e.life
          if e.fire then
            -- Swell to 1.8x in the first quarter, then shrink to a third.
            engine.set_scale(e.id, e.fire * (p < 0.25 and 1 + 3.2 * p or 1.8 - 1.6 * (p - 0.25)))
            local r, g, b = fire_color(p)
            engine.set_color(e.id, r, g, b, 0.95 * (1 - p * p))
            engine.set_glow(e.id, 1.6 * (1 - p))
          elseif e.smoke then
            engine.set_scale(e.id, e.smoke * (1 + 1.5 * p))
            engine.set_color(e.id, 0.13, 0.12, 0.12, 0.6 * math.min(1, (now - e.born) / e.delay) * (1 - p))
          end
        end
      end
      keep[#keep + 1] = e
    end
  end
  FX.live = keep
end)

return FX
