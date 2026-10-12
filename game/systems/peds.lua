-- Pedestrians: walk the sidewalk loop around their block, sometimes cross
-- the street at a corner, run from danger, and get knocked flying by cars.
-- Pure Lua on the engine API; the population follows the player around.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local prefabs = require "lib.prefabs"
local H = require "lib.health"

local Ped = {peds = {}, down = {}}
local COUNT, WALK, RUN = 40, 1.4, 6.5
local SKINS = {{0.95, 0.8, 0.65}, {0.85, 0.65, 0.5}, {0.6, 0.42, 0.3}, {0.4, 0.28, 0.2}}
local SHIRTS = {{0.8, 0.2, 0.2}, {0.2, 0.4, 0.8}, {0.9, 0.8, 0.3}, {0.3, 0.6, 0.35}, {0.15, 0.15, 0.15}, {0.9, 0.9, 0.9}, {0.6, 0.3, 0.6}, {0.9, 0.5, 0.2}}
local PANTS = {{0.15, 0.2, 0.4}, {0.25, 0.25, 0.25}, {0.5, 0.4, 0.3}, {0.1, 0.1, 0.1}}
local HAIR = {{0.1, 0.07, 0.04}, {0.45, 0.3, 0.12}, {0.8, 0.7, 0.4}, {0.5, 0.5, 0.5}}
local VARIANTS = 12

function Ped.build()
  local function pick(t, i) return t[i % #t + 1] end
  for i = 1, VARIANTS do
    prefabs.person("ped" .. i, pick(SHIRTS, i), pick(PANTS, i * 3), pick(SKINS, i * 5), pick(HAIR, i * 7))
  end
  engine.synth("scream", {wave = "square", freq = 780, freq_end = 420, dur = 0.5, attack = 0.03, release = 0.25, volume = 0.18, lowpass = 0.25})
end

-- ---- sidewalk geometry ------------------------------------------------------

-- Corners counter-clockwise; index <-> (sx, sz) sign pair.
local SIGNS = {{1, 1}, {-1, 1}, {-1, -1}, {1, -1}}

local function corner(i, j, k)
  local cx, cz = city.block_center(i, j)
  return cx + SIGNS[k][1] * (G.city.bx / 2 - 2.2), cz + SIGNS[k][2] * (G.city.bz / 2 - 2.2)
end

local block_of = city.block_of
local function walkable(i, j) return city.district(i, j) ~= "water" end

local function nearest_corner(p, x, z)
  local best, bk = math.huge, 1
  for k = 1, 4 do
    local cx, cz = corner(p.i, p.j, k)
    local d = U.dist2d(x, z, cx, cz)
    if d < best then best, bk = d, k end
  end
  return bk
end

local function set_target(p, x, z) p.tx, p.tz = x, z end

-- Reached a corner: keep circling, or now and then cross to the next block.
local function next_leg(p)
  local s = SIGNS[p.k]
  if math.random() < 0.25 then
    local opts = {}
    if walkable(p.i + s[1], p.j) then opts[#opts + 1] = {p.i + s[1], p.j, -s[1], s[2]} end
    if walkable(p.i, p.j + s[2]) then opts[#opts + 1] = {p.i, p.j + s[2], s[1], -s[2]} end
    if #opts > 0 then
      local o = opts[math.random(#opts)]
      for k, sg in ipairs(SIGNS) do
        if sg[1] == o[3] and sg[2] == o[4] then p.i, p.j, p.k = o[1], o[2], k end
      end
      p.crossing = true
      return set_target(p, corner(p.i, p.j, p.k))
    end
  end
  p.crossing = false
  p.k = (p.k - 1 + p.dir) % 4 + 1
  set_target(p, corner(p.i, p.j, p.k))
end

-- ---- population ---------------------------------------------------------------

local function spawn_ped(near_x, near_z, min_d, max_d)
  local bi, bj = block_of(near_x, near_z)
  for _ = 1, 30 do
    -- A block around the player: avenues are twice as far apart as streets.
    local i, j = bi + math.random(-2, 2), bj + math.random(-4, 4)
    if not walkable(i, j) then goto continue end
    local k = math.random(4)
    local a, b = corner(i, j, k)
    local n = k % 4 + 1
    local c, d = corner(i, j, n)
    local t = math.random()
    local x, z = a + (c - a) * t, b + (d - b) * t
    local dist = U.dist2d(x, z, near_x, near_z)
    if dist >= min_d and dist <= max_d and not engine.nearest(x, 1, z, 1.5) then
      local id = engine.spawn{mesh = "ped" .. math.random(VARIANTS), pos = {x, 1.15, z}, size = {0.7, 1.8, 0.7},
                              body = "dynamic", mass = 70, friction = 0, step = 0.45, lock_rotation = true, tag = "ped"}
      H.set(id, 30)
      local p = {id = id, i = i, j = j, k = n, dir = 1, speed = WALK * (0.8 + math.random() * 0.4), state = "walk", stuck = 0}
      if math.random() < 0.5 then p.dir, p.k = -1, k end
      set_target(p, corner(i, j, p.k))
      Ped.peds[id] = p
      return id
    end
    ::continue::
  end
end

function Ped.count()
  local n = 0
  for _ in pairs(Ped.peds) do n = n + 1 end
  return n
end

function Ped.start()
  local px, _, pz = U.player_pos()
  for _ = 1, COUNT do spawn_ped(px, pz, 0, 140) end
end

-- ---- behaviour ----------------------------------------------------------------

-- Make every ped within `radius` of (x, z) run away from it.
function Ped.scare(x, z, radius)
  -- Earlier contact/kill handlers may already have despawned the source.
  if not x or not z then return end
  for id, p in pairs(Ped.peds) do
    local px, _, pz = engine.pos(id)
    if U.dist2d(x, z, px, pz) < radius then
      if p.state ~= "flee" then
        engine.play("scream", {pos = {px, 1.5, pz}, pitch = 0.8 + math.random() * 0.5})
      end
      p.state, p.until_t = "flee", engine.time() + 3 + math.random() * 2
      p.fx, p.fz = px - x, pz - z
      local l = math.sqrt(p.fx * p.fx + p.fz * p.fz) + 1e-3
      p.fx, p.fz = p.fx / l, p.fz / l
    end
  end
end

local function walk(id, p, dt)
  local x, _, z = engine.pos(id)
  local _, vy = engine.vel(id)
  local mx, mz, speed
  if p.state == "flee" then
    if engine.time() > p.until_t then
      p.state = "walk"
      p.i, p.j = block_of(x, z)
      p.k = nearest_corner(p, x, z)
      set_target(p, corner(p.i, p.j, p.k))
      return
    end
    mx, mz, speed = p.fx, p.fz, RUN
  else
    if U.dist2d(x, z, p.tx, p.tz) < 0.8 then next_leg(p) end
    mx, mz = p.tx - x, p.tz - z
    local l = math.sqrt(mx * mx + mz * mz) + 1e-3
    mx, mz, speed = mx / l, mz / l, p.speed
    -- Wait at the curb while a car is coming.
    local hit = p.crossing and engine.raycast(x, 0.9, z, mx, 0, mz, 7, id)
    if hit and (engine.tag(hit) == "car" or engine.tag(hit) == "cop") then speed = 0 end
  end
  engine.set_vel(id, mx * speed, vy, mz * speed)
  if speed > 0 then
    local yaw = engine.yaw(id)
    engine.set_yaw(id, yaw + U.angle_diff(yaw, math.atan(mx, mz)) * math.min(1, dt * 10))
  end
  -- Blocked (a lamp, a parked car, a crowd): turn around.
  local vx, _, vz = engine.vel(id)
  p.stuck = (speed > 0 and vx * vx + vz * vz < 0.1) and p.stuck + dt or 0
  if p.stuck > 2 and p.state == "walk" then
    p.stuck, p.dir = 0, -p.dir
    p.k = (p.k - 1 + p.dir) % 4 + 1
    set_target(p, corner(p.i, p.j, p.k))
  end
end

-- Knocked down: swap the upright walker for a free-tumbling body.
local function knock(id, by, speed)
  local p = Ped.peds[id]
  if not p then return end
  Ped.peds[id] = nil
  local x, y, z = engine.pos(id)
  local yaw = engine.yaw(id)
  local mesh = "ped" .. math.random(VARIANTS)
  engine.despawn(id)
  local vx, vy, vz = engine.vel(by)
  local body = engine.spawn{mesh = mesh, pos = {x, y + 0.2, z}, yaw = yaw, size = {0.7, 1.8, 0.7},
                            body = "dynamic", mass = 70, friction = 0.8, tag = "ped_down"}
  engine.set_vel(body, vx * 0.9, math.max(vy, 0) + 2 + speed * 0.25, vz * 0.9)
  engine.set_angvel(body, (math.random() - 0.5) * 8, (math.random() - 0.5) * 4, (math.random() - 0.5) * 8)
  Ped.down[body] = engine.time() + 12
  engine.emit("ped_down", body, by)
end

engine.on("contact", function(a, b, speed)
  local ped, other
  if Ped.peds[a] then ped, other = a, b elseif Ped.peds[b] then ped, other = b, a else return end
  local tag = engine.tag(other)
  if (tag == "car" or tag == "cop") and speed > 4 then knock(ped, other, speed) end
end)

-- Shot, punched or blown up.
engine.on("killed", function(id, by, dx, dy, dz)
  if not Ped.peds[id] then return end
  Ped.peds[id] = nil
  local body = H.ragdoll(id, "ped" .. math.random(VARIANTS), dx, dy, dz, 5)
  Ped.down[body] = engine.time() + 12
  engine.emit("ped_down", body, by)
end)

engine.on("ped_down", function(_, by)
  if by and (by == G.vehicle or by == G.player) then require("lib.wanted").heat_up(1) end
  local x, _, z = engine.pos(by)
  Ped.scare(x, z, 20)
end)

-- Things that frighten people.
engine.on("key", function(k, down)
  if k == "h" and down and G.vehicle then
    local x, _, z = engine.pos(G.vehicle)
    Ped.scare(x, z, 18)
  end
end)
engine.on("contact", function(a, b, speed)
  if speed > 8 and (engine.tag(a) == "car" or engine.tag(b) == "car") then
    local x, _, z = engine.pos(a)
    Ped.scare(x, z, 15)
  end
end)

local recycle_t = 0
engine.on("tick", function(dt)
  if not G.city then return end
  local px, _, pz = U.player_pos()
  if not px then return end

  -- A fast car heading at someone sends them running.
  local car = G.vehicle
  local cvx, cvz, cx, cz = 0, 0, 0, 0
  if car then
    cx, _, cz = engine.pos(car)
    cvx, _, cvz = engine.vel(car)
  end
  local car_fast = car and cvx * cvx + cvz * cvz > 64

  for id, p in pairs(Ped.peds) do
    if not engine.exists(id) then
      Ped.peds[id] = nil
    else
      if car_fast and p.state ~= "flee" then
        local x, _, z = engine.pos(id)
        local dx, dz = x - cx, z - cz
        local d2 = dx * dx + dz * dz
        if d2 < 144 and dx * cvx + dz * cvz > 0 then Ped.scare(cx, cz, 4 + math.sqrt(d2)) end
      end
      walk(id, p, dt)
    end
  end

  -- The fallen get up... as someone new, elsewhere.
  local now = engine.time()
  for id, t in pairs(Ped.down) do
    if now > t then
      engine.despawn(id)
      Ped.down[id] = nil
    end
  end

  -- Keep the crowd near the player: recycle the far ones, top up the count.
  recycle_t = recycle_t - dt
  if recycle_t <= 0 then
    recycle_t = 0.5
    for id in pairs(Ped.peds) do
      local x, _, z = engine.pos(id)
      if U.dist2d(x, z, px, pz) > 160 then
        engine.despawn(id)
        Ped.peds[id] = nil
        break
      end
    end
    if Ped.count() < COUNT then spawn_ped(px, pz, 70, 140) end
  end
end)

return Ped
