-- Summer terraces by the Aurajoki: the cafés, restaurants and bars near
-- the river's stone quays put tables out between their door and the water,
-- under umbrellas in the place's colour, and by day and evening people sit
-- at them (more as the evening comes on; none in the small hours).
--
-- Put up once the world has had its first physics step, so rays can see
-- what's there: on open, dry, about level ground off the carriageway, with
-- nothing standing on it (no tree, bench, lamp or wall).
local U = require "lib.util"
local city = require "lib.city"
local pois = require "lib.pois"
local quality = require "lib.quality"
local roadnet = require "lib.roadnet"
local aurajoki = require "systems.aurajoki"

local T = {list = {}, seated = 0, why = {}} -- list: {x, z, yaw, name, mesh, people = {ids}}
local KINDS = {"cafe", "restaurant", "bar", "pub", "ice_cream"}
local REACH = 70           -- m: a place this near the bank gets a terrace
local WIDE, DEEP = 7.5, 4.6 -- the terrace along the river, and out from it
local APART = 14           -- m between terraces
local NEAR = 160           -- m: people sit at terraces this near the player
local UMBRELLAS = {{0.85, 0.15, 0.15}, {0.95, 0.95, 0.92}, {0.15, 0.35, 0.6}, {0.2, 0.45, 0.25}, {0.9, 0.6, 0.1}, {0.15, 0.15, 0.15}}
local SHIRTS = {{0.8, 0.2, 0.2}, {0.2, 0.4, 0.8}, {0.9, 0.8, 0.3}, {0.3, 0.6, 0.35}, {0.15, 0.15, 0.15}, {0.9, 0.9, 0.9}, {0.6, 0.3, 0.6}, {0.9, 0.5, 0.2}}
local PANTS = {{0.15, 0.2, 0.4}, {0.25, 0.25, 0.25}, {0.5, 0.4, 0.3}, {0.1, 0.1, 0.1}}
local SKINS = {{0.95, 0.8, 0.65}, {0.85, 0.65, 0.5}, {0.6, 0.42, 0.3}, {0.4, 0.28, 0.2}}
local HAIR = {{0.1, 0.07, 0.04}, {0.45, 0.3, 0.12}, {0.8, 0.7, 0.4}, {0.5, 0.5, 0.5}}
local SITTERS = 8

-- A number 0..1 from a few others, the same every run.
local function hash(a, b, c) return math.sin(a * 12.9898 + b * 78.233 + (c or 0) * 37.719) * 43758.5453 % 1 end

-- Tables at (along, out) on the terrace, metres from its middle: three
-- along the river, two rows.
local TABLES = {{-2.5, -1.1}, {0, -1.1}, {2.5, -1.1}, {-2.5, 1.1}, {0, 1.1}, {2.5, 1.1}}
T.TABLES = TABLES

-- One terrace's mesh: its tables, chairs and umbrellas in colour c, a low
-- fence of planters along its back (the side away from the river: +z is
-- towards the water).
local function terrace_mesh(name, c)
  local wood, steel, planter, green = {0.55, 0.38, 0.22}, {0.35, 0.36, 0.38}, {0.3, 0.3, 0.32}, {0.25, 0.5, 0.22}
  local parts = {
    {mesh = "cube", pos = {0, 0.04, 0}, size = {WIDE, 0.08, DEEP}, color = {0.5, 0.36, 0.24}}, -- a deck
  }
  for _, side in ipairs{-1, 1} do
    parts[#parts + 1] = {mesh = "cube", pos = {side * (WIDE / 2 - 0.2), 0.3, 0}, size = {0.4, 0.5, DEEP}, color = planter}
    parts[#parts + 1] = {mesh = "cube", pos = {side * (WIDE / 2 - 0.2), 0.6, 0}, size = {0.35, 0.2, DEEP - 0.1}, color = green}
  end
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.3, -DEEP / 2 + 0.2}, size = {WIDE, 0.5, 0.4}, color = planter}
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.6, -DEEP / 2 + 0.2}, size = {WIDE - 0.1, 0.2, 0.35}, color = green}
  for _, t in ipairs(TABLES) do
    local x, z = t[1], t[2]
    parts[#parts + 1] = {mesh = "cylinder", pos = {x, 0.45, z}, size = {0.08, 0.74, 0.08}, color = steel}
    parts[#parts + 1] = {mesh = "cylinder", pos = {x, 0.8, z}, size = {0.75, 0.04, 0.75}, color = wood}
    for _, s in ipairs{-1, 1} do
      parts[#parts + 1] = {mesh = "cube", pos = {x + s * 0.65, 0.5, z}, size = {0.42, 0.06, 0.42}, color = steel}
      parts[#parts + 1] = {mesh = "cube", pos = {x + s * 0.84, 0.75, z}, size = {0.05, 0.5, 0.42}, color = steel}
    end
    -- The umbrella: its pole and a shallow canopy.
    parts[#parts + 1] = {mesh = "cylinder", pos = {x, 1.4, z}, size = {0.05, 1.9, 0.05}, color = {0.85, 0.85, 0.85}}
    parts[#parts + 1] = {mesh = "cylinder", pos = {x, 2.3, z}, size = {2.1, 0.12, 2.1}, color = c}
    parts[#parts + 1] = {mesh = "cylinder", pos = {x, 2.4, z}, size = {1.2, 0.1, 1.2}, color = c}
  end
  engine.mesh(name, parts)
end

-- Someone sat on a chair (feet on the deck, the chair's seat at 0.53 m),
-- facing +z. The entity stands at the seat.
local function sitter_mesh(name, shirt, pants, skin, hair)
  engine.mesh(name, {
    {mesh = "cube", pos = {0.13, 0.06, 0.2}, size = {0.2, 0.18, 0.5}, color = pants},  -- thighs
    {mesh = "cube", pos = {-0.13, 0.06, 0.2}, size = {0.2, 0.18, 0.5}, color = pants},
    {mesh = "cube", pos = {0.13, -0.24, 0.42}, size = {0.18, 0.5, 0.18}, color = pants}, -- shins
    {mesh = "cube", pos = {-0.13, -0.24, 0.42}, size = {0.18, 0.5, 0.18}, color = pants},
    {mesh = "cube", pos = {0, 0.48, -0.02}, size = {0.56, 0.66, 0.32}, color = shirt},
    {mesh = "cube", pos = {0.34, 0.45, 0.04}, size = {0.14, 0.55, 0.18}, color = skin},
    {mesh = "cube", pos = {-0.34, 0.45, 0.04}, size = {0.14, 0.55, 0.18}, color = skin},
    {mesh = "sphere", pos = {0, 0.98, 0}, size = 0.34, color = skin},
    {mesh = "cube", pos = {0, 1.07, -0.03}, size = {0.36, 0.12, 0.36}, color = hair},
  })
end

function T.build()
  T.pending = city.map().id == "turku" and city.network() ~= nil
  if not T.pending then return end
  local function pick(t, i) return t[i % #t + 1] end
  for i = 1, SITTERS do
    sitter_mesh("sitter" .. i, pick(SHIRTS, i * 3), pick(PANTS, i), pick(SKINS, i * 5), pick(HAIR, i * 7))
  end
  for i, c in ipairs(UMBRELLAS) do terrace_mesh("terrace" .. i, c) end
end

-- The nearest point on the stone quays' banks to (x, z): bx, bz, distance.
local function bank_point(x, z)
  local best, bx, bz = math.huge
  for _, pts in pairs(aurajoki.BANKS) do
    for i = 2, #pts do
      local a, b = pts[i - 1], pts[i]
      local dx, dz = b[1] - a[1], b[2] - a[2]
      local t = U.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / (dx * dx + dz * dz), 0, 1)
      local px, pz = a[1] + dx * t, a[2] + dz * t
      local d = U.dist2d(x, z, px, pz)
      if d < best and pz > aurajoki.QUAYS[1] and pz < aurajoki.QUAYS[2] then best, bx, bz = d, px, pz end
    end
  end
  return bx, bz, best
end

-- Room for a terrace at (x, z) facing yaw (+z to the river): off the
-- road, dry, about level, nothing on it. Returns the ground's y or why not.
local function room(x, z, yaw)
  local fx, fz = U.forward(yaw)
  local rx, rz = U.right(yaw)
  local y = U.ground(x, z)
  for _, c in ipairs{{-1, -1}, {1, -1}, {-1, 1}, {1, 1}, {0, 0}, {-1, 0}, {1, 0}} do
    local px = x + rx * c[1] * (WIDE / 2 + 0.5) + fx * c[2] * (DEEP / 2 + 0.5)
    local pz = z + rz * c[1] * (WIDE / 2 + 0.5) + fz * c[2] * (DEEP / 2 + 0.5)
    if roadnet.on_carriageway(px, pz, 1.5) then return nil, "road" end
    if roadnet.wet(px, pz) then return nil, "water" end
    if math.abs(U.ground(px, pz) - y) > 0.5 then return nil, "slope" end
    local hit = engine.raycast(px, y + 8, pz, 0, -1, 0, 7.6)
    if hit and engine.tag(hit) ~= "sidewalk" then return nil, "taken" end
  end
  return y
end

local function put_up()
  local places = pois.find{amenity = KINDS, road = false}
  local t0 = os.clock()
  for _, p in ipairs(places) do
    local bx, bz, d = bank_point(p.x, p.z)
    local why
    if not bx or d > REACH then
      why = "far"
    else
      -- From the place towards the water, the first spot with room (not
      -- right at the bank: the quay's wall and willows are there).
      local yaw = math.atan(bx - p.x, bz - p.z)
      local fx, fz = U.forward(yaw)
      why = "no room"
      for s = 3, d - 4, 1.5 do
        local x, z = p.x + fx * s, p.z + fz * s
        local near = false
        for _, t in ipairs(T.list) do
          if U.dist2d(t.x, t.z, x, z) < APART then near = true break end
        end
        if near then why = "crowded" break end
        local y, no = room(x, z, yaw)
        if y then
          local mesh = "terrace" .. math.floor(hash(p.x, p.z) * #UMBRELLAS + 1)
          local id = engine.spawn{mesh = mesh, pos = {x, y, z}, yaw = yaw, tag = "prop"}
          T.list[#T.list + 1] = {id = id, x = x, y = y, z = z, yaw = yaw, name = p.name, kind = p.tags.amenity}
          why = nil
          break
        end
        why = no
      end
    end
    if why then T.why[why] = (T.why[why] or 0) + 1 end
  end
  local whys = {}
  for k, n in pairs(T.why) do whys[#whys + 1] = k .. " " .. n end
  table.sort(whys)
  print(string.format("terraces: %d at %d places, %.0f ms (none: %s)", #T.list, #places, (os.clock() - t0) * 1000, table.concat(whys, ", ")))
end

-- How full the terraces are at this hour, 0..1.
function T.busy(hour)
  if hour < 10 or hour >= 23.5 then return 0 end
  if hour < 12 then return 0.25 end
  if hour < 16 then return 0.45 end
  return 0.75
end

-- Seat people at terrace t for the hour: each chair taken with chance busy.
local function seat(t, hour)
  t.people = {}
  local busy = T.busy(hour)
  local fx, fz = U.forward(t.yaw)
  local rx, rz = U.right(t.yaw)
  for k, tb in ipairs(TABLES) do
    for _, s in ipairs{-1, 1} do
      if hash(t.x + k, t.z + s, math.floor(hour)) < busy then
        -- On the chair at the table's side, facing the table (the chair's
        -- at +-0.65 along the terrace).
        local along, out = tb[1] + s * 0.65, tb[2]
        local x = t.x - rx * along + fx * out
        local z = t.z - rz * along + fz * out
        local i = math.floor(hash(x, z, hour) * SITTERS) + 1
        t.people[#t.people + 1] = engine.spawn{mesh = "sitter" .. i, pos = {x, t.y + 0.53, z}, yaw = t.yaw - s * math.pi / 2, tag = "prop"}
      end
    end
  end
  T.seated = T.seated + #t.people
end

local function unseat(t)
  for _, id in ipairs(t.people or {}) do engine.despawn(id) end
  T.seated = T.seated - #(t.people or {})
  t.people = nil
end

local wait = 0
engine.on("tick", function(dt)
  -- (Once the shelters are up: a terrace mustn't go where one will stand.)
  if T.pending and engine.ticks() > 1 and not require("systems.shelters").pending then
    T.pending = false
    put_up()
  end
  wait = wait - dt
  if wait > 0 or #T.list == 0 then return end
  wait = 1
  -- (A still picture: around its camera rather than the player.)
  local still = os.getenv("SHOT_CAM")
  local x, _, z = U.player_pos()
  if still then x, z = still:match("^([^,]+),[^,]+,([^,]+)") end
  x, z = tonumber(x), tonumber(z)
  if not x then return end
  local hour = require("lib.daynight").hour
  for _, t in ipairs(T.list) do
    local near = U.dist2d(x, z, t.x, t.z) < NEAR and quality.tier() > 1
    -- A new hour, new people: only out of sight (60 m off).
    local stale = t.hour ~= math.floor(hour) and U.dist2d(x, z, t.x, t.z) > 60
    if t.people and (not near or stale) then unseat(t) end
    if near and not t.people then
      t.hour = math.floor(hour)
      seat(t, hour)
    end
  end
end)

return T
