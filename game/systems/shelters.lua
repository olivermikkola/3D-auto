-- Föli bus shelters at the map's bus stops (OpenStreetMap highway=bus_stop,
-- lib/pois): a glass shelter with a bench at the back of the pavement,
-- facing the road, and the stop's sign by it. The waiting passengers of
-- systems/busroute stand in front, at the kerb.
--
-- Put up once the world has had its first physics step, so rays can see
-- what's there: only where the space behind the kerb is free (no wall,
-- tree, lamp or other road) and the ground is about level; a stop with no
-- room gets none, as many in the old town have none.
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local pois = require "lib.pois"
local quality = require "lib.quality"

local S = {list = {}} -- list: {id, x, z, yaw, stop name}

local W, H, D = 3.6, 2.5, 1.3 -- the shelter's length along the road, height, depth
local FROM_KERB = 1.75         -- its front edge, from the kerb: people walk the pavement's middle (1.5 m)
local NEAR = 8                 -- how far off its road a stop may be (beyond the road's half width)
local SHIFTS = {0, 3, -3, 6, -6, 9, -9} -- along the road from the stop, to find room

local IGNORE = {ped = true, car = true, player = true, cop = true, bus = true, pickup = true, sidewalk = true}

local function mesh()
  local frame, glass, roof = {0.2, 0.21, 0.23}, {0.62, 0.74, 0.8}, {0.3, 0.31, 0.33}
  local yellow, wood, ad = {0.95, 0.82, 0.08}, {0.55, 0.36, 0.2}, {0.9, 0.42, 0.55}
  local y0 = -H / 2 -- parts from the foot; the entity stands at its middle
  local parts = {
    -- back and sides of glass in a dark frame
    {mesh = "cube", pos = {0, y0 + 1.25, -D / 2 + 0.05}, size = {W - 0.1, 1.9, 0.04}, color = glass, emissive = 0.15},
    {mesh = "cube", pos = {-W / 2 + 0.05, y0 + 1.25, -0.2}, size = {0.04, 1.9, D - 0.5}, color = glass, emissive = 0.15},
    -- one end an advert, lit at night
    {mesh = "cube", pos = {W / 2 - 0.05, y0 + 1.25, -0.2}, size = {0.08, 1.9, D - 0.5}, color = ad, emissive = 0.5},
    {mesh = "cube", pos = {0, y0 + 0.28, -D / 2 + 0.05}, size = {W, 0.08, 0.08}, color = frame},
    {mesh = "cube", pos = {0, y0 + 2.22, -D / 2 + 0.05}, size = {W, 0.08, 0.08}, color = frame},
    -- the roof, a little forward, with a yellow Föli edge
    {mesh = "cube", pos = {0, y0 + 2.38, 0.05}, size = {W + 0.3, 0.1, D + 0.2}, color = roof},
    {mesh = "cube", pos = {0, y0 + 2.33, D / 2 + 0.16}, size = {W + 0.3, 0.2, 0.05}, color = yellow},
    -- a bench along the back
    {mesh = "cube", pos = {0, y0 + 0.48, -D / 2 + 0.33}, size = {W - 1.0, 0.06, 0.42}, color = wood},
    {mesh = "cube", pos = {-(W - 1.4) / 2, y0 + 0.24, -D / 2 + 0.33}, size = {0.06, 0.46, 0.36}, color = frame},
    {mesh = "cube", pos = {(W - 1.4) / 2, y0 + 0.24, -D / 2 + 0.33}, size = {0.06, 0.46, 0.36}, color = frame},
  }
  for _, x in ipairs{-W / 2 + 0.05, W / 2 - 0.05} do
    for _, z in ipairs{-D / 2 + 0.05, D / 2 - 0.1} do
      parts[#parts + 1] = {mesh = "cube", pos = {x, y0 + 1.17, z}, size = {0.08, 2.34, 0.08}, color = frame}
    end
  end
  -- The stop's sign on its pole at the front corner, up the road.
  parts[#parts + 1] = {mesh = "cube", pos = {-W / 2 - 0.45, y0 + 1.4, D / 2 - 0.1}, size = {0.07, 2.8, 0.07}, color = frame}
  parts[#parts + 1] = {mesh = "cube", pos = {-W / 2 - 0.45, y0 + 2.55, D / 2 - 0.1}, size = {0.06, 0.5, 0.5}, color = yellow, emissive = 0.2}
  parts[#parts + 1] = {mesh = "cube", pos = {-W / 2 - 0.45, y0 + 2.55, D / 2 - 0.1}, size = {0.07, 0.22, 0.32}, color = {0.12, 0.12, 0.14}}
  engine.mesh("shelter", parts)
end

-- Nothing in the way from the kerb to behind the shelter's back, at knee
-- and head height, along its length?
local function room(x, y, z, fx, fz, nx, nz, kerb)
  for _, a in ipairs{-W / 2 - 0.5, 0, W / 2 + 0.2} do
    for _, h in ipairs{0.6, 2.0} do
      local ox, oz = x + fx * a + nx * (kerb - 0.2), z + fz * a + nz * (kerb - 0.2)
      local reach = FROM_KERB + D + 0.6
      local hit, d = engine.raycast(ox, y + h, oz, nx, 0, nz, reach)
      while hit and IGNORE[engine.tag(hit)] do -- (someone walking by isn't a wall)
        local d2
        hit, d2 = engine.raycast(ox + nx * (d + 0.05), y + h, oz + nz * (d + 0.05), nx, 0, nz, reach - d - 0.05, hit)
        d = hit and d + 0.05 + d2
      end
      if hit then return false end
    end
  end
  return true
end

-- Where a shelter goes for the stop at (x, z), if anywhere: x, z, ground y, yaw.
local function site(x, z)
  local ei, si, cx, cz, d = roadnet.nearest_edge(x, z, true)
  local e = ei and roadnet.net().edges[ei]
  if not e or e.tunnel or e.height or d > e.width / 2 + NEAR then return end
  local a, b = e.pts[si - 1], e.pts[si]
  local len = U.dist2d(a[1], a[2], b[1], b[2])
  if len < 1 then return end
  local fx, fz = (b[1] - a[1]) / len, (b[2] - a[2]) / len
  -- Which side the stop's on.
  local nx, nz = fz, -fx
  if (x - cx) * nx + (z - cz) * nz < 0 then nx, nz = -nx, -nz end
  local kerb = e.width / 2
  local o = kerb + FROM_KERB + D / 2
  for _, s in ipairs(SHIFTS) do
    local px, pz = cx + fx * s + nx * o, cz + fz * s + nz * o
    -- On the same road all along, clear of every other one.
    local ok = true
    for _, c in ipairs{{-W / 2 - 0.6, D / 2}, {W / 2, D / 2}, {-W / 2 - 0.6, -D / 2}, {W / 2, -D / 2}, {0, D / 2}} do
      local qx, qz = px + fx * c[1] + nx * c[2], pz + fz * c[1] + nz * c[2]
      local qi, _, _, _, qd = roadnet.nearest_edge(qx, qz)
      local q = qi and roadnet.net().edges[qi]
      if q and qd < q.width / 2 + 1.2 then ok = false break end
    end
    if ok then
      local y = U.ground(px, pz)
      for _, c in ipairs{{-W / 2, -D / 2}, {W / 2, -D / 2}, {-W / 2, D / 2}, {W / 2, D / 2}} do
        if math.abs(U.ground(px + fx * c[1] + nx * c[2], pz + fz * c[1] + nz * c[2]) - y) > 0.5 then ok = false break end
      end
      ok = ok and not engine.nearest(px, y, pz, W / 2 + 1.2, "lamp") and not engine.nearest(px, y, pz, W / 2 + 1.2, "signal")
      local rx, rz = cx + fx * s, cz + fz * s
      if ok and room(rx, y, rz, fx, fz, nx, nz, kerb) then
        return px, pz, y, math.atan(-nx, -nz)
      end
    end
  end
end

function S.build()
  mesh()
  S.pending = city.network() ~= nil and quality.tier() > 1
end

-- None on the lowest quality: taken down when it's picked, put up again
-- when it's raised.
local function take_down()
  for _, s in ipairs(S.list) do
    if engine.exists(s.id) then engine.despawn(s.id) end
  end
  S.list = {}
end
quality.watch(function(tier)
  if tier == 1 then take_down(); S.pending = false
  elseif #S.list == 0 and city.network() and S.pending == false then S.pending = true end
end)

local function put_up()
  local stops = {}
  for _, p in ipairs(pois.find{highway = "bus_stop", road = false}) do stops[#stops + 1] = p end
  table.sort(stops, function(a, b) return a.x < b.x or (a.x == b.x and a.z < b.z) end)
  for _, p in ipairs(stops) do
    local x, z, y, yaw = site(p.x, p.z)
    local near = false
    for _, s in ipairs(S.list) do
      if x and U.dist2d(s.x, s.z, x, z) < 12 then near = true break end
    end
    if x and not near then
      local id = engine.spawn{mesh = "shelter", pos = {x, y + H / 2, z}, yaw = yaw, size = {W, H, D},
                              tag = "shelter", body = "static"}
      S.list[#S.list + 1] = {id = id, x = x, z = z, yaw = yaw, name = p.name}
    end
  end
  print(string.format("shelters: %d at %d bus stops", #S.list, #stops))
end

engine.on("tick", function()
  if S.pending and engine.ticks() > 1 then
    S.pending = false
    put_up()
  end
end)

return S
