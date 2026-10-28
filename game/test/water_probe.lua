-- Driving into the water: from roads near the shore all round town, a car
-- is driven straight at the water for 4 s, then reversed for 5. Notes each
-- spot where it couldn't back out again (stuck at the bank), and where it
-- ended up below the bank. WATER_TEST=1 (MAP=turku; WATER_SPOTS=n spots,
-- WATER_TRACE=k: tick by tick at spot k, and what's around it at the end)
local G = require "lib.state"
local U = require "lib.util"
local roadnet = require "lib.roadnet"
local vehicle = require "lib.vehicle"
local input = require "lib.input"
local MAX = tonumber(os.getenv("WATER_SPOTS") or "") or 16

local thr = 0
input.drive = function() return thr, 0, false end

local function spots()
  local out = {}
  for x = -2500, 2500, 40 do
    for z = -2500, 2500, 40 do
      if roadnet.wet(x, z) and not roadnet.wet(x + 40, z) or roadnet.wet(x, z) and not roadnet.wet(x - 40, z)
         or roadnet.wet(x, z) and not roadnet.wet(x, z + 40) or roadnet.wet(x, z) and not roadnet.wet(x, z - 40) then
        local e, _, rx, rz, d = roadnet.nearest_edge(x, z)
        if e and d > 15 and d < 45 and not roadnet.wet(rx, rz) and not roadnet.net().edges[e].tunnel and not roadnet.net().edges[e].deck then
          local far = true
          for _, o in ipairs(out) do if U.dist2d(o[1], o[2], rx, rz) < 150 then far = false end end
          if far then out[#out + 1] = {rx, rz, x, z} end
        end
      end
    end
  end
  return out
end

local co = coroutine.create(function()
  for _ = 1, 30 do coroutine.yield() end
  local list, stuck, low = spots(), 0, 0
  local n = math.min(MAX, #list)
  for k = 1, n do
    local s = list[k]
    local car = G.vehicle
    if not car then
      car = vehicle.spawn(s[1], s[2], 0)
      if G.player then engine.despawn(G.player) end
      G.player, G.vehicle = nil, car
      engine.emit("vehicle_enter", car)
    end
    engine.set_pos(car, s[1], roadnet.ground(s[1], s[2]) + 1, s[2])
    engine.orient(car, math.atan(s[3] - s[1], s[4] - s[2]))
    engine.set_vel(car, 0, 0, 0)
    for _ = 1, 20 do coroutine.yield() end
    thr = 1
    local t = engine.time() + 4
    while engine.time() < t do coroutine.yield() end
    local x0, y0, z0 = engine.pos(car)
    thr = -1
    t = engine.time() + 5
    while engine.time() < t do
      coroutine.yield()
      if os.getenv("WATER_TRACE") == tostring(k) and engine.exists(car) then
        local x, y, z = engine.pos(car)
        local vx, vy, vz = engine.vel(car)
        print(string.format("  %.2f,%.2f,%.2f wet %s ground %.2f vel %.1f,%.1f,%.1f wheels %s", x, y, z, tostring(roadnet.wet(x, z)),
          roadnet.ground(x, z), vx, vy, vz, tostring(vehicle.on_wheels(car))))
      end
    end
    thr = 0
    if not engine.exists(car) then
      print(string.format("WATER: spot %d: the car was destroyed", k))
      G.vehicle = nil
      goto next
    end
    local x1, y1, z1 = engine.pos(car)
    if os.getenv("WATER_TRACE") == tostring(k) then
      local hit, d = engine.raycast(x1, y1, z1, 0, -1, 0, 5, car)
      print("  under:", hit and engine.tag(hit), hit and engine.mesh_of(hit), d)
      for _, a in ipairs{0, 1.57, 3.14, 4.71} do
        local fx, fz = math.sin(engine.yaw(car) + a), math.cos(engine.yaw(car) + a)
        local h2, d2 = engine.raycast(x1, y1 - 0.4, z1, fx, 0, fz, 4, car)
        print("  around", a, h2 and engine.tag(h2), h2 and engine.mesh_of(h2), d2)
      end
    end
    local moved = U.dist2d(x0, z0, x1, z1)
    local under = roadnet.ground(x1, z1) - y1
    local bad = moved < 4
    if bad then stuck = stuck + 1 end
    if y1 < roadnet.ground(s[1], s[2]) - 2 then low = low + 1 end
    print(string.format("WATER: spot %d from %.0f,%.0f toward %.0f,%.0f: reached %.0f,%.0f, backed %.1f m%s, %.1f m below the road it left",
      k, s[1], s[2], s[3], s[4], x0, z0, moved, bad and " STUCK" or "", roadnet.ground(s[1], s[2]) - y1))
    ::next::
  end
  print(string.format("WATER: %d spots, %d stuck, %d ended well below the road", n, stuck, low))
  -- (7 of the 16 were, before systems/shore put a car stuck at the bank back on the road.)
  if n < 10 then error("WATER: too few spots by the water", 0) end
  if stuck > 0 then error("WATER: stuck at the water's edge", 0) end
  print("WATER_OK")
  engine.quit()
end)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
