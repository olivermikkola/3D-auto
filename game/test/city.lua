-- The Manhattan layout (island, park, road graph, skyline), its landmarks,
-- and a drive up the car park: every ramp is climbed with the real car
-- controls, then off the roof kicker.
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

local function setup()
  local L = G.city
  -- The island: districts, the park, water round the tips.
  local count = {}
  for i = 0, L.NX - 1 do
    for j = 0, L.NZ - 1 do
      local d = city.district(i, j)
      count[d] = (count[d] or 0) + 1
    end
  end
  check(count.park == 14 and count.industrial == 4, "Central Park is 2x7 blocks, 4 blocks of West Side yards")
  check(count.water >= 6, count.water .. " blocks of the grid are river (the island narrows at the tips)")
  check(count.downtown >= 40 and count.residential >= 30,
        string.format("%d downtown and %d residential blocks", count.downtown, count.residential))

  -- The road graph: one piece, no roads into the river or across the park
  -- except the transverse, and nothing built on any of it.
  local nodes = city.nodes()
  local seen, queue, n = {}, {L.lot and {2, 15}}, 0
  seen["2,15"] = true
  while #queue > 0 do
    local q = table.remove(queue)
    n = n + 1
    for _, nb in ipairs(city.neighbors(q[1], q[2])) do
      local key = nb[1] .. "," .. nb[2]
      if not seen[key] then seen[key] = true; queue[#queue + 1] = nb end
    end
  end
  check(n == #nodes, string.format("every one of the %d intersections is reachable by road", #nodes))
  check(not city.road(0, 0, 1, 0) and not city.road(0, 19, 0, 1), "no roads off the island")
  check(not city.road(3, 6, 0, 1) and not city.road(2, 6, 1, 0) and city.road(2, 8, 1, 0) and city.road(3, 8, 1, 0),
        "the park interrupts the grid but for one transverse road")
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
  local sx, sz = city.node(0, 10)
  local hit = engine.raycast(sx, 1, sz, -1, 0, 0, 30)
  check(hit and engine.tag(hit) == "wall", "a wall at the shore keeps cars out of the river")

  -- The skyline: two peaks, Midtown and the Financial District, over a low uptown.
  local tall, rows = {}, {}
  for _, id in ipairs(engine.find("building")) do
    local x, _, z = engine.pos(id)
    local _, j = city.block_of(x, z)
    local h = top_at(x, z)
    local band = j <= 3 and "uptown" or (j >= 11 and j <= 14) and "midtown" or j >= 18 and "fidi" or nil
    if band then
      rows[band] = rows[band] or {n = 0, sum = 0, max = 0}
      local r = rows[band]
      r.n, r.sum, r.max = r.n + 1, r.sum + h, math.max(r.max, h)
    end
    if h > 100 then tall[#tall + 1] = id end
  end
  local avg = function(b) return rows[b].sum / rows[b].n end
  check(rows.midtown.max > 140 and rows.fidi.max > 100,
        string.format("supertalls in Midtown (%.0f m) and the Financial District (%.0f m)", rows.midtown.max, rows.fidi.max))
  check(avg("midtown") > 2 * avg("uptown"),
        string.format("Midtown averages %.0f m, uptown %.0f m", avg("midtown"), avg("uptown")))
  check(#tall >= 15, #tall .. " buildings over 100 m")

  -- What the blocks are made of.
  local rows_n, sheds, decos = 0, 0, 0
  for _, id in ipairs(engine.find("building")) do
    local m = engine.mesh_of(id) or ""
    if m:find("^lot_") then rows_n = rows_n + 1
    elseif m:find("^warehouse") then sheds = sheds + 1
    elseif m:find("^deco") then decos = decos + 1 end
  end
  check(rows_n >= 30, rows_n .. " terraces of brownstones uptown")
  check(decos >= 5, decos .. " Art Deco setback towers")
  check(sheds >= 10, sheds .. " warehouses in the yards")
  check(#engine.find("container") >= 8, #engine.find("container") .. " yards of shipping containers")
  check(#engine.find("rooftop") >= 40, #engine.find("rooftop") .. " water towers on the roofs")
  check(#engine.find("billboard") >= 20, #engine.find("billboard") .. " billboards in Times Square")
  local P, trees = L.park, 0
  for _, id in ipairs(engine.find("tree")) do
    local x, _, z = engine.pos(id)
    if x > P.x0 and x < P.x1 and z > P.z0 and z < P.z1 then trees = trees + 1 end
  end
  check(trees >= 150, trees .. " trees in Central Park")

  check(#L.landmarks == 3, "a TV tower, the Empire and a car park")
  local tx, tz = city.block_center(L.tower[1], L.tower[2])
  hit = engine.raycast(tx - 20, 60, tz, 1, 0, 0, 40)
  check(hit and engine.tag(hit) == "landmark", "the TV tower is solid at 60 m up")
  local ex, ez = city.block_center(L.empire[1], L.empire[2])
  hit = engine.raycast(ex - 40, 150, ez, 1, 0, 0, 80)
  check(hit and engine.tag(hit) == "landmark", "the Empire is solid at 150 m up")
  check(top_at(ex, ez) > rows.midtown.max - 1, string.format("and it's the tallest thing in town (%.0f m)", top_at(ex, ez)))

  cx, cz = city.block_center(L.carpark[1], L.carpark[2])
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
