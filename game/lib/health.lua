-- Health for everything that can be hurt. The player's health lives here
-- too (it outlasts the player entity, which changes on every car switch).
-- Emits: damaged(id, amount, by), killed(id, by, dx, dy, dz), wasted().
local G = require "lib.state"
local U = require "lib.util"

local H = {hp = {}, max = {}, player = {hp = 100, max = 100}}
H.VEHICLE_HP = 100

function H.set(id, hp) H.hp[id], H.max[id] = hp, hp end

-- Vehicles get health on first use, so any spawner's cars can be damaged.
local function ensure(id)
  if H.hp[id] == nil then
    local tag = engine.tag(id)
    if tag == "car" or tag == "cop" then H.set(id, H.VEHICLE_HP) end
  end
  return H.hp[id]
end

function H.get(id)
  if id == G.player then return H.player.hp end
  return ensure(id)
end

function H.hurt_player(amount, by)
  local p = H.player
  if p.hp <= 0 or G.dead then return end
  p.hp = math.max(0, p.hp - amount)
  engine.emit("player_hurt", amount, by)
  if p.hp <= 0 then engine.emit("wasted", by) end
end

-- dx, dy, dz: direction the hit came from, for knockback.
function H.damage(id, amount, by, dx, dy, dz)
  if not id or not engine.exists(id) then return end
  if id == G.player then return H.hurt_player(amount, by) end
  local hp = ensure(id)
  if not hp or hp <= 0 then return end
  hp = hp - amount
  H.hp[id] = hp
  engine.emit("damaged", id, amount, by)
  if hp <= 0 then engine.emit("killed", id, by, dx or 0, dy or 0, dz or 0) end
end

function H.heal_player(amount)
  local p = H.player
  p.hp = math.min(p.max, p.hp + amount)
end

-- Swap an upright character for a tumbling body, thrown along (dx, dy, dz).
function H.ragdoll(id, mesh, dx, dy, dz, force, tag)
  local x, y, z = engine.pos(id)
  local yaw = engine.yaw(id)
  engine.despawn(id)
  local body = engine.spawn{mesh = mesh, pos = {x, y + 0.1, z}, yaw = yaw, size = {0.7, 1.8, 0.7},
                            body = "dynamic", mass = 70, friction = 0.8, tag = tag or "ped_down"}
  local l = math.sqrt(dx * dx + dy * dy + dz * dz) + 1e-3
  force = force or 4
  engine.set_vel(body, dx / l * force, 2 + math.max(0, dy / l) * force, dz / l * force)
  engine.set_angvel(body, (math.random() - 0.5) * 8, (math.random() - 0.5) * 4, (math.random() - 0.5) * 8)
  return body
end

-- Forget the dead; entities come and go constantly.
local sweep = 0
engine.on("tick", function(dt)
  sweep = sweep - dt
  if sweep > 0 then return end
  sweep = 2
  for id in pairs(H.hp) do
    if not engine.exists(id) then H.hp[id], H.max[id] = nil, nil end
  end
end)

-- ---- wasted -------------------------------------------------------------------
-- Down you go; the screen fades; you wake up outside the hospital, poorer.
H.RESPAWN_DELAY = 4
engine.on("wasted", function()
  G.dead = engine.time()
  local x, y, z = U.player_pos()
  if G.vehicle then
    local car = G.vehicle
    G.vehicle = nil
    engine.emit("vehicle_exit", car)
    G.corpse = engine.spawn{mesh = "person", pos = {x, y + 1.5, z}, size = {0.7, 1.8, 0.7}, body = "dynamic", mass = 70, tag = "ped_down"}
  elseif G.player then
    G.corpse = H.ragdoll(G.player, "person", math.random() - 0.5, 0, math.random() - 0.5, 2)
    G.player = nil
  end
  U.message("WASTED", H.RESPAWN_DELAY)
end)

engine.on("tick", function()
  if not G.dead or engine.time() - G.dead < H.RESPAWN_DELAY then return end
  G.dead = nil
  if G.corpse then engine.despawn(G.corpse); G.corpse = nil end
  local fee = math.min(G.cash, 100 + math.floor(G.cash * 0.1))
  G.cash = G.cash - fee
  H.player.hp = H.player.max
  require("lib.wanted").clear()
  require("systems.police").clear()
  local h = G.hospital or G.spawn
  require("lib.player").spawn(h[1], h[2], h[3], 0)
  U.message(string.format("HOSPITAL BILL -$%d", fee), 3)
  engine.emit("respawned", fee)
end)

return H
