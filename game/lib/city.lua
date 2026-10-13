-- Procedural city built from a map file (game/maps/<name>.lua): a grid of
-- blocks between avenues (along z; north is -z) and streets (along x), an
-- outline of land with river round it, an optional park whose inner streets
-- are gone, district rules, skyline peaks, special blocks and named places.
-- Everything is boxes. See maps/manhattan.lua for what a map holds.
--
-- city.use(name) picks the map (main.lua does it first, so geometry and
-- places work before anything is built); city.build() builds it and
-- returns the layout. Systems that drive (traffic, police, the minimap)
-- use the road graph: junctions by id, C.links / C.pos / C.nearest /
-- C.roads. It doesn't care how the map was drawn, so curved roads and
-- several districts joined by bridges can plug into it. The grid functions
-- (C.node, C.neighbors, C.road, C.segments) are for building grid maps.
-- Find things with C.place / C.route rather than grid indices.
local C = {}

local CURB, WALK, FLOOR = 0.2, 3, 3.5
local WATER_DEEP = {0.16, 0.3, 0.52}

-- The current map, and the numbers everything below is written in:
-- blocks between avenues and between streets, block size (sidewalk
-- included), road widths, grid pitch, and where avenue 0 and street 0 are.
local MAP, NX, NZ, BX, BZ, AVE, ST, PX, PZ, OX, OZ
local PARK, SPECIAL, BILLBOARDS, roads, GRAPH
-- Set when the map is drawn as roads (lib/roadnet) rather than a grid.
local NET
local roadnet = require "lib.roadnet"

local palette = {
  {0.85, 0.82, 0.76}, {0.72, 0.68, 0.62}, {0.70, 0.45, 0.35}, {0.62, 0.66, 0.70},
  {0.90, 0.88, 0.80}, {0.55, 0.52, 0.50}, {0.78, 0.60, 0.45}, {0.68, 0.74, 0.78},
}

-- Every (i, j) a special entry names: one pair, or a list of them.
local function pairs_of(v)
  return type(v[1]) == "table" and v or {v}
end

-- Load a map by name (from maps/) or use a map table directly.
function C.use(map)
  if type(map) == "string" then
    local ok, m = pcall(require, "maps." .. map)
    if not ok then error("no map named '" .. map .. "' in maps/: " .. tostring(m), 2) end
    m.id = map
    map = m
  end
  assert(map.specials and map.specials.lot and map.places and map.places.hospital,
         "a map needs a lot (where you start) and a hospital")
  roads, GRAPH, NET = {}, nil, nil
  if map.roads then
    MAP = map
    NET = roadnet.load(map)
    roadnet.check(map)
    return map
  end
  local g = assert(map.grid, "a map needs a grid or roads")
  MAP, NX, NZ, BX, BZ, AVE, ST = map, g.nx, g.nz, g.bx, g.bz, g.avenue, g.street
  assert(BZ >= 36, "blocks must be at least 36 m deep: the lot, car park and stunt park need it")
  PX, PZ = BX + AVE, BZ + ST
  OX, OZ = -NX * PX / 2, -NZ * PZ / 2
  PARK = map.park
  SPECIAL, BILLBOARDS = {}, {}
  for kind, v in pairs(map.specials or {}) do
    for _, b in ipairs(pairs_of(v)) do SPECIAL[b[1] .. "," .. b[2]] = kind end
  end
  for _, b in ipairs(map.billboards or {}) do BILLBOARDS[b[1] .. "," .. b[2]] = true end
  roads, GRAPH = {}, nil
  C.check()
  return map
end

-- Catch mistakes in a map early, with the name of what's wrong: places on
-- intersections without a road, special blocks in the river or the park.
function C.check()
  if NET then return roadnet.check(MAP) end
  local function fail(fmt, ...) error(string.format("map '%s': " .. fmt, MAP.name or "?", ...), 0) end
  local function node_ok(n, what)
    if not C.on_road(n[1], n[2]) then fail("%s is at intersection %d,%d, which has no road", what, n[1], n[2]) end
  end
  local function block_ok(b, what)
    local d = C.district(b[1], b[2])
    if d == "water" or d == "park" then fail("%s is on block %d,%d, which is %s", what, b[1], b[2], d) end
  end
  for kind, v in pairs(MAP.specials or {}) do
    for _, b in ipairs(pairs_of(v)) do block_ok(b, kind) end
  end
  for name, p in pairs(MAP.places or {}) do
    if p.node then node_ok(p.node, name) end
    if p.block then block_ok(p.block, name) end
    for _, n in ipairs(p.route or {}) do node_ok(n, name) end
  end
end

function C.map() return MAP end

-- The cities the pause menu offers, and the one picked there last (kept in
-- the "city" save; MAP=<name> overrides it for a run).
C.MAPS = {{"manhattan", "MANHATTAN"}, {"harbor", "HARBOR"}, {"raisio", "RAISIO"}, {"raisio2030", "RAISIO 2030"}}
function C.chosen()
  local v = engine.load("city")
  for _, m in ipairs(C.MAPS) do if m[1] == v then return v end end
end

-- Switch city: remember it, and start the game afresh there.
function C.choose(name)
  local ok, err = engine.save("city", name)
  if not ok then print("city: " .. tostring(err)) end
  engine.reload()
end

-- ---- shape of the land -------------------------------------------------------

-- First and last land block in row j.
local function island(j)
  local r = MAP.land and MAP.land[j]
  if r then return r[1], r[2] end
  return 0, NX - 1
end

local function in_park(i, j)
  return PARK ~= nil and i >= PARK.i0 and i <= PARK.i1 and j >= PARK.j0 and j <= PARK.j1
end

local function within(v, range) return range == nil or (v >= range[1] and v <= range[2]) end

-- The district rule a block falls under (nil for downtown).
local function rule(i, j)
  for _, r in ipairs(MAP.districts or {}) do
    if within(i, r.i) and within(j, r.j) then return r end
  end
end

function C.district(i, j)
  if i < 0 or i >= NX or j < 0 or j >= NZ then return "water" end
  local a, b = island(j)
  if i < a or i > b then return "water" end
  if in_park(i, j) then return "park" end
  local r = rule(i, j)
  return r and r[1] or "downtown"
end

-- A block that faces streets: on land and not in the park.
local function street_block(i, j)
  local d = C.district(i, j)
  return d ~= "water" and d ~= "park"
end

-- 0..1: how tall downtown grows here, from the map's skyline peaks.
function C.height(x, z)
  local best = 0
  for _, p in ipairs(MAP.skyline and MAP.skyline.peaks or {}) do
    local dx, dz = x - (OX + p.k * PX), z - (OZ + p.l * PZ)
    best = math.max(best, p.weight * (1 - math.sqrt((dx / (p.rx / p.rz)) ^ 2 + dz ^ 2) / p.rz))
  end
  return best
end

-- ---- the grid --------------------------------------------------------------------------
-- Nodes are intersections (k, l): avenue line k = 0..NX, street line l = 0..NZ.

function C.node(k, l) return OX + k * PX, OZ + l * PZ end
function C.block_center(i, j) return OX + (i + 0.5) * PX, OZ + (j + 0.5) * PZ end

local function has_road(k, l, dk, dl)
  if k < 0 or l < 0 or k + dk > NX or l + dl > NZ then return false end
  if dk == 1 and dl == 0 then -- a street, between blocks (k, l-1) and (k, l)
    if PARK and l == PARK.transverse and k >= PARK.i0 and k <= PARK.i1 then return true end
    return street_block(k, l - 1) or street_block(k, l)
  elseif dk == 0 and dl == 1 then -- an avenue, between blocks (k-1, l) and (k, l)
    return street_block(k - 1, l) or street_block(k, l)
  end
  return false
end

-- Is there a road from node (k, l) one step along (dk, dl)? A map's layout
-- is fixed, so answers are remembered (until the next C.use): the police
-- ask every tick.
function C.road(k, l, dk, dl)
  if dk < 0 or dl < 0 then k, l, dk, dl = k + dk, l + dl, -dk, -dl end
  local key = ((k + 2) * 64 + l + 2) * 4 + dk * 2 + dl
  local r = roads[key]
  if r == nil then
    r = has_road(k, l, dk, dl)
    roads[key] = r
  end
  return r
end

local DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

function C.neighbors(k, l)
  local out = {}
  for _, d in ipairs(DIRS) do
    if C.road(k, l, d[1], d[2]) then out[#out + 1] = {k + d[1], l + d[2]} end
  end
  return out
end

function C.on_road(k, l) return #C.neighbors(k, l) > 0 end

-- Every intersection that has a road, as {k, l}.
function C.nodes()
  local out = {}
  for k = 0, NX do
    for l = 0, NZ do
      if C.on_road(k, l) then out[#out + 1] = {k, l} end
    end
  end
  return out
end

-- Every road segment, each once, as {k, l, dk, dl}.
function C.segments()
  local out = {}
  for k = 0, NX do
    for l = 0, NZ do
      if C.road(k, l, 1, 0) then out[#out + 1] = {k, l, 1, 0} end
      if C.road(k, l, 0, 1) then out[#out + 1] = {k, l, 0, 1} end
    end
  end
  return out
end

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

-- The block containing (or nearest to) a point.
function C.block_of(x, z)
  return clamp(math.floor((x - OX) / PX), 0, NX - 1), clamp(math.floor((z - OZ) / PZ), 0, NZ - 1)
end

-- The nearest intersection that is on a road.
function C.nearest_node(x, z)
  local k0, l0 = math.floor((x - OX) / PX + 0.5), math.floor((z - OZ) / PZ + 0.5)
  local best, bk, bl = math.huge
  for k = math.max(0, k0 - 2), math.min(NX, k0 + 2) do
    for l = math.max(0, l0 - 3), math.min(NZ, l0 + 3) do
      if C.on_road(k, l) then
        local nx, nz = C.node(k, l)
        local d = (nx - x) ^ 2 + (nz - z) ^ 2
        if d < best then best, bk, bl = d, k, l end
      end
    end
  end
  if bk then return bk, bl end
  local n = C.nodes()[1]
  return n[1], n[2]
end

-- A random intersection between min and max meters from (x, z), or nil.
function C.random_node(x, z, min, max)
  local cands = {}
  for _, n in ipairs(C.nodes()) do
    local nx, nz = C.node(n[1], n[2])
    local d = math.sqrt((nx - x) ^ 2 + (nz - z) ^ 2)
    if d >= min and d <= max then cands[#cands + 1] = n end
  end
  local n = cands[math.random(math.max(1, #cands))]
  if n then return n[1], n[2] end
end

-- ---- the road graph ----------------------------------------------------------------
-- Junctions are ids 1..n with a position; each road joins two of them. A
-- grid map's junctions are its intersections with a road, in grid order
-- (avenue by avenue, north to south), and its roads are C.segments() in
-- order, so anything random over them picks what it always did.

local function graph()
  if GRAPH then return GRAPH end
  if NET then
    GRAPH = {pos = NET.pos, links = NET.links, roads = NET.roads, id = {}}
    return GRAPH
  end
  local g = {pos = {}, links = {}, roads = {}, id = {}}
  for _, n in ipairs(C.nodes()) do
    local id = #g.pos + 1
    g.pos[id] = {C.node(n[1], n[2])}
    g.id[n[1] .. "," .. n[2]] = id
  end
  for _, n in ipairs(C.nodes()) do
    local out = {}
    for _, nb in ipairs(C.neighbors(n[1], n[2])) do out[#out + 1] = g.id[nb[1] .. "," .. nb[2]] end
    g.links[g.id[n[1] .. "," .. n[2]]] = out
  end
  for _, s in ipairs(C.segments()) do
    g.roads[#g.roads + 1] = {g.id[s[1] .. "," .. s[2]], g.id[(s[1] + s[3]) .. "," .. (s[2] + s[4])]}
  end
  GRAPH = g
  return g
end

-- How high junction `id` is (its road's level: a tunnel's, a bridge's),
-- or nil on a flat map; and the road from a to b at (x, z) on it.
function C.level(id)
  local ys = NET and roadnet.heights()
  return ys and ys[id]
end
function C.height_on(a, b, x, z) return NET and roadnet.height_on(a, b, x, z) end

-- Where junction `id` is, as x, z.
function C.pos(id)
  local p = graph().pos[id]
  return p[1], p[2]
end

-- The junctions one road away from `id`.
function C.links(id) return graph().links[id] end

-- Every junction id, and every road once, as {a, b}.
function C.junctions()
  local out = {}
  for id = 1, #graph().pos do out[id] = id end
  return out
end
function C.roads() return graph().roads end

-- Is the map drawn as roads rather than a grid?
function C.network() return NET ~= nil end

-- The road from junction a to b as points, a and b included; on a grid
-- it's straight, elsewhere it may bend.
function C.path(a, b)
  local g = graph()
  if a == b then return {g.pos[a], g.pos[a]} end
  if NET then return roadnet.path(a, b) end
  return {g.pos[a], g.pos[b]}
end

-- The junction at grid intersection (k, l), if it has a road.
function C.junction(k, l) return graph().id[k .. "," .. l] end

-- The nearest junction to (x, z); given a height y too, one on another
-- level (a tunnel under a street, the street over it) counts as far off.
function C.nearest(x, z, y)
  local g = graph()
  local ys = y and NET and roadnet.heights()
  local best, id = math.huge, 1
  for i, p in ipairs(g.pos) do
    local d = (p[1] - x) ^ 2 + (p[2] - z) ^ 2
    if ys and ys[i] and math.abs(ys[i] - y) > 4 then d = d + (30 * (ys[i] - y)) ^ 2 end
    if d < best then best, id = d, i end
  end
  return id
end

-- A random junction between min and max meters from (x, z), or nil.
function C.random_near(x, z, min, max)
  local cands = {}
  for i, p in ipairs(graph().pos) do
    local d = math.sqrt((p[1] - x) ^ 2 + (p[2] - z) ^ 2)
    if d >= min and d <= max then cands[#cands + 1] = i end
  end
  return cands[math.random(math.max(1, #cands))]
end

-- The first junction on a shortest route from `from` to `to` (breadth
-- first, so a route may start out away from the goal, round water or a
-- park). `from` itself if it's already there or `to` can't be reached.
function C.step_toward(from, to)
  local queue, first, i = {from}, {[from] = false}, 1
  while i <= #queue do
    local n = queue[i]
    i = i + 1
    if n == to then return first[n] or from end
    for _, nb in ipairs(C.links(n)) do
      if first[nb] == nil then
        first[nb] = first[n] or nb
        queue[#queue + 1] = nb
      end
    end
  end
  return from
end

-- ---- deterministic randomness ------------------------------------------------------
-- Each block draws from its own generator, so the city never touches
-- math.random and changing one block can't reshuffle the rest.
local function rng(a, b)
  local s = (a + 1) * 0x9E3779B97F4A7C15 ~ (b + 1) * 0xC2B2AE3D27D4EB4F
  return function(lo, hi)
    s = s * 6364136223846793005 + 1442695040888963407
    local r = ((s >> 33) & 0x7fffffff) / 0x80000000
    if lo then return lo + math.floor(r * (hi - lo + 1)) end
    return r
  end
end

-- ---- buildings -----------------------------------------------------------------------

local function static(t)
  t.body = t.body or "static"
  return engine.spawn(t)
end

-- Windows for one floor of a box of the given footprint fraction: a band
-- through each pair of opposite faces, so all four sides get glass.
local function window_band(parts, y, s, on)
  local glass = on and {0.34, 0.31, 0.25} or {0.25, 0.3, 0.38}
  parts[#parts + 1] = {mesh = "cube", pos = {0, y, 0}, size = {s + 0.01, 1.4, s * 0.94}, color = glass, emissive = on and 1 or 0}
  parts[#parts + 1] = {mesh = "cube", pos = {0, y, 0}, size = {s * 0.94, 1.4, s + 0.01}, color = glass, emissive = on and 1 or 0}
end

-- About a third of the floors have their lights on at night.
local function lit(f, floors) return (f * 7 + floors * 3) % 3 == 0 end

-- One baked mesh per (style, floors). Footprint is 1x1 (scaled per building),
-- height is real so window bands keep a sane spacing.
local baked = {}
local function building_mesh(style, floors)
  local name = style .. floors
  if baked[name] then return name end
  local h = floors * FLOOR
  local parts
  if style == "glass" then
    parts = {{mesh = "cube", size = {1, h, 1}, color = {0.35, 0.45, 0.55}, emissive = 0.08}}
    for f = 1, floors - 1 do
      parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * FLOOR, 0}, size = {1.01, 0.3, 1.01}, color = {0.85, 0.87, 0.9}}
    end
    if floors >= 30 then -- a mast on the supertalls
      parts[#parts + 1] = {mesh = "cube", pos = {0, h / 2 + 8, 0}, size = {0.03, 16, 0.03}, color = {0.75, 0.75, 0.78}}
    end
  elseif style == "balconies" then
    -- Flats of the 2010s: glass-railed balconies along the long sides on
    -- every floor above the shops, and orange-red panels up the ends and
    -- the middle.
    parts = {{mesh = "cube", size = {1, h, 1}, color = {0.9, 0.88, 0.84}}}
    for f = 0, floors - 1 do window_band(parts, -h / 2 + f * FLOOR + 1.9, 1, lit(f, floors)) end
    for f = 1, floors - 1 do
      parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * FLOOR + 0.1, 0}, size = {0.9, 0.2, 1.08}, color = {0.75, 0.75, 0.74}}
      parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * FLOOR + 0.75, 0}, size = {0.9, 1.1, 1.07}, color = {0.5, 0.6, 0.66}}
    end
    for _, u in ipairs{-0.475, 0, 0.475} do
      parts[#parts + 1] = {mesh = "cube", pos = {u, FLOOR / 2, 0}, size = {0.05, h - FLOOR, 1.09}, color = {0.76, 0.32, 0.18}}
    end
  else
    parts = {{mesh = "cube", size = {1, h, 1}, color = {1, 1, 1}}}
    for f = 0, floors - 1 do window_band(parts, -h / 2 + f * FLOOR + 1.9, 1, lit(f, floors)) end
  end
  parts[#parts + 1] = {mesh = "cube", pos = {0, h / 2 + 0.3, 0}, size = {1.02, 0.6, 1.02}, color = {0.6, 0.6, 0.6}}
  parts[#parts + 1] = {mesh = "cube", pos = {0.2, h / 2 + 1.0, -0.15}, size = {0.25, 1.0, 0.2}, color = {0.7, 0.7, 0.7}}
  engine.mesh(name, parts)
  baked[name] = true
  return name
end

-- Art Deco "wedding cake": the street wall rises to a setback, then
-- narrower tiers climb to a crown and a spire. The podium is the entity's
-- collider and the mesh origin; upper tiers get invisible boxes of their own.
local TIERS = {{1, 0.42}, {0.72, 0.34}, {0.46, 0.24}} -- footprint fraction, share of the floors

local function tier_floors(floors)
  local a = math.floor(floors * TIERS[1][2] + 0.5)
  local b = math.floor(floors * TIERS[2][2] + 0.5)
  return {a, b, floors - a - b}
end

local function deco_mesh(floors)
  local name = "deco" .. floors
  if baked[name] then return name end
  local fl = tier_floors(floors)
  local base = fl[1] * FLOOR
  local parts, y0 = {}, -base / 2 -- bottom of the current tier, from the podium's centre
  for t, tier in ipairs(TIERS) do
    local s, h = tier[1], fl[t] * FLOOR
    parts[#parts + 1] = {mesh = "cube", pos = {0, y0 + h / 2, 0}, size = {s, h, s}, color = {1, 1, 1}}
    for f = 0, fl[t] - 1 do window_band(parts, y0 + f * FLOOR + 1.9, s, lit(f + t, floors)) end
    -- A darker ledge at each setback.
    parts[#parts + 1] = {mesh = "cube", pos = {0, y0 + h + 0.25, 0}, size = {s + 0.02, 0.5, s + 0.02}, color = {0.55, 0.53, 0.5}}
    y0 = y0 + h
  end
  -- Crown and spire, lit at night.
  parts[#parts + 1] = {mesh = "cube", pos = {0, y0 + 2.5, 0}, size = {0.28, 5, 0.28}, color = {0.9, 0.85, 0.7}, emissive = 0.6}
  parts[#parts + 1] = {mesh = "cube", pos = {0, y0 + 5 + 7, 0}, size = {0.04, 14, 0.04}, color = {0.8, 0.8, 0.82}}
  engine.mesh(name, parts)
  baked[name] = true
  return name
end

-- The New York rooftop water tank, on stilts.
local function water_tower_mesh()
  if baked.watertower then return end
  local wood = {0.45, 0.32, 0.22}
  local parts = {}
  for _, c in ipairs{{1, 1}, {-1, 1}, {1, -1}, {-1, -1}} do
    parts[#parts + 1] = {mesh = "cube", pos = {c[1] * 0.9, 1.0, c[2] * 0.9}, size = {0.2, 2, 0.2}, color = {0.25, 0.25, 0.27}}
  end
  parts[#parts + 1] = {mesh = "cylinder", pos = {0, 3.6, 0}, size = {2.8, 3.2, 2.8}, color = wood}
  parts[#parts + 1] = {mesh = "cylinder", pos = {0, 5.5, 0}, size = {2.2, 0.6, 2.2}, color = {0.3, 0.3, 0.32}}
  parts[#parts + 1] = {mesh = "cylinder", pos = {0, 6.0, 0}, size = {0.9, 0.5, 0.9}, color = {0.3, 0.3, 0.32}}
  engine.mesh("watertower", parts)
  baked.watertower = true
end

-- A plain box building: brick with window bands, or a glass curtain wall.
local function building(x, z, w, d, floors, style, c, r)
  local h = floors * FLOOR
  static{mesh = building_mesh(style, floors), pos = {x, CURB + h / 2, z}, size = {w, h, d}, scale = {w, 1, d},
         color = style == "glass" and {1, 1, 1} or c, tag = "building"}
  if style == "brick" and floors >= 5 and floors <= 22 and r() < 0.4 then
    water_tower_mesh()
    engine.spawn{mesh = "watertower", pos = {x + (r() - 0.5) * w * 0.5, CURB + h + 0.6, z + (r() - 0.5) * d * 0.4},
                 scale = 1, tag = "rooftop"}
  end
  return h
end

local function deco(x, z, w, d, floors, c)
  local fl = tier_floors(floors)
  local base = fl[1] * FLOOR
  static{mesh = deco_mesh(floors), pos = {x, CURB + base / 2, z}, size = {w, base, d}, scale = {w, 1, d}, color = c,
         tag = "building"}
  local y = CURB + base
  for t = 2, 3 do
    local s, h = TIERS[t][1], fl[t] * FLOOR
    static{pos = {x, y + h / 2, z}, size = {w * s, h, d * s}, visible = false, tag = "building"}
    y = y + h
  end
  return y - CURB
end

-- ---- brownstones: a terrace of row houses with stoops ------------------------------
local STONE = {{0.45, 0.3, 0.24}, {0.58, 0.28, 0.2}, {0.84, 0.78, 0.66}, {0.52, 0.5, 0.48}, {0.55, 0.58, 0.48}, {0.4, 0.26, 0.22}}

-- `facing` is -1 if the street is to the north (-z), 1 if to the south.
local function rowhouses(x, z, w, d, facing, r, name)
  local stories = r(3, 5)
  local h, units = stories * 3.2, math.max(1, math.floor(w / 6.5))
  local uw = w / units
  local bd = d - 1.6 -- the stoops take the strip by the sidewalk
  local front = facing * bd / 2
  local parts = {}
  for u = 0, units - 1 do
    local ux = -w / 2 + (u + 0.5) * uw
    local c = STONE[r(1, #STONE)]
    parts[#parts + 1] = {mesh = "cube", pos = {ux, 0, 0}, size = {uw - 0.04, h, bd}, color = c}
    for f = 0, stories - 1 do
      local on = r() < 0.3
      local glass = on and {0.34, 0.31, 0.25} or {0.22, 0.26, 0.32}
      for _, s in ipairs{-0.25, 0.25} do
        parts[#parts + 1] = {mesh = "cube", pos = {ux + s * uw, -h / 2 + f * 3.2 + 1.8, 0}, size = {uw * 0.22, 1.5, bd + 0.06},
                             color = glass, emissive = on and 1 or 0}
      end
    end
    -- Cornice, door, and the stoop down to the sidewalk.
    parts[#parts + 1] = {mesh = "cube", pos = {ux, h / 2 + 0.2, 0}, size = {uw, 0.4, bd + 0.4},
                         color = {c[1] * 0.7, c[2] * 0.7, c[3] * 0.7}}
    parts[#parts + 1] = {mesh = "cube", pos = {ux + uw * 0.3, -h / 2 + 2.3, front + facing * 0.05}, size = {1.0, 2.0, 0.1},
                         color = {0.22, 0.14, 0.1}}
    for s = 0, 2 do
      parts[#parts + 1] = {mesh = "cube", pos = {ux + uw * 0.3, -h / 2 + 0.2 + s * 0.4, front + facing * (1.4 - s * 0.45) / 2},
                           size = {1.3, 0.4 + s * 0.4, 1.4 - s * 0.45}, color = {c[1] * 0.85, c[2] * 0.85, c[3] * 0.85}}
    end
  end
  engine.mesh(name, parts)
  static{mesh = name, pos = {x, CURB + h / 2, z - facing * 0.8}, size = {w, h, bd}, scale = 1, tag = "building"}
  return h
end

-- ---- industrial: warehouses with sawtooth roofs, containers, smokestacks ----
local METAL = {{0.55, 0.6, 0.65}, {0.62, 0.42, 0.32}, {0.75, 0.72, 0.62}, {0.4, 0.5, 0.45}}
local CONTAINER = {{0.75, 0.2, 0.15}, {0.15, 0.35, 0.65}, {0.2, 0.55, 0.3}, {0.85, 0.6, 0.15}, {0.5, 0.5, 0.52}}

local function warehouse_mesh(v, h)
  local name = "warehouse" .. v .. "_" .. h
  if baked[name] then return name end
  local c = METAL[v]
  local parts = {{mesh = "cube", size = {1, h, 1}, color = c}}
  -- Ribs of the cladding, a roller door and a strip of high windows.
  for k = -2, 2 do
    parts[#parts + 1] = {mesh = "cube", pos = {k * 0.2, 0, 0}, size = {0.02, h, 1.01}, color = {c[1] * 0.8, c[2] * 0.8, c[3] * 0.8}}
  end
  parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + 2.2, 0}, size = {0.35, 4.4, 1.02}, color = {0.3, 0.3, 0.32}}
  parts[#parts + 1] = {mesh = "cube", pos = {0, h / 2 - 1.2, 0}, size = {1.01, 0.8, 0.9}, color = {0.3, 0.33, 0.3}, emissive = v % 2}
  -- Sawtooth roof: wedges whose steep (glazed) faces all look the same way.
  for k = 0, 3 do
    parts[#parts + 1] = {mesh = "wedge", pos = {0, h / 2 + 0.8, -0.375 + k * 0.25}, size = {1, 1.6, 0.25}, color = {0.45, 0.45, 0.47}}
  end
  engine.mesh(name, parts)
  baked[name] = true
  return name
end

-- The shed takes most of the lot; containers fill the yard beside it.
local function warehouse(x, z, w, d, r, name)
  local h = 6 + r(0, 2) * 2
  local v = r(1, #METAL)
  local ww = w * 0.72
  static{mesh = warehouse_mesh(v, h), pos = {x - (w - ww) / 2, CURB + h / 2, z}, size = {ww, h, d}, scale = {ww, 1, d},
         tag = "building"}
  local yx = x + w / 2 - (w - ww) / 2
  local slots = math.floor(d / 3.2)
  local stack_slot = r() < 0.2 and slots - 1 -- some yards have a smokestack
  -- The yard's containers are baked into one mesh with one collider over the row.
  local cw = math.min(w - ww - 0.6, 6)
  local parts, z0, z1, top = {}, nil, nil, 0
  for n = 0, slots - 1 do
    local sz = z - d / 2 + 1.6 + n * 3.2
    if n == stack_slot then
      static{mesh = "smokestack", pos = {yx, CURB + 14, sz}, size = {2.2, 28, 2.2}, scale = 1, tag = "building"}
    elseif r() < 0.75 then
      local stack = r() < 0.35 and 2 or 1
      for st = 1, stack do
        local cc = CONTAINER[r(1, #CONTAINER)]
        parts[#parts + 1] = {mesh = "cube", pos = {0, 1.3 + (st - 1) * 2.6, sz - z}, size = {cw, 2.6, 2.6}, color = cc}
        parts[#parts + 1] = {mesh = "cube", pos = {0, 1.3 + (st - 1) * 2.6, sz - z}, size = {cw + 0.02, 0.15, 2.62},
                             color = {cc[1] * 0.7, cc[2] * 0.7, cc[3] * 0.7}}
      end
      z0, z1, top = math.min(z0 or sz, sz), math.max(z1 or sz, sz), math.max(top, stack * 2.6)
    end
  end
  if #parts > 0 then
    -- Parts sit relative to the row's middle, which is where the collider goes.
    local mid = (z0 + z1) / 2
    for _, pt in ipairs(parts) do pt.pos[2], pt.pos[3] = pt.pos[2] - top / 2, pt.pos[3] - (mid - z) end
    engine.mesh(name, parts)
    static{mesh = name, pos = {yx, CURB + top / 2, mid}, size = {cw, top, z1 - z0 + 2.6}, scale = 1, tag = "container"}
  end
  return h
end

-- ---- filling a block -----------------------------------------------------------------

-- One lot facing a street. `facing` is -1 (street to the north), 1 (south),
-- or 0 for a tower that takes the block's whole depth. Returns its height.
local function lot(x, z, w, d, facing, avenue, district, i, j, r, name)
  if district == "industrial" then return warehouse(x, z, w, d, r, name) end
  local c = palette[r(1, #palette)]
  if district == "residential" then
    -- Brownstones mid-block, apartment houses on the avenues.
    local brownstone = not avenue and r() < ((rule(i, j) or {}).brownstones or 0.5)
    if brownstone and facing ~= 0 then return rowhouses(x, z, w, d, facing, r, name) end
    return building(x, z, w, d, avenue and r(6, 12) or r(4, 7), "brick", c, r)
  end
  -- Downtown: avenue frontage builds taller than the side streets.
  local f = C.height(x, z)
  local floors = math.floor(r(3, 7) * (0.7 + 4.5 * f ^ 1.2) * (avenue and 1 or 0.8))
  if f > 0.5 and r() < 0.4 * f then -- the supertalls
    local st = MAP.skyline and MAP.skyline.supertall or {30, 50}
    floors = r(st[1], st[2])
  end
  floors = math.max(3, floors)
  local square = math.max(w, d) / math.min(w, d) < 1.7
  local roll = r()
  if floors >= 18 and square and roll < 0.35 then return deco(x, z, w, d, floors, c) end
  local glass = roll < (floors >= 18 and 0.75 or 0.18)
  return building(x, z, w, d, floors, glass and "glass" or "brick", c, r)
end

-- Fill [x0, x1] x [z0, z1] (inside the sidewalks) with lots, flush to the
-- sidewalk on both street sides like a Manhattan street wall. `ends` says
-- which ends of the span touch an avenue. Returns what it built, for
-- anything that wants to decorate the frontage.
local function fill(x0, x1, z0, z1, i, j, r, ends)
  local district = C.district(i, j)
  local built, segs, x = {}, {}, x0
  while x1 - x > 0.1 do
    local w = district == "industrial" and 26 or r(14, 28)
    if x1 - (x + w) < 12 then w = x1 - x end
    segs[#segs + 1] = {x, x + w}
    x = x + w
  end
  local depth = z1 - z0
  for n, s in ipairs(segs) do
    local sx0, sx1 = s[1] + 0.3, s[2] - 0.3
    local w, mx = sx1 - sx0, (sx0 + sx1) / 2
    local avenue = (n == 1 and ends[1]) or (n == #segs and ends[2])
    local name = string.format("lot_%d_%d_%d_%d", i, j, math.floor(x0), n)
    local f = district == "downtown" and C.height(mx, (z0 + z1) / 2) or 0
    if f > 0.45 and w >= 18 and r() < f * 0.8 then
      local h = lot(mx, (z0 + z1) / 2, w, depth, 0, avenue, district, i, j, r, name)
      built[#built + 1] = {x0 = sx0, x1 = sx1, z0 = z0, z1 = z1, h = h}
    else
      local d = depth / 2 - 0.3
      for _, side in ipairs{-1, 1} do
        local mz = side < 0 and z0 + d / 2 or z1 - d / 2
        local h = lot(mx, mz, w, d, side, avenue, district, i, j, r, name .. (side < 0 and "n" or "s"))
        built[#built + 1] = {x0 = sx0, x1 = sx1, z0 = mz - d / 2, z1 = mz + d / 2, h = h, side = side}
      end
    end
  end
  return built
end

-- Times Square: glowing billboards all over the frontages.
local BILLBOARD = {{1, 0.2, 0.3}, {0.2, 0.6, 1}, {1, 0.85, 0.2}, {0.3, 1, 0.5}, {1, 0.4, 0.1}, {0.85, 0.3, 1}, {1, 1, 1}}
local function billboards(built, r)
  for _, b in ipairs(built) do
    for _, side in ipairs{-1, 1} do
      if b.side == nil or b.side == side then
        local zf = side < 0 and b.z0 - 0.15 or b.z1 + 0.15
        local y = 4
        while y < math.min(b.h - 3, 40) do
          local bw, bh = math.min(b.x1 - b.x0 - 1, r(6, 14)), r(3, 7)
          local bx = b.x0 + 0.5 + bw / 2 + r() * (b.x1 - b.x0 - 1 - bw)
          engine.spawn{mesh = "cube", pos = {bx, y + bh / 2, zf}, size = {bw, bh, 0.2}, color = BILLBOARD[r(1, #BILLBOARD)],
                       glow = 1, tag = "billboard"}
          y = y + bh + r(1, 4)
        end
      end
    end
  end
end

local function trees(n, x0, x1, z0, z1, r, avoid)
  for _ = 1, n do
    local x, z = x0 + r() * (x1 - x0), z0 + r() * (z1 - z0)
    local ok = true
    for _, a in ipairs(avoid or {}) do
      if math.abs(x - a[1]) < a[3] / 2 + 2 and math.abs(z - a[2]) < a[4] / 2 + 2 then ok = false end
    end
    if ok then
      static{mesh = "tree", pos = {x, CURB, z}, size = {0.5, 6, 0.5}, scale = 0.75 + r() * 0.6, tag = "tree"}
    end
  end
end

-- A flat patch on top of a block. `layer` stacks patches (grass, then paths
-- and water on it) a little apart so they don't z-fight.
local function grass(x, z, w, d, c, layer)
  engine.spawn{mesh = "cube", pos = {x, CURB + 0.01 + (layer or 0) * 0.05, z}, size = {w, 0.04, d}, color = c or {0.3, 0.55, 0.25}}
end
local PATH, WATER = {0.72, 0.66, 0.54}, {0.2, 0.38, 0.6}

local function pocket_park(cx, cz, r)
  grass(cx, cz, BX - 5, BZ - 5)
  -- A cross of paths, benches of trees either side.
  grass(cx, cz, BX - 5, 2.5, PATH, 1)
  grass(cx, cz, 2.5, BZ - 5, PATH, 1)
  trees(16, cx - BX / 2 + 4, cx + BX / 2 - 4, cz - BZ / 2 + 4, cz + BZ / 2 - 4, r, {{cx, cz, BX, 4}, {cx, cz, 4, BZ}})
end

-- Washington Square: the arch at the foot of the avenue, a fountain, trees.
local function square(cx, cz, r)
  pocket_park(cx, cz, r)
  local stone = {0.88, 0.86, 0.8}
  engine.mesh("arch", {
    {mesh = "cube", pos = {-3.6, 0, 0}, size = {2.4, 10, 2.4}, color = stone},
    {mesh = "cube", pos = {3.6, 0, 0}, size = {2.4, 10, 2.4}, color = stone},
    {mesh = "cube", pos = {0, 6.3, 0}, size = {9.6, 2.6, 2.4}, color = stone},
    {mesh = "cube", pos = {0, 7.8, 0}, size = {10, 0.4, 2.6}, color = {0.78, 0.76, 0.7}},
  })
  -- The arch stands on the north path; its legs are solid, you can drive under it.
  engine.spawn{mesh = "arch", pos = {cx, CURB + 5, cz - BZ / 2 + 5}, scale = 1, tag = "arch"}
  for _, s in ipairs{-1, 1} do
    static{pos = {cx + s * 3.6, CURB + 5, cz - BZ / 2 + 5}, size = {2.4, 10, 2.4}, visible = false, tag = "building"}
  end
  static{mesh = "cylinder", pos = {cx, CURB + 0.3, cz}, size = {9, 0.6, 9}, color = stone, tag = "fountain"}
  engine.spawn{mesh = "cylinder", pos = {cx, CURB + 0.62, cz}, size = {8, 0.04, 8}, color = WATER}
end

-- Central Park: two slabs either side of the transverse road, the
-- reservoir with a running track, the lake, the meadow, and a lot of trees.
local function central_park(L)
  local x0, z0 = C.node(PARK.i0, PARK.j0)
  local x1, z1 = C.node(PARK.i1 + 1, PARK.j1 + 1)
  x0, x1, z0, z1 = x0 + AVE / 2, x1 - AVE / 2, z0 + ST / 2, z1 - ST / 2
  local _, zt = C.node(0, PARK.transverse)
  local r = rng(PARK.i0, PARK.j0)
  for _, part in ipairs{{z0, zt - ST / 2}, {zt + ST / 2, z1}} do
    local a, b = part[1], part[2]
    static{mesh = "cube", pos = {(x0 + x1) / 2, CURB / 2, (a + b) / 2}, size = {x1 - x0, CURB, b - a},
           color = {0.62, 0.62, 0.6}, tag = "sidewalk"}
    grass((x0 + x1) / 2, (a + b) / 2, x1 - x0 - 2 * WALK, b - a - 2 * WALK)
  end
  local mx = (x0 + x1) / 2
  -- The reservoir, ringed by a low wall and the track.
  local rz, rw, rd = z0 + 85, 110, 70
  grass(mx, rz, rw + 8, rd + 8, {0.7, 0.55, 0.42}, 1)
  grass(mx, rz, rw, rd, WATER, 2)
  for _, s in ipairs{-1, 1} do
    static{mesh = "cube", pos = {mx + s * rw / 2, CURB + 0.4, rz}, size = {0.6, 0.8, rd + 0.6}, color = {0.6, 0.58, 0.54}, tag = "wall"}
    static{mesh = "cube", pos = {mx, CURB + 0.4, rz + s * rd / 2}, size = {rw + 0.6, 0.8, 0.6}, color = {0.6, 0.58, 0.54}, tag = "wall"}
  end
  -- The lake: a few overlapping pools, and Bethesda Fountain on its shore.
  local lz = zt + 50
  local lake = {{mx - 25, lz, 50, 26}, {mx + 12, lz + 8, 40, 20}, {mx - 6, lz - 12, 22, 14}}
  for _, p in ipairs(lake) do
    grass(p[1], p[2], p[3], p[4], WATER, 2)
  end
  static{mesh = "cylinder", pos = {mx - 6, CURB + 0.35, lz - 26}, size = {7, 0.7, 7}, color = {0.82, 0.78, 0.7}, tag = "fountain"}
  -- Sheep Meadow, down at the south end.
  local meadow = {mx, z1 - 32, 90, 40}
  grass(meadow[1], meadow[2], meadow[3], meadow[4], {0.42, 0.66, 0.32}, 1)
  -- The park drive: a loop of road just inside the walls.
  local path = {0.5, 0.5, 0.52}
  for _, part in ipairs{{z0, zt - ST / 2}, {zt + ST / 2, z1}} do
    local a, b = part[1] + 9, part[2] - 9
    for _, s in ipairs{-1, 1} do
      grass(mx + s * ((x1 - x0) / 2 - 9), (a + b) / 2, 4, b - a + 4, path, 1)
    end
    grass(mx, a, x1 - x0 - 14, 4, path, 1)
    grass(mx, b, x1 - x0 - 14, 4, path, 1)
  end
  local avoid = {{mx, rz, rw + 10, rd + 10}, meadow, {mx, zt, x1 - x0, ST + 6}}
  for _, p in ipairs(lake) do avoid[#avoid + 1] = {p[1], p[2], p[3] + 2, p[4] + 2} end
  for _, s in ipairs{-1, 1} do
    avoid[#avoid + 1] = {mx + s * ((x1 - x0) / 2 - 9), (z0 + z1) / 2, 6, z1 - z0}
  end
  for _, e in ipairs{z0 + 9, zt - ST / 2 - 9, zt + ST / 2 + 9, z1 - 9} do avoid[#avoid + 1] = {mx, e, x1 - x0, 6} end
  trees(420, x0 + 4, x1 - 4, z0 + 4, z1 - 4, r, avoid)
  -- Lamps round the outside.
  for z = z0 + 20, z1 - 20, 40 do
    for _, s in ipairs{-1, 1} do
      local x = s < 0 and x0 + 1 or x1 - 1
      static{mesh = "lamp", pos = {x, CURB, z}, yaw = s < 0 and -math.pi / 2 or math.pi / 2, size = {0.3, 10, 0.3}, tag = "lamp"}
    end
  end
  L.park_area = {x0 = x0, x1 = x1, z0 = z0, z1 = z1, transverse = zt}
end

-- ---- landmarks and features --------------------------------------------------------

-- A ramp is just a tilted static box, buried at the low end so cars roll on.
-- yaw is the direction it launches you; pitch is the incline in radians.
function C.ramp(x, z, yaw, width, length, incline)
  local t = 0.6
  local y = CURB - 0.03 + length / 2 * math.sin(incline) - t / 2 * math.cos(incline)
  local name = string.format("ramp_%g_%g", width, length)
  local parts = {{mesh = "cube", size = {width, t, length}, color = {0.95, 0.55, 0.1}}}
  for k = 1, math.floor(length / 2.5) do
    parts[#parts + 1] = {mesh = "cube", pos = {0, 0.01, -length / 2 + k * 2.5 - 0.6}, size = {width + 0.02, t, 0.6}, color = {0.15, 0.15, 0.15}}
  end
  engine.mesh(name, parts)
  return engine.spawn{mesh = name, pos = {x, y, z}, yaw = yaw, pitch = -incline, size = {width, t, length}, scale = 1,
                      body = "static", tag = "ramp"}
end

function C.stunt_park(cx, cz)
  engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {32, 0.04, 32}, color = {0.36, 0.36, 0.38}}
  C.ramp(cx, cz - 4, 0, 7, 16, 0.3)              -- big kicker, launches south
  C.ramp(cx - 11, cz + 8, math.pi, 4, 8, 0.38)    -- small ones on the sides
  C.ramp(cx + 11, cz + 8, math.pi, 4, 8, 0.38)
end

-- How wide a strip in the middle of the block each feature takes.
local FEATURE_W = {lot = 36, plaza = 36, stunt = 36, carpark = 36, tower = 36, empire = 46}

local function feature(kind, cx, cz, L)
  local landmarks = require "lib.landmarks"
  if kind == "tower" then L.landmarks[#L.landmarks + 1] = landmarks.tower(cx, cz)
  elseif kind == "carpark" then L.landmarks[#L.landmarks + 1] = landmarks.carpark(cx, cz)
  elseif kind == "empire" then L.landmarks[#L.landmarks + 1] = landmarks.empire(cx, cz)
  elseif kind == "plaza" then
    engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {32, 0.04, 32}, color = {0.75, 0.68, 0.55}}
  elseif kind == "stunt" then C.stunt_park(cx, cz)
  elseif kind == "lot" then
    engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {32, 0.04, 32}, color = {0.3, 0.3, 0.32}}
    for s = -3, 3 do
      engine.spawn{mesh = "plane", pos = {cx + s * 4 + 2, CURB + 0.04, cz}, size = {0.15, 1, 6}, color = {0.9, 0.9, 0.9}}
    end
  end
end

-- ---- streets ---------------------------------------------------------------------------

-- Center-line dashes and zebra crossings, baked into one mesh per grid
-- line so the whole street network is a few dozen draw calls.
local function markings()
  local yellow, white = {0.9, 0.75, 0.2}, {0.88, 0.88, 0.86}
  local function line(name, x, z, along_z, segs)
    local parts = {}
    for _, s in ipairs(segs) do
      -- a, b: the segment's ends along the line, measured from (x, z).
      local a, b, cross = s[1], s[2], s[3]
      local function put(u, v, lu, lv, c)
        if along_z then parts[#parts + 1] = {mesh = "cube", pos = {v, 0, u}, size = {lv, 0.02, lu}, color = c}
        else parts[#parts + 1] = {mesh = "cube", pos = {u, 0, v}, size = {lu, 0.02, lv}, color = c} end
      end
      local u0, u1 = a + cross / 2 + 4, b - cross / 2 - 4
      local n = math.max(1, math.floor((u1 - u0 + 3) / 6))
      local step = (u1 - u0) / n
      for k = 0, n - 1 do put(u0 + (k + 0.5) * step, 0, 3, 0.25, yellow) end
      local width = along_z and AVE or ST
      for _, e in ipairs{a + cross / 2 + 1.4, b - cross / 2 - 1.4} do
        for q = -width / 2 + 1, width / 2 - 1, 1.4 do put(e, q, 2, 0.7, white) end
      end
    end
    if #parts > 0 then
      engine.mesh(name, parts)
      engine.spawn{mesh = name, pos = {x, 0.02, z}, scale = 1, tag = "markings"}
    end
  end
  for k = 0, NX do
    local x = OX + k * PX
    local segs = {}
    for l = 0, NZ - 1 do
      if C.road(k, l, 0, 1) then segs[#segs + 1] = {l * PZ + OZ, (l + 1) * PZ + OZ, ST} end
    end
    line("avenue" .. k, x, 0, true, segs)
  end
  for l = 0, NZ do
    local z = OZ + l * PZ
    local segs = {}
    for k = 0, NX - 1 do
      if C.road(k, l, 1, 0) then segs[#segs + 1] = {k * PX + OX, (k + 1) * PX + OX, AVE} end
    end
    line("street" .. l, 0, z, false, segs)
  end
end

-- Water inside the grid: every block, road strip and junction off the
-- island, each with an invisible wall so cars stay on land.
local function harbor()
  local function pool(x0, x1, z0, z1)
    local x, z, w, d = (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0
    engine.spawn{mesh = "cube", pos = {x, 0.04, z}, size = {w, 0.08, d}, color = WATER_DEEP, tag = "water"}
    static{pos = {x, 5, z}, size = {w, 10, d}, visible = false, tag = "wall"}
  end
  for i = 0, NX - 1 do
    for j = 0, NZ - 1 do
      if C.district(i, j) == "water" then
        local cx, cz = C.block_center(i, j)
        pool(cx - BX / 2, cx + BX / 2, cz - BZ / 2, cz + BZ / 2)
      end
    end
  end
  local function park_road(k, l, dk) -- interior park roads are under the park, not water
    if dk == 1 then return in_park(k, l - 1) and in_park(k, l) end
    return in_park(k - 1, l) and in_park(k, l)
  end
  for k = 0, NX do
    for l = 0, NZ do
      local x, z = C.node(k, l)
      if k < NX and not C.road(k, l, 1, 0) and not park_road(k, l, 1) then
        pool(x + AVE / 2, x + PX - AVE / 2, z - ST / 2, z + ST / 2)
      end
      if l < NZ and not C.road(k, l, 0, 1) and not park_road(k, l, 0) then
        pool(x - AVE / 2, x + AVE / 2, z + ST / 2, z + PZ - ST / 2)
      end
      if not C.on_road(k, l) and not (in_park(k - 1, l - 1) and in_park(k, l)) then
        pool(x - AVE / 2, x + AVE / 2, z - ST / 2, z + ST / 2)
      end
    end
  end
end

-- ---- the city ----------------------------------------------------------------------------

-- ---- places --------------------------------------------------------------------------

local SIDES = {n = {0, -1}, s = {0, 1}, e = {1, 0}, w = {-1, 0}}

-- Does the map have all these places?
function C.has(...)
  if NET then
    for _, name in ipairs{...} do if not roadnet.has(MAP, name) then return false end end
    return true
  end
  for _, name in ipairs{...} do
    if not ((MAP.places or {})[name] or (MAP.specials or {})[name]) then return false end
  end
  return true
end

-- The name of the street at (x, z), on maps drawn as roads; nil elsewhere.
function C.street(x, z)
  if NET then return (roadnet.where(x, z)) end
end

-- Where a named place is, as x, z: an intersection, a block's center, or a
-- point by one side of a block (see maps/manhattan.lua). Specials are
-- places too, at their block's center.
function C.place(name)
  if NET then return roadnet.place(MAP, name) end
  local p = (MAP.places or {})[name]
  if not p then
    local sp = (MAP.specials or {})[name]
    if not sp then error(string.format("map '%s' has no place '%s'", MAP.name or "?", name), 2) end
    p = {block = pairs_of(sp)[1]}
  end
  if p.node then return C.node(p.node[1], p.node[2]) end
  if p.block then
    local x, z = C.block_center(p.block[1], p.block[2])
    if not p.side then return x, z end
    local d = SIDES[p.side]
    local reach = (d[1] ~= 0 and BX or BZ) / 2 + (p.out or 0)
    local along = p.along or 0 -- toward +x on a north or south side, +z on east or west
    return x + d[1] * reach + (d[1] == 0 and along or 0), z + d[2] * reach + (d[2] == 0 and along or 0)
  end
  error(string.format("place '%s' is a route; use city.route", name), 2)
end

-- A named route: the list of its intersections as {x, z}.
function C.route(name)
  if NET then return roadnet.route(MAP, name) end
  local p = (MAP.places or {})[name]
  if not (p and p.route) then error(string.format("map '%s' has no route '%s'", MAP.name or "?", name), 2) end
  local out = {}
  for _, n in ipairs(p.route) do out[#out + 1] = {C.node(n[1], n[2])} end
  return out
end

-- Where the map's health, ammo and weapon pickups go, as {kind, x, z}: on
-- the avenue sidewalks near the named corner of their block.
function C.pickup_spots()
  if NET then return roadnet.pickup_spots(MAP) end
  local out = {}
  for _, s in ipairs(MAP.pickups or {}) do
    local kind, i, j, sx, sz = table.unpack(s)
    local cx, cz = C.block_center(i, j)
    out[#out + 1] = {kind, cx + sx * (BX / 2 - 1.2), cz + sz * (BZ / 2 - 6)}
  end
  return out
end

-- Where the gun shop's door goes: x, z on a building's street wall, facing
-- south (+z). The first ordinary downtown block of the map's candidates
-- gets it; nil if none qualifies. Call after C.build().
function C.gunshop_spot(L)
  if NET then
    local g = MAP.gunshop
    if g then return g[1], g[2] end
    return
  end
  for _, c in ipairs(MAP.gunshop or {}) do
    if L.kinds[c[1] .. "," .. c[2]] == "buildings" and C.district(c[1], c[2]) == "downtown" then
      local cx, cz = C.block_center(c[1], c[2])
      return cx, cz + BZ / 2 - WALK
    end
  end
end

function C.build()
  if NET then
    return roadnet.build(MAP, {static = static, rng = rng, CURB = CURB, FLOOR = FLOOR, feature = feature,
                               building_mesh = building_mesh, warehouse_mesh = warehouse_mesh, ramp = C.ramp})
  end
  local sx, sz = NX * PX + AVE, NZ * PZ + ST
  local L = {
    map = MAP.id or MAP.name, NX = NX, NZ = NZ, PX = PX, PZ = PZ, bx = BX, bz = BZ, avenue = AVE, street = ST, walk = WALK,
    ox = OX, oz = OZ, sx = sx, sz = sz, curb = CURB, kinds = {}, landmarks = {},
  }

  -- Pavement under the grid, the river round it (four slabs framing the
  -- grid, level with the water inside it, so nothing overlaps to z-fight
  -- and no edge shows where they meet), and invisible walls at the shore.
  static{mesh = "cube", pos = {0, -1.5, 0}, size = {sx, 3, sz}, color = {0.22, 0.22, 0.24}, tag = "ground"}
  local R = 1500
  for _, f in ipairs{{0, -(sz + R) / 2, sx + 2 * R, R}, {0, (sz + R) / 2, sx + 2 * R, R},
                     {-(sx + R) / 2, 0, R, sz}, {(sx + R) / 2, 0, R, sz}} do
    engine.spawn{mesh = "cube", pos = {f[1], 0.04 - 0.5, f[2]}, size = {f[3], 1, f[4]}, color = WATER_DEEP, tag = "water"}
  end
  for _, s in ipairs{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
    static{pos = {s[1] * sx / 2, 5, s[2] * sz / 2}, size = {s[1] == 0 and sx or 1, 10, s[2] == 0 and sz or 1}, visible = false, tag = "wall"}
  end
  harbor()
  markings()

  -- Each special's block, by kind (the first, for kinds with several).
  for kind, v in pairs(MAP.specials or {}) do L[kind] = pairs_of(v)[1] end

  engine.mesh("smokestack", {
    {mesh = "cylinder", size = {2.2, 28, 2.2}, color = {0.6, 0.55, 0.5}},
    {mesh = "cylinder", pos = {0, 11, 0}, size = {2.25, 2, 2.25}, color = {0.8, 0.15, 0.1}},
    {mesh = "cylinder", pos = {0, 6, 0}, size = {2.25, 2, 2.25}, color = {0.9, 0.9, 0.88}},
    {mesh = "cylinder", pos = {0, 13.6, 0}, size = {1.6, 0.8, 1.6}, color = {0.2, 0.2, 0.2}},
  })
  if PARK then central_park(L) end
  for i = 0, NX - 1 do
    for j = 0, NZ - 1 do
      local district = C.district(i, j)
      local key = i .. "," .. j
      local kind = district == "water" and "water" or district == "park" and "central_park" or SPECIAL[key] or "buildings"
      L.kinds[key] = kind
      if district ~= "water" and district ~= "park" then
        local cx, cz = C.block_center(i, j)
        local r = rng(i, j)
        static{mesh = "cube", pos = {cx, CURB / 2, cz}, size = {BX, CURB, BZ}, color = {0.62, 0.62, 0.6}, tag = "sidewalk"}
        local x0, x1, z0, z1 = cx - BX / 2 + WALK, cx + BX / 2 - WALK, cz - BZ / 2 + WALK, cz + BZ / 2 - WALK
        if kind == "buildings" then
          local built = fill(x0, x1, z0, z1, i, j, r, {true, true})
          if BILLBOARDS[key] then billboards(built, r) end
        elseif kind == "park" then pocket_park(cx, cz, r)
        elseif kind == "square" then square(cx, cz, r)
        else
          local half = FEATURE_W[kind] / 2
          fill(x0, cx - half, z0, z1, i, j, r, {true, false})
          fill(cx + half, x1, z0, z1, i, j, r, {false, true})
          feature(kind, cx, cz, L)
        end
        -- Street lamps on the corners and halfway along the long sides.
        for _, c in ipairs{{1, 1}, {-1, 1}, {1, -1}, {-1, -1}, {0, 1}, {0, -1}} do
          static{mesh = "lamp", pos = {cx + c[1] * (BX / 2 - 1), CURB, cz + c[2] * (BZ / 2 - 1)},
                 yaw = math.atan(c[1], c[2]), size = {0.3, 10, 0.3}, tag = "lamp"}
        end
      end
    end
  end
  return L
end

return C
