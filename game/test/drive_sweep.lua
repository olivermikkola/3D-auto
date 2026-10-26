-- Drive sweep: a car down every road of the map, by the traffic AI, and a
-- note of everywhere one gets into trouble: stuck (not moving for 4 s),
-- knocked off its wheels, fallen through the ground, thrown up in the air,
-- or not at the far end in time. Spots within 20 m of each other are one
-- problem. Prints them worst first; DRIVE_SWEEP=1 (DRIVE_SWEEP_BUS=1 to
-- drive buses, DRIVE_SWEEP_EVERY=n to drive every nth road only,
-- DRIVE_SWEEP_MAX=n to try only the first n, DRIVE_SWEEP_NEAR and _GO: see
-- below, DRIVE_SWEEP_TRACE=1 or "fine" to print each car as it goes).
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local vehicle = require "lib.vehicle"
local traffic = require "systems.traffic"

local BATCH, STUCK, TIPPED, SLACK = tonumber(os.getenv("DRIVE_SWEEP_BATCH") or "") or 60, 4, 2, 2.5 -- cars at once; seconds; time allowed = SLACK * length / cruise + 8
local CRUISE = 11

local function road_y(a, b, x, z) return city.height_on(a, b, x, z) or U.ground(x, z) end

engine.on("init", function()
  if not city.network() then print("DRIVE_SWEEP: grid map, nothing to sweep"); print("DRIVE_SWEEP: PASSED"); return end
  -- (The roads are what's checked: no traffic lights to wait at.)
  require("systems.signals").off = true
  -- No ambient traffic or crowds in the way: just the sweep's cars.
  for id in pairs(traffic.cars) do engine.despawn(id) end
  traffic.cars, traffic.target = {}, nil
  local peds = require "systems.peds"
  for id in pairs(peds.peds) do engine.despawn(id) end
  peds.peds = {}

  local todo = {}
  for _, r in ipairs(city.roads()) do
    todo[#todo + 1] = {r[1], r[2]}
    if not r.oneway then todo[#todo + 1] = {r[2], r[1]} end
  end
  -- DRIVE_SWEEP_NEAR="x,z,r": only roads starting within r m of x, z;
  -- DRIVE_SWEEP_GO=1: and stand the player there.
  local near = os.getenv("DRIVE_SWEEP_NEAR")
  if near then
    local nx, nz, nr = near:match("([-%d.]+),([-%d.]+),([%d.]+)")
    nx, nz, nr = tonumber(nx), tonumber(nz), tonumber(nr)
    local keep = {}
    for _, d in ipairs(todo) do
      local x, z = city.pos(d[1])
      if U.dist2d(x, z, nx, nz) <= nr then keep[#keep + 1] = d end
    end
    todo = keep
    if os.getenv("DRIVE_SWEEP_GO") then engine.set_pos(G.player, nx, U.ground(nx, nz) + 1.5, nz) end
  end
  local every = tonumber(os.getenv("DRIVE_SWEEP_EVERY") or "")
  if every then
    local keep = {}
    for i = 1, #todo, every do keep[#keep + 1] = todo[i] end
    todo = keep
  end
  local most = tonumber(os.getenv("DRIVE_SWEEP_MAX") or "")
  if most then for i = #todo, most + 1, -1 do todo[i] = nil end end
  local bus = (os.getenv("DRIVE_SWEEP_BUS") or "0") ~= "0" and os.getenv("DRIVE_SWEEP_BUS") ~= ""

  local next_i, live, trouble, done, t0 = 1, {}, {}, 0, os.clock()
  local function note(kind, x, y, z, a, b, what)
    trouble[#trouble + 1] = {kind = kind, x = x, y = y, z = z, a = a, b = b, what = what or "nothing"}
  end
  -- A sweep vehicle isn't started on top of another one still at the
  -- start of its road (many roads meet at a bus terminal): it waits its
  -- turn, put back at the end of the list, up to WAITS times.
  local ROOM, WAITS, waits, deferred = bus and 18 or 10, 50, {}, 0
  local function crowded(x, z)
    for id in pairs(live) do
      local ox, _, oz = engine.pos(id)
      if ox and U.dist2d(x, z, ox, oz) < ROOM then return true end
    end
  end
  -- Returns false (and launches nothing) when the start is crowded.
  local function launch(a, b, k)
    local path = city.path(a, b)
    local len = 0
    for i = 2, #path do len = len + U.dist2d(path[i - 1][1], path[i - 1][2], path[i][1], path[i][2]) end
    if len < 12 then done = done + 1; return true end -- too short to start on and get anywhere
    -- 6 m in, in the right-hand lane.
    local p, q = path[1], path[2]
    local seg = U.dist2d(p[1], p[2], q[1], q[2])
    local t = math.min(6, seg / 2) / math.max(seg, 1e-3)
    local yaw = math.atan(q[1] - p[1], q[2] - p[2])
    local rx, rz = U.right(yaw)
    local lane = city.lane(a, b)
    local x, z = p[1] + (q[1] - p[1]) * t + rx * lane, p[2] + (q[2] - p[2]) * t + rz * lane
    if (waits[k] or 0) < WAITS and crowded(x, z) then
      waits[k] = (waits[k] or 0) + 1
      deferred = deferred + 1
      return false
    end
    local id = vehicle.spawn(x, z, yaw, nil, bus and "bus" or nil, bus and "bus" or "car", road_y(a, b, x, z))
    local c = {from = a, to = b, path = path, wp = 2, lane = lane, speed = 0, stuck = 0, keep = true}
    traffic.cars[id] = c
    live[id] = {a = a, b = b, c = c, born = engine.time(), limit = SLACK * len / CRUISE + 8, still = 0, tipped = 0}
    return true
  end

  local GROUND = {terrain = true, road = true}
  engine.on("contact", function(a, b)
    for _, p in ipairs{{a, b}, {b, a}} do
      local s, tag = live[p[1]], engine.tag(p[2])
      if s and tag and not GROUND[tag] then s.hit, s.hit_at = tag, engine.time() end
    end
  end)

  engine.on("tick", function(dt)
    -- Top up the batch.
    local n = 0
    for _ in pairs(live) do n = n + 1 end
    local tries = 0
    while n < BATCH and next_i <= #todo and tries < BATCH do
      local d = todo[next_i]
      if launch(d[1], d[2], d) then n = n + 1 else todo[#todo + 1] = d end
      next_i, tries = next_i + 1, tries + 1
    end
    for id, s in pairs(live) do
      local finished, kind
      if not engine.exists(id) then
        finished, kind = true, "gone"
      else
        local x, y, z = engine.pos(id)
        local c = s.c
        local onto = c.from ~= s.a -- it has turned off our road: it got to the end
        if os.getenv("DRIVE_SWEEP_TRACE") then
          s.tr = (s.tr or 0) + dt
          local fine = os.getenv("DRIVE_SWEEP_TRACE") == "fine" and engine.time() - s.born > tonumber(os.getenv("FINE_FROM") or "7.2") and engine.time() - s.born < tonumber(os.getenv("FINE_TO") or "8.2")
          if fine then
            local fx, _, fz = engine.forward(id)
            local h1, d1 = engine.raycast(x + fx * 2.3, y, z + fz * 2.3, fx, 0, fz, 6, id)
            local h2, d2, _, gy = engine.raycast(x, y + 2, z, 0, -1, 0, 6, id)
            local vx, vy, vz = engine.vel(id)
            local ax, ay, az = engine.angvel(id)
            print(string.format("FINE %d t=%.3f pos %.2f %.2f %.2f v %.1f %.1f %.1f av %.1f %.1f %.1f yaw %.2f ahead %s %s below %s %s y %.2f wp %d/%d to %d",
              id, engine.time() - s.born, x, y, z, vx, vy, vz, ax, ay, az, engine.yaw(id), tostring(h1 and engine.tag(h1)), tostring(d1),
              tostring(h2 and engine.tag(h2)), tostring(h2), gy or -1, c.wp, #c.path, c.to))
          end
          if s.tr >= 0.25 then
            s.tr = 0
            local vx, vy, vz = engine.vel(id)
            print(string.format("TRACE %d %d>%d t=%.2f pos %.1f %.1f %.1f road %.1f ground %.1f v %.1f %.1f %.1f wheels %s",
              id, s.a, s.b, engine.time() - s.born, x, y, z, road_y(c.from, c.to, x, z), U.ground(x, z), vx, vy, vz, tostring(vehicle.on_wheels(id))))
          end
        end
        local here = road_y(c.from, c.to, x, z)
        -- Where it first went wrong: a jolt up or off its wheels. What it
        -- hit just before, if anything (a bus's nose is 6 m from its
        -- middle), else the nearest thing to it.
        if not s.first and engine.time() - s.born > 0.5 then -- (not yet settled on its wheels when new)
          local _, vy = engine.vel(id)
          if math.abs(vy) > 3 or not vehicle.on_wheels(id) then
            local what = s.hit and engine.time() - s.hit_at < 1 and s.hit or nil
            local near = not what and engine.nearest(x, y, z, 3.5, nil, id)
            if near then what = engine.tag(near) end
            s.first = {x = x, y = y, z = z, what = what}
          end
        end
        s.still = math.abs(vehicle.speed(id)) < 1 and s.still + dt or 0
        s.tipped = vehicle.on_wheels(id) and 0 or s.tipped + dt
        if onto then finished = true
        elseif y < U.ground(x, z) - 4 and y < here - 4 then finished, kind = true, "fell through"
        elseif y > here + 6 then finished, kind = true, "thrown up"
        elseif s.tipped > TIPPED then finished, kind = true, "off its wheels"
        elseif s.still > STUCK then finished, kind = true, "stuck"
        elseif engine.time() - s.born > s.limit then finished, kind = true, "too slow"
        end
        if kind then
          -- Where it started going wrong, and what was there (the nearest
          -- thing to it then, if anything was that close).
          local f = s.first or {x = x, y = y, z = z}
          note(kind, f.x, f.y, f.z, s.a, s.b, f.what)
        end
      end
      if finished then
        if engine.exists(id) then engine.despawn(id) end
        traffic.cars[id] = nil
        live[id] = nil
        done = done + 1
      end
    end
    if next_i > #todo and next(live) == nil then
      -- Group spots within 20 m, biggest groups first.
      local groups, whats = {}, {}
      for _, t in ipairs(trouble) do
        local g
        for _, o in ipairs(groups) do
          if U.dist2d(o.x, o.z, t.x, t.z) < 20 then g = o; break end
        end
        if not g then g = {x = t.x, z = t.z, y = t.y, n = 0, kinds = {}, a = t.a, b = t.b}; groups[#groups + 1] = g end
        g.n = g.n + 1
        g.kinds[t.kind] = (g.kinds[t.kind] or 0) + 1
        g.what = g.what or t.what
        whats[t.what] = (whats[t.what] or 0) + 1
      end
      table.sort(groups, function(p, q) return p.n > q.n end)
      for i, g in ipairs(groups) do
        local ks = {}
        for k, v in pairs(g.kinds) do ks[#ks + 1] = k .. " " .. v end
        table.sort(ks)
        local street, area = roadnet.where(g.x, g.z)
        print(string.format("DRIVE_SWEEP #%d at %.0f, %.0f (y %.1f): %d cars: %s; near %s; %s, %s", i, g.x, g.z, g.y, g.n,
          table.concat(ks, ", "), g.what, street or "?", area or "?"))
      end
      local ws = {}
      for k, v in pairs(whats) do ws[#ws + 1] = k .. " " .. v end
      table.sort(ws)
      print("DRIVE_SWEEP: near what: " .. table.concat(ws, ", "))
      print(string.format("DRIVE_SWEEP: %d drives, %d in trouble at %d spots, %.0f s (%d waits for room)", #todo - deferred, #trouble,
        #groups, os.clock() - t0, deferred))
      print("DRIVE_SWEEP: PASSED")
      engine.quit()
    end
  end)
end)
