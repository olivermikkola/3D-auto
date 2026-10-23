-- What free-roam jobs (taxi fares, ambulance calls) share: places picked
-- by the hour from a closed list, a stop at the kerb by a place with
-- someone waiting on the pavement, markers that the GPS heads for, and
-- "stopped there".
local G = require "lib.state"
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local E = {}

-- Is the hour inside h = {from, to} (round midnight if from > to)? nil: any hour.
function E.hours_ok(h)
  if not h then return true end
  local now = require("lib.daynight").hour
  if h[1] < h[2] then return now >= h[1] and now < h[2] end
  return now >= h[1] or now < h[2]
end

-- The kinds in list ({tags, hours, weight, ...} each) that fit the hour,
-- heaviest first by a seeded draw.
function E.kinds(list, seed)
  local out = {}
  for i, k in ipairs(list) do
    if E.hours_ok(k[2]) then out[#out + 1] = {k, ((seed * 7919 + i * 104729) % 1000) / 1000 * k[3]} end
  end
  table.sort(out, function(a, b) return a[2] > b[2] end)
  for i, k in ipairs(out) do out[i] = k[1] end
  return out
end

-- A lib/template role named `name` for a place of `kind`, with a name, and
-- the `extra` conditions.
function E.role(name, kind, extra)
  local r = {name, name = true}
  for k, v in pairs(kind[1]) do r[k] = v end
  for k, v in pairs(extra) do r[k] = v end
  return r
end

-- Where a car stops for place p (lib/pois), and a spot on the pavement
-- beside it on the place's side.
function E.kerb(p)
  local roadnet = require "lib.roadnet"
  local rx, rz = p.road[1], p.road[2]
  local dx, dz = p.x - rx, p.z - rz
  local l = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
  local e = roadnet.nearest_edge(rx, rz)
  local w = e and roadnet.net().edges[e].width or 8
  return rx, rz, rx + dx / l * (w / 2 + 1.2), rz + dz / l * (w / 2 + 1.2)
end

-- A marker at (x, z) with its blip on the minimap: entity id, blip.
function E.mark(x, z, color)
  local id = engine.spawn{mesh = "marker", pos = {x, 2.5 + U.ground(x, z), z}, scale = 4, color = {color[1], color[2], color[3], 0.35}}
  local blip = {id = id, color = color}
  G.markers[#G.markers + 1] = blip
  return id, blip
end

-- Off the minimap.
function E.forget(blip)
  for i, b in ipairs(G.markers) do if b == blip then table.remove(G.markers, i) break end end
end

-- Is the player's car stopped within r m of (x, z)?
function E.stopped_at(x, z, r)
  local px, _, pz = U.player_pos()
  return G.vehicle and px and U.dist2d(px, pz, x, z) < r and math.abs(vehicle.speed(G.vehicle)) < 2
end

return E
