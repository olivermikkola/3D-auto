-- Focused regressions at the consuming seams, plus a natural off-road chase.
-- RELIABILITY_TEST=1 auto game --headless 4000
local G = require "lib.state"
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
  local neighbors, road = city.neighbors, city.road
  local graph = {
    ["1,1"] = {{0,1}}, ["0,1"] = {{1,1},{0,2}},
    ["0,2"] = {{0,1},{1,2}}, ["1,2"] = {{0,2},{2,2}}, ["2,2"] = {{1,2}},
  }
  city.neighbors = function(k,l) return graph[k .. "," .. l] or {} end
  city.road = function(k,l,dk,dl)
    for _, nb in ipairs(city.neighbors(k,l)) do
      if nb[1] == k+dk and nb[2] == l+dl then return true end
    end
    return false
  end
  local ok, err = pcall(function()
    local k,l,visited = 1,1,{}
    while k ~= 2 or l ~= 2 do
      local key = k .. "," .. l
      assert(not visited[key], "pursuit must not loop on a coherent forced road detour")
      visited[key] = true
      local nk,nl = P.step_toward(k,l,2,2)
      assert(city.road(k,l,nk-k,nl-l), "detour step must use a synthetic road edge")
      k,l = nk,nl
    end
    assert(visited["0,1"] and visited["0,2"], "detour must initially lead away from target")
  end)
  city.neighbors, city.road = neighbors, road -- restore even if a negative fails
  check(ok, "coherent forced road detour: " .. (ok and "completed" or tostring(err)))
  -- Check every shipped intersection against independent distance fields.
  local nodes = city.nodes()
  for _, goal in ipairs(nodes) do
    local distance, queue = {[goal[1] .. "," .. goal[2]] = 0}, {goal}
    local i = 1
    while i <= #queue do
      local n = queue[i]; i = i + 1
      for _, nb in ipairs(city.neighbors(n[1],n[2])) do
        local key = nb[1] .. "," .. nb[2]
        if distance[key] == nil then
          distance[key] = distance[n[1] .. "," .. n[2]] + 1
          queue[#queue + 1] = nb
        end
      end
    end
    for _, n in ipairs(nodes) do
      local nk,nl = P.step_toward(n[1],n[2],goal[1],goal[2])
      local d = distance[n[1] .. "," .. n[2]]
      if d > 0 then
        assert(city.road(n[1],n[2],nk-n[1],nl-n[2]) and distance[nk .. "," .. nl] == d-1,
               "pursuit step must reduce shortest road distance")
      else assert(nk == n[1] and nl == n[2]) end
    end
  end
  check(true, "every shipped pursuit step is a shortest-path road edge")

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

  local bx,bz = city.block_center(G.city.lot[1],G.city.lot[2])
  local z = bz - (G.city.bz / 2 - 2.2)
  check(not F.clear_approach(bx,z,0,-1), "mid-side lamp blocks the full car-width corridor")
  -- Search for a true positive premise instead of assuming bx+8 is empty.
  -- Do not move ambient traffic or weaken the helper when it correctly blocks.
  local clear
  for offset = 6, G.city.bx / 2 - 8, 2 do
    for _, side in ipairs{-1, 1} do
      if F.clear_approach(bx + offset * side,z,0,-1) then clear = {bx + offset * side,z}; break end
    end
    if clear then break end
  end
  check(clear ~= nil, "a verified clear mid-side corridor remains selectable")
  local obstruction = vehicle.spawn(clear[1], clear[2] - 6, 0, 1)
  check(not F.clear_approach(clear[1],clear[2],0,-1), "a real car blocks the verified clear corridor")
  engine.despawn(obstruction)
  check(F.clear_approach(clear[1],clear[2],0,-1), "removing only the fixture car restores the clear premise")

  local flight = F.runover_spot(G.player)
  check(flight ~= nil, "a genuine clear road flight fixture is available")
  local fx,fz,dx,dz = table.unpack(flight)
  check(F.clear_flight(fx,fz,dx,dz), "flight fixture is clear before adding its backstop")
  local backstop = engine.spawn{pos = {fx+dx*16,2,fz+dz*16}, size = {4,4,4}, body = "static", tag = "building"}
  check(not F.clear_flight(fx,fz,dx,dz), "flight clearance rejects a building beyond the real collision point")
  engine.despawn(backstop)
  check(F.clear_flight(fx,fz,dx,dz), "removing only the backstop restores flight clearance")

  -- Drive the real walking handler into a solid fixture. Its commanded
  -- velocity stays nonzero, while physics stops it; recovery must use the
  -- previous physics result rather than the just-written intent.
  local i,j = G.city.lot[1],G.city.lot[2]
  blocked_ped = engine.spawn{mesh = "ped1", pos = {bx+8,1.2,bz-9}, size = {0.7,1.8,0.7},
                            body = "dynamic", mass = 70, friction = 0, step = 0.45, lock_rotation = true, tag = "ped"}
  H.set(blocked_ped,30)
  peds.peds[blocked_ped] = {id=blocked_ped,i=i,j=j,k=1,dir=1,state="walk",speed=1.4,stuck=0,tx=bx+18,tz=bz-9}
  blocker = engine.spawn{pos = {bx+9,2,bz-9}, size = {0.5,4,4}, body = "static", tag = "wall"}

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
    engine.set_pos(G.player,x,1.2,z-9)
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
