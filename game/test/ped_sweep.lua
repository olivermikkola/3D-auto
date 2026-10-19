-- Pedestrian sweep: a walker down the pavement of every road of the map
-- (each side that has one), walking as the crowd does, and a note of
-- everywhere one gets into trouble (and on a bridge, another from the
-- middle of its deck): blocked (stood still, then turned
-- back), below its pavement (under a bridge's deck, in the river), off the
-- pavement for a while (out on the asphalt, or into a yard), or not at the
-- far end in time. Spots within 15 m of each other are one problem. Prints
-- them worst first. PED_SWEEP=1 (PED_SWEEP_EVERY=n: every nth road only;
-- PED_SWEEP_MAX=n: the first n; PED_SWEEP_NEAR="x,z,r": roads starting
-- within r m of x, z).
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local peds = require "systems.peds"
local traffic = require "systems.traffic"

local BATCH, SLACK = 80, 2 -- walkers at once; time allowed = SLACK * length / walking speed + 10
local OFF_FOR = 2 -- seconds off the pavement before it counts

local todo, next_i, live, trouble, t0, started = {}, 1, {}, {}, nil, false
local function note(kind, x, y, z, e, what)
  trouble[#trouble + 1] = {kind = kind, x = x, y = y, z = z, e = e, what = what or "nothing"}
end

-- Metres from (x, z) to the middle of road e's carriageway.
local function from_middle(e, x, z)
  local pts, best = roadnet.net().edges[e].pts, math.huge
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    local dx, dz = b[1] - a[1], b[2] - a[2]
    local t = U.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / math.max(dx * dx + dz * dz, 1e-6), 0, 1)
    best = math.min(best, U.dist2d(x, z, a[1] + dx * t, a[2] + dz * t))
  end
  return best
end

local function launch(d)
  local e = roadnet.net().edges[d.e]
  -- From 3 m in, or on a bridge also from its middle bend (up on the deck).
  local k = d.mid and math.max(2, (#e.pts + 1) // 2) or 2
  local p = {e = d.e, dir = 1, hand = d.hand, wp = k}
  local ax, az = peds.net.point(p, k - 1)
  local bx, bz = peds.net.point(p, k)
  local seg = U.dist2d(ax, az, bx, bz)
  local t = d.mid and 0.5 or math.min(3, seg / 2) / math.max(seg, 1e-3)
  local x, z = ax + (bx - ax) * t, az + (bz - az) * t
  local len = 0
  for i = 2, #e.pts do len = len + U.dist2d(e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]) end
  local id = peds.add(p, x, z)
  live[id] = {p = p, e = d.e, born = engine.time(), limit = SLACK * len / 1.1 + 10, off = 0}
end

local function finish()
  local groups = {}
  for _, t in ipairs(trouble) do
    local g
    for _, o in ipairs(groups) do
      if U.dist2d(o.x, o.z, t.x, t.z) < 15 then g = o; break end
    end
    if not g then g = {x = t.x, z = t.z, y = t.y, n = 0, kinds = {}, whats = {}}; groups[#groups + 1] = g end
    g.n = g.n + 1
    g.kinds[t.kind] = (g.kinds[t.kind] or 0) + 1
    g.whats[t.what] = true
  end
  table.sort(groups, function(p, q) return p.n > q.n end)
  local kinds = {}
  for _, t in ipairs(trouble) do kinds[t.kind] = (kinds[t.kind] or 0) + 1 end
  for i, g in ipairs(groups) do
    local ks, ws = {}, {}
    for k, v in pairs(g.kinds) do ks[#ks + 1] = k .. " " .. v end
    for w in pairs(g.whats) do ws[#ws + 1] = w end
    table.sort(ks)
    table.sort(ws)
    local street, area = roadnet.where(g.x, g.z)
    print(string.format("PED_SWEEP #%d at %.0f, %.0f (y %.1f): %d walkers: %s; near %s; %s, %s", i, g.x, g.z, g.y, g.n,
      table.concat(ks, ", "), table.concat(ws, "/"), street or "?", area or "?"))
  end
  local ks = {}
  for k, v in pairs(kinds) do ks[#ks + 1] = k .. " " .. v end
  table.sort(ks)
  print("PED_SWEEP: by kind: " .. table.concat(ks, ", "))
  print(string.format("PED_SWEEP: %d walks, %d in trouble at %d spots, %.0f s", #todo, #trouble, #groups, os.clock() - t0))
  print("PED_SWEEP: PASSED")
  engine.quit()
end

-- What each walker last bumped into (not the ground it walks on).
local GROUND = {terrain = true, road = true, ground = true}
engine.on("contact", function(a, b)
  for _, q in ipairs{{a, b}, {b, a}} do
    local s, tag = live[q[1]], engine.tag(q[2])
    if s and tag and not GROUND[tag] then s.hit, s.hit_at = tag, engine.time() end
  end
end)

engine.on("tick", function(dt)
  if not started then
    if engine.time() < 0.5 then return end
    started, t0 = true, os.clock()
    if not city.network() then print("PED_SWEEP: grid map, nothing to sweep"); print("PED_SWEEP: PASSED"); engine.quit(); return end
    -- Nobody else about: no traffic, no crowd but the sweep's.
    for id in pairs(traffic.cars) do engine.despawn(id) end
    traffic.cars, traffic.target = {}, nil
    for id in pairs(peds.peds) do engine.despawn(id) end
    peds.peds, peds.hold = {}, true
    local near = os.getenv("PED_SWEEP_NEAR")
    local nx, nz, nr
    if near then
      nx, nz, nr = near:match("([-%d.]+),([-%d.]+),([%d.]+)")
      nx, nz, nr = tonumber(nx), tonumber(nz), tonumber(nr)
    end
    for ei, e in ipairs(roadnet.net().edges) do
      if roadnet.walkable(ei) and (not nx or U.dist2d(e.pts[1][1], e.pts[1][2], nx, nz) <= nr) then
        for _, hand in ipairs{1, -1} do
          if roadnet.pavement(ei, hand) then
            todo[#todo + 1] = {e = ei, hand = hand}
            if e.height then todo[#todo + 1] = {e = ei, hand = hand, mid = true} end
          end
        end
      end
    end
    local every = tonumber(os.getenv("PED_SWEEP_EVERY") or "")
    if every then
      local keep = {}
      for i = 1, #todo, every do keep[#keep + 1] = todo[i] end
      todo = keep
    end
    local most = tonumber(os.getenv("PED_SWEEP_MAX") or "")
    if most then for i = #todo, most + 1, -1 do todo[i] = nil end end
    return
  end

  local n = 0
  for _ in pairs(live) do n = n + 1 end
  while n < BATCH and next_i <= #todo do
    launch(todo[next_i])
    next_i, n = next_i + 1, n + 1
  end
  local now = engine.time()
  for id, s in pairs(live) do
    local p, kind, what = s.p, nil, nil
    local x, y, z = engine.pos(id)
    if not x or not peds.peds[id] then
      kind = "gone"
    elseif p.e ~= s.e then
      -- On to the next road: this one walked.
    else
      local age = now - s.born
      local floor = peds.pavement_y(p.e, x, z)
      if os.getenv("PED_SWEEP_TRACE") then
        s.tr = (s.tr or 0) + dt
        if s.tr >= 0.25 then
          s.tr = 0
          local vx, vy, vz = engine.vel(id)
          print(string.format("TRACE %d e%d t=%.2f pos %.2f %.2f %.2f floor %.2f ground %.2f v %.2f %.2f %.2f target %.1f %.1f stuck %.2f hit %s",
            id, p.e, age, x, y, z, floor, U.ground(x, z), vx, vy, vz, p.tx, p.tz, p.stuck, tostring(s.hit)))
        end
      end
      local edge = roadnet.net().edges[p.e]
      local mid = from_middle(p.e, x, z)
      -- On the asphalt (more than half a metre in from the kerb), or out
      -- beyond the pavement's far side.
      local off = mid < edge.width / 2 - 0.5 or mid > edge.width / 2 + roadnet.SIDEWALK + 1.5
      s.off = off and s.off + dt or 0
      if age > 1 and y < floor + 0.9 - 1 then
        kind = "below its pavement"
      elseif p.dir ~= 1 and (s.stuck or 0) < 1.5 then
        -- Turned back at a dead end: the end of this road, walked.
      elseif p.dir ~= 1 then
        kind = "blocked" -- stood still, then turned back
        what = s.hit and now - s.hit_at < 3 and s.hit or nil
        if os.getenv("PED_SWEEP_WHY") and what == "lamp" then
          local l = engine.nearest(x, y, z, 3, "lamp")
          local lx, _, lz = engine.pos(l)
          local e = roadnet.net().edges[p.e]
          print(string.format("WHY ped %.2f,%.2f leg %.1f,%.1f -> %.1f,%.1f lamp %.2f,%.2f (%.2f from road middle; ped %.2f) width %.1f hand %d",
            x, z, p.sx or -1, p.sz or -1, p.tx, p.tz, lx, lz, from_middle(p.e, lx, lz), from_middle(p.e, x, z), e.width, p.hand))
        end
      elseif s.off > OFF_FOR then
        kind = mid < edge.width / 2 and "on the road" or "off the pavement"
      elseif age > s.limit then
        kind = "too slow"
      else
        s.stuck = p.stuck
        goto continue
      end
    end
    if kind and kind ~= "gone" then note(kind, x, y, z, s.e, what) end
    if engine.exists(id) then engine.despawn(id) end
    peds.peds[id] = nil
    live[id] = nil
    ::continue::
  end
  if next_i > #todo and next(live) == nil then finish() end
end)
