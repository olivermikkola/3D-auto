-- Maps drawn as roads instead of a grid: named junctions, and roads as
-- lists of points through them (bends are plain points; a road only meets
-- another at a named junction). lib/city loads one of these when a map has
-- `roads` instead of `grid`, and builds it with R.build. Buildings line
-- the roads by district; landmarks are placed by hand. See maps/raisio.lua.
local tunnel = require "lib.tunnel"
local R = {}

local SIDEWALK = 3          -- meters of pavement each side of a non-highway road
local WIDTH = {highway = 18, main = 13, street = 10}
local LAND, PAVE, ROAD = {0.3, 0.42, 0.24}, {0.6, 0.6, 0.58}, {0.24, 0.24, 0.26}
local WATER = {0.16, 0.3, 0.52}
local PATH = {0.36, 0.36, 0.37} -- foot and cycle paths: asphalt, a little paler than the road

local NET -- the loaded network
-- On a map with terrain, the height of the ground (or water) at x, z; nil on
-- a flat map. BASE, while set, stands in for it (a building's footprint).
local GROUND, BASE
local wet_rows -- the water's strips by row, built when first needed

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
  local n = {pos = {}, links = {}, roads = {}, edges = {}, paths = {}, id = {}, name = {}, map = map, edge_of = {}}
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
    local pts, ids, cum = {}, {}, {0}
    for i, p in ipairs(road) do
      local id
      if type(p) == "string" then id = junction(p)
      elseif i == 1 or i == #road then
        id = #n.pos + 1
        n.pos[id], n.links[id] = {p[1], p[2]}, {}
      end
      pts[i] = id and n.pos[id] or p
      ids[i] = id
      if i > 1 then cum[i] = cum[i - 1] + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2) end
    end
    -- Graded heights along the whole road, evenly spaced end to end.
    local prof = road.heights and #road.heights >= 2 and {hs = road.heights, step = math.max(cum[#cum], 1e-3) / (#road.heights - 1)}
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
        n.edge_of[a .. ">" .. b], n.edge_of[b .. ">" .. a] = #n.edges + 1, #n.edges + 1
        n.edges[#n.edges + 1] = {a = a, b = b, pts = seg, kind = kind, width = width, name = label, street = road.name, bridge = road.bridge,
                                 deck = road.deck, prof = prof, s0 = cum[start], tunnel = road.tunnel, over = road.over,
                                 sidewalk = road.sidewalk}
        start = i
      end
    end
  end
  n.grid = R.index(n.edges)
  NET, wet_rows = n, nil
  return n
end

function R.net() return NET end

-- Each junction's height (the road's there), once the map is built.
function R.heights() return NET and NET.heights end

-- The height of the road from junction a to b at (x, z) on it: its deck or
-- tunnel's, not just the ground's. Nil on a flat map.
function R.height_on(a, b, x, z)
  local e = NET and NET.edges[NET.edge_of[a .. ">" .. b] or 0]
  if not (GROUND and e) then return nil end
  return (e.height or GROUND)(x, z)
end

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
-- edge it's on. Given a height y, a tunnel or a street over one on another
-- level counts as far off.
function R.nearest_edge(x, z, walkable, y)
  local best, be, bi, bx, bz = math.huge
  local ci, cj = math.floor(x / CELL), math.floor(z / CELL)
  local function try(list)
    for _, it in ipairs(list) do
      local e = NET.edges[it[1]]
      if not (walkable and e.kind == "highway") then
        local a, b = e.pts[it[2] - 1], e.pts[it[2]]
        local d, cx, cz = dist_seg(x, z, a[1], a[2], b[1], b[2])
        if y and GROUND and (e.tunnel or e.over) then -- on another level: as good as far off
          local h = (e.height or GROUND)(cx, cz)
          if math.abs(h - y) > 4 then d = d + 30 * math.abs(h - y) end
        end
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

-- Where (x, z) is, for the HUD: the street it's on (nil off the road or on
-- one without a name; a numbered road is the map's `street_names` for it,
-- or "Road 40") and the part of town,
-- the nearest of the map's named `areas` (nil if it has none).
function R.where(x, z)
  local street
  local e, _, _, _, d = R.nearest_edge(x, z)
  if e and d < NET.edges[e].width / 2 + SIDEWALK + 2 then
    street = NET.edges[e].street
    if street and street:match("^%d+$") then
      street = (NET.map.street_names or {})[street] or ("Road " .. street)
    end
  end
  local area, best = nil, math.huge
  for _, a in ipairs(NET.map.areas or {}) do
    local d2 = (a[2] - x) ^ 2 + (a[3] - z) ^ 2
    if d2 < best then area, best = a[1], d2 end
  end
  return street, area
end

-- ---- checking ------------------------------------------------------------------------

function R.check(map)
  local name = map.name or "?"
  local function fail(fmt, ...) error(string.format("map '%s': " .. fmt, name, ...), 0) end
  -- Roads may only meet at junctions (a bridge passes over, a tunnel under). Only stretches
  -- sharing a grid cell can cross.
  local E = NET.edges
  for _, list in pairs(NET.grid) do
    for p = 1, #list do
      for q = p + 1, #list do
        local ea, eb = list[p][1], list[q][1]
        local a, b = E[ea], E[eb]
        if ea ~= eb and not (a.bridge or b.bridge or a.tunnel or b.tunnel) then
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

-- `survey`: one of the surveyed buildings, which may touch each other.
local function add_circle(H, x, z, r, survey)
  H.add({x = x, z = z, r = r, survey = survey}, x - r, z - r, x + r, z + r)
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
  for _, p in ipairs(parts) do
    local g = (GROUND and not p.abs) and GROUND(p.pos[1], p.pos[3]) or 0
    p.pos, p.abs = {p.pos[1] - cx, p.pos[2] + g - y, p.pos[3] - cz}, nil
  end
  engine.mesh(name, parts)
  engine.spawn{mesh = name, pos = {cx, y, cz}, scale = 1, tag = tag or "road", abs = true}
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
  {"cemetery", {0.3, 0.44, 0.27}, 500}, {"works", {0.46, 0.45, 0.43}}, {"parking", {0.3, 0.3, 0.32}},
  {"track", {0.68, 0.33, 0.24}}, {"sand", {0.78, 0.68, 0.5}}, {"court", {0.36, 0.46, 0.6}}, {"pitch", {0.25, 0.56, 0.22}},
  {"water", WATER},
}
local LINE = {0.95, 0.95, 0.92}

-- A Finnish stone church: grey fieldstone walls, a steep black roof, and
-- red wooden boards in its gables. Unit footprint, real height.
local churches = {}
local CHURCH_ROOF = 12
local function church_mesh(h)
  local name = string.format("church_%g", h)
  if churches[name] then return name end
  local hw, R = math.min(h, 7), CHURCH_ROOF
  local parts = {{mesh = "cube", pos = {0, hw / 2, 0}, size = {1, hw, 1}, color = {0.6, 0.58, 0.55}}}
  for _, back in ipairs{-1, 1} do
    parts[#parts + 1] = {mesh = "wedge", pos = {0, hw + R / 2, 0.26 * back}, yaw = back > 0 and math.pi or 0,
                         size = {1.03, R, 0.53}, color = {0.12, 0.12, 0.13}}
    for _, e in ipairs{-1, 1} do -- the gables' red boarding
      parts[#parts + 1] = {mesh = "wedge", pos = {e * 0.518, hw + R * 0.45, 0.24 * back}, yaw = back > 0 and math.pi or 0,
                           size = {0.01, R * 0.9, 0.48}, color = {0.5, 0.2, 0.14}}
    end
  end
  for k = -2, 2 do -- small deep windows
    parts[#parts + 1] = {mesh = "cube", pos = {k * 0.17, hw * 0.6, 0}, size = {0.025, hw * 0.25, 1.01}, color = {0.15, 0.15, 0.18},
                         emissive = 1}
  end
  engine.mesh(name, parts)
  churches[name] = true
  return name
end
-- An air dome over a pitch: white fabric, a round-ended vault h meters
-- high over a w x d floor (w the long side), stacked in bands.
local function dome_mesh(w, d, h)
  local name = string.format("dome_%g_%g_%g", w, d, h)
  if churches[name] then return name end
  local parts, n = {}, 9
  for j = 0, n - 1 do
    local c = math.sqrt(1 - ((j + 0.5) / n) ^ 2)
    parts[#parts + 1] = {mesh = "cube", pos = {0, (j + 0.5) * h / n, 0}, size = {w - d * (1 - c), h / n, d * c},
                         color = {0.95, 0.95, 0.93}}
  end
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.4, 0}, size = {w - 0.2, 0.8, d + 0.3}, color = {0.4, 0.42, 0.45}}
  engine.mesh(name, parts)
  churches[name] = true
  return name
end
-- A strip along a polyline: a box per segment and a disc at each bend, so
-- curves have no gaps.
local function strip(parts, pts, width, top, color, discs, hf)
  hf = hf or GROUND
  if hf then -- on terrain: pieces at most 6 m long, each tilted to follow the ground
    for i = 2, #pts do
      local ax, az, bx, bz = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
      local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
      local n = math.max(1, math.ceil(len / 6))
      local yaw = math.atan(bx - ax, bz - az)
      for k = 0, n - 1 do
        local t0, t1 = k / n, (k + 1) / n
        local h0, h1 = hf(ax + (bx - ax) * t0, az + (bz - az) * t0), hf(ax + (bx - ax) * t1, az + (bz - az) * t1)
        local l = len / n
        parts[#parts + 1] = {mesh = "cube", pos = {ax + (bx - ax) * (t0 + t1) / 2, (h0 + h1) / 2 + top - 0.15, az + (bz - az) * (t0 + t1) / 2},
                             yaw = yaw, pitch = -math.atan(h1 - h0, l), size = {width, 0.3, l + 0.1}, color = color, abs = true}
      end
    end
    for i = discs and 1 or 2, discs and #pts or #pts - 1 do
      parts[#parts + 1] = {mesh = "cylinder", pos = {pts[i][1], hf(pts[i][1], pts[i][2]) + top - 0.15, pts[i][2]},
                           size = {width, 0.3, width}, color = color, abs = true}
    end
    return
  end
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
local function dashes(parts, pts, top, hf)
  hf = hf or GROUND
  for i = 2, #pts do
    local ax, az, bx, bz = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
    local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    local yaw = math.atan(bx - ax, bz - az)
    for s = 8, len - 8, 9 do
      local t = s / len
      local x, z = ax + (bx - ax) * t, az + (bz - az) * t
      local part = {mesh = "cube", pos = {x, top, z}, yaw = yaw, size = {0.18, 0.01, 3}, color = {0.9, 0.9, 0.86}}
      if hf then
        local d = 1.5 / len
        local h0, h1 = hf(ax + (bx - ax) * (t - d), az + (bz - az) * (t - d)), hf(ax + (bx - ax) * (t + d), az + (bz - az) * (t + d))
        part.pos[2], part.pitch, part.abs = (h0 + h1) / 2 + top, -math.atan(h1 - h0, 3), true
      end
      parts[#parts + 1] = part
    end
  end
end

-- A bridge deck's height along its edge: straight from one end's ground to
-- the other's, whatever is below; a street over a tunnel keeps its own
-- surveyed heights.
local function deck_height(e)
  local cum = {0}
  for i = 2, #e.pts do
    cum[i] = cum[i - 1] + math.sqrt((e.pts[i][1] - e.pts[i - 1][1]) ^ 2 + (e.pts[i][2] - e.pts[i - 1][2]) ^ 2)
  end
  local total = math.max(cum[#cum], 1e-3)
  local ha, hb = GROUND(e.pts[1][1], e.pts[1][2]), GROUND(e.pts[#e.pts][1], e.pts[#e.pts][2])
  local own = e.over and e.prof
  return function(x, z)
    local best, bs = math.huge, 0
    for i = 2, #e.pts do
      local d, _, _, t = dist_seg(x, z, e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2])
      if d < best then best, bs = d, cum[i - 1] + (cum[i] - cum[i - 1]) * t end
    end
    if own then
      local hs, u = own.hs, math.max(0, (e.s0 + bs) / own.step)
      local k = math.min(math.floor(u), #hs - 2)
      return hs[k + 1] + (hs[k + 2] - hs[k + 1]) * math.min(u - k, 1)
    end
    return ha + (hb - ha) * bs / total
  end
end

-- Detached houses: a painted wooden box under a gable roof, the ridge
-- running along the street. Unit footprint, real height.
local HOUSE = {{0.72, 0.2, 0.15}, {0.9, 0.78, 0.4}, {0.88, 0.88, 0.84}, {0.45, 0.55, 0.62}, {0.6, 0.38, 0.25}, {0.78, 0.7, 0.55}}
local ROOF = {{0.25, 0.22, 0.22}, {0.45, 0.18, 0.12}, {0.3, 0.32, 0.35}}
local baked = {}
local function house_mesh(v, floors, roof)
  local name = string.format("house%d_%d", v, floors) .. (roof and string.format("_%g_%g_%g", roof[1], roof[2], roof[3]) or "")
  if baked[name] then return name end
  local h, c, rc = floors * 2.9, HOUSE[v], roof or ROOF[v % #ROOF + 1]
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

-- A row house (rivitalo): one long low block under a pitched roof, a door
-- and window per home along the front. Unit footprint, real height.
local TILE = {{0.55, 0.24, 0.17}, {0.24, 0.22, 0.22}, {0.62, 0.36, 0.25}}
local function row_mesh(v, roof)
  local name = string.format("row%d_%g_%g_%g", v, roof[1], roof[2], roof[3])
  if baked[name] then return name end
  local h = 2.9
  local parts = {{mesh = "cube", size = {1, h, 1}, color = HOUSE[v]}}
  for k = 0, 9 do -- ten homes' worth of doors and windows, front and back
    local x = -0.45 + k * 0.1
    parts[#parts + 1] = {mesh = "cube", pos = {x, -h / 2 + 1.05, 0.5}, size = {0.025, 2.1, 0.02}, color = {0.95, 0.95, 0.92}}
    parts[#parts + 1] = {mesh = "cube", pos = {x + 0.04, -h / 2 + 1.6, 0}, size = {0.035, 1.0, 1.01}, color = {0.22, 0.26, 0.32},
                         emissive = (v + k) % 3 == 0 and 1 or 0}
  end
  parts[#parts + 1] = {mesh = "wedge", pos = {0, h / 2 + 0.9, -0.28}, size = {1.04, 1.8, 0.56}, color = roof}
  parts[#parts + 1] = {mesh = "wedge", pos = {0, h / 2 + 0.9, 0.28}, yaw = math.pi, size = {1.04, 1.8, 0.56}, color = roof}
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

-- ---- what's beside the roads -----------------------------------------------------------

-- Beside a road's asphalt, piece by piece and side by side, one of:
--   walk    a pavement SIDEWALK wide, a kerb up;
--   median  between the two halves of a divided road, a kerb up: paving
--           where it's narrow, grass where it's wide (`w`: its half);
--   verge   grass behind a kerb, then a foot and cycle path of its own
--           (the map's paths, drawn as they are);
--   none    the asphalt's edge, as on most suburban streets.
-- Side 1 is toward (dz, -dx) going along the road, its left on the map
-- (x east, z south); side 2 its right. A street has pavements where the
-- map data says (`sidewalk`: "left", "right", "no"; both by default).
local KERB = 0.12 -- how far a pavement or median stands above the road
local PIECE = 6
local PATH_CELL = 32

local function near_edges(x, z, r, fn)
  for ci = math.floor((x - r) / CELL), math.floor((x + r) / CELL) do
    for cj = math.floor((z - r) / CELL), math.floor((z + r) / CELL) do
      for _, it in ipairs(NET.grid[cell_key(ci, cj)] or {}) do fn(it[1], it[2]) end
    end
  end
end

-- The closest point of segment ab to (x, z): along u = (ux, uz) from it,
-- across (on r = (uz, -ux)), and how parallel ab runs to u.
local function beside(x, z, ux, uz, ax, az, bx, bz)
  local _, cx, cz = dist_seg(x, z, ax, az, bx, bz)
  local l = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
  if l < 1e-6 then return math.huge, 0, 0 end
  local along = (cx - x) * ux + (cz - z) * uz
  local across = (cx - x) * uz - (cz - z) * ux
  return along, across, math.abs(((bx - ax) * ux + (bz - az) * uz) / l)
end

local function classify(map)
  -- The map's foot and cycle paths by PATH_CELL square.
  local paths = {}
  for _, p in ipairs(map.paved or {}) do
    if p.path then
      for i = 4, #p do
        local a, b = p[i - 1], p[i]
        for ci = math.floor(math.min(a[1], b[1]) / PATH_CELL), math.floor(math.max(a[1], b[1]) / PATH_CELL) do
          for cj = math.floor(math.min(a[2], b[2]) / PATH_CELL), math.floor(math.max(a[2], b[2]) / PATH_CELL) do
            local k = cell_key(ci, cj)
            paths[k] = paths[k] or {}
            table.insert(paths[k], {a[1], a[2], b[1], b[2], p.sidewalk})
          end
        end
      end
    end
  end
  for ei, e in ipairs(NET.edges) do
    local tagged = e.kind == "highway" and "no" or (e.sidewalk or "both")
    local default = {(tagged == "both" or tagged == "left") and "walk" or "none",
                     (tagged == "both" or tagged == "right") and "walk" or "none"}
    local half = e.width / 2
    e.pieces = {}
    for i = 2, #e.pts do
      local ax, az, bx, bz = e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]
      local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
      local ux, uz = (bx - ax) / math.max(len, 1e-6), (bz - az) / math.max(len, 1e-6)
      local n = math.max(1, math.ceil(len / PIECE))
      for k = 0, n - 1 do
        local t0, t1 = k / n, (k + 1) / n
        local mx, mz = ax + (bx - ax) * (t0 + t1) / 2, az + (bz - az) * (t0 + t1) / 2
        local side = {{kind = default[1]}, {kind = default[2]}}
        if k % 2 == 1 then -- every other piece goes with the one before (half the looking)
          side = e.pieces[#e.pieces].side
        elseif not (e.deck or e.over) then
          -- A path alongside: a pavement if the map says that's what it is
          -- and it's about where one would be, else a verge before it.
          local best = {math.huge, math.huge}
          local r = half + 16
          for ci = math.floor((mx - r) / PATH_CELL), math.floor((mx + r) / PATH_CELL) do
            for cj = math.floor((mz - r) / PATH_CELL), math.floor((mz + r) / PATH_CELL) do
              for _, sg in ipairs(paths[cell_key(ci, cj)] or {}) do
                local along, across, par = math.huge, 0, 0
                if math.min(sg[1], sg[3]) <= mx + r and math.max(sg[1], sg[3]) >= mx - r and math.min(sg[2], sg[4]) <= mz + r
                   and math.max(sg[2], sg[4]) >= mz - r then
                  along, across, par = beside(mx, mz, ux, uz, sg[1], sg[2], sg[3], sg[4])
                end
                local d = math.abs(across)
                if math.abs(along) < 3 and par > 0.8 and d > half - 1 and d < half + 15 then
                  local s = across > 0 and 1 or 2
                  if d < best[s] then
                    best[s] = d
                    side[s] = {kind = (sg[5] and d < half + SIDEWALK + 1.5 and e.kind ~= "highway") and "walk" or "verge"}
                  end
                end
              end
            end
          end
          -- The other half of a divided road (or another road close
          -- alongside): a median between.
          best = {math.huge, math.huge}
          local r2 = half + 24
          near_edges(mx, mz, r2, function(oj, q)
            local o = NET.edges[oj]
            if oj == ei or o.deck or o.over or o.tunnel ~= e.tunnel then return end
            local a, b = o.pts[q - 1], o.pts[q]
            if math.min(a[1], b[1]) > mx + r2 or math.max(a[1], b[1]) < mx - r2 or math.min(a[2], b[2]) > mz + r2
               or math.max(a[2], b[2]) < mz - r2 then
              return
            end
            local along, across, par = beside(mx, mz, ux, uz, a[1], a[2], b[1], b[2])
            local gap = math.abs(across) - half - o.width / 2
            if math.abs(along) < 3 and par > 0.9 and gap > -1 and (gap < 3 or (gap < 14 and o.street and o.street == e.street)) then
              local s = across > 0 and 1 or 2
              if gap < best[s] then
                best[s] = gap
                side[s] = gap > 0.6 and {kind = "median", w = gap / 2} or {kind = "none"}
              end
            end
          end)
        end
        e.pieces[#e.pieces + 1] = {ax + (bx - ax) * t0, az + (bz - az) * t0, ax + (bx - ax) * t1, az + (bz - az) * t1, seg = i,
                                   side = side}
      end
    end
    -- A short run (two pieces or less) between two of another kind goes
    -- with them.
    for s = 1, 2 do
      local k = 2
      while k < #e.pieces do
        local before, j = e.pieces[k - 1].side[s], k
        while j <= #e.pieces and e.pieces[j].side[s].kind == e.pieces[k].side[s].kind do j = j + 1 end
        if j <= #e.pieces and j - k <= 2 and e.pieces[j].side[s].kind == before.kind and before.kind ~= e.pieces[k].side[s].kind then
          for m = k, j - 1 do e.pieces[m].side[s] = before end
        end
        k = j
      end
    end
  end
end

-- How far past the asphalt a side reaches, and whether it's a kerb up.
local function reach(sd)
  if sd.kind == "walk" then return SIDEWALK, true end
  if sd.kind == "median" then return math.min(sd.w, SIDEWALK), true end
  if sd.kind == "verge" then return 1.5, false end
  return 1, false
end

-- Where along a piece of edge ei (from a, along u, `len` long) the strip
-- `o0` to `o1` meters out on side (rx, rz) is off every other road's
-- asphalt: runs {from, to} of meters along it. Pavements stop where a
-- side street crosses them.
local function clear_runs(ei, ax, az, ux, uz, len, rx, rz, o0, o1)
  local mx, mz = ax + ux * len / 2 + rx * (o0 + o1) / 2, az + uz * len / 2 + rz * (o0 + o1) / 2
  local e, near = NET.edges[ei], {}
  local reach = len / 2 + (o1 - o0) / 2 + 1
  near_edges(mx, mz, reach + 10, function(oj, q)
    local o = NET.edges[oj]
    if oj == ei or o.deck or o.over or o.tunnel ~= e.tunnel or e.deck or e.over then return end
    local a, b, r = o.pts[q - 1], o.pts[q], o.width / 2 + reach
    if math.min(a[1], b[1]) <= mx + r and math.max(a[1], b[1]) >= mx - r and math.min(a[2], b[2]) <= mz + r
       and math.max(a[2], b[2]) >= mz - r and dist_seg(mx, mz, a[1], a[2], b[1], b[2]) < r then near[#near + 1] = {a[1], a[2], b[1], b[2], o.width / 2 + 0.2} end
  end)
  if #near == 0 then return {{0, len}} end
  local runs, from = {}, nil
  local n = math.max(1, math.ceil(len / 0.5))
  for k = 0, n do
    local t = len * k / n
    local clear = true
    for _, o in ipairs{o0 + 0.3, (o0 + o1) / 2, o1} do
      local x, z = ax + ux * t + rx * o, az + uz * t + rz * o
      for _, sg in ipairs(near) do
        if dist_seg(x, z, sg[1], sg[2], sg[3], sg[4]) < sg[5] then clear = false break end
      end
      if not clear then break end
    end
    if clear and not from then from = t end
    if not clear and from then
      if t - from > 0.4 then runs[#runs + 1] = {from, t - len / n} end
      from = nil
    end
  end
  if from and len - from > 0.4 then runs[#runs + 1] = {from, len} end
  return runs
end

local WALK, KERBSTONE, BRICK, GRASS = {0.44, 0.44, 0.43}, {0.68, 0.67, 0.64}, {0.52, 0.34, 0.29}, {0.32, 0.46, 0.24}

-- Each side of an edge as classify found it: pavements and medians a kerb
-- up, a kerbstone along the asphalt's edge, verges a kerbstone alone.
local function kerbs(parts, ei, e)
  local half = e.width / 2
  for _, pc in ipairs(e.pieces) do
    local ax, az, bx, bz = pc[1], pc[2], pc[3], pc[4]
    local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
    if len > 1e-3 then
      local ux, uz = (bx - ax) / len, (bz - az) / len
      for s = 1, 2 do
        local sd = pc.side[s]
        if sd.kind ~= "none" then
          local sign = s == 1 and 1 or -1
          local rx, rz = sign * uz, -sign * ux
          local w = sd.kind == "walk" and SIDEWALK or sd.kind == "median" and sd.w or 0
          local function at(t, o) return {ax + ux * t + rx * o, az + uz * t + rz * o} end
          for _, run in ipairs(clear_runs(ei, ax, az, ux, uz, len, rx, rz, half, half + math.max(w, 0.3))) do
            -- One height each end for the slab and its kerbstone: on a
            -- pavement the ground's (a kerb up already), on a verge the
            -- road's edge plus a kerb.
            local o = w > 0 and half + w / 2 or half + 0.1
            local p0, p1 = at(run[1], o), at(run[2], o)
            local o2 = w > 0 and half + math.min(w, SIDEWALK) / 2 or o -- within the raised part
            local g0, g1 = at(run[1], o2), at(run[2], o2)
            local h0, h1 = GROUND and GROUND(g0[1], g0[2]) or 0, GROUND and GROUND(g1[1], g1[2]) or 0
            if w == 0 or not GROUND then h0, h1 = h0 + KERB, h1 + KERB end
            local l, pitch = run[2] - run[1], -math.atan(h1 - h0, run[2] - run[1])
            local yaw = math.atan(ux, uz)
            if w > 0 then
              local color = sd.kind == "walk" and WALK or (w <= 2.5 and BRICK or GRASS)
              parts[#parts + 1] = {mesh = "cube", pos = {(p0[1] + p1[1]) / 2, (h0 + h1) / 2 + 0.08 - 0.15, (p0[2] + p1[2]) / 2}, yaw = yaw,
                                   pitch = pitch, size = {w, 0.3, l + 0.1}, color = color, abs = true}
            end
            local k0, k1 = at(run[1], half + 0.1), at(run[2], half + 0.1)
            parts[#parts + 1] = {mesh = "cube", pos = {(k0[1] + k1[1]) / 2, (h0 + h1) / 2 + 0.095 - 0.15, (k0[2] + k1[2]) / 2}, yaw = yaw,
                                 pitch = pitch, size = {0.2, 0.3, l + 0.1}, color = KERBSTONE, abs = true}
          end
        end
      end
    end
  end
end

-- The side (1 or 2) of edge e at fraction t along its bend i.
local function side_at(e, i, t, s)
  local first, n
  for k, pc in ipairs(e.pieces) do
    if pc.seg == i then
      first = first or k
      n = k - first + 1
    end
  end
  if not first then return {kind = "none"} end
  return e.pieces[first + math.min(n - 1, math.floor(t * n))].side[s]
end

-- The roads as the engine's driving surface over the terrain: their graded
-- profiles in pieces of PIECE m or less, {ax, az, ay, bx, bz, by, half width,
-- edge, asphalt half width, side 1 a kerb up?, side 2?}, level across out
-- past their pavements. Bridge decks are solid already.
local function road_surface()
  local out = {}
  for ei, e in ipairs(NET and NET.edges or {}) do
    if e.prof and not e.deck and not e.over then
      local hs, step = e.prof.hs, e.prof.step
      local function h(s)
        local u = math.max(0, s / step)
        local k = math.min(math.floor(u), #hs - 2)
        return hs[k + 1] + (hs[k + 2] - hs[k + 1]) * math.min(u - k, 1)
      end
      local s = e.s0
      for _, pc in ipairs(e.pieces) do
        local len = math.sqrt((pc[3] - pc[1]) ^ 2 + (pc[4] - pc[2]) ^ 2)
        local r1, up1 = reach(pc.side[1])
        local r2, up2 = reach(pc.side[2])
        local seg = {pc[1], pc[2], h(s), pc[3], pc[4], h(s + len), e.width / 2 + math.max(r1, r2), ei, e.width / 2,
                     up1 and 1 or 0, up2 and 1 or 0}
        table.move(seg, 1, 11, #out + 1, out)
        s = s + len
      end
    end
  end
  return out
end

local build

-- Build the map. With terrain, everything placed during the build sits on
-- the ground: engine.spawn adds the ground's height under a thing's x, z to
-- its y, unless it says abs = true (it was placed on the ground already).
function R.build(map, kit)
  GROUND, BASE = nil, nil
  local t = map.terrain
  if not t then
    classify(map)
    return build(map, kit)
  end
  local palette = {LAND}
  for _, name in ipairs(t.classes) do
    for _, c in ipairs(COVER) do if c[1] == name then palette[#palette + 1] = c[2] end end
  end
  classify(map)
  engine.terrain{x0 = t.x0, z0 = t.z0, step = t.step, w = t.w, d = t.d, heights = t.file, palette = palette,
                 roads = road_surface(), kerb = KERB}
  GROUND = function(x, z) return R.water_level(x, z) or engine.terrain_height(x, z) or 0 end
  local spawn = engine.spawn
  engine.spawn = function(e)
    if e.abs then e.abs = nil
    elseif e.pos then e.pos = {e.pos[1], e.pos[2] + (BASE or GROUND(e.pos[1], e.pos[3])), e.pos[3]} end
    return spawn(e)
  end
  local ok, L = pcall(build, map, kit)
  engine.spawn, BASE = spawn, nil
  if not ok then error(L, 0) end
  return L
end

-- The ground's height at x, z: the terrain, or water's level over it; 0 on a
-- flat map.
function R.ground(x, z) return GROUND and GROUND(x, z) or 0 end

build = function(map, kit)
  local sx, sz = map.size[1], map.size[2]
  local r = kit.rng(7, 11)
  local H = hash(40)
  local L = {map = map.id or map.name, network = true, sx = sx, sz = sz, curb = kit.CURB, walk = SIDEWALK,
             avenue = 14, street = 12, kinds = {}, landmarks = {}, labels = {}}
  -- Is (x, z) under a tunnel's roof (where nothing tall can stand on the road)?
  local function under_roof(x, z)
    for _, spec in ipairs(map.tunnels or {}) do
      local len, uv = tunnel.frame(spec)
      local u, v = uv(x, z)
      if u > -10 and u < len + 10 and math.abs(v) < spec.half + 4 then return true end
    end
    return false
  end

  -- Land (the terrain, if there is one), the sea round it, and invisible
  -- walls at the shore.
  if not GROUND then kit.static{mesh = "cube", pos = {0, -1.5, 0}, size = {sx, 3, sz}, color = LAND, tag = "ground"} end
  local W = 1500
  for _, f in ipairs{{0, -(sz + W) / 2, sx + 2 * W, W}, {0, (sz + W) / 2, sx + 2 * W, W},
                     {-(sx + W) / 2, 0, W, sz}, {(sx + W) / 2, 0, W, sz}} do
    engine.spawn{mesh = "cube", pos = {f[1], 0.04 - 0.5, f[2]}, size = {f[3], 1, f[4]}, color = WATER, tag = "water", abs = true}
  end
  for _, s in ipairs{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
    kit.static{pos = {s[1] * sx / 2, 60, s[2] * sz / 2}, size = {s[1] == 0 and sx or 1, 140, s[2] == 0 and sz or 1}, visible = false,
               tag = "wall", abs = true}
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

  local piers, rails = {}, {}
  -- Roads: pavement under, asphalt on top, a dashed center line. On
  -- terrain a bridge's deck is solid, a ramp from one end to the other,
  -- with railings and a pier under each end and in the middle.
  for ei, e in ipairs(NET.edges) do
    local parts = {}
    local walk = e.kind ~= "highway"
    local hf = GROUND and (e.deck or e.over) and deck_height(e) or nil
    e.height = hf
    if hf then
      if walk then strip(parts, e.pts, e.width + 2 * SIDEWALK, 0.05, PAVE, true, hf) end
    else
      kerbs(parts, ei, e)
    end
    strip(parts, e.pts, e.width, 0.08, ROAD, true, hf)
    dashes(parts, e.pts, 0.09, hf)
    if hf then
      local wide = e.width + (walk and 2 * SIDEWALK or 1)
      for i = 2, #e.pts do
        local ax, az, bx, bz = e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]
        local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
        local yaw = math.atan(bx - ax, bz - az)
        local rx, rz = math.cos(yaw), -math.sin(yaw)
        local n = math.max(1, math.ceil(len / 6))
        for k = 0, n - 1 do
          local t0, t1 = k / n, (k + 1) / n
          local h0, h1 = hf(ax + (bx - ax) * t0, az + (bz - az) * t0), hf(ax + (bx - ax) * t1, az + (bz - az) * t1)
          local mx, mz, mh, pitch = ax + (bx - ax) * (t0 + t1) / 2, az + (bz - az) * (t0 + t1) / 2, (h0 + h1) / 2, -math.atan(h1 - h0, len / n)
          kit.static{pos = {mx, mh - 0.5, mz}, yaw = yaw, pitch = pitch, size = {wide, 1, len / n + 0.05}, visible = false,
                     tag = "bridge", abs = true}
          parts[#parts + 1] = {mesh = "cube", pos = {mx, mh - 0.7, mz}, yaw = yaw, pitch = pitch, size = {wide, 1.2, len / n + 0.05},
                               color = {0.55, 0.55, 0.53}, abs = true}
          for _, side in ipairs(e.over and {} or {-1, 1}) do -- over a tunnel, the roof is the ground
            rails[#rails + 1] = {mx + rx * side * wide / 2, mh + 0.5, mz + rz * side * wide / 2, yaw, pitch, len / n + 0.05, ei}
          end
        end
      end
      for i = 2, #e.pts do -- where piers could go, under each bend and the middle of each stretch
        for _, f in ipairs{0, 0.5} do
          local x, z = e.pts[i - 1][1] + (e.pts[i][1] - e.pts[i - 1][1]) * f, e.pts[i - 1][2] + (e.pts[i][2] - e.pts[i - 1][2]) * f
          piers[#piers + 1] = {x, z, hf(x, z), ei}
        end
      end
    end
    bake("road" .. ei, parts, 0)
    for i = 2, #e.pts do
      add_seg(H, e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2], e.width / 2 + (walk and SIDEWALK or 1.5), ei, e.width)
    end
  end
  -- Bridge railings and piers, once every road is known: none on another
  -- road (where ramps meet, or the road a bridge spans); piers only where
  -- the deck is well above the ground.
  for _, r in ipairs(rails) do
    local x, z, ei = r[1], r[3], r[7]
    local on_road = H.near(x, z, 40, function(it)
      return it.edge and it.edge ~= ei and dist_seg(x, z, it.ax, it.az, it.bx, it.bz) < it.width / 2 + 0.5
                 and math.abs(((NET.edges[it.edge].height or GROUND)(x, z)) - r[2]) < 4
    end)
    if not on_road then
      kit.static{mesh = "cube", pos = {x, r[2], z}, yaw = r[4], pitch = r[5], size = {0.25, 1, r[6]}, color = {0.62, 0.64, 0.66},
                 tag = "wall", abs = true}
    end
  end
  for _, p in ipairs(piers) do
    local x, z, top, ei = p[1], p[2], p[3], p[4]
    local g = engine.terrain_height(x, z) or 0
    local on_road = H.near(x, z, 40, function(it)
      return it.edge and it.edge ~= ei and dist_seg(x, z, it.ax, it.az, it.bx, it.bz) < it.width / 2 + 3
    end)
    if top - g > 3 and not on_road then
      kit.static{mesh = "cube", pos = {x, (top - 1.3 + g) / 2, z}, size = {1.6, top - 1.3 - g, 1.6}, color = {0.6, 0.6, 0.58},
                 tag = "wall", abs = true}
    end
  end
  -- Street lamps along the pavement (or the verge, or the median),
  -- alternating sides, once every road is known: none on another road's
  -- asphalt.
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
          local t = s / len
          local sd = e.height and {kind = "walk"} or side_at(e, i, t, side > 0 and 1 or 2)
          local o = e.width / 2 + (sd.kind == "walk" and SIDEWALK - 0.6 or sd.kind == "median" and sd.w or sd.kind == "verge" and 1.5 or 1.2)
          o = o * side
          local lx, lz = ax + (bx - ax) * t + rx * o, az + (bz - az) * t + rz * o
          local on_road = H.near(lx, lz, 40, function(it)
            return it.edge and it.edge ~= ei and dist_seg(lx, lz, it.ax, it.az, it.bx, it.bz) < it.width / 2 + 1.5
          end)
          if not on_road and not under_roof(lx, lz) and (sd.kind ~= "median" or sd.w > 0.5) then
            kit.static{mesh = "lamp", pos = {lx, 0.05 + (e.height and e.height(lx, lz) or (GROUND and GROUND(lx, lz) or 0)), lz},
                       yaw = yaw - side * math.pi / 2, size = {0.3, 10, 0.3}, tag = "lamp", abs = true}
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
  -- On terrain the ground is colored by them already; only water is drawn,
  -- flat at its level.
  for k, c in ipairs(COVER) do
    local strips = (map.cover or {})[c[1]]
    if strips and #strips > 0 and (not GROUND or c[1] == "water") then
      local ch = chunked()
      for _, st in ipairs(strips) do
        local x, z = (st[1] + st[3]) / 2, (st[2] + st[4]) / 2
        ch.add(x, z, {mesh = "cube", pos = {x, (st[5] or 0) + k * 0.004 - 0.008, z}, size = {st[3] - st[1], 0.02, st[4] - st[2]}, color = c[2],
                      abs = GROUND and true or nil})
      end
      ch.bake("cover_" .. c[1], c[1] == "water" and "water" or "cover")
    end
  end
  -- Service roads and paved paths: drawn, not driven by the AI.
  if map.paved then
    local ch = chunked()
    -- A path is left out where it runs under a road's asphalt (the roads
    -- are a little wider than the real ones, and a path mapped along one's
    -- edge would show through it).
    local E = NET.edges
    -- The stretches of road whose asphalt could reach segment ab of a path
    -- w wide.
    local function roads_near(a, b, w)
      local out, r = {}, 10 + w / 2
      local mx, mz, l = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
      for ci = math.floor((math.min(a[1], b[1]) - r) / CELL), math.floor((math.max(a[1], b[1]) + r) / CELL) do
        for cj = math.floor((math.min(a[2], b[2]) - r) / CELL), math.floor((math.max(a[2], b[2]) + r) / CELL) do
          for _, it in ipairs(NET.grid[cell_key(ci, cj)] or {}) do
            local o, q = E[it[1]], it[2]
            if not (o.deck or o.over or o.tunnel) then
              local c, d = o.pts[q - 1], o.pts[q]
              if dist_seg(mx, mz, c[1], c[2], d[1], d[2]) < l / 2 + o.width / 2 + w / 2 then
                out[#out + 1] = {c[1], c[2], d[1], d[2], o.width / 2 + w / 2 - 0.2}
              end
            end
          end
        end
      end
      return out
    end
    for _, p in ipairs(map.paved) do
      local runs, cur, last = {}, nil, nil
      if p.path then
        for i = 4, #p do
          local a, b = p[i - 1], p[i]
          local near = roads_near(a, b, p[1])
          local n = #near == 0 and 1 or math.max(1, math.ceil(math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) / 2))
          for k = i == 4 and 0 or 1, n do
            local x, z = a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n
            local under = false
            for _, sg in ipairs(near) do
              if dist_seg(x, z, sg[1], sg[2], sg[3], sg[4]) < sg[5] then under = true break end
            end
            -- Only the path's own bends and where it goes under or comes
            -- out make points: a strip has a piece and a disc each.
            if under then
              if cur then
                if last then cur[#cur + 1] = last end
                if #cur >= 2 then runs[#runs + 1] = cur end
              end
              cur, last = nil, nil
            elseif not cur then
              cur, last = {{x, z}}, nil
            elseif k == n then
              cur[#cur + 1], last = {x, z}, nil
            else
              last = {x, z}
            end
          end
        end
        if cur and #cur >= 2 then runs[#runs + 1] = cur end
      else
        runs[1] = {}
        for i = 3, #p do runs[1][#runs[1] + 1] = p[i] end
      end
      for _, pts in ipairs(runs) do
        local parts = {}
        strip(parts, pts, p[1], p[2] and 0.047 or 0.044, p[2] and ROAD or p.stone and {0.6, 0.5, 0.45} or PATH, true)
        for _, part in ipairs(parts) do ch.add(part.pos[1], part.pos[3], part) end
      end
    end
    ch.bake("paved", "cover")
  end

  -- Football pitches: white lines, and goals you can hit.
  local lines = chunked()
  for _, p in ipairs(map.pitches or {}) do
    local px, pz, len, wid, yaw = p[1], p[2], p[3], p[4], p[5]
    local ux, uz, vx, vz = math.cos(yaw), -math.sin(yaw), math.sin(yaw), math.cos(yaw)
    local function at(u, v) return px + ux * u + vx * v, pz + uz * u + vz * v end
    local function line(u0, v0, u1, v1)
      local x0, z0 = at(u0, v0)
      local x1, z1 = at(u1, v1)
      local l = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
      lines.add((x0 + x1) / 2, (z0 + z1) / 2, {mesh = "cube", pos = {(x0 + x1) / 2, 0.05, (z0 + z1) / 2}, yaw = math.atan(x1 - x0, z1 - z0),
                                                size = {0.14, 0.01, l}, color = LINE})
    end
    local L, W = len / 2 - 1.5, wid / 2 - 1.5
    line(-L, -W, L, -W); line(-L, W, L, W); line(-L, -W, -L, W); line(L, -W, L, W); line(0, -W, 0, W)
    local cr = math.min(9.15, W * 0.35)
    for k = 0, 15 do
      local a0, a1 = k / 16 * 2 * math.pi, (k + 1) / 16 * 2 * math.pi
      line(cr * math.cos(a0), cr * math.sin(a0), cr * math.cos(a1), cr * math.sin(a1))
    end
    local bd, bw = math.min(16.5, L * 0.3), math.min(20, W * 0.6)
    for _, e in ipairs{-1, 1} do
      line(e * L, -bw, e * (L - bd), -bw); line(e * L, bw, e * (L - bd), bw); line(e * (L - bd), -bw, e * (L - bd), bw)
      local gw = math.min(3.66, W * 0.15)
      for _, side in ipairs{-1, 1} do
        local x, z = at(e * (L + 0.3), side * gw)
        kit.static{mesh = "cube", pos = {x, 1.22, z}, size = {0.15, 2.44, 0.15}, color = LINE, tag = "goal"}
      end
      local x, z = at(e * (L + 0.3), 0)
      kit.static{mesh = "cube", pos = {x, 2.4, z}, yaw = yaw, size = {0.15, 0.15, 2 * gw + 0.15}, color = LINE, tag = "goal"}
    end
  end
  -- Running tracks placed by hand: a 400 m oval, red, round a grass infield.
  for _, t in ipairs(map.tracks or {}) do
    local tx, tz, yaw = t[1], t[2], t[3]
    local ux, uz, vx, vz = math.cos(yaw), -math.sin(yaw), math.sin(yaw), math.cos(yaw)
    local STRAIGHT, R, LANES = 84.4, 41.3, 9.8 -- R: middle of the lanes
    local pts = {}
    for _, e in ipairs{1, -1} do -- each bend: the half circle round one end
      for k = 0, 16 do
        local a = (k / 16 - 0.5) * math.pi
        local u, v = e * (STRAIGHT / 2 + R * math.cos(a)), e * R * math.sin(a)
        pts[#pts + 1] = {tx + ux * u + vx * v, tz + uz * u + vz * v}
      end
    end
    pts[#pts + 1] = pts[1]
    local parts = {}
    strip(parts, pts, LANES, 0.047, {0.7, 0.32, 0.24}, true)
    for _, part in ipairs(parts) do lines.add(part.pos[1], part.pos[3], part) end
    lines.add(tx, tz, {mesh = "cube", pos = {tx, 0.04, tz}, yaw = yaw, size = {STRAIGHT, 0.02, 2 * R - LANES}, color = {0.25, 0.56, 0.22}})
    for _, e in ipairs{1, -1} do -- grass in the bends too
      for k = 1, 6 do
        local a = k / 7 * math.pi / 2
        local w = 2 * (R - LANES / 2) * math.cos(a - math.pi / 14)
        local u = e * (STRAIGHT / 2 + (R - LANES / 2) * math.sin(a))
        lines.add(tx + ux * u, tz + uz * u, {mesh = "cube", pos = {tx + ux * u, 0.04, tz + uz * u}, yaw = yaw,
                                            size = {(R - LANES / 2) / 6, 0.02, w}, color = {0.25, 0.56, 0.22}})
      end
    end
    add_circle(H, tx, tz, STRAIGHT / 2 + R + LANES / 2)
  end
  lines.bake("lines", "cover")

  -- Foot and cycle bridges over roads: a deck high enough to drive under,
  -- ramping down to the paths at its ends (unless an end is `up`: it meets
  -- a raised deck there); solid where it's up. `concrete` ones have the
  -- 1970s' solid parapets.
  local TOP = 5.6
  for _, b in ipairs(map.footbridges or {}) do
    local width, pts = b[1], {}
    for i = 2, #b do pts[#pts + 1] = b[i] end
    local total = 0
    for i = 2, #pts do total = total + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2) end
    local up = b.up or {}
    local function height(sv)
      local a, z = up[1] and math.huge or sv, up[2] and math.huge or total - sv
      return math.min(TOP, math.min(a, z) * 0.35) + 0.2
    end
    local sv = 0
    for i = 2, #pts do
      local ax, az, bx, bz = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
      local seg = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
      local n = math.max(1, math.ceil(seg / 4))
      local yaw = math.atan(bx - ax, bz - az)
      local rx, rz = math.cos(yaw), -math.sin(yaw)
      for k = 0, n - 1 do
        local t0, t1 = k / n, (k + 1) / n
        local h0, h1 = height(sv + seg * t0), height(sv + seg * t1)
        local x, z = ax + (bx - ax) * (t0 + t1) / 2, az + (bz - az) * (t0 + t1) / 2
        local l, pitch = seg / n, -math.atan(h1 - h0, seg / n)
        local high = math.min(h0, h1) >= TOP
        local deck = {mesh = "cube", pos = {x, (h0 + h1) / 2, z}, yaw = yaw, pitch = pitch, size = {width, 0.4, l * 1.02},
                      color = {0.62, 0.62, 0.6}, tag = "bridge"}
        if high then kit.static(deck) else engine.spawn(deck) end
        for _, side in ipairs{-1, 1} do
          if b.concrete then
            kit.static{mesh = "cube", pos = {x + rx * side * (width / 2 - 0.1), (h0 + h1) / 2 + 0.35, z + rz * side * (width / 2 - 0.1)},
                       yaw = yaw, pitch = pitch, size = {0.25, 1.3, l * 1.02}, color = {0.72, 0.71, 0.68}, tag = "wall"}
          else
            engine.spawn{mesh = "cube", pos = {x + rx * side * width / 2, (h0 + h1) / 2 + 0.6, z + rz * side * width / 2}, yaw = yaw,
                         pitch = pitch, size = {0.1, 1.0, l * 1.02}, color = {0.35, 0.4, 0.45}}
          end
        end
        -- Pillars off the asphalt, every few pieces.
        if k % 3 == 1 and (h0 + h1) / 2 > 2.5 then
          local ei, _, _, _, d = R.nearest_edge(x, z)
          if not ei or d > NET.edges[ei].width / 2 + 1.5 then
            kit.static{mesh = "cylinder", pos = {x, (h0 + h1) / 4, z}, size = {0.7, (h0 + h1) / 2, 0.7}, color = {0.6, 0.6, 0.58}, tag = "bridge"}
          end
        end
      end
      sv = sv + seg
    end
  end

  -- Raised decks for walking, at a footbridge's height, the 1970s way:
  -- {x0, z0, x1, z1, open = "nswe" sides without a parapet}, a slab on
  -- round columns. Paved squares: {x0, z0, x1, z1}. Market stalls:
  -- {x, z, columns, rows}, white awnings over tables.
  for _, dk in ipairs(map.decks or {}) do
    local x0, z0, x1, z1 = dk[1], dk[2], dk[3], dk[4]
    local nx, nz = math.max(1, math.ceil((x1 - x0) / 7)), math.max(1, math.ceil((z1 - z0) / 7))
    local px, pz = (x1 - x0) / nx, (z1 - z0) / nz
    for i = 0, nx - 1 do
      for j = 0, nz - 1 do
        local cx, cz = x0 + px * (i + 0.5), z0 + pz * (j + 0.5)
        kit.static{mesh = "cube", pos = {cx, TOP + 0.2, cz}, size = {px + 0.05, 0.4, pz + 0.05}, color = {0.66, 0.65, 0.62}, tag = "bridge"}
        if (i + j) % 2 == 0 then
          kit.static{mesh = "cylinder", pos = {cx, TOP / 2, cz}, size = {0.8, TOP, 0.8}, color = {0.7, 0.69, 0.66}, tag = "bridge"}
        end
      end
    end
    -- Parapets round the edges (but the `open` ones), in pieces, with a gap
    -- wherever a footbridge comes up onto the deck or another deck joins.
    local function landing(x, z)
      for _, b in ipairs(map.footbridges or {}) do
        local up = b.up or {}
        if (up[1] and (b[2][1] - x) ^ 2 + (b[2][2] - z) ^ 2 < 16) or (up[2] and (b[#b][1] - x) ^ 2 + (b[#b][2] - z) ^ 2 < 16) then
          return true
        end
      end
    end
    local open = dk.open or ""
    local sides = {n = {x0, z0, x1, z0}, s = {x0, z1, x1, z1}, w = {x0, z0, x0, z1}, e = {x1, z0, x1, z1}}
    for name, sd in pairs(sides) do
      if not open:find(name) then
        local len = math.sqrt((sd[3] - sd[1]) ^ 2 + (sd[4] - sd[2]) ^ 2)
        local n = math.max(1, math.ceil(len / 3.5))
        for k = 0, n - 1 do
          local f = (k + 0.5) / n
          local x, z = sd[1] + (sd[3] - sd[1]) * f, sd[2] + (sd[4] - sd[2]) * f
          local joined = false -- where another deck carries on
          for _, o in ipairs(map.decks) do
            if o ~= dk and x > o[1] - 0.5 and x < o[3] + 0.5 and z > o[2] - 0.5 and z < o[4] + 0.5 then joined = true end
          end
          if not landing(x, z) and not joined then
            kit.static{mesh = "cube", pos = {x, TOP + 0.85, z}, yaw = math.atan(sd[3] - sd[1], sd[4] - sd[2]), size = {0.25, 1.3, len / n + 0.02},
                       color = {0.72, 0.71, 0.68}, tag = "wall"}
          end
        end
      end
    end
  end
  for _, sq in ipairs(map.squares or {}) do
    engine.spawn{mesh = "cube", pos = {(sq[1] + sq[3]) / 2, 0.03, (sq[2] + sq[4]) / 2}, size = {sq[3] - sq[1], 0.06, sq[4] - sq[2]},
                 color = {0.66, 0.64, 0.6}, tag = "plaza"}
  end
  for _, mk in ipairs(map.market or {}) do
    for i = 0, mk[3] - 1 do
      for j = 0, mk[4] - 1 do
        local x, z = mk[1] + (i - (mk[3] - 1) / 2) * 7, mk[2] + (j - (mk[4] - 1) / 2) * 8
        kit.static{mesh = "cube", pos = {x, 0.45, z}, size = {3.6, 0.9, 1.6}, color = {0.55, 0.42, 0.3}, tag = "stall"}
        engine.spawn{mesh = "cube", pos = {x, 2.3, z}, size = {4.2, 0.12, 3.2}, color = {0.95, 0.95, 0.93}}
        for _, c in ipairs{{-1, -1}, {1, -1}, {-1, 1}, {1, 1}} do
          engine.spawn{mesh = "cube", pos = {x + c[1] * 2, 1.15, z + c[2] * 1.5}, size = {0.08, 2.3, 0.08}, color = {0.8, 0.8, 0.8}}
        end
      end
    end
  end

  -- Roofs you can park on (and drive up to): ramps first, so nothing is
  -- built where they land.
  for _, rp in ipairs(map.roof_parking or {}) do
    for _, rm in ipairs(rp.ramps or {}) do
      local incline = 0.2
      local len = (rp.height + kit.CURB) / math.sin(incline)
      local fx, fz = math.sin(rm[3]), math.cos(rm[3])
      kit.ramp(rm[1], rm[2], rm[3], 9, len, incline)
      for t = -len / 2, len / 2, 8 do add_circle(H, rm[1] + fx * t, rm[2] + fz * t, 7) end
    end
  end
  local function roof_parked(x, z)
    for _, rp in ipairs(map.roof_parking or {}) do
      if (x - rp.x) ^ 2 + (z - rp.z) ^ 2 < rp.r * rp.r then return rp end
    end
  end

  -- Towers and masts: steel lattice, a sign pylon (Mylly's), or a brick
  -- chimney narrowing as it climbs.
  for _, t in ipairs(map.towers or {}) do
    local tx, tz, th, kind = t[1], t[2], t[3], t[4]
    if kind == "chimney" then
      local y, base = 0, math.max(4, th / 12)
      for _, s in ipairs{{1, 0.4}, {0.85, 0.35}, {0.72, 0.25}} do
        local sh = th * s[2]
        engine.spawn{mesh = "cylinder", pos = {tx, y + sh / 2, tz}, size = {base * s[1], sh, base * s[1]}, color = {0.5, 0.24, 0.17}}
        y = y + sh
      end
      engine.spawn{mesh = "cylinder", pos = {tx, th - 1, tz}, size = {base * 0.76, 2, base * 0.76}, color = {0.2, 0.18, 0.17}}
      kit.static{pos = {tx, th / 2, tz}, size = {base * 0.8, th, base * 0.8}, visible = false, tag = "landmark"}
    elseif kind == "pylon" then
      kit.static{mesh = "cube", pos = {tx, th / 2, tz}, size = {4, th, 4}, color = {0.13, 0.13, 0.14}, tag = "landmark"}
      engine.spawn{mesh = "cube", pos = {tx, th - 6, tz}, size = {4.2, 10, 4.2}, color = {0.86, 0.3, 0.2}}
      engine.spawn{mesh = "cube", pos = {tx, th - 16, tz}, size = {4.3, 5, 4.3}, color = {0.95, 0.95, 0.95}, glow = 0.6}
    else
      local base = math.max(2, th / 12)
      for k = 0, 3 do -- four legs leaning in
        local a = k * math.pi / 2 + math.pi / 4
        local lx, lz = math.cos(a) * base * 0.7, math.sin(a) * base * 0.7
        engine.spawn{mesh = "cube", pos = {tx + lx * 0.6, th / 2, tz + lz * 0.6}, size = {0.25, th, 0.25}, color = {0.62, 0.63, 0.65}}
      end
      for y = 4, th - 2, 4 do
        local wd = base * 1.2 * (1 - y / th * 0.6)
        engine.spawn{mesh = "cube", pos = {tx, y, tz}, size = {wd, 0.12, wd}, color = {0.62, 0.63, 0.65}}
      end
      kit.static{pos = {tx, th / 2, tz}, size = {base, th, base}, visible = false, tag = "landmark"}
      engine.spawn{mesh = "cube", pos = {tx, th + 1.5, tz}, size = {0.6, 3, 0.6}, color = {0.85, 0.85, 0.85}}
    end
  end

  -- Strings of lanterns across a street: poles down both sides, wires
  -- zigzagging between them. {x0, z0, x1, z1, half width}; one mesh each.
  for k, sl in ipairs(map.string_lights or {}) do
    local x0, z0, x1, z1, hw = sl[1], sl[2], sl[3], sl[4], sl[5]
    local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
    local ux, uz = (x1 - x0) / len, (z1 - z0) / len
    local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
    local parts, POLE, WIRE = {}, {0.22, 0.22, 0.26}, 9
    local function at(t, side) return ux * t - uz * side * hw, uz * t + ux * side * hw end
    local function wire(ax, az, bx, bz)
      local l = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
      parts[#parts + 1] = {mesh = "cube", pos = {(ax + bx) / 2, WIRE, (az + bz) / 2}, yaw = math.atan(bx - ax, bz - az),
                           size = {0.04, 0.04, l}, color = POLE}
      for s = 2, l - 2, 3 do
        local f = s / l
        parts[#parts + 1] = {mesh = "cube", pos = {ax + (bx - ax) * f, WIRE - 0.45, az + (bz - az) * f}, size = {0.02, 0.5, 0.02},
                             color = POLE}
        parts[#parts + 1] = {mesh = "cylinder", pos = {ax + (bx - ax) * f, WIRE - 0.85, az + (bz - az) * f}, size = {0.26, 0.4, 0.26},
                             color = {0.3, 0.28, 0.25}, emissive = 0.5}
      end
    end
    local GAP = 18
    for t = -len / 2, len / 2 + 0.1, GAP do
      for _, side in ipairs{-1, 1} do
        local px, pz = at(t, side)
        parts[#parts + 1] = {mesh = "cube", pos = {px, WIRE / 2 + 0.5, pz}, size = {0.3, WIRE + 1, 0.3}, color = POLE}
      end
      local ax, az = at(t, -1)
      local bx, bz = at(t, 1)
      wire(ax, az, bx, bz)
      if t + GAP <= len / 2 + 0.1 then -- and an X to the next pair
        local cx, cz = at(t + GAP, 1)
        local dx, dz = at(t + GAP, -1)
        wire(ax, az, cx, cz)
        wire(bx, bz, dx, dz)
        wire(ax, az, dx, dz) -- and along each side
        wire(bx, bz, cx, cz)
      end
    end
    engine.mesh("string_lights_" .. k, parts)
    engine.spawn{mesh = "string_lights_" .. k, pos = {mx, 0, mz}}
  end

  -- Gantry cranes over a shipyard's dock, and a cruise ship building under them.
  for _, cr in ipairs(map.cranes or {}) do
    local cx, cz, len, span, yaw, n = cr[1], cr[2], cr[3], cr[4], cr[5], cr[6]
    local ux, uz, vx, vz = math.cos(yaw), -math.sin(yaw), math.sin(yaw), math.cos(yaw)
    local H, BLUE = 78, {0.16, 0.26, 0.62}
    for k = 1, n do
      local t = (k / (n + 1) - 0.5) * len * 0.8
      local gx, gz = cx + ux * t, cz + uz * t
      for _, side in ipairs{-1, 1} do
        local lx, lz = gx + vx * side * span / 2, gz + vz * side * span / 2
        kit.static{mesh = "cube", pos = {lx, H / 2, lz}, yaw = yaw, size = {14, H, 3}, color = BLUE, tag = "landmark"}
      end
      engine.spawn{mesh = "cube", pos = {gx, H + 4, gz}, yaw = yaw, size = {9, 8, span + 8}, color = BLUE}
      engine.spawn{mesh = "cube", pos = {gx, H + 4, gz}, yaw = yaw, size = {9.2, 1.8, span + 6}, color = {0.95, 0.95, 0.95}}
      engine.spawn{mesh = "cube", pos = {gx + vx * span * 0.15, H - 2, gz + vz * span * 0.15}, yaw = yaw, size = {11, 5, 9},
                   color = {0.9, 0.75, 0.15}}
    end
    -- The ship: blue hull, white decks stacked high, a funnel aft.
    local sl, sb = math.min(300, len * 0.6), 42
    kit.static{mesh = "cube", pos = {cx, 7, cz}, yaw = yaw, size = {sl, 14, sb}, color = {0.12, 0.3, 0.7}, tag = "landmark"}
    engine.spawn{mesh = "cube", pos = {cx, 2, cz}, yaw = yaw, size = {sl + 0.2, 4, sb + 0.2}, color = {0.5, 0.15, 0.12}}
    kit.static{mesh = "cube", pos = {cx - ux * 8, 32, cz - uz * 8}, yaw = yaw, size = {sl * 0.85, 36, sb - 2}, color = {0.94, 0.94, 0.92},
               tag = "landmark"}
    for y = 18, 46, 3.5 do -- rows of balconies
      engine.spawn{mesh = "cube", pos = {cx - ux * 8, y, cz - uz * 8}, yaw = yaw, size = {sl * 0.85 + 0.2, 0.8, sb - 1.6},
                   color = {0.3, 0.38, 0.48}}
    end
    local fx, fz = cx - ux * sl * 0.33, cz - uz * sl * 0.33
    engine.spawn{mesh = "cube", pos = {fx, 56, fz}, yaw = yaw, size = {14, 14, 8}, color = {0.85, 0.15, 0.12}}
    engine.spawn{mesh = "cube", pos = {fx, 60, fz}, yaw = yaw, size = {14.2, 3, 8.2}, color = {0.1, 0.25, 0.65}}
  end

  -- Piers: wooden decks you can walk, boats moored along them.
  local boats = chunked()
  for pi, p in ipairs(map.piers or {}) do
    local width = p[1]
    for i = 3, #p do
      local ax, az, bx, bz = p[i - 1][1], p[i - 1][2], p[i][1], p[i][2]
      local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
      if len > 0.5 then
        local yaw = math.atan(bx - ax, bz - az)
        local rx, rz, fx, fz = math.cos(yaw), -math.sin(yaw), (bx - ax) / len, (bz - az) / len
        kit.static{mesh = "cube", pos = {(ax + bx) / 2, 0.35, (az + bz) / 2}, yaw = yaw, size = {width, 0.5, len + 0.5},
                   color = {0.55, 0.5, 0.42}, tag = "pier"}
        if width < 4 then
          for t = 3, len - 2, 4.2 do
            for _, side in ipairs{-1, 1} do
              if r() < 0.7 then
                local bx2, bz2 = ax + fx * t + rx * side * (width / 2 + 4), az + fz * t + rz * side * (width / 2 + 4)
                local by = yaw + math.pi / 2
                boats.add(bx2, bz2, {mesh = "cube", pos = {bx2, 0.6, bz2}, yaw = by, size = {2.6, 1.3, 7}, color = {0.95, 0.95, 0.94}})
                boats.add(bx2, bz2, {mesh = "cube", pos = {bx2, 1.6, bz2}, yaw = by, size = {1.8, 0.9, 2.8}, color = {0.75, 0.78, 0.82}})
                if r() < 0.4 then
                  boats.add(bx2, bz2, {mesh = "cylinder", pos = {bx2, 6.5, bz2}, size = {0.15, 11, 0.15}, color = {0.9, 0.9, 0.9}})
                end
              end
            end
          end
        end
      end
    end
  end
  boats.bake("boats", "cover")

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

  -- Surveyed buildings, each a box (or a few), clear of what's placed. The
  -- map's `looks` restyle the ones near a spot as the real building.
  local function look_of(x, z)
    for _, l in ipairs(map.looks or {}) do
      if (x - l[1]) ^ 2 + (z - l[2]) ^ 2 < l[3] ^ 2 then return l[4] end
    end
  end
  local count, yards = 0, {}
  for i, f in ipairs(map.footprints or {}) do
    local x, z, w, d, yaw, h, kind = f[1], f[2], f[3], f[4], f[5], f[6], f[7]
    local fx, fz = math.cos(yaw), -math.sin(yaw)
    if GROUND then -- on a slope it stands on its lowest corner
      BASE = math.huge
      for _, c in ipairs{{1, 1}, {1, -1}, {-1, 1}, {-1, -1}} do
        local cx, cz = x + fx * c[1] * w / 2 - fz * c[2] * d / 2, z + fz * c[1] * w / 2 + fx * c[2] * d / 2
        BASE = math.min(BASE, engine.terrain_height(cx, cz) or 0)
      end
    end
    local circles = box_circles(x, z, fx, fz, w, d)
    local ok = true
    for _, c in ipairs(circles) do
      ok = ok and not H.near(c[1], c[2], c[3] + 40, function(it)
        return not it.seg and not it.survey and (c[1] - it.x) ^ 2 + (c[2] - it.z) ^ 2 < (c[3] + it.r) ^ 2 and it.r > 8
      end)
    end
    local rp = (kind == "shop" or kind == "works") and roof_parked(x, z)
    local look = ok and look_of(x, z)
    if ok and kind == "round" then -- a silo or a tank: a drum with a darker cap
      local rh, color = look and look.height or h, look and look.color or {0.8, 0.8, 0.78}
      kit.static{mesh = "cylinder", pos = {x, rh / 2, z}, size = {w, rh, w}, color = color, tag = "building"}
      engine.spawn{mesh = "cylinder", pos = {x, rh + 0.3, z}, size = {w * 0.9, 0.6, w * 0.9},
                   color = {color[1] * 0.7, color[2] * 0.7, color[3] * 0.7}}
      for _, c in ipairs(circles) do add_circle(H, c[1], c[2], c[3], true) end
      count = count + 1
    elseif look and look.dome then
      if d > w then w, d, yaw = d, w, yaw + math.pi / 2 end
      engine.spawn{mesh = dome_mesh(w, d, look.dome), pos = {x, 0, z}, yaw = yaw}
      kit.static{pos = {x, look.dome * 0.35, z}, yaw = yaw, size = {w - d * 0.3, look.dome * 0.7, d * 0.8}, visible = false,
                 tag = "building"}
      for _, c in ipairs(circles) do add_circle(H, c[1], c[2], c[3], true) end
      count = count + 1
    elseif look then
      local style, floors = look.style or "brick", look.floors or math.max(1, math.floor(h / kit.FLOOR + 0.5))
      kit.static{mesh = kit.building_mesh(style, floors), pos = {x, kit.CURB + floors * kit.FLOOR / 2, z}, yaw = yaw,
                 size = {w, floors * kit.FLOOR, d}, scale = {w, 1, d}, color = look.color, tag = "building"}
      for _, c in ipairs(circles) do add_circle(H, c[1], c[2], c[3], true) end
      count = count + 1
    elseif ok and rp then
      -- A flat roof at the deck's height, asphalt on top with bays marked.
      local h2 = rp.height
      kit.static{mesh = "cube", pos = {x, h2 / 2, z}, yaw = yaw, size = {w, h2, d}, color = {0.78, 0.74, 0.66}, tag = "building"}
      engine.spawn{mesh = "cube", pos = {x, h2 + 0.05, z}, yaw = yaw, size = {w - 0.2, 0.06, d - 0.2}, color = {0.3, 0.3, 0.32}}
      local ux, uz, vx, vz = math.cos(yaw), -math.sin(yaw), math.sin(yaw), math.cos(yaw)
      for u = -w / 2 + 3, w / 2 - 3, 2.6 do
        for _, v in ipairs{-d / 4, d / 4} do
          engine.spawn{mesh = "cube", pos = {x + ux * u + vx * v, h2 + 0.09, z + uz * u + vz * v}, yaw = yaw,
                       size = {0.1, 0.01, d / 2 - 8}, color = LINE}
        end
      end
      -- The facade: a black band under the roof, a red stripe through it.
      engine.spawn{mesh = "cube", pos = {x, h2 - 1.4, z}, yaw = yaw, size = {w + 0.2, 2.6, d + 0.2}, color = {0.14, 0.14, 0.15}}
      engine.spawn{mesh = "cube", pos = {x, h2 - 1.7, z}, yaw = yaw, size = {w + 0.25, 0.8, d + 0.25}, color = {0.86, 0.3, 0.2}}
      for _, side in ipairs{-1, 1} do -- a low wall round the edge
        kit.static{mesh = "cube", pos = {x + vx * side * d / 2, h2 + 0.5, z + vz * side * d / 2}, yaw = yaw, size = {w, 1, 0.3},
                   color = {0.7, 0.68, 0.62}, tag = "wall"}
      end
      for _, c in ipairs(circles) do add_circle(H, c[1], c[2], c[3], true) end
      count = count + 1
    elseif ok and kind == "church" then
      local main = f[8] and f[8]:lower():find("kirkko")
      local hw = math.min(h, 7)
      -- The mapped outline takes in vestries and porches; the nave under
      -- the roof is narrower.
      d = math.min(d, 15)
      engine.spawn{mesh = church_mesh(h), pos = {x, 0, z}, yaw = yaw, scale = {w, 1, d}}
      kit.static{pos = {x, hw / 2, z}, yaw = yaw, size = {w, hw, d}, visible = false, tag = "building"}
      if main then -- a small red bell turret on the ridge at the west gable, a cross on top
        local ux, uz = math.cos(yaw), -math.sin(yaw)
        local e = ux > 0 and -1 or 1
        local tx, tz = x + ux * e * (w / 2 - 2), z + uz * e * (w / 2 - 2)
        local top = hw + CHURCH_ROOF
        engine.spawn{mesh = "cube", pos = {tx, top + 0.5, tz}, yaw = yaw, size = {2.6, 3.4, 2.6}, color = {0.52, 0.2, 0.14}}
        for _, turn in ipairs{0, math.pi / 2} do
          for _, back in ipairs{-1, 1} do
            local a = yaw + turn
            engine.spawn{mesh = "wedge", pos = {tx + math.sin(a) * 0.75 * back, top + 3.4, tz + math.cos(a) * 0.75 * back},
                         yaw = a + (back > 0 and math.pi or 0), size = {3, 2.6, 1.5}, color = {0.12, 0.12, 0.13}}
          end
        end
        engine.spawn{mesh = "cube", pos = {tx, top + 5.6, tz}, size = {0.15, 1.8, 0.15}, color = {0.3, 0.3, 0.3}}
        engine.spawn{mesh = "cube", pos = {tx, top + 5.9, tz}, yaw = yaw, size = {0.9, 0.15, 0.15}, color = {0.3, 0.3, 0.3}}
      end
      for _, c in ipairs(circles) do add_circle(H, c[1], c[2], c[3], true) end
      count = count + 1
    elseif ok then
      if kind == "terrace" or (kind == "house" and w > 2.4 * d and w > 25) then
        kit.static{mesh = row_mesh(1 + i % #HOUSE, f[9] or TILE[1 + i % #TILE]), pos = {x, 1.45, z}, yaw = yaw,
                   size = {w, 2.9, d}, scale = {w, 1, d}, tag = "building"}
      elseif kind == "house" then
        local floors = h < 4.5 and 1 or 2
        kit.static{mesh = house_mesh(1 + i % #HOUSE, floors, f[9]), pos = {x, floors * 1.45, z}, yaw = yaw,
                   size = {w, floors * 2.9, d}, scale = {w, 1, d}, tag = "building"}
      elseif kind == "police" then -- red brick, and a wing of glass
        local floors = math.max(3, math.floor(h / kit.FLOOR + 0.5))
        local glass = i % 2 == 0
        kit.static{mesh = kit.building_mesh(glass and "glass" or "brick", floors), pos = {x, kit.CURB + floors * kit.FLOOR / 2, z},
                   yaw = yaw, size = {w, floors * kit.FLOOR, d}, scale = {w, 1, d}, color = glass and {0.8, 0.9, 0.92} or {0.66, 0.32, 0.24},
                   tag = "building"}
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
      for _, c in ipairs(circles) do add_circle(H, c[1], c[2], c[3], true) end
      count = count + 1
      if kind == "house" or kind == "terrace" then yards[#yards + 1] = {x, z, w, d, yaw} end
    end
  end
  BASE = nil
  -- A tree or two in the yards round homes, once every building stands.
  pine_mesh()
  local planted = 0
  for _, y in ipairs(yards) do
    for _ = 1, r() < 0.5 and 2 or 1 do
      local a = r() * 2 * math.pi
      local reach = math.max(y[3], y[4]) / 2 + 3 + r() * 5
      local tx, tz = y[1] + math.cos(a) * reach, y[2] + math.sin(a) * reach
      if free(H, tx, tz, 2) then
        kit.static{mesh = r() < 0.6 and "pine" or "tree", pos = {tx, 0, tz}, size = {0.5, 6, 0.5}, scale = 0.7 + r() * 0.6, tag = "tree"}
        add_circle(H, tx, tz, 1.5)
        planted = planted + 1
      end
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
  -- Which pavements are clear, worked out now rather than when the first
  -- pedestrian asks (half a second on a big town).
  for ei, e in ipairs(NET.edges) do
    if e.kind ~= "highway" then R.pavement(ei, 1); R.pavement(ei, -1) end
  end
  -- Each junction's height, on its road (a tunnel's, a deck's), for
  -- telling levels apart.
  if GROUND then
    NET.heights = {}
    for _, e in ipairs(NET.edges) do
      local f = e.height or GROUND
      NET.heights[e.a] = NET.heights[e.a] or f(e.pts[1][1], e.pts[1][2])
      NET.heights[e.b] = NET.heights[e.b] or f(e.pts[#e.pts][1], e.pts[#e.pts][2])
    end
  end

  -- Tunnels (lib/tunnel.lua): over the covered stretch a concrete roof at
  -- the ground's old height with a park on it, lights along its underside,
  -- and walls down both sides of the open ramps at its ends.
  for ti, spec in ipairs(map.tunnels or {}) do
    local len = tunnel.frame(spec)
    local ax, az = spec.from[1], spec.from[2]
    local ux, uz = (spec.to[1] - ax) / len, (spec.to[2] - az) / len
    local yaw = math.atan(ux, uz)
    local rx, rz = math.cos(yaw), -math.sin(yaw)
    local W, ramp = 2 * spec.half + 4, spec.ramp or 100
    local function floor(u) return engine.terrain_height(ax + ux * u, az + uz * u) or 0 end
    local function top(u) return floor(u) + tunnel.dip(spec, len, u) end
    local parts = {}
    local n = math.ceil(len / 10)
    for k = 0, n - 1 do
      local u0, u1 = len * k / n, len * (k + 1) / n
      local h0, h1 = top(u0), top(u1)
      local mx, mz, mh, l = ax + ux * (u0 + u1) / 2, az + uz * (u0 + u1) / 2, (h0 + h1) / 2, u1 - u0
      local pitch = -math.atan(h1 - h0, l)
      kit.static{mesh = "cube", pos = {mx, mh - 0.65, mz}, yaw = yaw, pitch = pitch, size = {W, 1.3, l + 0.05},
                 color = {0.6, 0.6, 0.58}, tag = "roof", abs = true}
      parts[#parts + 1] = {mesh = "cube", pos = {mx, mh + 0.02, mz}, yaw = yaw, pitch = pitch, size = {W - 1, 0.06, l + 0.05},
                           color = {0.32, 0.5, 0.26}, abs = true}
      parts[#parts + 1] = {mesh = "cube", pos = {mx, mh + 0.04, mz}, yaw = yaw, pitch = pitch, size = {3, 0.06, l + 0.05},
                           color = {0.72, 0.68, 0.6}, abs = true}
      for _, v in ipairs{-spec.half / 2, spec.half / 2} do
        parts[#parts + 1] = {mesh = "cube", pos = {mx + rx * v, mh - 1.35, mz + rz * v}, yaw = yaw, pitch = pitch, size = {0.5, 0.1, 3},
                             color = {1, 0.97, 0.88}, emissive = 1, abs = true}
      end
      -- The park: trees down both sides, clear of the streets crossing it.
      for _, v in ipairs{-spec.half + 2, spec.half - 2} do
        local tx, tz = mx + rx * v, mz + rz * v
        local on_road = H.near(tx, tz, 40, function(it)
          return it.edge and not NET.edges[it.edge].tunnel and dist_seg(tx, tz, it.ax, it.az, it.bx, it.bz) < it.width / 2 + 4
        end)
        if k % 2 == 0 and not on_road then
          kit.static{mesh = r() < 0.5 and "pine" or "tree", pos = {tx, mh, tz}, size = {0.5, 6, 0.5}, scale = 0.7 + r() * 0.5,
                     tag = "tree", abs = true}
        end
      end
    end
    -- Down the open ramps, a wall along the outer edge of each carriageway
    -- (none between them).
    local _, uv = tunnel.frame(spec)
    for ei, e in ipairs(NET.edges) do
      if e.tunnel then
        local off = e.width / 2 + (e.kind ~= "highway" and SIDEWALK or 1) + 0.6
        for i = 2, #e.pts do
          local px, pz, qx, qz = e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]
          local l = math.sqrt((qx - px) ^ 2 + (qz - pz) ^ 2)
          local wy = math.atan(qx - px, qz - pz)
          local wx, wz = math.cos(wy), -math.sin(wy)
          local n = math.max(1, math.ceil(l / 8))
          for k = 0, n - 1 do
            local f = (k + 0.5) / n
            local cx, cz = px + (qx - px) * f, pz + (qz - pz) * f
            local u = uv(cx, cz)
            local d = tunnel.dip(spec, len, u)
            if (u < 0 or u > len) and u > -ramp and u < len + ramp and d > 0.3 then
              local g = engine.terrain_height(cx, cz) or 0
              for _, side in ipairs{-1, 1} do
                local x, z = cx + wx * side * off, cz + wz * side * off
                local inside = H.near(x, z, 40, function(it)
                  return it.edge and it.edge ~= ei and dist_seg(x, z, it.ax, it.az, it.bx, it.bz) < it.width / 2 + 2
                end)
                if not inside then
                  kit.static{mesh = "cube", pos = {x, g + (d + 1.1) / 2, z}, yaw = wy, size = {0.5, d + 1.1, l / n + 0.3},
                             color = {0.62, 0.62, 0.6}, tag = "wall", abs = true}
                end
              end
            end
          end
        end
      end
    end
    bake("tunnel" .. ti, parts, 0, "roof")
  end

  return L
end

-- Pickup spots: {kind, x, z} straight from the map.
function R.pickup_spots(map)
  local out = {}
  for _, s in ipairs(map.pickups or {}) do out[#out + 1] = {s[1], s[2], s[3]} end
  return out
end

-- Is (x, z) on the map's water (its surveyed cover), and not on a bridge?
-- Rows of water spans, ROW meters tall like the importer's strips.
local ROW = 4
local function water_rows()
  local water = NET and (NET.map.cover or {}).water
  if not water then return nil end
  if not wet_rows then
    wet_rows = {}
    for _, st in ipairs(water) do
      for j = math.floor(st[2] / ROW + 0.5), math.floor(st[4] / ROW + 0.5) - 1 do
        wet_rows[j] = wet_rows[j] or {}
        table.insert(wet_rows[j], st)
      end
    end
  end
  return wet_rows
end

-- The level of the surveyed water at (x, z), on a map with terrain (whose
-- water strips carry it); nil on land.
function R.water_level(x, z)
  for _, st in ipairs((water_rows() or {})[math.floor(z / ROW)] or {}) do
    if st[5] and x >= st[1] and x <= st[3] then return st[5] end
  end
end

function R.wet(x, z)
  local rows = water_rows()
  if not rows then return false end
  for _, st in ipairs(rows[math.floor(z / ROW)] or {}) do
    if x >= st[1] and x <= st[3] then
      for _, p in ipairs(NET.map.piers or {}) do -- out on a pier is dry
        for i = 3, #p do
          if dist_seg(x, z, p[i - 1][1], p[i - 1][2], p[i][1], p[i][2]) < p[1] / 2 + 0.5 then return false end
        end
      end
      local e, _, _, _, d = R.nearest_edge(x, z)
      return not (e and d < NET.edges[e].width / 2 + 1)
    end
  end
  return false
end

-- Is the pavement on side `side` of edge e (+1: right of its first bend
-- toward its last) clear to walk? Not where it lies on another road's
-- asphalt, as between the two halves of a divided road. The ends, where
-- every pavement crosses the side street, don't count.
function R.pavement(e, side)
  NET.pave = NET.pave or {}
  local key = e * 2 + (side > 0 and 1 or 0)
  if NET.pave[key] == nil then
    local E, ed = NET.edges, NET.edges[e]
    local n, bad = 0, 0
    for i = 2, #ed.pts do
      local a, b = ed.pts[i - 1], ed.pts[i]
      local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
      if len > 0 then
        local fx, fz = (b[1] - a[1]) / len, (b[2] - a[2]) / len
        local o = (ed.width / 2 + SIDEWALK / 2) * side
        local from, to = i == 2 and math.min(15, len / 2) or 2, i == #ed.pts and math.max(len - 15, len / 2) or len - 2
        for t = from, to, 4 do
          local x, z = a[1] + fx * t + fz * o, a[2] + fz * t - fx * o
          local oe, _, _, _, d = R.nearest_edge(x, z)
          n = n + 1
          if oe ~= e and d < E[oe].width / 2 then bad = bad + 1 end
        end
      end
    end
    NET.pave[key] = n == 0 or bad <= n * 0.2
  end
  return NET.pave[key]
end

-- Pavement for pedestrians: the edges they can walk (not highways, and with
-- a clear pavement on at least one side).
function R.walkable(e)
  return NET.edges[e].kind ~= "highway" and (R.pavement(e, 1) or R.pavement(e, -1))
end
R.SIDEWALK = SIDEWALK

return R
