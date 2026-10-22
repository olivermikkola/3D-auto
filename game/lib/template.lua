-- Mission templates: a story's places as roles, each a condition on the
-- map's points of interest (lib/pois), filled with real places by a seed
-- (see docs/MISSION_TEMPLATES.md). The same seed gives the same places;
-- another seed, another version of the same story.
--
--   local cast, why = template.cast{
--     seed = 7, from = {x, z},            -- where the player is
--     roles = {                            -- filled in order
--       {"pickup", amenity = "place_of_worship", max_dist = 2000},
--       {"hideout", leisure = "pitch", from = "pickup", min_dist = 3000, max_dist = 6000,
--        relax = {{min_dist = 1500}}},
--       {"drop", shop = "supermarket", from = "hideout", drive_min = 1000},
--     },
--   }
--   -- cast.pickup = a point of interest (see lib/pois), ...; nil and why if
--   -- some role has no place on this map.
--
-- A role is its name, then tag conditions as lib/pois takes them, and:
--   from = "role" or {x, z}  distances are from there (default: t.from)
--   min_dist, max_dist       straight-line meters from `from`
--   drive_min, drive_max     meters by road from `from`, one-way streets the
--                            right way; a place cars can't get to from
--                            `from` is never picked
--   across_water = "role" or {x, z}   the straight line from there to the
--                            place crosses water (a river, a strait, a bay;
--                            roadnet.across_water)
--   relax = {{...}, ...}     if nothing fits, try again with these changes,
--                            one after another (false drops a condition)
--   weight = function(p, cast) -> number   how much to like a candidate
--                            (default 1); 0 rules it out
-- Places in t.avoid (keys from template.key) are picked only when nothing
-- else fits. No place fills two roles.
local city = require "lib.city"
local pois = require "lib.pois"

local T = {}

local OWN = {from = true, drive_min = true, drive_max = true, relax = true, weight = true, across_water = true}
local TRIES = 8 -- whole casts tried, each from its own seed, before giving up

function T.key(p) return string.format("%.0f,%.0f", p.x, p.z) end

-- Repeatable random numbers of our own, so a cast doesn't depend on (or
-- disturb) math.random.
local function rng(seed)
  local s = math.tointeger(seed) or math.floor(seed)
  s = (s * 2654435761 + 1013904223) & 0x7fffffff
  return function()
    s = (s * 1103515245 + 12345) & 0x7fffffff
    return s / 0x80000000
  end
end

-- ---- road distances ----------------------------------------------------------------
-- Meters by road from one junction to every other it leads to (Dijkstra on
-- the one-way-aware links), kept per map and start junction.

local lengths = setmetatable({}, {__mode = "k"})
local function road_length(a, b)
  local map = city.map()
  local per = lengths[map]
  if not per then per = {}; lengths[map] = per end
  local key = a .. ">" .. b
  local l = per[key]
  if not l then
    l = 0
    local pts = city.path(a, b)
    for i = 2, #pts do l = l + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2) end
    per[key] = l
  end
  return l
end

local drives, prevs = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
function T.drive_from(start)
  local map = city.map()
  local per = drives[map]
  if not per then per = {}; drives[map] = per; prevs[map] = {} end
  if per[start] then return per[start] end
  local dist, prev, heap = {[start] = 0}, {}, {{0, start}}
  local function push(d, id)
    heap[#heap + 1] = {d, id}
    local i = #heap
    while i > 1 do
      local up = i // 2
      if heap[up][1] <= heap[i][1] then break end
      heap[up], heap[i] = heap[i], heap[up]
      i = up
    end
  end
  local function pop()
    local top, last = heap[1], heap[#heap]
    heap[#heap] = nil
    if #heap > 0 then
      heap[1] = last
      local i = 1
      while true do
        local l, r, m = 2 * i, 2 * i + 1, i
        if heap[l] and heap[l][1] < heap[m][1] then m = l end
        if heap[r] and heap[r][1] < heap[m][1] then m = r end
        if m == i then break end
        heap[m], heap[i] = heap[i], heap[m]
        i = m
      end
    end
    return top
  end
  while #heap > 0 do
    local d, id = table.unpack(pop())
    if d <= dist[id] then
      for _, nb in ipairs(city.links(id) or {}) do
        local nd = d + road_length(id, nb)
        if nd < (dist[nb] or math.huge) then dist[nb], prev[nb] = nd, id; push(nd, nb) end
      end
    end
  end
  per[start], prevs[map][start] = dist, prev
  return dist
end

-- The junctions of the shortest way by road from (x, z) (its nearest
-- junction) to point of interest p, both ends included; nil if there's none.
function T.route(x, z, p)
  local start = city.nearest(x, z)
  if T.drive_from(start)[p.junction] == nil then return nil end
  local prev, out, j = prevs[city.map()][start], {}, p.junction
  while j do
    table.insert(out, 1, j)
    j = j ~= start and prev[j] or nil
  end
  return out
end

-- Meters by road from (x, z) (its nearest junction) to point of interest p
-- (the junction of its street), or math.huge if there's no way.
function T.drive(x, z, p)
  return T.drive_from(city.nearest(x, z))[p.junction] or math.huge
end

-- ---- casting -----------------------------------------------------------------------

-- The role with `changes` on it (false drops a condition).
local function with(role, changes)
  local r = {}
  for k, v in pairs(role) do r[k] = v end
  for k, v in pairs(changes) do
    if v == false then r[k] = nil else r[k] = v end
  end
  return r
end

-- The places that could fill `role`, given the ones already cast.
local function candidates(role, t, cast, used)
  local from = role.from or t.from
  if type(from) == "string" then
    local p = cast[from]
    assert(p, "role '" .. role[1] .. "' is from '" .. from .. "', which isn't cast before it")
    from = {p.x, p.z}
  end
  local q = {from = from}
  for k, v in pairs(role) do
    if k ~= 1 and not OWN[k] then q[k] = v end
  end
  local across = role.across_water
  if type(across) == "string" then
    local p = cast[across]
    assert(p, "role '" .. role[1] .. "' is across water from '" .. across .. "', which isn't cast before it")
    across = {p.x, p.z}
  end
  local out = {}
  local reach = T.drive_from(city.nearest(from[1], from[2]))
  for _, p in ipairs(pois.find(q)) do
    local d = reach[p.junction] or math.huge
    if not used[T.key(p)] and d < math.huge
       and (not role.drive_min or d >= role.drive_min) and (not role.drive_max or d <= role.drive_max)
       and (not across or require("lib.roadnet").across_water(across[1], across[2], p.x, p.z)) then
      p.drive = d
      out[#out + 1] = p
    end
  end
  return out
end

-- Pick one by weight; places to avoid only if there's nothing else.
local function pick(list, role, cast, avoid, rand)
  local fresh, total, weights = {}, 0, {}
  for _, p in ipairs(list) do
    if not avoid[T.key(p)] then fresh[#fresh + 1] = p end
  end
  if #fresh > 0 then list = fresh end
  for i, p in ipairs(list) do
    local w = role.weight and role.weight(p, cast) or 1
    weights[i] = math.max(0, w)
    total = total + weights[i]
  end
  if total <= 0 then return nil end
  local r = rand() * total
  for i, p in ipairs(list) do
    r = r - weights[i]
    if r < 0 then return p end
  end
  return list[#list]
end

local function cast_once(t, rand)
  local cast, used, relaxed = {}, {}, {}
  for _, role in ipairs(t.roles) do
    local name = role[1]
    local steps, r, chosen = role.relax or {}, role, nil
    for step = 0, #steps do
      if step > 0 then r = with(r, steps[step]) end
      chosen = pick(candidates(r, t, cast, used), r, cast, t.avoid or {}, rand)
      if chosen then
        if step > 0 then relaxed[name] = step end
        break
      end
    end
    if not chosen then return nil, name end
    cast[name], used[T.key(chosen)] = chosen, true
  end
  return cast, relaxed
end

-- A new seed for each templated mission played, kept with the progress
-- save, so the next run is another version of the story (and a new game
-- starts from the same ones again).
function T.next_seed()
  local G = require "lib.state"
  G.stats.mission_runs = (G.stats.mission_runs or 0) + 1
  require("lib.progress").touch()
  return G.stats.mission_runs
end

-- Fill every role (see the top of the file). Returns the cast and, per
-- role that needed it, how many relax steps it took; or nil and why.
function T.cast(t)
  assert(t.from and t.roles, "a template needs from and roles")
  local missing
  for k = 0, TRIES - 1 do
    local cast, info = cast_once(t, rng((t.seed or 0) * 31 + k))
    if cast then return cast, info end
    missing = info
  end
  return nil, missing .. ": no place like that on this map"
end

return T
