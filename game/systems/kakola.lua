-- Kakolanmäki 500m visual slice and slope elevator (Funikulaari) system.
-- Connects Linnankatu (ala-asema) with the Kakola hilltop fortress (yläasema).
local U = require "lib.util"

local K = {
  funicular = nil,
  tracks = {},
}

-- Station positions from OSM
local ALA_POS = {-1373.7, 1108.9}
local YLA_POS = {-1467.3, 1031.2}

function K.build(map)
  if not map or (map.id ~= "turku" and map.name ~= "Turku") then return end

  local y0 = U.ground(ALA_POS[1], ALA_POS[2])
  local y1 = U.ground(YLA_POS[1], YLA_POS[2])
  local dx = YLA_POS[1] - ALA_POS[1]
  local dz = YLA_POS[2] - ALA_POS[2]
  local dist = math.sqrt(dx * dx + dz * dz)
  local yaw = math.atan(dx, dz)

  -- 1. Lower and upper funicular stations
  engine.spawn{
    mesh = "funicular_station",
    pos = {ALA_POS[1], y0, ALA_POS[2]},
    yaw = yaw,
    tag = "building",
    body = "static",
  }
  engine.spawn{
    mesh = "funicular_station",
    pos = {YLA_POS[1], y1, YLA_POS[2]},
    yaw = yaw + math.pi,
    tag = "building",
    body = "static",
  }

  -- 2. Steel inclined railway track between stations
  local n_sleepers = math.floor(dist / 4.0)
  local rail_steel = {0.25, 0.26, 0.28}
  local concrete_beam = {0.62, 0.62, 0.65}

  for i = 1, n_sleepers - 1 do
    local t = i / n_sleepers
    local x = ALA_POS[1] + dx * t
    local z = ALA_POS[2] + dz * t
    local ground_y = U.ground(x, z)
    local track_y = y0 + (y1 - y0) * t + 0.35

    -- Track bridge support pillar where terrain dips under the trestle
    local clearance = track_y - ground_y
    if clearance > 0.4 then
      engine.spawn{
        mesh = "cube",
        pos = {x, ground_y + clearance / 2, z},
        yaw = yaw,
        size = {1.8, clearance, 0.5},
        color = concrete_beam,
        body = "static",
        tag = "wall",
      }
    end

    -- Rail guide track beam
    engine.spawn{
      mesh = "cube",
      pos = {x, track_y, z},
      yaw = yaw,
      size = {2.2, 0.3, 4.1},
      color = rail_steel,
      body = "static",
      tag = "bridge",
    }
  end

  -- 3. Hilltop granite fortress decorative battlements & view rail
  local rock_grey = {0.36, 0.35, 0.36}
  -- Hilltop cliff overlook pointing toward Forum Marinum & Aurajoki mouth
  local overlook_pts = {
    {-1410, 1070}, {-1440, 1050}, {-1480, 1010}, {-1510, 960}
  }
  for i = 2, #overlook_pts do
    local p0, p1 = overlook_pts[i - 1], overlook_pts[i]
    local mx, mz = (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2
    local my = U.ground(mx, mz)
    local len = U.dist2d(p0[1], p0[2], p1[1], p1[2])
    local wyaw = math.atan(p1[1] - p0[1], p1[2] - p0[2])
    engine.spawn{
      mesh = "cube",
      pos = {mx, my + 0.5, mz},
      yaw = wyaw,
      size = {0.4, 1.0, len * 1.02},
      color = rock_grey,
      body = "static",
      tag = "wall",
    }
  end

  -- 4. Funikulaari passenger car
  local init_progress = 0.5
  local cur_x = ALA_POS[1] + dx * init_progress
  local cur_z = ALA_POS[2] + dz * init_progress
  local cur_y = y0 + (y1 - y0) * init_progress + 0.5

  local cabin_id = engine.spawn{
    mesh = "funikulaari",
    pos = {cur_x, cur_y, cur_z},
    yaw = yaw,
    tag = "vehicle",
    body = "kinematic",
  }

  K.funicular = {
    id = cabin_id,
    p0 = ALA_POS,
    p1 = YLA_POS,
    y0 = y0,
    y1 = y1,
    dx = dx,
    dz = dz,
    dist = dist,
    yaw = yaw,
    progress = init_progress,
    direction = 1, -- 1 = ascending to yläasema, -1 = descending
    pause = 0.0,
    speed = 0.035, -- progress delta per second (~4 m/s real funicular pace)
  }
end

function K.tick(dt)
  local f = K.funicular
  if not f or not engine.exists(f.id) then return end

  if f.pause > 0 then
    f.pause = f.pause - dt
    return
  end

  f.progress = f.progress + f.direction * f.speed * dt
  if f.progress >= 1.0 then
    f.progress = 1.0
    f.direction = -1
    f.pause = 4.0 -- station boarding pause at top
  elseif f.progress <= 0.0 then
    f.progress = 0.0
    f.direction = 1
    f.pause = 4.0 -- station boarding pause at bottom
  end

  local cur_x = f.p0[1] + f.dx * f.progress
  local cur_z = f.p0[2] + f.dz * f.progress
  local cur_y = f.y0 + (f.y1 - f.y0) * f.progress + 0.5

  engine.set_pos(f.id, cur_x, cur_y, cur_z)
end

engine.on("tick", function(dt)
  K.tick(dt or (1/60))
end)

return K
