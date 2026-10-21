-- Vehicle damage: crashes and bullets wear cars down; badly hurt cars smoke,
-- then burn, then explode. Explosions throw things, kill people nearby, chain
-- to other cars, and leave a burnt-out wreck.
local G = require "lib.state"
local U = require "lib.util"
local H = require "lib.health"
local FX = require "lib.fx"

local C = {burning = {}}
local VEHICLE = {car = true, cop = true}

function C.explode(id)
  if not engine.exists(id) then return end
  C.burning[id] = nil
  local x, y, z = engine.pos(id)
  local qx, qy, qz, qw = engine.rot(id)
  local vx, vy, vz = engine.vel(id)
  -- The car itself becomes a blackened wreck thrown into the air.
  -- (the same kind of car: a van leaves a burnt-out van)
  local prefabs = require "lib.prefabs"
  local kind = prefabs.car_kind(engine.mesh_of(id))
  local k = prefabs.CAR_KINDS[kind or "car"]
  local wreck = engine.spawn{mesh = (kind or "car") .. "1", pos = {x, y + 0.3, z}, size = k.size, color = {0.12, 0.1, 0.09},
                             body = "dynamic", mass = k.mass, friction = 0.8, tag = "wreck"}
  engine.set_rot(wreck, qx, qy, qz, qw)
  engine.set_vel(wreck, vx * 0.3, 7, vz * 0.3)
  engine.set_angvel(wreck, (math.random() - 0.5) * 3, (math.random() - 0.5) * 2, (math.random() - 0.5) * 3)
  local was_mine = id == G.vehicle
  engine.despawn(id)
  if was_mine then
    G.vehicle = nil
    H.hurt_player(999, wreck)
  end
  FX.explosion(x, y, z)
  engine.emit("explosion", x, y, z, wreck)

  -- Blast: shove and hurt everything nearby.
  local R = 9
  local function blast(other)
    if other == wreck or not engine.exists(other) then return end
    local ox, oy, oz = engine.pos(other)
    local dx, dy, dz = ox - x, oy - y + 1, oz - z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d > R then return end
    local k = (1 - d / R)
    local ovx, ovy, ovz = engine.vel(other)
    if ovx then
      local s = 16 * k / (d + 0.5)
      engine.set_vel(other, ovx + dx * s, ovy + 6 * k + dy * s, ovz + dz * s)
    end
    local tag = engine.tag(other)
    if VEHICLE[tag] then H.damage(other, 70 * k + 10, wreck)
    elseif tag == "ped" or tag == "officer" then H.damage(other, 200 * k, wreck, dx, dy, dz)
    elseif other == G.player then H.hurt_player(90 * k, wreck) end
  end
  for _, tag in ipairs{"car", "cop", "ped", "officer", "crate", "cone", "wreck", "ped_down", "player"} do
    for _, other in ipairs(engine.find(tag)) do blast(other) end
  end
  -- Wrecks are cleared away later, once nobody is looking.
  C.wrecks = C.wrecks or {}
  C.wrecks[wreck] = engine.time()
end

engine.on("killed", function(id)
  if VEHICLE[engine.tag(id) or ""] and not C.burning[id] then
    C.burning[id] = engine.time() + 3.5 -- on fire; boom shortly
  end
end)

-- Crashes into solid things hurt. Landing on the road or a ramp, or
-- running over people and crates, doesn't.
local SOLID = {building = true, wall = true, lamp = true, tree = true, car = true, cop = true, wreck = true}
-- One collision, one hit: AI cars pressed together re-collide every tick.
local recent = {}
engine.on("contact", function(a, b, speed)
  if speed < 8 then return end
  -- Ambient fender-benders don't add up: only the player's crashes, or real smashes.
  if speed < 15 and a ~= G.vehicle and b ~= G.vehicle then return end
  local key, now = a .. ":" .. b, engine.time()
  if (recent[key] or -1) > now then return end
  recent[key] = now + 1.0
  for _, pair in ipairs{{a, b}, {b, a}} do
    local id, other = pair[1], pair[2]
    if VEHICLE[engine.tag(id) or ""] and SOLID[engine.tag(other) or ""] then H.damage(id, (speed - 8) * 3, other) end
  end
end)

local fx_t = 0
engine.on("tick", function(dt)
  local now = engine.time()
  -- Exploding emits callbacks and can ignite another car. Adding entries
  -- during pairs() can rehash the table and invalidate Lua's next key.
  -- Snapshot first; new chain fires are processed on the following tick.
  local burning = {}
  for id, t in pairs(C.burning) do burning[#burning + 1] = {id, t} end
  for _, entry in ipairs(burning) do
    local id, t = entry[1], entry[2]
    if not engine.exists(id) then C.burning[id] = nil
    elseif C.burning[id] == t and now >= t then C.explode(id) end
  end
  fx_t = fx_t - dt
  if fx_t > 0 then return end
  fx_t = 0.12
  -- Smoke from damaged cars, flames from burning ones.
  for tag in pairs(VEHICLE) do
    for _, id in ipairs(engine.find(tag)) do
      local hp = H.hp[id]
      if hp and hp < 35 then
        local x, y, z = engine.pos(id)
        local fx, fy, fz = engine.forward(id)
        local hx, hy, hz = x + fx * 1.6, y + 0.6, z + fz * 1.6
        if C.burning[id] then
          FX.puff(hx, hy, hz, {1, 0.5 + math.random() * 0.3, 0.1}, 0.6, 3, 0.5, 2)
        else
          local g = 0.25 + hp / 100
          FX.puff(hx, hy, hz, {g, g, g, 0.6}, 0.4, 2, 1.5)
        end
      end
    end
  end
  for k, t in pairs(recent) do if t < now then recent[k] = nil end end
  for id, t in pairs(C.wrecks or {}) do
    local age = now - t
    if age > 45 then
      local px, _, pz = U.player_pos()
      local x, _, z = engine.pos(id)
      if not x or not px or U.dist2d(x, z, px, pz) > 40 or age > 180 then
        engine.despawn(id)
        C.wrecks[id] = nil
      end
    end
  end
end)

return C
