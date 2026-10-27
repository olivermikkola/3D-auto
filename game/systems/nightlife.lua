-- Night out: from nine in the evening to four in the morning people stand
-- about on the pavement outside the bars, pubs and nightclubs near the
-- player, more as the night goes on and most outside the clubs. They're
-- browsers (systems/peds) whose spots are the pavement by the door: they
-- shuffle about between them, a car can knock them over and a fright
-- sends them running, and they come back.
local U = require "lib.util"
local city = require "lib.city"
local pois = require "lib.pois"
local quality = require "lib.quality"
local roadnet = require "lib.roadnet"

local N = {venues = {}, out = 0}
N.OPEN, N.CLOSE = 21, 4    -- hours
N.NEAR, N.FAR = 140, 170   -- m: venues within NEAR of the player fill; beyond FAR they empty
N.APPEAR = 50              -- m: not closer than this (they'd pop up in view)
N.MOST = {nightclub = 10, bar = 5, pub = 5}
N.TIERS = {0.4, 0.7, 1}    -- of MOST, by quality tier

local function peds() return require "systems.peds" end

-- A number 0..1 from a few others, the same every run.
local function hash(a, b, c) return math.sin(a * 12.9898 + b * 78.233 + (c or 0) * 37.719) * 43758.5453 % 1 end

-- How full the pavements are at this hour, 0..1: filling up from nine,
-- fullest around one, emptying by four.
function N.busy(hour)
  if hour >= N.CLOSE and hour < N.OPEN then return 0 end
  local h = hour < 12 and hour + 24 or hour -- 21..28
  if h < 23 then return 0.3 end
  if h < 24 then return 0.6 end
  if h < 26.5 then return 1 end
  return 0.5
end

-- The places to stand outside venue v: on the pavement by the road nearest
-- it, between the pavement's middle and the wall, a few metres either way.
local function spots_for(v)
  local ei, si, cx, cz = roadnet.nearest_edge(v.x, v.z, true)
  local e = ei and roadnet.net().edges[ei]
  if not e or e.tunnel or e.height then return nil end
  local a, b = e.pts[si - 1], e.pts[si]
  local len = U.dist2d(a[1], a[2], b[1], b[2])
  if len < 1 then return nil end
  local fx, fz = (b[1] - a[1]) / len, (b[2] - a[2]) / len
  local nx, nz = fz, -fx -- across the road, to the venue's side
  if (v.x - cx) * nx + (v.z - cz) * nz < 0 then nx, nz = -nx, -nz end
  local kerb = e.width / 2
  local spots = {taken = {}}
  for _, out in ipairs{2.2, 2.9} do
    for along = -4.2, 4.2, 1.2 do
      -- (Not in a neat row: a little either way.)
      local j1, j2 = hash(cx + along, cz + out) - 0.5, hash(cz + along, cx + out) - 0.5
      along, out = along + j1 * 0.7, out + j2 * 0.5
      local x, z = cx + fx * along + nx * (kerb + out), cz + fz * along + nz * (kerb + out)
      local y = U.ground(x, z)
      local hit = engine.raycast(x, y + 4, z, 0, -1, 0, 3.8)
      local tag = hit and engine.tag(hit)
      if not roadnet.on_carriageway(x, z, 0.4) and not roadnet.wet(x, z)
        and not (tag == "building" or tag == "wall" or tag == "shelter" or tag == "tree") then
        -- Facing the venue's side, turned a little either way.
        spots[#spots + 1] = {x, z, math.atan(nx, nz) + (hash(x, z) - 0.5) * 2.4, y}
      end
    end
  end
  -- Filled in a mixed order, so a small crowd stands in a loose group or
  -- two rather than a row from one end.
  local order = {}
  for i, sp in ipairs(spots) do order[i] = {sp, hash(sp[1], sp[2], 5)} end
  table.sort(order, function(a, b) return a[2] < b[2] end)
  for i, o in ipairs(order) do spots[i] = o[1] end
  return #spots >= 3 and spots or nil
end

function N.build()
  N.venues = {}
  if not city.network() then return end
  for _, p in ipairs(pois.find{amenity = {"nightclub", "bar", "pub"}, road = false}) do
    N.venues[#N.venues + 1] = {x = p.x, z = p.z, name = p.name, kind = p.tags.amenity}
  end
end

local function empty(v)
  for _, id in ipairs(v.people or {}) do
    if peds().peds[id] then
      peds().peds[id] = nil
      engine.despawn(id)
      N.out = N.out - 1
    end
  end
  v.people = nil
end

local wait = 0
engine.on("tick", function(dt)
  wait = wait - dt
  if wait > 0 or #N.venues == 0 or engine.ticks() < 2 then return end
  wait = 1
  -- (A still picture: around its camera rather than the player.)
  local still = os.getenv("SHOT_CAM")
  local x, _, z = U.player_pos()
  if still then x, z = still:match("^([^,]+),[^,]+,([^,]+)") end
  x, z = tonumber(x), tonumber(z)
  if not x then return end
  local hour = require("lib.daynight").hour
  local busy = N.busy(hour) * N.TIERS[quality.tier()]
  local P = peds()
  for _, v in ipairs(N.venues) do
    local d = U.dist2d(x, z, v.x, v.z)
    if v.people then
      local alive = {}
      for _, id in ipairs(v.people) do
        if P.peds[id] then alive[#alive + 1] = id else N.out = N.out - 1 end
      end
      v.people = alive
      -- Gone too far, or closing time and out of sight: they go home.
      if d > N.FAR or (busy == 0 and d > N.APPEAR) then empty(v) end
    end
    -- Out of sight, the crowd grows or shrinks to the hour's.
    if d < N.NEAR and (still or d > N.APPEAR) and busy > 0 then
      if v.spots == nil then
        v.spots = spots_for(v) or false
        -- Next door to another venue already out on the pavement: one crowd.
        for _, o in ipairs(N.venues) do
          if v.spots and o ~= v and o.spots and U.dist2d(o.spots[1][1], o.spots[1][2], v.spots[1][1], v.spots[1][2]) < 9 then
            v.spots = false
          end
        end
      end
      if v.spots then
        v.people = v.people or {}
        local want = math.min(#v.spots, math.floor(N.MOST[v.kind] * busy * (0.5 + hash(v.x, v.z)) + 0.5))
        while #v.people > want do
          local id = table.remove(v.people)
          P.peds[id] = nil
          engine.despawn(id)
          N.out = N.out - 1
        end
        for k = 1, #v.spots do
          if #v.people >= want then break end
          if not P.peds[v.spots.taken[k]] then
            v.people[#v.people + 1] = P.add_browser(v.spots, k)
            N.out = N.out + 1
          end
        end
      end
    end
  end
end)

return N
