-- Pedestrians: walk the sidewalk loop around their block (or, on a map
-- drawn as roads, along the pavements from junction to junction),
-- sometimes cross the street at a corner, run from danger, and get knocked flying by cars.
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

-- ---- pavements of a map drawn as roads ---------------------------------------
-- There a ped walks the pavement along one road (edge e), toward bend wp,
-- in direction dir (+1 up the bends, -1 down), on the `hand` side of the
-- way it's walking. At a junction it takes another road there, now and
-- then crossing to the other side.

local roadnet = require "lib.roadnet"
local net = {}

local function edges() return roadnet.net().edges end

-- Keep ped p on a clear pavement of its road: its side of the road is
-- hand * dir; switch hands if that side's pavement isn't walkable.
local function clear_side(p)
  if not roadnet.pavement(p.e, p.hand * p.dir) then p.hand = -p.hand end
end

-- Walkable roads meeting at each junction.
local function at_junction(j)
  if not net.inc then
    net.inc = {}
    for ei, e in ipairs(edges()) do
      if roadnet.walkable(ei) then
        for _, end_ in ipairs{e.a, e.b} do
          net.inc[end_] = net.inc[end_] or {}
          table.insert(net.inc[end_], ei)
        end
      end
    end
  end
  return net.inc[j] or {}
end

-- Bend i of the ped's road, moved out to the pavement on its hand side.
function net.point(p, i)
  local e = edges()[p.e]
  local pts = e.pts
  local j = (pts[i - p.dir] and i - p.dir) or i + p.dir -- a neighbor to take the direction from
  local a, b = pts[math.min(i, j)], pts[math.max(i, j)]
  local fx, fz = b[1] - a[1], b[2] - a[2]
  if p.dir < 0 then fx, fz = -fx, -fz end
  local l = math.sqrt(fx * fx + fz * fz) + 1e-6
  local o = (e.width / 2 + roadnet.SIDEWALK / 2) * p.hand
  return pts[i][1] + fz / l * o, pts[i][2] - fx / l * o
end

function net.next_leg(p)
  local pts = edges()[p.e].pts
  local n = p.wp + p.dir
  p.crossing = false
  if n >= 1 and n <= #pts then
    p.wp = n
  else
    -- At a junction: carry on down another road (back the way we came only
    -- at a dead end), now and then crossing over.
    local e = edges()[p.e]
    local j = p.dir > 0 and e.b or e.a
    local opts = {}
    for _, ei in ipairs(at_junction(j)) do if ei ~= p.e then opts[#opts + 1] = ei end end
    local ne = opts[math.random(math.max(1, #opts))] or p.e
    local hand = p.hand
    if math.random() < 0.25 then p.hand = -p.hand end
    p.e = ne
    local ed = edges()[ne]
    if ed.a == j then p.dir, p.wp = 1, 1 else p.dir, p.wp = -1, #ed.pts end
    clear_side(p)
    p.crossing = p.hand ~= hand
  end
  set_target(p, net.point(p, p.wp))
end

-- Back to the nearest pavement (after running away).
function net.rejoin(p, x, z)
  local e, i = roadnet.nearest_edge(x, z, true)
  local pts = edges()[e].pts
  local a, b = pts[i - 1], pts[i]
  local side = (b[1] - a[1]) * (z - a[2]) - (b[2] - a[2]) * (x - a[1]) -- > 0: left of a->b
  p.e, p.dir = e, math.random() < 0.5 and 1 or -1
  p.wp = p.dir > 0 and i or i - 1
  p.hand = (side > 0) == (p.dir > 0) and -1 or 1
  clear_side(p)
  set_target(p, net.point(p, p.wp))
end

function net.turn(p)
  p.dir, p.hand = -p.dir, -p.hand
  local pts = edges()[p.e].pts
  p.wp = math.max(1, math.min(#pts, p.wp + p.dir))
  set_target(p, net.point(p, p.wp))
end

function net.spawn(near_x, near_z, min_d, max_d)
  -- Only roads that come within reach are worth trying.
  local E, near = edges(), {}
  for ei, e in ipairs(E) do
    if roadnet.walkable(ei) then
      for _, q in ipairs(e.pts) do
        if U.dist2d(q[1], q[2], near_x, near_z) < max_d + 60 then near[#near + 1] = ei break end
      end
    end
  end
  if #near == 0 then return end
  for _ = 1, 30 do
    local ei = near[math.random(#near)]
    local pts = E[ei].pts
    local i = math.random(2, #pts)
    do
      local p = {e = ei, dir = math.random() < 0.5 and 1 or -1, hand = math.random() < 0.5 and 1 or -1}
      clear_side(p)
      p.wp = p.dir > 0 and i or i - 1
      local ax, az = net.point(p, p.dir > 0 and i - 1 or i)
      local bx, bz = net.point(p, p.wp)
      local t = math.random()
      local x, z = ax + (bx - ax) * t, az + (bz - az) * t
      local dist = U.dist2d(x, z, near_x, near_z)
      if dist >= min_d and dist <= max_d and not engine.nearest(x, 1, z, 1.5) then return p, x, z end
    end
  end
end

-- ---- population ---------------------------------------------------------------

local function spawn_ped(near_x, near_z, min_d, max_d)
  if city.network() then
    local p, x, z = net.spawn(near_x, near_z, min_d, max_d)
    if not p then return end
    local id = engine.spawn{mesh = "ped" .. math.random(VARIANTS), pos = {x, 1.15, z}, size = {0.7, 1.8, 0.7},
                            body = "dynamic", mass = 70, friction = 0, step = 0.45, lock_rotation = true, tag = "ped"}
    H.set(id, 30)
    p.id, p.speed, p.state, p.stuck = id, WALK * (0.8 + math.random() * 0.4), "walk", 0
    set_target(p, net.point(p, p.wp))
    Ped.peds[id] = p
    return id
  end
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

-- Which way the road is from where ped `id` stands (a unit x, z), and
-- whether it's mid-block: on the pavement well away from any corner.
function Ped.curb(id)
  local p = Ped.peds[id]
  local x, _, z = engine.pos(id)
  if city.network() then
    local e = edges()[p.e]
    local best, cx, cz = math.huge, x, z
    for i = 2, #e.pts do
      local ax, az, bx, bz = e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]
      local dx, dz = bx - ax, bz - az
      local t = math.max(0, math.min(1, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
      local d = U.dist2d(x, z, ax + dx * t, az + dz * t)
      if d < best then best, cx, cz = d, ax + dx * t, az + dz * t end
    end
    local l = math.max(1e-6, U.dist2d(x, z, cx, cz))
    local jx, jz = city.pos(city.nearest(x, z))
    return (cx - x) / l, (cz - z) / l, U.dist2d(x, z, jx, jz) > 20
  end
  local bx, bz = city.block_center(p.i, p.j)
  local ex, ez = math.abs(x - bx) - (G.city.bx / 2 - 2.2), math.abs(z - bz) - (G.city.bz / 2 - 2.2)
  local mid = (math.abs(ex) < 1 and ez < -7) or (math.abs(ez) < 1 and ex < -7)
  if math.abs(x - bx) / G.city.bx > math.abs(z - bz) / G.city.bz then return x > bx and 1 or -1, 0, mid end
  return 0, z > bz and 1 or -1, mid
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
  local vx, vy, vz = engine.vel(id)
  -- Read the previous physics result before replacing velocity with AI intent.
  -- Sampling after set_vel always saw commanded walking speed, even at a wall.
  local actual_speed2 = vx * vx + vz * vz
  local mx, mz, speed
  if p.state == "flee" then
    if engine.time() > p.until_t then
      p.state = "walk"
      if city.network() then net.rejoin(p, x, z) return end
      p.i, p.j = block_of(x, z)
      p.k = nearest_corner(p, x, z)
      set_target(p, corner(p.i, p.j, p.k))
      return
    end
    mx, mz, speed = p.fx, p.fz, RUN
  else
    if U.dist2d(x, z, p.tx, p.tz) < 0.8 then
      if city.network() then net.next_leg(p) else next_leg(p) end
    end
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
  p.stuck = (speed > 0 and actual_speed2 < 0.1) and p.stuck + dt or 0
  if p.stuck > 2 and p.state == "walk" and city.network() then
    p.stuck = 0
    net.turn(p)
  elseif p.stuck > 2 and p.state == "walk" then
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

Ped.net = net
return Ped
