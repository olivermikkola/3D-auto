-- People waiting at the Föli shelters (systems/shelters), and the buses in
-- traffic that stop for them.
--
-- Shelters near the player get a few people standing in front, between the
-- shelter and the kerb, looking at the road: browsers (systems/peds) whose
-- only spots are that stop's, so a car can knock them over and a fright
-- sends them running, and they come back to wait. A Föli bus coming along
-- the road pulls in with its front door by them and stands with the doors
-- open: they walk to the door and get on, and now and then someone gets
-- off and walks away. A stop that has been served stays empty a while.
local U = require "lib.util"
local shelters = require "systems.shelters"

local B = {}
B.NEAR, B.FAR = 140, 170 -- m: shelters within NEAR of the player fill up; beyond FAR they empty
B.APPEAR = 60            -- m: not closer than this (they'd pop up in view)
B.DOORS = 8              -- s: a bus stands at a stop this long
B.SERVED = 120           -- s: a stop the bus has been to stays empty this long
B.DOOR = 4.5             -- m: the front door, ahead of the bus's middle
B.boarded, B.alighted, B.stops_made = 0, 0, 0

local function peds() return require "systems.peds" end

-- How many wait at a shelter, 0-3, from its place and how many times it
-- has filled (the same every run).
local function how_many(s)
  return math.floor(math.sin(s.x * 12.9898 + s.z * 78.233 + (s.fills or 0) * 3.7) * 43758.5453 % 1 * 4)
end

-- Three places in front of shelter s, between it and the kerb, looking at
-- the road and a little up it (the way the bus comes: its sign's side).
local function spots_for(s)
  local fx, fz = math.sin(s.yaw), math.cos(s.yaw) -- to the road
  local lx, lz = math.cos(s.yaw), -math.sin(s.yaw) -- the shelter's +x (its sign's at -x, up the road)
  local out = shelters.D / 2 + 0.8
  local spots = {taken = {}}
  for i, a in ipairs{-1.1, 0.2, 1.4} do
    local x, z = s.x + fx * out + lx * a, s.z + fz * out + lz * a
    spots[i] = {x, z, s.yaw - 0.35 - 0.15 * i, U.ground(x, z)}
  end
  return spots
end

local function alive(s)
  local n = 0
  for _, id in ipairs(s.people or {}) do
    if peds().peds[id] then n = n + 1 end
  end
  return n
end

local function empty(s)
  for _, id in ipairs(s.people or {}) do
    if peds().peds[id] then
      peds().peds[id] = nil
      engine.despawn(id)
    end
  end
  s.people = nil
end

-- A stop with people waiting ahead of a bus at (x, z) heading (fx, fz),
-- on its right, facing the road: the shelter, or nil.
function B.ahead(x, z, fx, fz)
  local rx, rz = -fz, fx -- (U.right)
  local now = engine.time()
  for _, s in ipairs(shelters.list) do
    if s.people and now > (s.served or 0) then
      local dx, dz = s.x - x, s.z - z
      local along, side = dx * fx + dz * fz, dx * rx + dz * rz
      if along > B.DOOR and along < 45 and side > 2 and side < 14
        and math.sin(s.yaw) * rx + math.cos(s.yaw) * rz < -0.7 and alive(s) > 0 then
        return s
      end
    end
  end
end

-- Bus `bus` stands at stop s with its doors open: those waiting go to the
-- front door and get on; now and then one or two get off.
function B.board(s, bus)
  local P = peds()
  local x, _, z = engine.pos(bus)
  local fx, fz = U.forward(engine.yaw(bus))
  local rx, rz = -fz, fx
  local dx, dz = x + fx * B.DOOR + rx * 1.8, z + fz * B.DOOR + rz * 1.8
  for _, id in ipairs(s.people or {}) do
    local p = P.peds[id]
    if p then
      p.to = {dx, dz}
      p.arrive = function(pid)
        P.peds[pid] = nil
        engine.despawn(pid)
        B.boarded = B.boarded + 1
      end
    end
  end
  s.served, s.people = engine.time() + B.SERVED, nil
  B.stops_made = B.stops_made + 1
  for i = 1, math.floor(math.sin(x * 3.1 + z * 7.7) * 43758.5453 % 1 * 3) do
    local p, px, pz = P.net.spawn(dx + rx * i * 0.6, dz + rz * i * 0.6, 0, 6)
    if p then
      P.add(p, px, pz)
      B.alighted = B.alighted + 1
    end
  end
end

local wait = 0
engine.on("tick", function(dt)
  wait = wait - dt
  if wait > 0 or #shelters.list == 0 then return end
  wait = 1
  -- (A still picture has one frame: filled at once around its camera.)
  local still = os.getenv("SHOT_CAM")
  local x, _, z = U.player_pos()
  if still then x, z = still:match("^([^,]+),[^,]+,([^,]+)") end
  x, z = tonumber(x), tonumber(z)
  if not x then return end
  local now = engine.time()
  for _, s in ipairs(shelters.list) do
    local d = U.dist2d(x, z, s.x, s.z)
    if s.people then
      if d > B.FAR then empty(s) end
    elseif d < B.NEAR and (still or d > B.APPEAR) and now > (s.served or 0) then
      s.spots = s.spots or spots_for(s)
      s.people, s.fills = {}, (s.fills or 0) + 1
      for k = 1, how_many(s) do
        s.people[k] = peds().add_browser(s.spots, k)
      end
    end
  end
end)

return B
