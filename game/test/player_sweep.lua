-- Player sweep: the player's own car, driven by the player's controls (a
-- robot works the throttle and the wheel: test.robot), down every road of
-- the map one after another (and on round a corner at its end), and a note of everywhere it gets into
-- trouble: stuck (not moving for 3 s), off its wheels, thrown up in the
-- air, fallen through the ground, off the road it should be on, or not at
-- the far end in time. Traffic drives by setting its velocity outright;
-- this is the physics the player gets. Spots within 15 m of each other
-- are one problem; worst first. PLAYER_SWEEP=1 (PLAYER_SWEEP_EVERY=n:
-- every nth road, default 8; PLAYER_SWEEP_MAX=n: the first n;
-- PLAYER_SWEEP_NEAR="x,z,r": roads starting within r m of x, z;
-- PLAYER_SWEEP_SPEED=m/s on straights, default 17; PLAYER_SWEEP_TRACE=1).
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local vehicle = require "lib.vehicle"
local input = require "lib.input"
local robot = require "test.robot"
local traffic = require "systems.traffic"
local peds = require "systems.peds"

local FAST = tonumber(os.getenv("PLAYER_SWEEP_SPEED") or "") or 17
local STUCK, TIPPED, OFF = 3, 1.5, 1.5 -- seconds

local todo, next_i, run, trouble, done, t0 = {}, 1, nil, {}, 0, nil
local driver, give_car

local function road_y(a, b, x, z) return city.height_on(a, b, x, z) or U.ground(x, z) end

-- Metres from (x, z) to the nearest point of road a -> b's middle line.
local function from_middle(path, x, z)
  local best = math.huge
  for i = 2, #path do
    local a, b = path[i - 1], path[i]
    local dx, dz = b[1] - a[1], b[2] - a[2]
    local t = U.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / math.max(dx * dx + dz * dz, 1e-6), 0, 1)
    best = math.min(best, U.dist2d(x, z, a[1] + dx * t, a[2] + dz * t))
  end
  return best
end

input.drive = function()
  if not (G.vehicle and run) then return 0, 0, false end
  local throttle, steer = driver.inputs(G.vehicle)
  return throttle, steer, false
end

-- Put the car 6 m into road a -> b, in its lane, still, and set off: down
-- it, through junction b, and down road b -> c (the n-th way on from b,
-- so the turns at a junction all get driven).
local function start(d, n)
  local a, b = d[1], d[2]
  local path = city.path(a, b)
  local len = 0
  for i = 2, #path do len = len + U.dist2d(path[i - 1][1], path[i - 1][2], path[i][1], path[i][2]) end
  if len < 20 then done = done + 1; return end -- too short to get going on
  local ways = {}
  for _, c in ipairs(city.links(b)) do if c ~= a then ways[#ways + 1] = c end end
  local c = ways[n % math.max(1, #ways) + 1]
  local js = c and {a, b, c} or {a, b}
  local after = c and city.path(b, c) or {}
  for i = 2, #after do len = len + U.dist2d(after[i - 1][1], after[i - 1][2], after[i][1], after[i][2]) end
  local pts = robot.lane_points(js, {})
  local p, q = pts[1], pts[2]
  local seg = U.dist2d(p[1], p[2], q[1], q[2])
  local t = math.min(6, seg / 2) / math.max(seg, 1e-3)
  local x, z = p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t
  local car = G.vehicle
  engine.set_pos(car, x, road_y(a, b, x, z) + 0.8, z)
  engine.set_rot(car, 0, 0, 0, 1)
  engine.set_yaw(car, math.atan(q[1] - p[1], q[2] - p[2]))
  engine.set_vel(car, 0, 0, 0)
  engine.set_angvel(car, 0, 0, 0)
  driver = robot.driver(pts, FAST, 7)
  local function width(p, q)
    local e = roadnet.net().edges[roadnet.net().edge_of[p .. ">" .. q] or 0]
    return e and e.width or 7
  end
  run = {a = a, b = b, roads = {{path, width(a, b), a, b}}, born = engine.time(), limit = 2 * len / FAST + 12,
         still = 0, tipped = 0, off = 0, last = pts[#pts]}
  if c then run.roads[2] = {after, width(b, c), b, c} end
end

-- How far (x, z) is out beyond the edge of the roads being driven, and
-- the height of the nearest of them there.
local function beyond(x, z)
  local best, y = math.huge, nil
  for _, r in ipairs(run.roads) do
    local d = from_middle(r[1], x, z) - r[2] / 2
    if d < best then best, y = d, road_y(r[3], r[4], x, z) end
  end
  return best, y
end

local function note(kind, x, y, z, what)
  trouble[#trouble + 1] = {kind = kind, x = x, y = y, z = z, what = what or "nothing", a = run.a, b = run.b}
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
    print(string.format("PLAYER_SWEEP #%d at %.0f, %.0f (y %.1f): %d drives: %s; near %s; %s, %s", i, g.x, g.z, g.y, g.n,
      table.concat(ks, ", "), table.concat(ws, "/"), street or "?", area or "?"))
  end
  local ks = {}
  for k, v in pairs(kinds) do ks[#ks + 1] = k .. " " .. v end
  table.sort(ks)
  print("PLAYER_SWEEP: by kind: " .. table.concat(ks, ", "))
  print(string.format("PLAYER_SWEEP: %d drives, %d in trouble at %d spots, %.0f s", #todo - done, #trouble, #groups, os.clock() - t0))
  print("PLAYER_SWEEP: PASSED")
  engine.quit()
end

-- What the car last bumped into (not the ground it drives on).
local GROUND = {terrain = true, road = true, ground = true}
engine.on("contact", function(a, b)
  local car = G.vehicle
  if not (run and car) then return end
  local other = a == car and b or (b == car and a)
  local tag = other and engine.tag(other)
  if tag and not GROUND[tag] then run.hit, run.hit_at = tag, engine.time() end
end)

-- Into a car of the player's own (again, if the last one was lost).
local last_pos
give_car = function()
  local x, z
  if G.player then x, _, z = engine.pos(G.player)
  elseif last_pos then x, z = last_pos[1], last_pos[3]
  else x, z = city.pos(1) end
  local car = vehicle.spawn(x, z, 0, 1, nil, "car", U.ground(x, z))
  if G.player then engine.despawn(G.player) end
  G.player, G.vehicle = nil, car
  engine.emit("vehicle_enter", car)
end

local started = false
engine.on("tick", function(dt)
  if not started then
    if engine.time() < 0.5 then return end
    started, t0 = true, os.clock()
    if not city.network() then print("PLAYER_SWEEP: grid map, nothing to sweep"); print("PLAYER_SWEEP: PASSED"); engine.quit(); return end
    for _, r in ipairs(city.roads()) do
      todo[#todo + 1] = {r[1], r[2]}
      if not r.oneway then todo[#todo + 1] = {r[2], r[1]} end
    end
    local near = os.getenv("PLAYER_SWEEP_NEAR")
    if near then
      local nx, nz, nr = near:match("([-%d.]+),([-%d.]+),([%d.]+)")
      nx, nz, nr = tonumber(nx), tonumber(nz), tonumber(nr)
      local keep = {}
      for _, d in ipairs(todo) do
        local x, z = city.pos(d[1])
        if U.dist2d(x, z, nx, nz) <= nr then keep[#keep + 1] = d end
      end
      todo = keep
    end
    local every = tonumber(os.getenv("PLAYER_SWEEP_EVERY") or "") or 8
    local keep = {}
    for i = 1, #todo, every do keep[#keep + 1] = todo[i] end
    todo = keep
    local most = tonumber(os.getenv("PLAYER_SWEEP_MAX") or "")
    if most then for i = #todo, most + 1, -1 do todo[i] = nil end end
    give_car()
    return
  end
  -- No driving over a border crossing into the other city mid-sweep.
  require("lib.borders").crossings = {}
  -- Nobody else on the streets.
  for id in pairs(traffic.cars) do engine.despawn(id) end
  traffic.cars, traffic.target = {}, nil
  for id in pairs(peds.peds) do engine.despawn(id) end
  peds.peds = {}
  require("lib.wanted").clear()

  local car = G.vehicle
  if not car or not engine.exists(car) then
    -- Lost it (wrecked, sunk): that's trouble on this road; a new car.
    if run and last_pos then note("lost the car", last_pos[1], last_pos[2], last_pos[3], run.hit) end
    run = nil
    give_car()
    return
  end
  last_pos = {engine.pos(car)}
  if not run then
    if next_i > #todo then return finish() end
    start(todo[next_i], next_i)
    next_i = next_i + 1
    return
  end
  local x, y, z = engine.pos(car)
  local now = engine.time()
  local age = now - run.born
  local out, here = beyond(x, z)
  if os.getenv("PLAYER_SWEEP_TRACE") then
    run.tr = (run.tr or 0) + dt
    if run.tr >= 0.25 then
      run.tr = 0
      local vx, vy, vz = engine.vel(car)
      print(string.format("TRACE %d>%d t=%.2f pos %.1f %.1f %.1f road %.1f v %.1f %.1f %.1f wheels %s beyond %.1f hit %s",
        run.a, run.b, age, x, y, z, here, vx, vy, vz, tostring(vehicle.on_wheels(car)), out, tostring(run.hit)))
    end
  end
  -- Where it first went wrong, and what it had just hit.
  if not run.first and age > 0.5 then
    local _, vy = engine.vel(car)
    if math.abs(vy) > 4 or not vehicle.on_wheels(car) then
      run.first = {x = x, y = y, z = z, what = run.hit and now - run.hit_at < 1 and run.hit or nil}
    end
  end
  run.still = math.abs(vehicle.speed(car)) < 1 and age > 1 and run.still + dt or 0
  run.tipped = vehicle.on_wheels(car) and 0 or run.tipped + dt
  -- Off the road: more than a metre beyond its edge.
  run.off = out > 1 and run.off + dt or 0
  local kind
  if U.dist2d(x, z, run.last[1], run.last[2]) < 8 then
    kind = "done"
  elseif y < U.ground(x, z) - 3 and y < here - 3 then kind = "fell through"
  elseif y > here + 4 then kind = "thrown up"
  elseif run.tipped > TIPPED then kind = "off its wheels"
  elseif run.still > STUCK then kind = "stuck"
  elseif run.off > OFF then kind = "off the road"
  elseif age > run.limit then kind = "too slow"
  end
  if kind then
    if kind ~= "done" then
      local f = run.first or {x = x, y = y, z = z}
      note(kind, f.x, f.y, f.z, f.what or (run.hit and now - run.hit_at < 2 and run.hit) or nil)
    end
    run = nil
  end
end)
