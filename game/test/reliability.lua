-- Focused regressions at the consuming seams, plus a natural off-road chase.
-- RELIABILITY_TEST=1 auto game --headless 4000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local P = require "systems.police"
local H = require "lib.health"
local C = require "systems.carnage"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"
local F = require "test.fixtures"
local function check(ok, what)
  if not ok then engine.quit(); error("RELIABILITY FAILED: " .. what, 0) end
  print("  ok  " .. what)
end
local r = F.runovers()
local phase, start = 0, 0
local chain, detonations = {}, 0
local blocked_ped, blocker, recovered = nil, nil, false
local peds = require "systems.peds"

engine.on("explosion", function()
  if phase ~= 1 then return end
  detonations = detonations + 1
  if detonations == 1 then
    -- Reentrant event handlers can add many fires while the current one
    -- explodes. Exercise the real killed -> burning handler and table rehash.
    for _, id in ipairs(chain) do H.damage(id, 200) end
  end
end)

local function fixtures()
  check(P.direct_pursuit(true, 60) and not P.direct_pursuit(false, 60) and not P.direct_pursuit(true, 100),
        "visible 50-90m targets are pursued; occluded or distant targets still use roads")
  -- A forced detour: neither greedy axis toward the target exists at the
  -- start. There is exactly one shortest path, initially away from target.
  -- Junctions 1..5 are grid points (1,1) (0,1) (0,2) (1,2) (2,2).
  local links = city.links
  local graph = {{2}, {1, 3}, {2, 4}, {3, 5}, {4}}
  local function linked(a, b)
    for _, nb in ipairs(city.links(a)) do if nb == b then return true end end
    return false
  end
  city.links = function(id) return graph[id] or {} end
  local ok, err = pcall(function()
    local at, visited = 1, {}
    while at ~= 5 do
      assert(not visited[at], "pursuit must not loop on a coherent forced road detour")
      visited[at] = true
      local nxt = city.step_toward(at, 5)
      assert(linked(at, nxt), "detour step must use a synthetic road edge")
      at = nxt
    end
    assert(visited[2] and visited[3], "detour must initially lead away from target")
  end)
  city.links = links -- restore even if a negative fails
  check(ok, "coherent forced road detour: " .. (ok and "completed" or tostring(err)))
  -- Check every shipped junction against independent distance fields. Each
  -- step is a search of its own, so on a big town (real Raisio has
  -- thousands of junctions) check an evenly spread sample of goals and
  -- starts instead of every pair.
  local junctions = city.junctions()
  local function spread(list, n)
    if #list <= n then return list end
    local out = {}
    for k = 1, n do out[k] = list[math.floor((k - 1) * #list / n) + 1] end
    return out
  end
  local starts = spread(junctions, 60)
  for _, goal in ipairs(spread(junctions, 300 > #junctions and #junctions or 40)) do
    local distance, queue = {[goal] = 0}, {goal}
    local i = 1
    while i <= #queue do
      local n = queue[i]; i = i + 1
      for _, nb in ipairs(city.links(n)) do
        if distance[nb] == nil then
          distance[nb] = distance[n] + 1
          queue[#queue + 1] = nb
        end
      end
    end
    for _, n in ipairs(#junctions <= 300 and junctions or starts) do
      local nxt = city.step_toward(n, goal)
      local d = distance[n]
      if d > 0 then
        assert(linked(n, nxt) and distance[nxt] == d - 1, "pursuit step must reduce shortest road distance")
      else assert(nxt == n) end
    end
  end
  check(true, #junctions <= 300 and "every shipped pursuit step is a shortest-path road edge"
              or "sampled pursuit steps across the town are shortest-path road edges")

  local car = vehicle.spawn(0,0,0)
  local ambient = vehicle.spawn(20,0,0)
  local previous = G.vehicle
  G.vehicle = car
  engine.emit("ped_down", ambient, ambient)
  check(r.count == 0, "events before the run-over phase are ignored")
  r:start(car)
  engine.emit("ped_down", ambient, ambient)
  check(r.count == 0 and r.victim == nil, "ambient knockdowns cannot satisfy the player run-over")
  engine.emit("ped_down", ambient, car)
  check(r.count == 1 and r.victim == ambient and wanted.stars() >= 1, "player event is counted and production crime attribution runs")
  r:stop()
  engine.emit("ped_down", car, car)
  check(r.count == 1, "events after the phase do not replace its victim")
  G.vehicle = nil
  check(not pcall(function() r:start(car) end), "run-over refuses an unoccupied attacker")
  local stale = vehicle.spawn(40,0,0,1)
  engine.despawn(stale)
  G.vehicle = stale
  check(not pcall(function() r:start(stale) end), "run-over refuses a missing stale attacker")
  G.vehicle = car
  H.damage(car,200)
  check(C.burning[car] ~= nil, "invalid-attacker fixture uses a real killed/burning car")
  check(not pcall(function() r:start(car) end), "run-over refuses a genuinely burning attacker")
  G.vehicle = previous
  engine.despawn(car); engine.despawn(ambient)
  wanted.clear(); P.clear()

  local bx,bz = city.place("lot")
  -- A pavement spot just behind a street lamp, and the way to the road
  -- (nx, nz); fx, fz runs along the pavement. On a grid, the lamp halfway
  -- along the lot block's north side; on a road map, the lamp nearest the lot.
  local x, z, nx, nz, fx, fz, reach = bx, bz - (G.city.bz or 0) / 2 + 2.2, 0, -1, 1, 0, (G.city.bx or 0) / 2 - 8
  if city.network() then
    local roadnet = require "lib.roadnet"
    local best, lamp = math.huge
    for _, id in ipairs(engine.find("lamp")) do
      local lx,_,lz = engine.pos(id)
      local d = (lx-bx)^2+(lz-bz)^2
      if d < best then best, lamp = d, id end
    end
    local lx,_,lz = engine.pos(lamp)
    local e, i = roadnet.nearest_edge(lx, lz, true)
    local pts = roadnet.net().edges[e].pts
    local ax,az,ex,ez = pts[i-1][1],pts[i-1][2],pts[i][1],pts[i][2]
    local len = math.sqrt((ex-ax)^2+(ez-az)^2)
    fx, fz = (ex-ax)/len, (ez-az)/len
    nx, nz = fz, -fx
    if (lx-ax)*nx + (lz-az)*nz > 0 then nx, nz = -nx, -nz end -- toward the road
    x, z, reach = lx - nx*1.2, lz - nz*1.2, 20
  end
  check(not F.clear_approach(x,z,nx,nz), "mid-side lamp blocks the full car-width corridor")
  -- Search for a true positive premise instead of assuming bx+8 is empty.
  -- Do not move ambient traffic or weaken the helper when it correctly blocks.
  local clear
  for offset = 6, reach, 2 do
    for _, side in ipairs{-1, 1} do
      local cx, cz = x + fx*offset*side, z + fz*offset*side
      if F.clear_approach(cx,cz,nx,nz) then clear = {cx,cz}; break end
    end
    if clear then break end
  end
  check(clear ~= nil, "a verified clear mid-side corridor remains selectable")
  local obstruction = vehicle.spawn(clear[1] + nx*6, clear[2] + nz*6, 0, 1)
  check(not F.clear_approach(clear[1],clear[2],nx,nz), "a real car blocks the verified clear corridor")
  engine.despawn(obstruction)
  check(F.clear_approach(clear[1],clear[2],nx,nz), "removing only the fixture car restores the clear premise")

  local flight = F.runover_spot(G.player)
  check(flight ~= nil, "a genuine clear road flight fixture is available")
  local fx,fz,dx,dz = table.unpack(flight)
  check(F.clear_flight(fx,fz,dx,dz), "flight fixture is clear before adding its backstop")
  local backstop = engine.spawn{pos = {fx+dx*16, 2 + U.ground(fx+dx*16, fz+dz*16), fz+dz*16}, size = {4,4,4}, body = "static", tag = "building"}
  check(not F.clear_flight(fx,fz,dx,dz), "flight clearance rejects a building beyond the real collision point")
  engine.despawn(backstop)
  check(F.clear_flight(fx,fz,dx,dz), "removing only the backstop restores flight clearance")

  -- Drive the real walking handler into a solid fixture. Its commanded
  -- velocity stays nonzero, while physics stops it; recovery must use the
  -- previous physics result rather than the just-written intent.
  blocked_ped = engine.spawn{mesh = "ped1", pos = {bx+8, 1.2 + U.ground(bx+8, bz-9), bz-9}, size = {0.7,1.8,0.7},
                            body = "dynamic", mass = 70, friction = 0, step = 0.45, lock_rotation = true, tag = "ped"}
  H.set(blocked_ped,30)
  local where = {i=G.city.lot and G.city.lot[1], j=G.city.lot and G.city.lot[2], k=1}
  if city.network() then where = {e=require("lib.roadnet").nearest_edge(bx+8, bz-9, true), hand=1, wp=2} end
  local walker = {id=blocked_ped,dir=1,state="walk",speed=1.4,stuck=0,tx=bx+18,tz=bz-9}
  for key, v in pairs(where) do walker[key] = v end
  peds.peds[blocked_ped] = walker
  blocker = engine.spawn{pos = {bx+9, 2 + U.ground(bx+9, bz-9), bz-9}, size = {0.5,4,4}, body = "static", tag = "wall"}

  -- Remote cars don't disturb pursuit/population. The first explosion
  -- ignites all others through the production killed handler.
  for i=1,64 do chain[i] = vehicle.spawn(1000+i*20,1000,0) end
  local first = vehicle.spawn(980,1000,0)
  H.damage(first,200)
  C.burning[first] = engine.time()
  phase, start = 1, engine.time()
end

engine.on("tick", function()
  if phase == 0 then
    if engine.ticks() < 30 then return end
    fixtures()
  elseif phase == 1 then
    local p = peds.peds[blocked_ped]
    recovered = recovered or (p and p.dir == -1)
    if engine.time()-start <= 4 then return end
    check(recovered, "a physically blocked walker turns around within four seconds")
    peds.peds[blocked_ped] = nil
    engine.despawn(blocked_ped); engine.despawn(blocker)
    check(detonations == #chain+1, "reentrant chain fires all detonate without invalidating iteration")
    -- Same off-road lot target that failed in the baseline: no cop moves,
    -- no bypass of its graph, sight, deployment or shooting requirements.
    local x,z = city.place("lot")
    engine.set_pos(G.player, x, 1.2 + U.ground(x, z-9), z-9)
    wanted.clear(); P.clear(); wanted.set(3)
    phase,start = 2,engine.time()
  elseif phase == 2 then
    if P.officer_count() > 0 then
      check(true, "naturally dispatched cops reach and deploy at the off-road target")
      print("RELIABILITY PASSED")
      engine.quit()
    elseif engine.time()-start > 45 then check(false,"natural off-road pursuit and deployment within 45s") end
  end
end)
