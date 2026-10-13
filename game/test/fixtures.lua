-- Shared autoplay fixtures: attribution is scoped to a phase and an attacker;
-- geometry checks reserve a car-width approach, not just a center ray.
local G = require "lib.state"
local F = {}

function F.runovers()
  local r = {count = 0}
  function r:start(car)
    assert(car and engine.exists(car) and G.vehicle == car and not G.dead,
           "run-over phase requires a live occupied attacker")
    assert(require("lib.health").get(car) > 0 and not require("systems.carnage").burning[car],
           "run-over phase requires a healthy non-burning attacker")
    self.car, self.count, self.victim = car, 0, nil
  end
  function r:stop() self.car = nil end
  engine.on("ped_down", function(body, by)
    if r.car and by == r.car and by == G.vehicle then
      r.count, r.victim = r.count + 1, body
    end
  end)
  return r
end

function F.outward(x, z, bx, bz)
  if math.abs(x - bx) / G.city.bx > math.abs(z - bz) / G.city.bz then
    return x > bx and 1 or -1, 0
  end
  return 0, z > bz and 1 or -1
end

function F.clear_approach(x, z, nx, nz, car)
  for _, tag in ipairs{"lamp", "car", "cop"} do
    for _, obstacle in ipairs(engine.find(tag)) do
      if obstacle ~= car then
        local lx, _, lz = engine.pos(obstacle)
        local along = (lx - x) * nx + (lz - z) * nz
        local across = math.abs((lx - x) * nz - (lz - z) * nx)
        local margin = tag == "lamp" and 3 or 5
        if along > -margin and along < 12 + margin and across < margin then return false end
      end
    end
  end
  return true
end

-- Horizontal swept corridor, including the space AFTER contact. A center
-- ray alone misses the car's sides; the ragdoll also needs vertical room.
-- Walk through dynamic hits so a pedestrian cannot mask a building behind it.
local BACKSTOP = {building = true, container = true, landmark = true, wall = true,
                  tree = true, lamp = true, carpark = true, garage = true, fountain = true}
function F.clear_flight(x, z, dx, dz, car)
  -- Thin poles can fall BETWEEN swept rays; reserve their full footprint.
  for _, tag in ipairs{"lamp", "tree", "car", "cop", "wreck"} do
    local margin = (tag == "lamp" or tag == "tree") and 2 or 5
    for _, id in ipairs(engine.find(tag)) do
      if id ~= car then
        local ox, _, oz = engine.pos(id)
        local along, across = (ox-x)*dx + (oz-z)*dz, math.abs((ox-x)*dz - (oz-z)*dx)
        if along > -12-margin and along < 30+margin and across < margin then return false end
      end
    end
  end
  for across = -1.2, 1.2, 0.2 do
    for _, height in ipairs{0.8, 1.8, 3, 5} do
      local ox, oz = x - dx * 12 + dz * across, z - dz * 12 - dx * across
      local remaining, ignore, y = 42, car, height + require("lib.util").ground(ox, oz)
      for _ = 1, 64 do
        local hit, distance = engine.raycast(ox, y, oz, dx, 0, dz, remaining, ignore)
        if not hit then break end
        local tag = engine.tag(hit)
        if BACKSTOP[tag] or ((tag == "car" or tag == "cop" or tag == "wreck") and hit ~= car) then return false end
        local advance = distance + 0.05
        ox, oz, remaining, ignore = ox + dx * advance, oz + dz * advance, remaining - advance, hit
        if remaining <= 0 then break end
      end
    end
  end
  return true
end

-- A crossing fixture on a verified road corridor avoids the narrow sidewalk's
-- frontage/corner-lamp backstops. Move only one existing walker for setup;
-- its normal walk/flee AI and the real car contact/ragdoll remain untouched.
function F.runover_spot(car)
  local city = require "lib.city"
  local px, _, pz = engine.pos(car)
  local best, spot = math.huge, nil
  for _, road in ipairs(city.roads()) do
    local path = city.path(road[1], road[2])
    for i = 2, #path do
      local ax, az, bx, bz = path[i-1][1], path[i-1][2], path[i][1], path[i][2]
      local len = math.sqrt((bx-ax)^2+(bz-az)^2)
      local dx, dz = (bx-ax)/len, (bz-az)/len
      for _, t in ipairs{0.35, 0.65} do
        local x, z = ax+(bx-ax)*t, az+(bz-az)*t
        local distance = (x-px)^2+(z-pz)^2
        if distance < best and F.clear_flight(x,z,dx,dz,car) then
          best, spot = distance, {x,z,dx,dz}
        end
      end
    end
  end
  return spot
end
return F
