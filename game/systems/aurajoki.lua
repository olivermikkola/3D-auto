-- Turku's Aurajoki: the restaurant boats on its quays, Suomen Joutsen at
-- Forum Marinum, the Föri ferry, a speedboat to take, and the cathedral's
-- bells at noon.
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local A = {
  bridges = {},
  riverboats = {},
  fori = nil,
}

-- The Föri's quays on either bank.
local FORI_ROUTE = {
  bank_east = {-1166.2, 1174.0},  -- Tervatori (Itäinen Rantakatu)
  bank_west = {-1258.2, 1117.2},  -- Wechterinkuja (Läntinen Rantakatu)
  yaw = -2.13,
}

function A.build(map)
  if not map or (map.id ~= "turku" and map.name ~= "Turku") then return end

  -- The river, its quays and its bridges are the map's own, from
  -- OpenStreetMap and the LiDAR terrain (lib/roadnet); this adds what floats
  -- on it. Every spot here is on the surveyed water (test/aurajoki_probe).
  local R = require "lib.roadnet"
  for _, e in ipairs(R.net().edges) do
    if e.deck and e.height and e.street then
      local a, b = e.pts[1], e.pts[#e.pts]
      local mx, mz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
      local w = R.water_level(mx, mz)
      if w then A.bridges[#A.bridges + 1] = {name = e.street, pos = {mx, mz}, deck = e.height(mx, mz), water = w} end
    end
  end

  -- Restaurant boats along the quay between Auransilta and Myllysilta, as they lie in summer.
  local boat_moorings = {
    {pos = {-101, 356}, yaw = -1.0, name = "Donna"},
    {pos = {-177, 396}, yaw = -1.0, name = "Papa Joe"},
    {pos = {-254, 436}, yaw = -1.2, name = "Aussie Bar"},
    {pos = {-322, 472}, yaw = -1.3, name = "Cindy"},
    {pos = {-410, 521}, yaw = -1.3, name = "Svarte Rudolf"},
  }
  for _, m in ipairs(boat_moorings) do
    local bid = engine.spawn{
      mesh = "riverboat",
      pos = {m.pos[1], 0.1, m.pos[2]},
      yaw = m.yaw,
      tag = "prop",
      body = "static",
    }
    A.riverboats[#A.riverboats + 1] = bid
  end

  -- Suomen Joutsen moored at Forum Marinum
  engine.spawn{
    mesh = "suomen_joutsen",
    pos = {-1708, 0.2, 1601},
    yaw = -0.7,
    tag = "ship",
    body = "static",
  }

  -- It runs between the quays, on the part of the line that's water, its
  -- ramps a few meters short of either side.
  local p0, p1 = FORI_ROUTE.bank_east, FORI_ROUTE.bank_west
  local t0, t1
  for k = 0, 100 do
    local t = k / 100
    if R.water_level(p0[1] + (p1[1] - p0[1]) * t, p0[2] + (p1[2] - p0[2]) * t) then t0, t1 = t0 or t, t end
  end
  local pad = 5.5 / U.dist2d(p0[1], p0[2], p1[1], p1[2])
  t0, t1 = (t0 or 0) + pad, (t1 or 1) - pad
  local init_progress = 0.45
  local fx = p0[1] + (p1[1] - p0[1]) * (t0 + (t1 - t0) * init_progress)
  local fz = p0[2] + (p1[2] - p0[2]) * (t0 + (t1 - t0) * init_progress)
  local fori_id = engine.spawn{
    mesh = "fori",
    pos = {fx, 0.45, fz},
    yaw = FORI_ROUTE.yaw,
    size = {10.5, 1.2, 9.2},
    tag = "ferry",
    body = "kinematic",
  }
  A.fori = {
    id = fori_id,
    target = 1, -- 0 for bank_east, 1 for bank_west
    progress = init_progress,
    t0 = t0, t1 = t1,
    pause = 0.0,
  }

  -- A Puskuri speedboat to take, by Auransilta
  local boat_id = vehicle.spawn(-45, 320, -1.8, nil, "speedboat", "boat")
  A.speedboat = boat_id

  -- 6. Aurajoki Riverbank Promenade: Stone Quays, Willows, Bollards & Lamps
  -- Follows both banks from Satama/Forum Marinum past Tuomiokirkko to Koroistenniemi.
  local river_banks = {
    -- West bank (Läntinen Rantakatu & river path)
    west = {
      {-2150, 1720}, {-1850, 1520}, {-1550, 1330}, {-1258, 1117},
      {-980, 920}, {-820, 770}, {-680, 670}, {-460, 520},
      {-310, 430}, {-150, 350}, {-25, 295}, {120, 150},
      {250, -40}, {360, -320}, {420, -680}, {460, -950},
      {620, -1250}, {880, -1550}, {1120, -1750}, {1210, -1860}
    },
    -- East bank (Itäinen Rantakatu & river path)
    east = {
      {-2050, 1820}, {-1750, 1610}, {-1450, 1410}, {-1166, 1174},
      {-920, 970}, {-760, 820}, {-620, 720}, {-400, 580},
      {-250, 480}, {-100, 400}, {25, 345}, {180, 200},
      {300, 10}, {420, -260}, {490, -640}, {540, -920},
      {720, -1210}, {980, -1510}, {1200, -1710}, {1280, -1820}
    }
  }

  -- The banks are drawn by hand and run over the riverside streets in
  -- places: nothing goes down on a carriageway.
  local function off_road(x, z, r) return not R.on_carriageway(x, z, r) end
  local quay_stone = {0.52, 0.50, 0.48}
  local bollard_iron = {0.18, 0.18, 0.20}

  for bank_name, pts in pairs(river_banks) do
    for i = 2, #pts do
      local p0, p1 = pts[i - 1], pts[i]
      local len = U.dist2d(p0[1], p0[2], p1[1], p1[2])
      local yaw = math.atan(p1[1] - p0[1], p1[2] - p0[2])
      local n_steps = math.max(1, math.floor(len / 16.0))

      for s = 0, n_steps - 1 do
        local t = s / n_steps
        local x = p0[1] + (p1[1] - p0[1]) * t
        local z = p0[2] + (p1[2] - p0[2]) * t
        local y = U.ground(x, z)

        -- Urban stone quay section (Forum Marinum to Tuomiokirkko)
        if z > -400 and z < 1700 then
          -- Low granite edge quay barrier, where it misses the street
          local fx, fz = math.sin(yaw) * 7.9, math.cos(yaw) * 7.9
          local wall = off_road(x, z, 0.6) and off_road(x + fx, z + fz, 0.6) and off_road(x - fx, z - fz, 0.6)
          if wall then engine.spawn{
            mesh = "cube",
            pos = {x, y + 0.35, z},
            yaw = yaw,
            size = {1.2, 0.7, 15.8},
            color = quay_stone,
            tag = "wall",
            body = "static",
          } end

          -- Quayside cast-iron mooring bollard every other segment
          if s % 2 == 0 and off_road(x, z, 0.4) then
            engine.spawn{
              mesh = "cylinder",
              pos = {x, y + 0.8, z},
              size = {0.35, 0.6, 0.35},
              color = bollard_iron,
              tag = "prop",
              body = "static",
            }
          end

          -- Riverside promenade weeping willows & linden trees
          local rx, rz = U.right(yaw)
          local tx = x + rx * (bank_name == "west" and -4.5 or 4.5)
          local tz = z + rz * (bank_name == "west" and -4.5 or 4.5)
          local ty = U.ground(tx, tz)
          if not R.wet(tx, tz) and off_road(tx, tz, 1.5) then
            engine.spawn{
              mesh = (s % 2 == 0) and "willow_tree" or "tree",
              pos = {tx, ty, tz},
              scale = 0.95 + (s % 3) * 0.15,
              tag = "tree",
            }
          end

          -- Promenade park benches & night lighting
          local bx = x + rx * (bank_name == "west" and -3.2 or 3.2)
          local bz = z + rz * (bank_name == "west" and -3.2 or 3.2)
          if s % 3 == 0 and off_road(bx, bz, 1) then
            engine.spawn{
              mesh = "park_bench",
              pos = {bx, U.ground(bx, bz), bz},
              yaw = yaw + (bank_name == "west" and math.pi/2 or -math.pi/2),
              tag = "prop",
            }
            engine.spawn{
              mesh = "lamp",
              pos = {bx, U.ground(bx, bz), bz},
              yaw = yaw,
              tag = "lamp",
            }
          end
        else
          -- Natural green riverbank upstream toward Koroistenniemi
          local rx, rz = U.right(yaw)
          local tx = x + rx * (bank_name == "west" and -6.0 or 6.0)
          local tz = z + rz * (bank_name == "west" and -6.0 or 6.0)
          local ty = U.ground(tx, tz)
          if not R.wet(tx, tz) and off_road(tx, tz, 1.5) then
            engine.spawn{
              mesh = "tree",
              pos = {tx, ty, tz},
              scale = 1.1 + (s % 2) * 0.2,
              tag = "tree",
            }
          end
        end
      end
    end
  end

  -- 7. Koroistenniemi Historic Memorial Cross & Bishop's Knoll
  -- Sits on the elevated promontory where Vähäjoki meets Aurajoki
  local kx, kz = 1222.0, -1865.0
  local ky = U.ground(kx, kz)
  engine.spawn{
    mesh = "koroisten_risti",
    pos = {kx, ky, kz},
    yaw = 0.45,
    tag = "landmark",
    body = "static",
  }
end

-- Update Föri ferry position across Aurajoki
function A.tick(dt)
  if not A.fori then return end
  local f = A.fori
  if f.pause > 0 then
    f.pause = f.pause - dt
    return
  end

  local speed = 0.08 * dt -- crossing takes ~12.5 seconds
  if f.target == 1 then
    f.progress = math.min(1.0, f.progress + speed)
    if f.progress >= 1.0 then
      f.target = 0
      f.pause = 6.0 -- boarding pause on west bank
    end
  else
    f.progress = math.max(0.0, f.progress - speed)
    if f.progress <= 0.0 then
      f.target = 1
      f.pause = 6.0 -- boarding pause on east bank
    end
  end

  local p0, p1 = FORI_ROUTE.bank_east, FORI_ROUTE.bank_west
  local t = f.t0 + (f.t1 - f.t0) * f.progress
  local cur_x = p0[1] + (p1[1] - p0[1]) * t
  local cur_z = p0[2] + (p1[2] - p0[2]) * t
  if engine.exists(f.id) then
    engine.set_pos(f.id, cur_x, 0.25, cur_z)
  end
end

-- The cathedral's bells ring noon over the river.
local CATHEDRAL = {428, -104} -- the tower
local last_hour
engine.on("tick", function(dt)
  A.tick(dt or (1/60))
  if not A.fori then return end
  local hour = math.floor(require("lib.daynight").hour)
  if last_hour and hour ~= last_hour and hour == 12 then
    engine.play("cathedral_bell", {pos = {CATHEDRAL[1], 25, CATHEDRAL[2]}, volume = 0.8})
  end
  last_hour = hour
end)

return A
