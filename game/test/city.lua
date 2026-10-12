-- Whatever map is loaded (MAP=<name>): its layout (land, park, road graph,
-- skyline), its landmarks, and a drive up the car park if it has one:
-- every ramp is climbed with the real car controls, then off the roof kicker.
-- CITY_TEST=1 auto game --headless 2400
local G = require "lib.state"
local city = require "lib.city"
local vehicle = require "lib.vehicle"
local landmarks = require "lib.landmarks"

local held = {}
engine.key = function(k) return held[k] == true end
local function check(ok, what)
  if not ok then engine.quit(); error("CITY TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local car, stage, t0, stunts, peak = nil, 0, 0, 0, 0
local cx, cz, D, CURB

-- Put the car somewhere, pointing somewhere, at rest.
local function place(x, y, z, yaw)
  engine.set_pos(car, x, y + 0.8, z)
  engine.orient(car, yaw)
  engine.set_vel(car, 0, 0, 0)
  engine.set_angvel(car, 0, 0, 0)
  held = {w = true}
end

engine.on("stunt", function() stunts = stunts + 1 end)

-- Height of whatever solid is at (x, z), from a ray dropped from above.
local function top_at(x, z)
  local _, d = engine.raycast(x, 400, z, 0, -1, 0, 400)
  return d and 400 - d or 0
end

-- Minimums for the maps we ship, beyond what any map must pass. A map
-- without an entry just has to have one of each thing its data asks for.
local EXPECT = {
  raisio = {buildings = 200, houses = 150, apartments = 35, warehouses = 2, trees = 1400, lamps = 110},
  manhattan = {
    downtown = 40, residential = 30, over_100m = 15, peak_top = 140, terraces = 30, deco = 5, warehouses = 10,
    containers = 8, rooftop = 40, billboards = 20, park_trees = 150,
  },
}

-- A grid map: its districts, road graph, skyline and what the blocks are
-- made of. Returns the top of each skyline peak.
local function grid_layout(L, M, want, at_least)
  -- Districts: the land, the park and every district the rules name.
  local count, water = {}, 0
  for i = 0, L.NX - 1 do
    for j = 0, L.NZ - 1 do
      local d = city.district(i, j)
      count[d] = (count[d] or 0) + 1
    end
  end
  for j = 0, L.NZ - 1 do
    local r = M.land and M.land[j]
    if r then water = water + L.NX - (r[2] - r[1] + 1) end
  end
  check((count.water or 0) == water, (count.water or 0) .. " blocks of river, as the map's outline says")
  if M.park then
    local P = M.park
    check(count.park == (P.i1 - P.i0 + 1) * (P.j1 - P.j0 + 1), "the park takes its " .. count.park .. " blocks")
  end
  local named = {}
  for _, r in ipairs(M.districts or {}) do
    if not named[r[1]] then
      named[r[1]] = true
      check((count[r[1]] or 0) > 0, string.format("%d %s blocks", count[r[1]] or 0, r[1]))
    end
  end
  at_least("downtown", count.downtown or 0, "downtown blocks")
  if want.residential then at_least("residential", count.residential or 0, "residential blocks") end

  -- The road graph: one piece, the park crossed only by its transverse,
  -- and nothing built on any of it.
  local nodes = city.nodes()
  local sk, sl = city.nearest_node(city.place("lot"))
  local seen, queue, n = {[sk .. "," .. sl] = true}, {{sk, sl}}, 0
  while #queue > 0 do
    local q = table.remove(queue)
    n = n + 1
    for _, nb in ipairs(city.neighbors(q[1], q[2])) do
      local key = nb[1] .. "," .. nb[2]
      if not seen[key] then seen[key] = true; queue[#queue + 1] = nb end
    end
  end
  check(n == #nodes, string.format("every one of the %d intersections is reachable by road", #nodes))
  if M.park then
    local P = M.park
    check(city.road(P.i0, P.transverse, 1, 0), "a transverse road crosses the park")
    if P.j1 - P.j0 >= 2 then
      local l = P.transverse == P.j0 + 1 and P.j0 + 2 or P.j0 + 1
      check(not city.road(P.i0, l, 1, 0), "the park's other inner streets are gone")
    end
  end
  local solid = {building = true, container = true, landmark = true, wall = true, tree = true, lamp = true, carpark = true,
                 ramp = true, fountain = true}
  local blocked = 0
  for _, sg in ipairs(city.segments()) do
    local ax, az = city.node(sg[1], sg[2])
    local bx, bz = city.node(sg[1] + sg[3], sg[2] + sg[4])
    local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    for _, lane in ipairs{-3.2, 0, 3.2} do
      local ox, oz = ax + sg[4] * lane, az + sg[3] * lane
      local hit = engine.raycast(ox, 1, oz, (bx - ax) / len, 0, (bz - az) / len, len)
      if hit and solid[engine.tag(hit)] then
        blocked = blocked + 1
        if blocked <= 3 then print(string.format("    blocked: %s at segment %d,%d +%d,%d", engine.tag(hit), sg[1], sg[2], sg[3], sg[4])) end
      end
    end
  end
  check(blocked == 0, string.format("all %d road segments are clear to drive, in both lanes", #city.segments()))
  local edge
  for l = 0, L.NZ do if city.on_road(0, l) then edge = edge or l end end
  local sx, sz = city.node(0, edge)
  local hit = engine.raycast(sx, 1, sz, -1, 0, 0, 30)
  check(hit and engine.tag(hit) == "wall", "a wall at the shore keeps cars out of the river")

  -- The skyline: the tallest buildings stand under the map's peaks, well
  -- above the low-rise parts of town.
  local low, low_n, over_100, peak_tops = 0, 0, 0, {}
  for _, id in ipairs(engine.find("building")) do
    local x, _, z = engine.pos(id)
    local h = top_at(x, z)
    if h > 100 then over_100 = over_100 + 1 end
    if city.height(x, z) == 0 then low, low_n = low + h, low_n + 1 end
    for k, p in ipairs(M.skyline and M.skyline.peaks or {}) do
      local dx, dz = x - (L.ox + p.k * L.PX), z - (L.oz + p.l * L.PZ)
      if (dx / p.rx) ^ 2 + (dz / p.rz) ^ 2 < 0.25 then peak_tops[k] = math.max(peak_tops[k] or 0, h) end
    end
  end
  local avg_low = low / math.max(1, low_n)
  for k, top in pairs(peak_tops) do
    check(top > 2.5 * avg_low and top > (want.peak_top or 0) * (M.skyline.peaks[k].weight),
          string.format("peak %d tops out at %.0f m over a low-rise average of %.0f m", k, top, avg_low))
  end
  if want.over_100m then at_least("over_100m", over_100, "buildings over 100 m") end

  -- What the blocks are made of, for each thing the map asks for.
  local terraces, sheds, decos = 0, 0, 0
  for _, id in ipairs(engine.find("building")) do
    local m = engine.mesh_of(id) or ""
    if m:find("^lot_") then terraces = terraces + 1
    elseif m:find("^warehouse") then sheds = sheds + 1
    elseif m:find("^deco") then decos = decos + 1 end
  end
  if count.residential then at_least("terraces", terraces, "terraces of brownstones") end
  if count.industrial then
    at_least("warehouses", sheds, "warehouses in the yards")
    at_least("containers", #engine.find("container"), "yards of shipping containers")
  end
  if want.deco then at_least("deco", decos, "Art Deco setback towers") end
  at_least("rooftop", #engine.find("rooftop"), "water towers on the roofs")
  if M.billboards then at_least("billboards", #engine.find("billboard"), "billboards") end
  local P, trees = L.park_area, 0
  if P then
    for _, id in ipairs(engine.find("tree")) do
      local x, _, z = engine.pos(id)
      if x > P.x0 and x < P.x1 and z > P.z0 and z < P.z1 then trees = trees + 1 end
    end
    at_least("park_trees", trees, "trees in the park")
  end

  return peak_tops
end

-- A map drawn as roads: every lane of every road clear to drive, a wall
-- at the shore, and enough of everything built along the roads.
local function road_layout(L, M, want, at_least)
  local solid = {building = true, container = true, landmark = true, wall = true, tree = true, lamp = true, carpark = true,
                 ramp = true, fountain = true}
  local roadnet = require "lib.roadnet"
  local blocked, segs = 0, 0
  for _, e in ipairs(roadnet.net().edges) do
    for i = 2, #e.pts do
      local ax, az, bx, bz = e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]
      local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
      local fx, fz = (bx - ax) / len, (bz - az) / len
      segs = segs + 1
      for _, lane in ipairs{-3.2, 0, 3.2} do
        local hit, _, hx, _, hz = engine.raycast(ax + fz * lane, 1, az - fx * lane, fx, 0, fz, len)
        if hit and solid[engine.tag(hit)] then
          blocked = blocked + 1
          if blocked <= 3 then
            print(string.format("    blocked: %s %s on %s at (%.0f, %.0f)", engine.tag(hit), engine.mesh_of(hit) or "", e.name, hx, hz))
          end
        end
      end
    end
  end
  check(blocked == 0, string.format("all %d stretches of road are clear to drive, in both lanes", segs))
  local west, wx, wz = math.huge
  for _, j in ipairs(city.junctions()) do
    local x, z = city.pos(j)
    if x < west then west, wx, wz = x, x, z end
  end
  local hit = engine.raycast(wx, 1, wz, -1, 0, 0, 60)
  check(hit and engine.tag(hit) == "wall", "a wall at the shore keeps cars out of the sea")
  local houses, apartments, sheds = 0, 0, 0
  for _, id in ipairs(engine.find("building")) do
    local m = engine.mesh_of(id) or ""
    if m:find("^house") then houses = houses + 1
    elseif m:find("^warehouse") then sheds = sheds + 1
    elseif m:find("^brick") or m:find("^glass") then apartments = apartments + 1 end
  end
  at_least("buildings", #engine.find("building"), "buildings")
  at_least("houses", houses, "detached houses with pitched roofs")
  at_least("apartments", apartments, "apartment and office blocks")
  at_least("warehouses", sheds, "warehouses")
  at_least("trees", #engine.find("tree"), "trees")
  at_least("lamps", #engine.find("lamp"), "street lamps")
  return {}
end

local function setup()
  local L, M = G.city, city.map()
  local want = EXPECT[L.map] or {}
  local function at_least(key, n, what)
    local need = want[key] or 1
    check(n >= need, string.format("%d %s (at least %d)", n, what, need))
  end
  print("  map: " .. M.name)

  local peak_tops = city.network() and road_layout(L, M, want, at_least) or grid_layout(L, M, want, at_least)

  -- Landmarks, for the ones the map has.
  local sp = M.specials
  local expected = (sp.tower and 1 or 0) + (sp.empire and 1 or 0) + (sp.carpark and 1 or 0)
  check(#L.landmarks == expected, #L.landmarks .. " landmarks, one for each the map places")
  if sp.tower then
    local tx, tz = city.place("tower")
    hit = engine.raycast(tx - 20, 60, tz, 1, 0, 0, 40)
    check(hit and engine.tag(hit) == "landmark", "the TV tower is solid at 60 m up")
  end
  if sp.empire then
    local ex, ez = city.place("empire")
    hit = engine.raycast(ex - 40, 150, ez, 1, 0, 0, 80)
    check(hit and engine.tag(hit) == "landmark", "the Empire is solid at 150 m up")
    local tallest = 0
    for _, top in pairs(peak_tops) do tallest = math.max(tallest, top) end
    check(top_at(ex, ez) > tallest - 1, string.format("and it's the tallest thing in town (%.0f m)", top_at(ex, ez)))
  end
  if not sp.carpark then
    print("CITY TEST PASSED")
    stage = 5
    engine.quit()
    return
  end

  cx, cz = city.place("carpark")
  D, CURB = landmarks.DECK, L.curb
  engine.despawn(G.player)
  G.player = nil
  car = vehicle.spawn(cx + 12, cz + 17, math.pi)
  G.vehicle = car
  place(cx + 12, 0, cz + 17, math.pi) -- south of the first ramp, facing north
end

-- Each leg: drive until past `z_stop`, brake, and check the deck we're on.
local legs = {
  {dir = -1, z_stop = -6, deck = 1, next = function() place(cx - 12, CURB + D, cz - 12, 0) end},
  {dir = 1, z_stop = 6, deck = 2, next = function() place(cx + 12, CURB + 2 * D, cz + 12, math.pi) end},
  {dir = -1, z_stop = -6, deck = 3, next = function() place(cx, CURB + 3 * D, cz - 8, 0) end},
}

engine.on("tick", function(dt)
  if stage == 0 then
    if engine.ticks() < 30 then return end
    setup()
    stage, t0 = 1, engine.time()
    return
  end
  local x, y, z = engine.pos(car)
  local leg = legs[stage]
  if leg then
    if held.w and (z - cz - leg.z_stop) * leg.dir > 0 then
      held = {space = true, s = true}
    end
    if not held.w and math.abs(vehicle.speed(car)) < 0.5 then
      local want = CURB + leg.deck * D
      check(math.abs(y - 0.75 - want) < 0.5, string.format("drove up to deck %d (%.1f m)", leg.deck, y - 0.75))
      leg.next()
      stage, t0 = stage + 1, engine.time()
    elseif engine.time() - t0 > 12 then
      check(false, string.format("stuck on the way to deck %d at (%.1f, %.1f, %.1f)", leg.deck, x - cx, y, z - cz))
    end
  elseif stage == 4 then
    peak = math.max(peak, y)
    if stunts > 0 then
      check(peak > CURB + 3 * D + 2, string.format("the roof kicker launches the car (peak %.1f m)", peak))
      print("CITY TEST PASSED")
      stage = 5
      engine.quit()
    elseif engine.time() - t0 > 10 then
      check(false, "no stunt off the roof")
    end
  end
end)
