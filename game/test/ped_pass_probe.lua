-- Do two pedestrians meeting head-on get past each other, and stay on the
-- pavement while they do? Pairs are set walking toward each other, 10 m
-- apart, down the middle of clear, straight pavements near the player;
-- every other ped is cleared away. Prints per pair whether they passed, how
-- long they stood still and how close to the carriageway each came, then
-- PED_PASS_OK if every pair passed without stepping off the kerb. A pair that
-- something else sent running (a crash nearby) is not counted; at least
-- three must count.
local roadnet = require "lib.roadnet"
local U = require "lib.util"
local G = require "lib.state"
local Ped = require "systems.peds"

local PAIRS, RUN_FOR = tonumber(os.getenv("PED_PASS_PAIRS") or "8"), 16
local KERB = 0.3 -- a ped's middle at least this far from the road's edge

local pairs_, mine, t = nil, {}, 0

local function spawn(p, x, z)
  local id = engine.spawn{mesh = "ped1", pos = {x, 1.15 + U.ground(x, z), z}, size = {0.7, 1.8, 0.7},
                          body = "dynamic", mass = 70, friction = 0, step = 0.45, lock_rotation = true, tag = "ped"}
  p.id, p.speed, p.state, p.stuck = id, 1.4, "walk", 0
  p.tx, p.tz = Ped.net.point(p, p.wp)
  p.sx, p.sz = Ped.net.point(p, p.wp - p.dir)
  Ped.peds[id] = p
  mine[id] = true
  return id
end

-- Straight, clear pavements within reach of (px, pz).
local function setup(px, pz)
  local E, found = roadnet.net().edges, {}
  for ei, e in ipairs(E) do
    if #found >= PAIRS then break end
    if roadnet.walkable(ei) and not e.deck and not e.tunnel then
      for i = 2, #e.pts do
        local a, b = e.pts[i - 1], e.pts[i]
        local mx, mz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
        local len = U.dist2d(a[1], a[2], b[1], b[2])
        if len > 20 and U.dist2d(mx, mz, px, pz) < 120 then
          for _, h in ipairs{1, -1} do
            if roadnet.pavement(ei, h) then
              local p = {e = ei, dir = 1, hand = h, wp = i}
              local q = {e = ei, dir = -1, hand = -h, wp = i - 1}
              local ax, az = Ped.net.point(p, i - 1)
              local bx, bz = Ped.net.point(p, i)
              local dx, dz = (bx - ax) / len, (bz - az) / len
              local x0, z0 = mx - dx * 5, mz - dz * 5
              local x1, z1 = mx + dx * 5, mz + dz * 5
              local o = (e.width / 2 + roadnet.SIDEWALK / 2) * h
              x0, z0, x1, z1 = x0 + dz * o, z0 - dx * o, x1 + dz * o, z1 - dx * o
              -- Nothing standing on the line, and level enough to walk.
              local y0, y1 = U.ground(x0, z0), U.ground(x1, z1)
              local clear = math.abs(y1 - y0) < 1.5
                and not engine.raycast(x0 - dx * 4, y0 + 0.9, z0 - dz * 4, dx, (y1 - y0) / 18, dz, 18)
                and not engine.raycast(x0 - dx * 4, y0 + 0.3, z0 - dz * 4, dx, (y1 - y0) / 18, dz, 18)
              if clear then
                found[#found + 1] = {e = ei, a = a, dx = (b[1] - a[1]) / len, dz = (b[2] - a[2]) / len,
                                     half = e.width / 2, p = spawn(p, x0, z0), q = spawn(q, x1, z1),
                                     passed = false, still = 0, road = math.huge}
                goto next_edge
              end
            end
          end
        end
      end
    end
    ::next_edge::
  end
  return found
end

engine.on("tick", function(dt)
  if not G.city then return end
  if not roadnet.net() then
    print("PED_PASS_FAILED: the map has no road network (grid maps walk their blocks)")
    engine.quit()
    return
  end
  local px, _, pz = U.player_pos()
  if not px then return end
  -- Only the pairs walk: anyone else could get in the way.
  for id in pairs(Ped.peds) do
    if not mine[id] then
      engine.despawn(id)
      Ped.peds[id] = nil
    end
  end
  if not pairs_ then
    -- Turku starts by the river, out of reach of any pavement: go to the
    -- nearest one first.
    local best, bx, bz = math.huge
    for ei, e in ipairs(roadnet.net().edges) do
      if roadnet.walkable(ei) and not e.deck and not e.tunnel then
        for i = 2, #e.pts do
          local a, b = e.pts[i - 1], e.pts[i]
          local mx, mz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
          local d = U.dist2d(mx, mz, px, pz)
          if d < best and U.dist2d(a[1], a[2], b[1], b[2]) > 20 then best, bx, bz = d, mx, mz end
        end
      end
    end
    if best > 60 and bx then
      local id = G.vehicle or G.player
      engine.set_pos(id, bx, U.ground(bx, bz) + 30, bz) -- high above the road: out of the pairs' way
      engine.set_vel(id, 0, 0, 0)
      px, pz = bx, bz
    end
    pairs_ = setup(px, pz)
    if #pairs_ == 0 then
      print("PED_PASS_FAILED: no clear straight pavement near the player")
      engine.quit()
    end
    return
  end
  t = t + dt
  for _, s in ipairs(pairs_) do
    -- Something else (a crash in the traffic nearby) sent them running:
    -- that pair no longer tells anything about passing.
    for _, id in ipairs{s.p, s.q} do
      if not Ped.peds[id] or Ped.peds[id].state == "flee" then s.scared = true end
    end
    if not s.scared and engine.exists(s.p) and engine.exists(s.q) then
      local along, side = {}, {}
      for k, id in ipairs{s.p, s.q} do
        local x, _, z = engine.pos(id)
        local rx, rz = x - s.a[1], z - s.a[2]
        along[k] = rx * s.dx + rz * s.dz
        side[k] = math.abs(rz * s.dx - rx * s.dz) -- from the road's middle
        local vx, _, vz = engine.vel(id)
        if vx * vx + vz * vz < 0.05 then s.still = s.still + dt / 2 end
      end
      if along[1] > along[2] + 0.5 then s.passed = s.passed or t end
      -- Only while both are still on this stretch.
      if not s.passed or t - s.passed < 2 then
        s.road = math.min(s.road, side[1] - s.half, side[2] - s.half)
      end
    end
  end
  if t < RUN_FOR then return end
  local ok, n = true, 0
  for k, s in ipairs(pairs_) do
    local good = s.scared or (s.passed and s.road >= KERB)
    ok, n = ok and good, n + (s.scared and 0 or 1)
    if s.scared then print(string.format("ped pair %d (edge %d): scared off, not counted", k, s.e)) goto next_pair end
    print(string.format("ped pair %d (edge %d): %s%s, still %.1f s, nearest the road %.2f m from the kerb%s", k, s.e,
                        s.passed and "passed after " or "did not pass", s.passed and string.format("%.1f s", s.passed) or "",
                        s.still, s.road, good and "" or "  FAIL"))
    ::next_pair::
  end
  ok = ok and n >= 3
  print(ok and "PED_PASS_OK pairs=" .. n or "PED_PASS_FAILED pairs=" .. n)
  engine.quit()
end)
