-- Municipal borders, border crossings, natural barriers and restricted military zones.
-- OpenStreetMap data (ODbL) + terrain elevation (Maanmittauslaitos CC BY 4.0).
local G = require "lib.state"
local U = require "lib.util"
local wanted = require "lib.wanted"
local city = require "lib.city"

local B = {
  fences = {},
  gates = {},
  crossings = {},
  military_zones = {},
}

function B.build(map)
  if not map then return end
  local roadnet = require "lib.roadnet"

  -- 1. Military zone perimeter fences, gates, and guard posts (e.g. Pansion varuskunta)
  for _, m in ipairs(map.military or {}) do
    local ring = m.polygon
    if ring and #ring >= 3 then
      B.military_zones[#B.military_zones + 1] = {
        name = m.name or "Military Area",
        stars = m.stars or 3,
        polygon = ring,
      }

      -- Spawn security fences along segments, skipping gate openings
      local gates = m.gates or {}
      for i = 2, #ring do
        local ax, az = ring[i - 1][1], ring[i - 1][2]
        local bx, bz = ring[i][1], ring[i][2]
        local len = U.dist2d(ax, az, bx, bz)
        if len > 0.1 then
          local yaw = math.atan(bx - ax, bz - az)
          local n = math.max(1, math.ceil(len / 4))
          for k = 0, n - 1 do
            local mx = ax + (bx - ax) * (k + 0.5) / n
            local mz = az + (bz - az) * (k + 0.5) / n
            -- Check if near any gate opening
            local near_gate = false
            for _, g in ipairs(gates) do
              if U.dist2d(mx, mz, g.pos[1], g.pos[2]) < (g.width or 7) / 2 + 1 then
                near_gate = true
                break
              end
            end
            if not near_gate then
              local ground_y = U.ground(mx, mz)
              -- Extrude fence panel with posts
              local seg_len = len / n
              engine.spawn{
                mesh = "cube",
                pos = {mx, ground_y + 1.25, mz},
                yaw = yaw,
                size = {0.12, 2.5, seg_len * 1.02},
                color = {0.32, 0.35, 0.34},
                tag = "fence",
                body = "static",
              }
              -- Barbed-wire top strip
              engine.spawn{
                mesh = "cube",
                pos = {mx, ground_y + 2.55, mz},
                yaw = yaw,
                size = {0.35, 0.15, seg_len * 1.02},
                color = {0.22, 0.22, 0.25},
                tag = "fence",
                body = "static",
              }
            end
          end
        end
      end

      -- Spawn gates with guardhouse, barrier posts, and boom barriers
      for _, g in ipairs(gates) do
        local gx, gz = g.pos[1], g.pos[2]
        local gy = U.ground(gx, gz)
        local gyaw = g.yaw or 0
        local rx, rz = U.right(gyaw)

        -- Guardhouse prop
        engine.spawn{
          mesh = "guardhouse",
          pos = {gx + rx * 4.2, gy, gz + rz * 4.2},
          yaw = gyaw,
          tag = "guardhouse",
          body = "static",
        }

        -- Barrier posts on either side
        engine.spawn{
          mesh = "barrier_post",
          pos = {gx - rx * 2.8, gy, gz - rz * 2.8},
          yaw = gyaw,
          tag = "prop",
          body = "static",
        }
        engine.spawn{
          mesh = "barrier_post",
          pos = {gx + rx * 2.8, gy, gz + rz * 2.8},
          yaw = gyaw,
          tag = "prop",
          body = "static",
        }

        -- Boom barrier arm across the entrance
        local arm_id = engine.spawn{
          mesh = "cube",
          pos = {gx, gy + 1.1, gz},
          yaw = gyaw,
          size = {5.4, 0.14, 0.14},
          color = {0.95, 0.2, 0.15},
          tag = "boom_barrier",
        }

        B.gates[#B.gates + 1] = {
          pos = {gx, gz},
          radius = 9,
          barrier_id = arm_id,
          open = false,
          arm_y = gy + 1.1,
          yaw = gyaw,
        }
      end
    end
  end

  -- 2. Wooden footbridge over river/boundary (e.g. Punttamäenpolun silta)
  for _, fb in ipairs(map.wooden_footbridges or {}) do
    local width = fb.width or 2.6
    local pts = fb.points
    if pts and #pts >= 2 then
      local total_len = 0
      for i = 2, #pts do total_len = total_len + U.dist2d(pts[i-1][1], pts[i-1][2], pts[i][1], pts[i][2]) end
      for i = 2, #pts do
        local ax, az = pts[i - 1][1], pts[i - 1][2]
        local bx, bz = pts[i][1], pts[i][2]
        local seg = U.dist2d(ax, az, bx, bz)
        local n = math.max(1, math.ceil(seg / 3))
        local yaw = math.atan(bx - ax, bz - az)
        local rx, rz = U.right(yaw)
        for k = 0, n - 1 do
          local t0, t1 = k / n, (k + 1) / n
          local mx = ax + (bx - ax) * (t0 + t1) / 2
          local mz = az + (bz - az) * (t0 + t1) / 2
          local my = math.max(U.ground(mx, mz), 1.6)
          -- Wooden deck planks
          engine.spawn{
            mesh = "cube",
            pos = {mx, my + 0.1, mz},
            yaw = yaw,
            size = {width, 0.2, seg / n * 1.02},
            color = {0.48, 0.36, 0.24}, -- warm wood plank color
            tag = "bridge",
            body = "static",
          }
          -- Wooden handrails on left and right
          for _, side in ipairs{-1, 1} do
            engine.spawn{
              mesh = "cube",
              pos = {mx + rx * side * (width / 2 - 0.08), my + 0.65, mz + rz * side * (width / 2 - 0.08)},
              yaw = yaw,
              size = {0.14, 0.9, seg / n * 1.02},
              color = {0.42, 0.31, 0.19},
              tag = "wall",
              body = "static",
            }
          end
        end
        -- Wooden bollards at both bridge ends so cars cannot physically enter
        for _, end_pt in ipairs{pts[1], pts[#pts]} do
          local ey = U.ground(end_pt[1], end_pt[2])
          engine.spawn{
            mesh = "wood_bollard",
            pos = {end_pt[1], ey, end_pt[2]},
            tag = "bollard",
            body = "static",
          }
        end
      end
    end
  end

  -- 3. Border road crossings with roadworks/blockades
  for _, c in ipairs(map.border_crossings or {}) do
    B.crossings[#B.crossings + 1] = {
      pos = c.pos,
      target_map = c.target_map or "turku",
      target_pos = c.target_pos or {0, 0},
      name = c.name,
    }
    local cx, cz = c.pos[1], c.pos[2]
    local cy = U.ground(cx, cz)
    local cyaw = c.yaw or 0
    local rx, rz = U.right(cyaw)
    local width = c.kind == "highway" and 12 or 9

    -- Place roadside boundary markers and warning cones (leaving drivable passing lane)
    local count = math.ceil(width / 3.0)
    for i = 0, count - 1 do
      local offset = (i - (count - 1) / 2) * 2.8
      engine.spawn{
        mesh = "jersey_barrier",
        pos = {cx + rx * offset, cy, cz + rz * offset},
        tag = "barrier",
        body = "static",
      }
    end
  end

  for _, c in ipairs(map.crossings or {}) do
    B.crossings[#B.crossings + 1] = {
      pos = c.pos,
      target_map = c.target_map or "raisio",
      target_pos = c.target_pos or {0, 0},
      name = c.name,
    }
    local cx, cz = c.pos[1], c.pos[2]
    local cy = U.ground(cx, cz)
    local cyaw = c.yaw or 0
    local rx, rz = U.right(cyaw)
    engine.spawn{
      mesh = "jersey_barrier",
      pos = {cx + rx * 2.5, cy, cz + rz * 2.5},
      tag = "barrier",
      body = "static",
    }
    engine.spawn{
      mesh = "jersey_barrier",
      pos = {cx - rx * 2.5, cy, cz - rz * 2.5},
      tag = "barrier",
      body = "static",
    }
  end

  -- 4. Raisionjoki River natural boundary pine belt along the western municipal border
  if map.id == "turku" or map.id == "raisio" then
    local border_line = {
      {-2200, -800}, {-2400, -200}, {-2600, 50}, {-2700, 350}, {-2800, 600}, {-2000, 750}, {-920, -820}
    }
    for i = 2, #border_line do
      local p0, p1 = border_line[i - 1], border_line[i]
      local dist = U.dist2d(p0[1], p0[2], p1[1], p1[2])
      local steps = math.floor(dist / 25)
      for k = 1, steps - 1 do
        local bx = p0[1] + (p1[1] - p0[1]) * k / steps
        local bz = p0[2] + (p1[2] - p0[2]) * k / steps
        -- Ensure trees don't spawn right on the active paved crossings or any road
        local near_road = false
        for _, cr in ipairs(B.crossings) do
          if U.dist2d(bx, bz, cr.pos[1], cr.pos[2]) < 25 then
            near_road = true
            break
          end
        end
        if not near_road and city.network() and roadnet then
          local _, _, rx, rz = roadnet.nearest_edge(bx, bz)
          if rx and U.dist2d(bx, bz, rx, rz) < 18 then
            near_road = true
          end
        end
        if not near_road then
          local by = U.ground(bx, bz)
          engine.spawn{
            mesh = "tree",
            pos = {bx + (k % 2 == 0 and 6 or -6), by, bz},
            size = {0.8, 8.5, 0.8},
            scale = 1.1,
            tag = "tree",
            body = "static",
          }
        end
      end
    end
  end
end

-- Tick checks: wanted level alert on crossing military perimeter & gate boom barrier interaction
local warned = false
local last_check = 0
local transitioning = false

engine.on("tick", function()
  local px, py, pz = U.player_pos()
  if not px then return end

  -- Check military zone perimeter intrusion
  for _, zone in ipairs(B.military_zones) do
    if U.inside_polygon(px, pz, zone.polygon) then
      if wanted.stars() < zone.stars then
        wanted.set(zone.stars)
        if not warned then
          U.message("RESTRICTED MILITARY ZONE: " .. zone.name, 4)
          warned = true
        end
      end
    else
      warned = false
    end
  end

  local now = engine.time()
  if now - last_check < 0.25 then return end
  last_check = now

  -- 4. Check seamless cross-border highway transitions
  if not transitioning and (B.crossings and #B.crossings > 0) then
    for _, cr in ipairs(B.crossings) do
      if U.dist2d(px, pz, cr.pos[1], cr.pos[2]) < 12 then
        transitioning = true
        U.message("ENTERING " .. (cr.target_map == "turku" and "TURKU" or "RAISIO") .. "...", 3)
        -- Save player transition state: car/on-foot, wanted level, weapons, cash
        local v_id = G.vehicle
        local state = {
          target_pos = cr.target_pos or {0, 0},
          wanted_stars = wanted.stars(),
          in_vehicle = (v_id ~= nil),
        }
        engine.save("cross_city_transfer", state)
        local city = require "lib.city"
        city.choose(cr.target_map)
        return
      end
    end
  end

  -- Check gate approach: if wanted, gate stays down / alarms; if player approaches gate, raise boom barrier
  for _, g in ipairs(B.gates) do
    local d = U.dist2d(px, pz, g.pos[1], g.pos[2])
    if d < g.radius and not g.open then
      -- Animate/raise barrier
      g.open = true
      engine.set_pos(g.barrier_id, g.pos[1], g.arm_y + 3.0, g.pos[2])
    elseif d >= g.radius + 3 and g.open then
      -- Lower barrier
      g.open = false
      engine.set_pos(g.barrier_id, g.pos[1], g.arm_y, g.pos[2])
    end
  end
end)

return B
