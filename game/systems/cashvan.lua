-- A Lumis cash van: now and then, between missions, one pulls away from a
-- bank near you (a real one on maps with points of interest) and does its
-- round with traffic, green on the map. Ram it or shoot it and it runs for
-- it; wreck it and the cash bags spill on the street: grab them before the
-- cops grab you (two stars). Nobody makes you: leave it and it drives off.
local G = require "lib.state"
local H = require "lib.health"
local U = require "lib.util"
local city = require "lib.city"
local pois = require "lib.pois"
local traffic = require "systems.traffic"
local wanted = require "lib.wanted"

local V = {
  FIRST = 150,   -- seconds of play before the first van
  EVERY = 300,   -- between vans
  BAGS = 4, BAG_CASH = 250,
  BAG_LIFE = 60, -- seconds the bags lie there
  GONE = 450,    -- a van this far off (m) is done with its round
}
local van, blip, bags, next_at, banks_used = nil, nil, {}, nil, 0

function V.build()
  local grey, dark, glass, tire = {0.72, 0.74, 0.76}, {0.2, 0.22, 0.24}, {0.15, 0.2, 0.28}, {0.08, 0.08, 0.08}
  -- Collider 2.2 x 2.2 x 5.2, +Z the front: a cab and a windowless box.
  local parts = {
    {mesh = "cube", pos = {0, -0.55, 0}, size = {2.2, 0.5, 5.2}, color = dark},
    {mesh = "cube", pos = {0, 0.35, -0.6}, size = {2.2, 1.5, 4.0}, color = grey},
    {mesh = "cube", pos = {0, 0.1, 1.95}, size = {2.1, 1.0, 1.3}, color = grey},
    {mesh = "cube", pos = {0, 0.3, 2.42}, size = {1.9, 0.5, 0.4}, color = glass},
    {mesh = "cube", pos = {0, 0.3, 1.95}, size = {2.14, 0.45, 0.9}, color = glass},
    -- The company stripe and the armoured rear doors.
    {mesh = "cube", pos = {0, 0.55, -0.6}, size = {2.24, 0.3, 3.6}, color = {0.1, 0.55, 0.3}},
    {mesh = "cube", pos = {0, 0.3, -2.62}, size = {1.8, 1.2, 0.06}, color = dark},
    {mesh = "cube", pos = {0.65, -0.35, 2.61}, size = {0.4, 0.18, 0.04}, color = {1, 0.95, 0.7}, emissive = 1},
    {mesh = "cube", pos = {-0.65, -0.35, 2.61}, size = {0.4, 0.18, 0.04}, color = {1, 0.95, 0.7}, emissive = 1},
    {mesh = "cube", pos = {0.75, -0.35, -2.61}, size = {0.35, 0.15, 0.04}, color = {0.9, 0.05, 0.05}, emissive = 1},
    {mesh = "cube", pos = {-0.75, -0.35, -2.61}, size = {0.35, 0.15, 0.04}, color = {0.9, 0.05, 0.05}, emissive = 1},
    {mesh = "cube", pos = {0, 1.12, 1.0}, size = {0.6, 0.12, 0.3}, color = {1, 0.6, 0.1}, emissive = 1},
  }
  for _, w in ipairs{{1.0, 1.7}, {-1.0, 1.7}, {1.0, -1.7}, {-1.0, -1.7}} do
    parts[#parts + 1] = {mesh = "cylinder", axis = "x", pos = {w[1], -0.7, w[2]}, size = {0.34, 0.85, 0.85}, color = tire}
  end
  engine.mesh("cashvan", parts)
  engine.mesh("cashbag", {
    {mesh = "cube", pos = {0, 0, 0}, size = {0.5, 0.45, 0.4}, color = {0.85, 0.85, 0.75}},
    {mesh = "cube", pos = {0, 0.26, 0}, size = {0.2, 0.1, 0.2}, color = {0.85, 0.85, 0.75}},
    {mesh = "cube", pos = {0, 0, 0.21}, size = {0.22, 0.22, 0.02}, color = {0.1, 0.6, 0.25}, emissive = 1},
  })
  next_at = engine.time() + V.FIRST
end

-- Where the next van sets off: the junction by a bank 120-500 m from you
-- (the next one along each time), else the map's own bank spot; nil if
-- there's none.
local function bank_near(x, z)
  local list = pois.find{amenity = "bank", from = {x, z}, min_dist = 120, max_dist = 500}
  if #list > 0 then
    banks_used = banks_used + 1
    local b = list[(banks_used - 1) % #list + 1]
    if b.junction then
      local jx, jz = city.pos(b.junction)
      return jx, jz, b.name
    end
    return b.x, b.z, b.name
  end
  if city.has("bank") then
    local bx, bz = city.place("bank")
    if U.dist2d(bx, bz, x, z) <= 600 then return bx, bz end
  end
end

local function forget_blip()
  for i, b in ipairs(G.markers) do if b == blip then table.remove(G.markers, i) break end end
  blip = nil
end

-- The van is done: driven off, or wrecked (it burns on as carnage's).
local function done()
  if van and traffic.cars[van] then traffic.cars[van].keep = nil end
  van = nil
  forget_blip()
  next_at = engine.time() + V.EVERY
end

function V.spawn(x, z, name)
  local id = engine.spawn{mesh = "cashvan", pos = {x, 1.15 + U.ground(x, z), z}, yaw = 0, size = {2.2, 2.2, 5.2},
                          body = "dynamic", mass = 3500, friction = 0, step = 0.45, tag = "car"}
  H.set(id, H.VEHICLE_HP * 1.6)
  van = id
  local c = traffic.adopt(id, {keep = true, cruise = 8})
  -- Facing the way it drives off.
  local a, b = c.path[1], c.path[2]
  if a and b and (a[1] ~= b[1] or a[2] ~= b[2]) then engine.orient(id, math.atan(b[1] - a[1], b[2] - a[2])) end
  blip = {id = id, color = {0.2, 0.95, 0.4}, ambient = true} -- (the GPS takes a job's goal first)
  G.markers[#G.markers + 1] = blip
  U.message("A LUMIS CASH VAN IS LEAVING " .. (name and name:upper() or "THE BANK"), 4)
  engine.emit("cashvan", name)
  return id
end

local function spill(x, y, z)
  for i = 1, V.BAGS do
    local a = i / V.BAGS * math.pi * 2
    local id = engine.spawn{mesh = "cashbag", pos = {x + math.cos(a) * 1.5, y + 1.2, z + math.sin(a) * 1.5}, size = {0.5, 0.45, 0.4},
                            body = "dynamic", mass = 8, friction = 0.8, tag = "cashbag", glow = 0.6}
    engine.set_vel(id, math.cos(a) * 4, 5, math.sin(a) * 4)
    bags[#bags + 1] = {id = id, till = engine.time() + V.BAG_LIFE}
  end
end

engine.on("damaged", function(id)
  if id ~= van then return end
  local c = traffic.cars[id]
  if c and (c.cruise or 0) < 18 then
    c.cruise = 19
    U.message("THE CASH VAN IS RUNNING", 3)
    if wanted.stars() < 1 then wanted.set(1) end
  end
end)

engine.on("killed", function(id)
  if id ~= van then return end
  local x, y, z = engine.pos(id)
  spill(x, y, z)
  U.message("THE CASH IS OUT: GRAB THE BAGS!", 4)
  wanted.set(math.max(wanted.stars(), 2))
  engine.emit("cashvan_robbed")
  done()
end)

-- Bags are picked up by walking or driving over them.
engine.on("tick", function()
  if not next_at then return end
  local now = engine.time()
  local px, py, pz = U.player_pos()
  for i = #bags, 1, -1 do
    local b = bags[i]
    if not engine.exists(b.id) or now > b.till then
      if engine.exists(b.id) then engine.despawn(b.id) end
      table.remove(bags, i)
    elseif px and not G.dead then
      local x, y, z = engine.pos(b.id)
      if U.dist2d(x, z, px, pz) < (G.vehicle and 3 or 1.6) and math.abs(y - py) < 3 then
        engine.despawn(b.id)
        table.remove(bags, i)
        G.cash = G.cash + V.BAG_CASH
        engine.play("pickup")
        U.message(string.format("+$%d", V.BAG_CASH), 1.5)
        require("lib.progress").touch()
      end
    end
  end

  if van then
    if not engine.exists(van) or G.vehicle == van then return done() end
    local x, _, z = engine.pos(van)
    if px and U.dist2d(x, z, px, pz) > V.GONE then
      engine.despawn(van)
      return done()
    end
    return
  end
  -- A new van only in free roam: no mission, no cops, not wasted.
  if now < next_at or G.mission or G.dead or wanted.stars() > 0 or not px then return end
  local bx, bz, name = bank_near(px, pz)
  if not bx then next_at = now + 30; return end
  V.spawn(bx, bz, name)
end)

-- For tests: the next van as soon as it may come.
function V.soon() next_at = engine.time() end
V.van = function() return van end
V.bags = function() return bags end

return V
