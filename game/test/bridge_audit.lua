-- Bridge audit: every bridge deck on the map, measured. Length, end and
-- top heights, room over the water and over any road or railway under it
-- (to the slab's underside, 1.3 m below the deck), and how sharply the road
-- turns on it and where it meets the streets at its ends. Prints one line
-- per bridge; BRIDGE_AUDIT=1.
local roadnet = require "lib.roadnet"
local city = require "lib.city"

local CELL, UNDER, BUS = 64, 1.3, 3.2
local function dist_seg(px, pz, ax, az, bx, bz)
  local dx, dz = bx - ax, bz - az
  local l2 = dx * dx + dz * dz
  local t = l2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (pz - az) * dz) / l2)) or 0
  return math.sqrt((px - ax - t * dx) ^ 2 + (pz - az - t * dz) ^ 2)
end
local function heading(a, b) return math.atan(b[2] - a[2], b[1] - a[1]) end
local function turn(h1, h2)
  local d = math.abs(h2 - h1) % (2 * math.pi)
  return math.deg(math.min(d, 2 * math.pi - d))
end

-- How high road o is where it meets junction id: its graded profile if
-- the importer gave it one (what is drawn and driven), else its deck or the
-- ground.
local function surface(o, id)
  local x, z = city.pos(id)
  if o.height then return o.height(x, z) end
  if o.prof then
    local len = 0
    for i = 2, #o.pts do len = len + math.sqrt((o.pts[i][1] - o.pts[i - 1][1]) ^ 2 + (o.pts[i][2] - o.pts[i - 1][2]) ^ 2) end
    local hs, u = o.prof.hs, (o.s0 + (id == o.a and 0 or len)) / o.prof.step
    local k = math.max(0, math.min(math.floor(u), #hs - 2))
    return hs[k + 1] + (hs[k + 2] - hs[k + 1]) * math.max(0, math.min(u - k, 1))
  end
  return roadnet.ground(x, z)
end

-- Road o's graded height at (x, z) on it.
local function surface_at(o, x, z)
  if not o.prof then return roadnet.ground(x, z) end
  local best, bs, s = math.huge, 0, 0
  for i = 2, #o.pts do
    local l = math.sqrt((o.pts[i][1] - o.pts[i - 1][1]) ^ 2 + (o.pts[i][2] - o.pts[i - 1][2]) ^ 2)
    local d = dist_seg(x, z, o.pts[i - 1][1], o.pts[i - 1][2], o.pts[i][1], o.pts[i][2])
    if d < best then
      local dx, dz = o.pts[i][1] - o.pts[i - 1][1], o.pts[i][2] - o.pts[i - 1][2]
      local t = l > 0 and math.max(0, math.min(1, ((x - o.pts[i - 1][1]) * dx + (z - o.pts[i - 1][2]) * dz) / (l * l))) or 0
      best, bs = d, s + l * t
    end
    s = s + l
  end
  local hs, u = o.prof.hs, math.max(0, (o.s0 + bs) / o.prof.step)
  local k = math.min(math.floor(u), #hs - 2)
  return hs[k + 1] + (hs[k + 2] - hs[k + 1]) * math.min(u - k, 1)
end

engine.on("init", function()
  local NET = roadnet.net()
  local G = roadnet.ground
  local rails = city.map().railways or {}
  local rows, seen = {}, {}
  for ei, e in ipairs(NET.edges) do
    if e.deck and e.height and not seen[e] then
      seen[e] = true
      local pts, len = e.pts, 0
      for i = 2, #pts do len = len + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2) end
      local top, water_room, road_room, road_under, rail_room = -math.huge, math.huge, math.huge, nil, math.huge
      local bend, checked, blocked, blocked_on = 0, 0, 0, nil
      for i = 3, #pts do bend = math.max(bend, turn(heading(pts[i - 2], pts[i - 1]), heading(pts[i - 1], pts[i]))) end
      for i = 2, #pts do
        local ax, az, bx, bz = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
        local n = math.max(1, math.ceil(math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2) / 2))
        for k = 0, n do
          local x, z = ax + (bx - ax) * k / n, az + (bz - az) * k / n
          local h = e.height(x, z)
          top = math.max(top, h)
          local w = roadnet.water_level(x, z)
          if w then water_room = math.min(water_room, h - UNDER - w) end
          -- Roads under: other edges that aren't decks, within their half width.
          local ci, cj = math.floor(x / CELL), math.floor(z / CELL)
          for _, it in ipairs(NET.grid[ci * 100003 + cj] or {}) do
            local o = NET.edges[it[1]]
            if o ~= e and not (o.deck or o.over or o.tunnel) and o.a ~= e.a and o.a ~= e.b and o.b ~= e.a and o.b ~= e.b then
              local a, b = o.pts[it[2] - 1], o.pts[it[2]]
              if dist_seg(x, z, a[1], a[2], b[1], b[2]) < o.width / 2 then
                local low = surface_at(o, x, z)
                local room = h - UNDER - low
                -- Would a bus (3.2 m) driving here touch the deck's collider?
                if room > -0.5 then
                  checked = checked + 1
                  local id = engine.raycast(x, low + 0.2, z, 0, 1, 0, BUS - 0.2 + 0.1)
                  if id and engine.tag(id) == "bridge" then
                    blocked = blocked + 1; blocked_on = o.street or o.name
                    if os.getenv("BRIDGE_DEBUG") == (e.street or e.name) then
                      print(string.format("  blocked at %.0f, %.0f: deck %.1f, %s %.1f (junctions %s-%s; bridge %s-%s)",
                        x, z, h, o.street or o.name, low, o.a, o.b, e.a, e.b))
                    end
                  end
                end
                if room > -0.5 and room < road_room then road_room, road_under = room, o.street or o.name end
              end
            end
          end
          for _, r in ipairs(rails) do
            for q = 4, #r do
              if dist_seg(x, z, r[q - 1][1], r[q - 1][2], r[q][1], r[q][2]) < 2 then
                rail_room = math.min(rail_room, h - UNDER - G(x, z))
              end
            end
          end
        end
      end
      -- At each end: the smallest turn onto any road going on (a straight
      -- run on is ~0; a road that only goes on by a hairpin is a hook).
      local hooks = {}
      for side, id in ipairs{e.a, e.b} do
        local into = side == 1 and heading(pts[2], pts[1]) or heading(pts[#pts - 1], pts[#pts])
        local best = 180
        for _, nb in ipairs(city.links(id) or {}) do
          local p = city.path(id, nb)
          if not ((side == 1 and nb == e.b) or (side == 2 and nb == e.a)) and #p >= 2 then
            best = math.min(best, turn(into, heading(p[1], p[2])))
          end
        end
        hooks[side] = best
      end
      -- The step at each end: the deck's height there against the roads
      -- that meet it (on the ground: the ground's; another deck: its own).
      local step = 0
      for side, id in ipairs{e.a, e.b} do
        local jx, jz = city.pos(id)
        local own = e.height(jx, jz)
        local function check(nb)
          local o = NET.edges[NET.edge_of[id .. ">" .. nb] or NET.edge_of[nb .. ">" .. id] or 0]
          if o and o ~= e and not o.tunnel then
            local d = math.abs(own - surface(o, id))
            if d > step then step = d end
          end
        end
        for _, nb in ipairs(city.links(id) or {}) do check(nb) end
        for _, nb in ipairs(city.links_in(id) or {}) do check(nb) end
      end
      rows[#rows + 1] = string.format(
        "BRIDGE %-28s %4.0f m  ends %5.1f/%5.1f top %5.1f  water %s  road %s  rail %s  bend %3.0f  ends turn %3.0f/%3.0f  step %4.1f  bus %s%s",
        (e.street or e.name):sub(1, 28), len, G(pts[1][1], pts[1][2]), G(pts[#pts][1], pts[#pts][2]), top,
        water_room < math.huge and string.format("%4.1f", water_room) or "   -",
        road_room < math.huge and string.format("%4.1f (%s)", road_room, road_under) or "   -",
        rail_room < math.huge and string.format("%4.1f", rail_room) or "   -",
        bend, hooks[1], hooks[2], step,
        checked == 0 and "-" or blocked == 0 and string.format("fits (%d spots)", checked)
          or string.format("BLOCKED %d/%d (%s)", blocked, checked, blocked_on), e.oneway and "  oneway" or "")
    end
  end
  table.sort(rows)
  for _, r in ipairs(rows) do print(r) end
  local nblocked = 0
  for _, r in ipairs(rows) do if r:find("BLOCKED", 1, true) then nblocked = nblocked + 1 end end
  print(string.format("BRIDGE_AUDIT: %d bridge stretches, %d with a road under that a bus can't pass", #rows, nblocked))
end)
