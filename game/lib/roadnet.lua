-- Maps drawn as roads instead of a grid: named junctions, and roads as
-- lists of points through them (bends are plain points; a road only meets
-- another at a named junction). lib/city loads one of these when a map has
-- `roads` instead of `grid`, and builds it with R.build. Buildings line
-- the roads by district; landmarks are placed by hand. See maps/raisio.lua.
local R = {}

local SIDEWALK = 3          -- meters of pavement each side of a non-highway road
local WIDTH = {highway = 18, main = 13, street = 10}
local LAND, PAVE, ROAD = {0.3, 0.42, 0.24}, {0.6, 0.6, 0.58}, {0.24, 0.24, 0.26}
local WATER = {0.16, 0.3, 0.52}

local NET -- the loaded network

local function dist_seg(px, pz, ax, az, bx, bz)
  local dx, dz = bx - ax, bz - az
  local l2 = dx * dx + dz * dz
  local t = l2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (pz - az) * dz) / l2)) or 0
  local cx, cz = ax + dx * t, az + dz * t
  return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2), cx, cz, t
end

-- Do segments ab and cd cross (not just touch at an end)? Returns the point.
local function crossing(ax, az, bx, bz, cx, cz, dx, dz)
  local rx, rz, sx, sz = bx - ax, bz - az, dx - cx, dz - cz
  local den = rx * sz - rz * sx
  if math.abs(den) < 1e-9 then return end
  local t = ((cx - ax) * sz - (cz - az) * sx) / den
  local u = ((cx - ax) * rz - (cz - az) * rx) / den
  if t > 1e-3 and t < 1 - 1e-3 and u > 1e-3 and u < 1 - 1e-3 then return ax + rx * t, az + rz * t end
end

-- ---- loading -------------------------------------------------------------------------

-- Parse the map into a graph: junction ids in the order the map names them,
-- then any road ends that aren't named; one edge per stretch of road between
-- junctions, with its bends.
function R.load(map)
  local n = {pos = {}, links = {}, roads = {}, edges = {}, paths = {}, id = {}, name = {}, map = map}
  local function junction(name)
    if n.id[name] then return n.id[name] end
    local p = map.junctions[name]
    if not p then error(string.format("map '%s': no junction named '%s'", map.name or "?", name), 0) end
    local id = #n.pos + 1
    n.pos[id], n.links[id], n.id[name], n.name[id] = {p[1], p[2]}, {}, id, name
    return id
  end
  for _, name in ipairs(map.junction_order or {}) do junction(name) end
  local names = {}
  for name in pairs(map.junctions) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do junction(name) end

  for ri, road in ipairs(map.roads) do
    local kind = road.kind or "street"
    local width = road.width or WIDTH[kind] or 10
    local label = road.name or ("road " .. ri)
    assert(#road >= 2, label .. " needs at least two points")
    -- Ends that aren't junctions become nameless ones (dead ends).
    local pts, ids = {}, {}
    for i, p in ipairs(road) do
      local id
      if type(p) == "string" then id = junction(p)
      elseif i == 1 or i == #road then
        id = #n.pos + 1
        n.pos[id], n.links[id] = {p[1], p[2]}, {}
      end
      pts[i] = id and n.pos[id] or p
      ids[i] = id
    end
    local start = 1
    for i = 2, #pts do
      if ids[i] then
        local a, b = ids[start], ids[i]
        local seg = {}
        for k = start, i do seg[#seg + 1] = {pts[k][1], pts[k][2]} end
        n.paths[a] = n.paths[a] or {}
        n.paths[b] = n.paths[b] or {}
        if n.paths[a][b] then error(string.format("map '%s': two roads join the same pair of junctions (%s)", map.name or "?", label), 0) end
        n.paths[a][b] = seg
        local back = {}
        for k = #seg, 1, -1 do back[#back + 1] = seg[k] end
        n.paths[b][a] = back
        table.insert(n.links[a], b)
        table.insert(n.links[b], a)
        n.roads[#n.roads + 1] = {a, b}
        n.edges[#n.edges + 1] = {a = a, b = b, pts = seg, kind = kind, width = width, name = label, bridge = road.bridge}
        start = i
      end
    end
  end
  n.grid = R.index(n.edges)
  NET = n
  return n
end

function R.net() return NET end

-- Every stretch of road by the grid cells its bounding box touches: cell
-- key -> {{edge, bend}, ...}, so lookups only look nearby.
local CELL = 64
local function cell_key(i, j) return i * 100003 + j end
function R.index(edges)
  local g = {}
  for ei, e in ipairs(edges) do
    for i = 2, #e.pts do
      local a, b = e.pts[i - 1], e.pts[i]
      for ci = math.floor(math.min(a[1], b[1]) / CELL), math.floor(math.max(a[1], b[1]) / CELL) do
        for cj = math.floor(math.min(a[2], b[2]) / CELL), math.floor(math.max(a[2], b[2]) / CELL) do
          local k = cell_key(ci, cj)
          g[k] = g[k] or {}
          table.insert(g[k], {ei, i})
        end
      end
    end
  end
  return g
end

-- The bends from junction a to b, as {x, z} points, a and b included.
function R.path(a, b) return NET.paths[a][b] end

-- Where the nearest pavement or road of any kind is from (x, z), and the
-- edge it's on.
function R.nearest_edge(x, z, walkable)
  local best, be, bi, bx, bz = math.huge
  local ci, cj = math.floor(x / CELL), math.floor(z / CELL)
  local function try(list)
    for _, it in ipairs(list) do
      local e = NET.edges[it[1]]
      if not (walkable and e.kind == "highway") then
        local a, b = e.pts[it[2] - 1], e.pts[it[2]]
        local d, cx, cz = dist_seg(x, z, a[1], a[2], b[1], b[2])
        if d < best then best, be, bi, bx, bz = d, it[1], it[2], cx, cz end
      end
    end
  end
  -- Rings of cells outward, until the nearest found is closer than the
  -- next ring can be.
  for r = 0, 400 do
    for i = ci - r, ci + r do
      for j = cj - r, cj + r do
        if math.max(math.abs(i - ci), math.abs(j - cj)) == r then
          local list = NET.grid[cell_key(i, j)]
          if list then try(list) end
        end
      end
    end
    if best <= r * CELL then break end
  end
  return be, bi, bx, bz, best
end

-- ---- checking ------------------------------------------------------------------------

function R.check(map)
  local name = map.name or "?"
  local function fail(fmt, ...) error(string.format("map '%s': " .. fmt, name, ...), 0) end
  -- Roads may only meet at junctions (a bridge passes over). Only stretches
  -- sharing a grid cell can cross.
  local E = NET.edges
  for _, list in pairs(NET.grid) do
    for p = 1, #list do
      for q = p + 1, #list do
        local ea, eb = list[p][1], list[q][1]
        local a, b = E[ea], E[eb]
        if ea ~= eb and not (a.bridge or b.bridge) then
          local i, k = list[p][2], list[q][2]
          local x, z = crossing(a.pts[i - 1][1], a.pts[i - 1][2], a.pts[i][1], a.pts[i][2],
                                b.pts[k - 1][1], b.pts[k - 1][2], b.pts[k][1], b.pts[k][2])
          if x then fail("%s crosses %s at (%.0f, %.0f) without a junction", a.name, b.name, x, z) end
        end
      end
    end
  end
  -- Everything reachable from the first junction.
  local seen, queue = {[1] = true}, {1}
  for _, q in ipairs(queue) do
    for _, nb in ipairs(NET.links[q]) do
      if not seen[nb] then seen[nb] = true; queue[#queue + 1] = nb end
    end
  end
  for id = 1, #NET.pos do
    if not seen[id] then fail("junction %s can't be reached by road", NET.name[id] or ("at " .. NET.pos[id][1] .. "," .. NET.pos[id][2])) end
  end
  for kind, p in pairs(map.specials or {}) do
    local _, _, _, _, d = R.nearest_edge(p[1], p[2])
    local e = E[select(1, R.nearest_edge(p[1], p[2]))]
    if d < 20 + e.width / 2 then fail("the %s's 40 m pad at (%.0f, %.0f) is on %s", kind, p[1], p[2], e.name) end
  end
  for _, b in ipairs(map.buildings or {}) do
    local yaw = b.yaw or 0
    local fx, fz, nx, nz = math.cos(yaw), -math.sin(yaw), math.sin(yaw), math.cos(yaw)
    for _, a in ipairs{-0.5, 0, 0.5} do
      for _, c in ipairs{-0.5, 0, 0.5} do
        local x, z = b.x + fx * b.w * a + nx * b.d * c, b.z + fz * b.w * a + nz * b.d * c
        local ei, _, _, _, dd = R.nearest_edge(x, z)
        local e = E[ei]
        if dd < e.width / 2 + (e.kind == "highway" and 1.5 or SIDEWALK) then fail("%s stands on %s", b.name or "a building", e.name) end
      end
    end
  end
  for pname, p in pairs(map.places or {}) do
    for _, j in ipairs(p.route or (p.junction and {p.junction}) or {}) do
      if not NET.id[j] then fail("place %s names junction '%s', which doesn't exist", pname, j) end
    end
  end
end

-- ---- places --------------------------------------------------------------------------

function R.has(map, name) return (map.places or {})[name] ~= nil or (map.specials or {})[name] ~= nil end

function R.place(map, name)
  local p = (map.places or {})[name]
  if not p then
    local sp = (map.specials or {})[name]
    if not sp then error(string.format("map '%s' has no place '%s'", map.name or "?", name), 3) end
    return sp[1], sp[2]
  end
  if p.junction then local q = NET.pos[NET.id[p.junction]]; return q[1], q[2] end
  if p.at then return p.at[1], p.at[2] end
  error(string.format("place '%s' needs `at` or `junction`", name), 3)
end

function R.route(map, name)
  local p = (map.places or {})[name]
  if not (p and p.route) then error(string.format("map '%s' has no route '%s'", map.name or "?", name), 3) end
  local out = {}
  for _, j in ipairs(p.route) do local q = NET.pos[NET.id[j]]; out[#out + 1] = {q[1], q[2]} end
  return out
end

function R.route_ids(map, name)
  local out = {}
  for _, j in ipairs(map.places[name].route) do out[#out + 1] = NET.id[j] end
  return out
end

-- ---- building ------------------------------------------------------------------------

-- A spatial hash of things placed so far (roads, buildings, pads, water),
-- each a circle or a segment with a clearance, for "is this spot free?".
local function hash(cell)
  local h = {cell = cell, cells = {}}
  local function key(i, j) return i * 100003 + j end
  function h.add(item, x0, z0, x1, z1)
    for i = math.floor(x0 / cell), math.floor(x1 / cell) do
      for j = math.floor(z0 / cell), math.floor(z1 / cell) do
        local k = key(i, j)
        h.cells[k] = h.cells[k] or {}
        table.insert(h.cells[k], item)
      end
    end
  end
  function h.near(x, z, r, fn)
    for i = math.floor((x - r) / cell), math.floor((x + r) / cell) do
      for j = math.floor((z - r) / cell), math.floor((z + r) / cell) do
        for _, it in ipairs(h.cells[key(i, j)] or {}) do
          if fn(it) then return true end
        end
      end
    end
    return false
  end
  return h
end

-- Is a circle of radius r at (x, z) clear of everything in the hash?
local function free(H, x, z, r)
  return not H.near(x, z, r + 40, function(it)
    if it.seg then
      return dist_seg(x, z, it.ax, it.az, it.bx, it.bz) < r + it.clear
    end
    return (x - it.x) ^ 2 + (z - it.z) ^ 2 < (r + it.r) ^ 2
  end)
end

local function add_seg(H, ax, az, bx, bz, clear, edge, width)
  H.add({seg = true, ax = ax, az = az, bx = bx, bz = bz, clear = clear, edge = edge, width = width},
        math.min(ax, bx) - clear, math.min(az, bz) - clear, math.max(ax, bx) + clear, math.max(az, bz) + clear)
end

local function add_circle(H, x, z, r)
  H.add({x = x, z = z, r = r}, x - r, z - r, x + r, z + r)
end

-- Are the corners and edge midpoints of a w x d box along (fx, fz) all
-- clear of the roads and water? (Circles alone miss corners.)
local function box_clear(H, cx, cz, fx, fz, w, d)
  local nx, nz = fz, -fx
  for _, a in ipairs{-0.5, 0, 0.5} do
    for _, b in ipairs{-0.5, 0, 0.5} do
      local x, z = cx + fx * w * a + nx * d * b, cz + fz * w * a + nz * d * b
      local hit = H.near(x, z, 40, function(it) return it.seg and dist_seg(x, z, it.ax, it.az, it.bx, it.bz) < it.clear end)
      if hit then return false end
    end
  end
  return true
end

-- A w x d box along (fx, fz) as a row of circles d wide: close enough to
-- its footprint that long buildings can stand near a road.
local function box_circles(cx, cz, fx, fz, w, d)
  local out, n = {}, math.max(1, math.ceil(w / d))
  for k = 0, n - 1 do
    local t = n == 1 and 0 or (k / (n - 1) - 0.5) * (w - d)
    out[#out + 1] = {cx + fx * t, cz + fz * t, d * 0.5}
  end
  return out
end

-- The district at (x, z): the first of the map's areas containing it.
local function district(map, x, z)
  for _, a in ipairs(map.areas or {}) do
    if (x - a.x) ^ 2 + (z - a.z) ^ 2 < a.r * a.r then return a[1] end
  end
  return map.default_district or "suburb"
end

-- Bake a list of parts in world space into one mesh around their middle,
-- and spawn it (scenery: no collider).
local function bake(name, parts, y, tag)
  if #parts == 0 then return end
  local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(parts) do
    x0, x1 = math.min(x0, p.pos[1]), math.max(x1, p.pos[1])
    z0, z1 = math.min(z0, p.pos[3]), math.max(z1, p.pos[3])
  end
  local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
  for _, p in ipairs(parts) do p.pos = {p.pos[1] - cx, p.pos[2] - y, p.pos[3] - cz} end
  engine.mesh(name, parts)
  engine.spawn{mesh = name, pos = {cx, y, cz}, scale = 1, tag = tag or "road"}
end

-- Parts grouped by which CHUNK x CHUNK square they're in, baked one mesh a
-- square, so what's out of sight is culled a square at a time.
local CHUNK = 300
local function chunked()
  local c = {}
  function c.add(x, z, part)
    local k = math.floor(x / CHUNK) .. "," .. math.floor(z / CHUNK)
    c[k] = c[k] or {}
    table.insert(c[k], part)
  end
  function c.bake(prefix, tag)
    local keys = {}
    for k, v in pairs(c) do if type(v) == "table" then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do bake(prefix .. k, c[k], 0, tag) end
  end
  return c
end

-- Ground cover drawn under everything, in this order, each a little above
-- the last; the color and a tree every so many square meters (nil: none).
local COVER = {
  {"field", {0.5, 0.56, 0.3}}, {"forest", {0.2, 0.33, 0.17}, 700}, {"park", {0.34, 0.52, 0.27}, 2500},
  {"works", {0.46, 0.45, 0.43}}, {"parking", {0.3, 0.3, 0.32}}, {"water", WATER},
}

-- A strip along a polyline: a box per segment and a disc at each bend, so
-- curves have no gaps.
local function strip(parts, pts, width, top, color, discs)
  for i = 2, #pts do
    local ax, az, bx, bz = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
    local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    parts[#parts + 1] = {mesh = "cube", pos = {(ax + bx) / 2, top - 0.01, (az + bz) / 2}, yaw = math.atan(bx - ax, bz - az),
                         size = {width, 0.02, len}, color = color}
  end
  for i = discs and 1 or 2, discs and #pts or #pts - 1 do
    parts[#parts + 1] = {mesh = "cylinder", pos = {pts[i][1], top - 0.01, pts[i][2]}, size = {width, 0.02, width}, color = color}
  end
end

-- Dashed center line.
local function dashes(parts, pts, top)
  for i = 2, #pts do
    local ax, az, bx, bz = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
    local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    local yaw = math.atan(bx - ax, bz - az)
    for s = 8, len - 8, 9 do
      local t = s / len
      parts[#parts + 1] = {mesh = "cube", pos = {ax + (bx - ax) * t, top, az + (bz - az) * t}, yaw = yaw,
                           size = {0.18, 0.01, 3}, color = {0.9, 0.9, 0.86}}
    end
  end
end

-- Detached houses: a painted wooden box under a gable roof, the ridge
-- running along the street. Unit footprint, real height.
local HOUSE = {{0.72, 0.2, 0.15}, {0.9, 0.78, 0.4}, {0.88, 0.88, 0.84}, {0.45, 0.55, 0.62}, {0.6, 0.38, 0.25}, {0.78, 0.7, 0.55}}
local ROOF = {{0.25, 0.22, 0.22}, {0.45, 0.18, 0.12}, {0.3, 0.32, 0.35}}
local baked = {}
local function house_mesh(v, floors)
  local name = string.format("house%d_%d", v, floors)
  if baked[name] then return name end
  local h, c, rc = floors * 2.9, HOUSE[v], ROOF[v % #ROOF + 1]
  local parts = {{mesh = "cube", size = {1, h, 1}, color = c}}
  for f = 0, floors - 1 do -- windows front and back
    for _, x in ipairs{-0.28, 0.28} do
      parts[#parts + 1] = {mesh = "cube", pos = {x, -h / 2 + f * 2.9 + 1.6, 0}, size = {0.14, 1.0, 1.01}, color = {0.22, 0.26, 0.32},
                           emissive = (v + f) % 3 == 0 and 1 or 0}
    end
  end
  parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + 1.05, 0.5}, size = {0.12, 2.1, 0.02}, color = {0.95, 0.95, 0.92}}
  -- The roof overhangs a little; two wedges back to back.
  parts[#parts + 1] = {mesh = "wedge", pos = {0, h / 2 + 1.1, -0.28}, size = {1.08, 2.2, 0.56}, color = rc}
  parts[#parts + 1] = {mesh = "wedge", pos = {0, h / 2 + 1.1, 0.28}, yaw = math.pi, size = {1.08, 2.2, 0.56}, color = rc}
  engine.mesh(name, parts)
  baked[name] = true
  return name
end

-- A Finnish spruce: stacked tiers of dark green.
local function pine_mesh()
  if baked.pine then return end
  local parts = {{mesh = "cylinder", pos = {0, 1.0, 0}, size = {0.35, 2, 0.35}, color = {0.35, 0.24, 0.15}}}
  for k = 0, 3 do
    local s = 3.6 - k * 0.8
    parts[#parts + 1] = {mesh = "cylinder", pos = {0, 2.4 + k * 1.6, 0}, size = {s, 1.8, s}, color = {0.12, 0.3 + k * 0.03, 0.16}}
  end
  engine.mesh("pine", parts)
  baked.pine = true
end

local PLASTER = {{0.9, 0.88, 0.82}, {0.85, 0.8, 0.68}, {0.78, 0.8, 0.82}, {0.88, 0.82, 0.72}, {0.7, 0.45, 0.35}, {0.92, 0.92, 0.9}}

-- What lines a road in each district: footprint ranges, setback from the
-- pavement, floors, and how often a lot is left empty.
local KINDS = {
  downtown = {w = {16, 30}, d = {14, 22}, back = {0.5, 1}, floors = {3, 6}, gap = {0, 2}, empty = 0.1},
  apartments = {w = {28, 46}, d = {12, 14}, back = {8, 14}, floors = {3, 7}, gap = {10, 18}, empty = 0.2},
  suburb = {w = {9, 13}, d = {8, 11}, back = {5, 9}, floors = {1, 2}, gap = {7, 12}, empty = 0.15},
  industrial = {w = {28, 48}, d = {24, 36}, back = {6, 10}, floors = {0, 0}, gap = {8, 14}, empty = 0.25},
}

function R.build(map, kit)
  local sx, sz = map.size[1], map.size[2]
  local r = kit.rng(7, 11)
  local H = hash(40)
  local L = {map = map.id or map.name, network = true, sx = sx, sz = sz, curb = kit.CURB, walk = SIDEWALK,
             avenue = 14, street = 12, kinds = {}, landmarks = {}, labels = {}}

  -- Land, the sea round it, and invisible walls at the shore.
  kit.static{mesh = "cube", pos = {0, -1.5, 0}, size = {sx, 3, sz}, color = LAND, tag = "ground"}
  local W = 1500
  for _, f in ipairs{{0, -(sz + W) / 2, sx + 2 * W, W}, {0, (sz + W) / 2, sx + 2 * W, W},
                     {-(sx + W) / 2, 0, W, sz}, {(sx + W) / 2, 0, W, sz}} do
    engine.spawn{mesh = "cube", pos = {f[1], 0.04 - 0.5, f[2]}, size = {f[3], 1, f[4]}, color = WATER, tag = "water"}
  end
  for _, s in ipairs{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
    kit.static{pos = {s[1] * sx / 2, 5, s[2] * sz / 2}, size = {s[1] == 0 and sx or 1, 10, s[2] == 0 and sz or 1}, visible = false, tag = "wall"}
  end

  -- Rivers: water ribbons with nothing built on them; railings where a road
  -- passes over.
  for ri, river in ipairs(map.rivers or {}) do
    local parts = {}
    strip(parts, river, river.width or 10, 0.03, WATER, true)
    bake("river" .. ri, parts, 0)
    for i = 2, #river do
      add_seg(H, river[i - 1][1], river[i - 1][2], river[i][1], river[i][2], (river.width or 10) / 2 + 2)
    end
    for _, e in ipairs(NET.edges) do
      for p = 2, #e.pts do
        for q = 2, #river do
          local x, z = crossing(e.pts[p - 1][1], e.pts[p - 1][2], e.pts[p][1], e.pts[p][2],
                                river[q - 1][1], river[q - 1][2], river[q][1], river[q][2])
          if x then
            local yaw = math.atan(e.pts[p][1] - e.pts[p - 1][1], e.pts[p][2] - e.pts[p - 1][2])
            local rx, rz = math.cos(yaw), -math.sin(yaw)
            for _, s in ipairs{-1, 1} do
              local o = e.width / 2 + 0.4
              kit.static{mesh = "cube", pos = {x + rx * o * s, 0.6, z + rz * o * s}, yaw = yaw, size = {0.3, 1.2, (river.width or 10) + 6},
                         color = {0.55, 0.55, 0.58}, tag = "wall"}
            end
          end
        end
      end
    end
  end

  -- Roads: pavement under, asphalt on top, a dashed center line.
  for ei, e in ipairs(NET.edges) do
    local parts = {}
    local walk = e.kind ~= "highway"
    if walk then strip(parts, e.pts, e.width + 2 * SIDEWALK, 0.05, PAVE, true) end
    strip(parts, e.pts, e.width, 0.08, ROAD, true)
    dashes(parts, e.pts, 0.09)
    bake("road" .. ei, parts, 0)
    for i = 2, #e.pts do
      add_seg(H, e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2], e.width / 2 + (walk and SIDEWALK or 1.5), ei, e.width)
    end
  end
  -- Street lamps along the pavement, alternating sides, once every road is
  -- known: none on another road's asphalt.
  for ei, e in ipairs(NET.edges) do
    local walk = e.kind ~= "highway"
    if walk then
      local side = 1
      for i = 2, #e.pts do
        local ax, az, bx, bz = e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]
        local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
        local yaw = math.atan(bx - ax, bz - az)
        local rx, rz = math.cos(yaw), -math.sin(yaw)
        for s = 14, len - 14, map.lamp_every or 38 do
          local t, o = s / len, (e.width / 2 + SIDEWALK - 0.6) * side
          local lx, lz = ax + (bx - ax) * t + rx * o, az + (bz - az) * t + rz * o
          local on_road = H.near(lx, lz, 40, function(it)
            return it.edge and it.edge ~= ei and dist_seg(lx, lz, it.ax, it.az, it.bx, it.bz) < it.width / 2 + 1.5
          end)
          if not on_road then
            kit.static{mesh = "lamp", pos = {lx, 0.05, lz}, yaw = yaw - side * math.pi / 2, size = {0.3, 10, 0.3}, tag = "lamp"}
          end
          side = -side
        end
      end
    end
  end
  for id, p in ipairs(NET.pos) do
    local ring = (NET.map.roundabouts or {})[NET.name[id] or ""]
    if ring then -- a planted island in the middle
      engine.spawn{mesh = "cylinder", pos = {p[1], 0.1, p[2]}, size = {ring, 0.04, ring}, color = {0.35, 0.55, 0.28}, tag = "island"}
      engine.spawn{mesh = "cylinder", pos = {p[1], 0.11, p[2]}, size = {ring + 1, 0.03, ring + 1}, color = PAVE}
    end
  end

  -- Ground cover from the map's survey: fields, forest, water... as strips.
  for k, c in ipairs(COVER) do
    local strips = (map.cover or {})[c[1]]
    if strips and #strips > 0 then
      local ch = chunked()
      for _, st in ipairs(strips) do
        local x, z = (st[1] + st[3]) / 2, (st[2] + st[4]) / 2
        ch.add(x, z, {mesh = "cube", pos = {x, k * 0.006 - 0.005, z}, size = {st[3] - st[1], 0.02, st[4] - st[2]}, color = c[2]})
      end
      ch.bake("cover_" .. c[1], c[1] == "water" and "water" or "cover")
    end
  end
  -- Service roads and paved paths: drawn, not driven by the AI.
  if map.paved then
    local ch = chunked()
    for _, p in ipairs(map.paved) do
      local pts = {}
      for i = 3, #p do pts[#pts + 1] = p[i] end
      local parts = {}
      strip(parts, pts, p[1], p[2] and 0.047 or 0.044, p[2] and ROAD or {0.56, 0.55, 0.52}, true)
      for _, part in ipairs(parts) do ch.add(part.pos[1], part.pos[3], part) end
    end
    ch.bake("paved", "cover")
  end

  -- Pads for the game's features (the lot, the stunt park...).
  for kind, p in pairs(map.specials or {}) do
    kit.static{mesh = "cube", pos = {p[1], kit.CURB / 2, p[2]}, size = {40, kit.CURB, 40}, color = PAVE, tag = "sidewalk"}
    kit.feature(kind, p[1], p[2], L)
    add_circle(H, p[1], p[2], 30)
  end

  -- Hand-placed buildings: the town hall, schools, the mall.
  for bi, b in ipairs(map.buildings or {}) do
    local yaw = b.yaw or 0
    if b.style == "warehouse" then
      local h = b.floors and b.floors * 3.5 or 8
      kit.static{mesh = kit.warehouse_mesh(1 + bi % 4, h), pos = {b.x, kit.CURB + h / 2, b.z}, yaw = yaw, size = {b.w, h, b.d},
                 scale = {b.w, 1, b.d}, tag = "building"}
    else
      local floors = b.floors or 3
      local h = floors * kit.FLOOR
      kit.static{mesh = kit.building_mesh(b.style or "brick", floors), pos = {b.x, kit.CURB + h / 2, b.z}, yaw = yaw,
                 size = {b.w, h, b.d}, scale = {b.w, 1, b.d}, color = b.color or PLASTER[1 + bi % #PLASTER], tag = "building"}
    end
    if b.letter then L.labels[#L.labels + 1] = {x = b.x, z = b.z, letter = b.letter, name = b.name} end
    add_circle(H, b.x, b.z, math.sqrt(b.w * b.w + b.d * b.d) / 2 + 2)
  end
  for _, a in ipairs(map.areas or {}) do
    if a[1] == "open" or a[1] == "park" then add_circle(H, a.x, a.z, a.r) end
  end
  for _, lb in ipairs(map.labels or {}) do L.labels[#L.labels + 1] = lb end
  -- The gun shop's door is on the south wall of a small block of its own.
  if map.gunshop then
    local gx, gz = map.gunshop[1], map.gunshop[2]
    local h = 2 * kit.FLOOR
    kit.static{mesh = kit.building_mesh("brick", 2), pos = {gx, kit.CURB + h / 2, gz - 6}, size = {14, h, 12}, scale = {14, 1, 12},
               color = PLASTER[2], tag = "building"}
    add_circle(H, gx, gz - 6, 10)
  end

  -- Surveyed buildings, each a box (or a few), clear of what's placed.
  local count = 0
  for i, f in ipairs(map.footprints or {}) do
    local x, z, w, d, yaw, h, kind = f[1], f[2], f[3], f[4], f[5], f[6], f[7]
    local fx, fz = math.cos(yaw), -math.sin(yaw)
    local circles = box_circles(x, z, fx, fz, w, d)
    local ok = true
    for _, c in ipairs(circles) do
      ok = ok and not H.near(c[1], c[2], c[3] + 40, function(it)
        return not it.seg and (c[1] - it.x) ^ 2 + (c[2] - it.z) ^ 2 < (c[3] + it.r) ^ 2 and it.r > 8
      end)
    end
    if ok then
      if kind == "house" or kind == "terrace" then
        local floors = h < 4.5 and 1 or 2
        kit.static{mesh = house_mesh(1 + i % #HOUSE, floors), pos = {x, floors * 1.45, z}, yaw = yaw,
                   size = {w, floors * 2.9, d}, scale = {w, 1, d}, tag = "building"}
      elseif kind == "shed" then
        kit.static{mesh = "cube", pos = {x, h / 2, z}, yaw = yaw, size = {w, h, d}, color = HOUSE[1 + i % #HOUSE], tag = "building"}
      elseif kind == "works" or (kind == "shop" and w * d > 1500) then
        kit.static{mesh = kit.warehouse_mesh(1 + i % 4, h), pos = {x, kit.CURB + h / 2, z}, yaw = yaw, size = {w, h, d},
                   scale = {w, 1, d}, tag = "building"}
      else
        local floors = math.max(1, math.floor(h / kit.FLOOR + 0.5))
        local style = kind == "shop" and i % 3 == 0 and "glass" or "brick"
        local color = kind == "church" and {0.94, 0.93, 0.9} or style == "glass" and {1, 1, 1} or PLASTER[1 + i % #PLASTER]
        kit.static{mesh = kit.building_mesh(style, floors), pos = {x, kit.CURB + floors * kit.FLOOR / 2, z}, yaw = yaw,
                   size = {w, floors * kit.FLOOR, d}, scale = {w, 1, d}, color = color, tag = "building"}
      end
      for _, c in ipairs(circles) do add_circle(H, c[1], c[2], c[3]) end
      count = count + 1
    end
  end

  -- Without a survey, buildings line the roads, by district.
  for _, e in ipairs(map.footprints and {} or NET.edges) do
    if e.kind ~= "highway" then
      for _, side in ipairs{-1, 1} do
        for i = 2, #e.pts do
          local ax, az, bx, bz = e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]
          local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
          local yaw = math.atan(bx - ax, bz - az)
          local fx, fz = (bx - ax) / len, (bz - az) / len
          local nx, nz = fz * side, -fx * side
          local s = 4
          while s < len - 4 do
            local mx, mz = ax + fx * s, az + fz * s
            local kind = district(map, mx, mz)
            local K = KINDS[kind]
            if not K then s = s + 20 else
              local w, d = r(K.w[1], K.w[2]), r(K.d[1], K.d[2])
              if s + w > len then break end
              local off = e.width / 2 + SIDEWALK + r(K.back[1], K.back[2]) + d / 2
              local cx, cz = mx + fx * w / 2 + nx * off, mz + fz * w / 2 + nz * off
              local rad = math.sqrt(w * w + d * d) / 2
              local circles = box_circles(cx, cz, fx, fz, w, d)
              local ok = r() > K.empty and math.abs(cx) < sx / 2 - rad and math.abs(cz) < sz / 2 - rad
              for _, c in ipairs(circles) do ok = ok and free(H, c[1], c[2], c[3] * 0.96) end
              ok = ok and box_clear(H, cx, cz, fx, fz, w, d)
              if ok then
                local wall = PLASTER[r(1, #PLASTER)]
                -- The model's x (its width) runs along the road; its front
                -- (+z, where a house's door is) faces the street.
                local yaw = yaw - math.pi / 2 + (side < 0 and math.pi or 0)
                if kind == "suburb" then
                  local floors = r(1, 2)
                  kit.static{mesh = house_mesh(r(1, #HOUSE), floors), pos = {cx, floors * 1.45, cz}, yaw = yaw,
                             size = {w, floors * 2.9, d}, scale = {w, 1, d}, tag = "building"}
                  if r() < 0.5 then -- a tree in the yard
                    pine_mesh()
                    local tx, tz = cx - nx * (d / 2 + 2.5) + fx * (w / 2 + 1), cz - nz * (d / 2 + 2.5) + fz * (w / 2 + 1)
                    if free(H, tx, tz, 1) then kit.static{mesh = "pine", pos = {tx, 0, tz}, size = {0.5, 6, 0.5}, scale = 0.8 + r() * 0.5, tag = "tree"} end
                  end
                elseif kind == "industrial" then
                  local h = 6 + r(0, 3) * 2
                  kit.static{mesh = kit.warehouse_mesh(r(1, 4), h), pos = {cx, kit.CURB + h / 2, cz}, yaw = yaw, size = {w, h, d},
                             scale = {w, 1, d}, tag = "building"}
                else
                  local floors = r(K.floors[1], K.floors[2])
                  local style = (kind == "downtown" and r() < 0.15) and "glass" or "brick"
                  kit.static{mesh = kit.building_mesh(style, floors), pos = {cx, kit.CURB + floors * kit.FLOOR / 2, cz}, yaw = yaw,
                             size = {w, floors * kit.FLOOR, d}, scale = {w, 1, d}, color = style == "glass" and {1, 1, 1} or wall,
                             tag = "building"}
                end
                for _, c in ipairs(circles) do add_circle(H, c[1], c[2], c[3]) end
                count = count + 1
              end
              s = s + w + r(K.gap[1], K.gap[2])
            end
          end
        end
      end
    end
  end

  -- Forest wherever there's room: in the surveyed woods and parks, else
  -- anywhere, up to the map's budget.
  pine_mesh()
  local trees, budget = 0, map.trees or 900
  local want = 0 -- trees the cover asks for; thinned evenly to the budget
  for _, c in ipairs(COVER) do
    for _, st in ipairs(c[3] and (map.cover or {})[c[1]] or {}) do want = want + (st[3] - st[1]) * (st[4] - st[2]) / c[3] end
  end
  local thin = math.min(1, budget / math.max(1, want))
  for _, c in ipairs(COVER) do
    for _, st in ipairs(c[3] and (map.cover or {})[c[1]] or {}) do
      local n = (st[3] - st[1]) * (st[4] - st[2]) / c[3] * thin
      n = math.floor(n) + (r() < n % 1 and 1 or 0)
      for _ = 1, n do
        if trees >= budget then break end
        local x, z = st[1] + r() * (st[3] - st[1]), st[2] + r() * (st[4] - st[2])
        if free(H, x, z, 3) then
          kit.static{mesh = r() < 0.75 and "pine" or "tree", pos = {x, 0, z}, size = {0.5, 6, 0.5}, scale = 0.8 + r() * 0.7, tag = "tree"}
          add_circle(H, x, z, 2)
          trees = trees + 1
        end
      end
    end
  end
  for _ = 1, map.cover and 0 or budget do
    local x, z = (r() - 0.5) * (sx - 20), (r() - 0.5) * (sz - 20)
    local a = district(map, x, z)
    if a ~= "open" and free(H, x, z, 3) then
      kit.static{mesh = r() < 0.7 and "pine" or "tree", pos = {x, 0, z}, size = {0.5, 6, 0.5}, scale = 0.8 + r() * 0.7, tag = "tree"}
      add_circle(H, x, z, 2)
      trees = trees + 1
    end
  end
  L.buildings, L.trees = count, trees
  return L
end

-- Pickup spots: {kind, x, z} straight from the map.
function R.pickup_spots(map)
  local out = {}
  for _, s in ipairs(map.pickups or {}) do out[#out + 1] = {s[1], s[2], s[3]} end
  return out
end

-- Pavement for pedestrians: the edges they can walk (not highways).
function R.walkable(e) return NET.edges[e].kind ~= "highway" end
R.SIDEWALK = SIDEWALK

return R
