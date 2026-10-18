-- Points of interest from the map data (OpenStreetMap tags, made by
-- tools/osm_import.py --only-pois), for missions that say what a place is
-- rather than where it is (see docs/MISSION_TEMPLATES.md):
--
--   pois.find{amenity = "place_of_worship", from = {x, z}, min_dist = 2000}
--
-- A tag condition is a value ("supermarket"), a list of values (any of them
-- will do) or true (the tag is there at all). Every result is by a street a
-- car can stop on (not a motorway): its nearest such road is at most
-- `road_dist` meters off (default 80); `road = false` drops that condition.
-- Results are nearest `from` first (by name without it), at most `limit` of
-- them, each as {x, z, tags, name, road = {x, z}, junction, dist} (dist is 0
-- without `from`). A map without points of interest (the grid maps) finds
-- nothing.
local city = require "lib.city"
local roadnet = require "lib.roadnet"

local P = {}

local OPTIONS = {from = true, min_dist = true, max_dist = true, road = true, road_dist = true, limit = true}
local ROAD_DIST = 80

local lists = setmetatable({}, {__mode = "k"}) -- per map table

local function all()
  local map = city.map()
  local list = lists[map]
  if not list then
    list = {}
    for i, p in ipairs(map.pois or {}) do
      list[i] = {x = p[1], z = p[2], tags = p[3], name = p[3].name}
    end
    lists[map] = list
  end
  return list
end

-- Where a car stops for p: the nearest point on a street (not a motorway),
-- how far that is from p, and the nearer junction of that street. Worked
-- out once per point.
local function road_of(p)
  if p.road_d == nil then
    p.road_d = math.huge
    if roadnet.net() then
      local e, _, rx, rz, d = roadnet.nearest_edge(p.x, p.z, true)
      if e then
        local E = roadnet.net().edges[e]
        local ax, az = city.pos(E.a)
        local bx, bz = city.pos(E.b)
        p.road, p.road_d = {rx, rz}, d
        p.junction = ((ax - rx) ^ 2 + (az - rz) ^ 2 <= (bx - rx) ^ 2 + (bz - rz) ^ 2) and E.a or E.b
      end
    end
  end
  return p.road_d
end

local function matches(tags, q)
  for k, want in pairs(q) do
    if not OPTIONS[k] then
      local have = tags[k]
      if want == true then
        if have == nil then return false end
      elseif type(want) == "table" then
        local any = false
        for _, v in ipairs(want) do
          if have == v then any = true; break end
        end
        if not any then return false end
      elseif have ~= want then
        return false
      end
    end
  end
  return true
end

function P.find(q)
  q = q or {}
  local fx, fz = q.from and q.from[1], q.from and q.from[2]
  local lo, hi = (q.min_dist or 0) ^ 2, (q.max_dist or math.huge) ^ 2
  local road_dist = q.road_dist or ROAD_DIST
  local out = {}
  for _, p in ipairs(all()) do
    if matches(p.tags, q) then
      local d2 = fx and (p.x - fx) ^ 2 + (p.z - fz) ^ 2 or 0
      if d2 >= lo and d2 <= hi and (q.road == false or road_of(p) <= road_dist) then
        out[#out + 1] = {x = p.x, z = p.z, tags = p.tags, name = p.name, road = p.road,
                         junction = p.junction, dist = fx and math.sqrt(d2) or 0}
      end
    end
  end
  -- Ties broken by name and place, so the order is the same every run.
  table.sort(out, function(a, b)
    if a.dist ~= b.dist then return a.dist < b.dist end
    if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
    if a.x ~= b.x then return a.x < b.x end
    return a.z < b.z
  end)
  if q.limit then
    for i = #out, q.limit + 1, -1 do out[i] = nil end
  end
  return out
end

-- Is there at least one place like this?
function P.has(q) return #P.find(q) > 0 end

-- How many points of interest the map has at all.
function P.count() return #all() end

return P
