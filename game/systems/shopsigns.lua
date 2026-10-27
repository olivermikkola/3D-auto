-- Shop signs: a lettered plate over the door of every shop, café, pub and
-- pharmacy the map knows (OpenStreetMap shop=* and amenity=*, lib/pois),
-- on the wall of its building that faces the street. They say what the
-- place is, in Finnish (PARTURI, KAHVILA, APTEEKKI...), not the real
-- business's name; the one chain that gets its parody brand is the
-- burger one.
--
-- Put up once the world has had its first physics step, so rays can find
-- the walls: from the nearest street toward the place, the first building
-- wall that faces back is where the sign goes, snapped onto the drawn
-- outline when the building is one (its collision boxes sit inside it).
-- Baked into one mesh a chunk of the map at a time; lit at night. None on
-- the lowest quality.
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local pois = require "lib.pois"
local quality = require "lib.quality"

local S = {list = {}, ids = {}, why = {}} -- list: {x, z, y, yaw, word}; ids: the baked chunks

local LETTER = 0.34  -- letter height
local PLATE_H = 0.6
local PLATE_D = 0.1
local OVER = 3.2     -- the plate's middle, over the ground: between the shop's windows and the first floor's
local BAND = 4.3     -- where a big shop's sign band is (render.rs facade 5)
local REACH = 45     -- how far from its street a place may be
local APART = 5      -- signs at least this far from each other
local CHUNK = 200

-- What the sign says, and its colours.
local FOOD = {bg = {0.72, 0.1, 0.08}, fg = {1, 0.95, 0.75}}
local CAFE = {bg = {0.32, 0.2, 0.13}, fg = {1, 0.88, 0.6}}
local PUB = {bg = {0.08, 0.24, 0.16}, fg = {0.95, 0.8, 0.4}}
local NIGHT = {bg = {0.12, 0.08, 0.2}, fg = {1, 0.4, 0.8}}
local GREEN = {bg = {0.1, 0.5, 0.25}, fg = {1, 1, 1}}
local BLUE = {bg = {0.08, 0.2, 0.5}, fg = {1, 1, 1}}
local SHOP = {bg = {0.15, 0.15, 0.17}, fg = {1, 1, 1}}
local LIGHT = {bg = {0.92, 0.9, 0.86}, fg = {0.15, 0.15, 0.17}}
local PINK = {bg = {0.62, 0.22, 0.42}, fg = {1, 1, 1}}
local MARKET = {bg = {0.95, 0.5, 0.08}, fg = {1, 1, 1}}

S.SHOPS = {
  hairdresser = {"PARTURI", PINK}, beauty = {"KAUNEUS", PINK}, cosmetics = {"KOSMETIIKKA", PINK},
  massage = {"HIERONTA", LIGHT}, clothes = {"VAATTEET", SHOP}, shoes = {"KENGÄT", SHOP},
  convenience = {"LÄHIKAUPPA", MARKET}, supermarket = {"MARKET", MARKET}, kiosk = {"KIOSKI", MARKET},
  optician = {"OPTIKKO", LIGHT}, florist = {"KUKKA", GREEN}, second_hand = {"KIRPPIS", LIGHT},
  bicycle = {"PYÖRÄT", BLUE}, jewelry = {"KULTA", SHOP}, bakery = {"LEIPOMO", CAFE},
  hardware = {"RAUTA", BLUE}, books = {"KIRJAT", LIGHT}, pet = {"LEMMIKKI", GREEN},
  sports = {"URHEILU", BLUE}, gift = {"LAHJAT", PINK}, mobile_phone = {"PUHELIMET", BLUE},
  computer = {"TIETOKONE", BLUE}, antiques = {"ANTIIKKI", LIGHT}, furniture = {"HUONEKALU", LIGHT},
  interior_decoration = {"SISUSTUS", LIGHT}, car_repair = {"KORJAAMO", SHOP}, laundry = {"PESULA", BLUE},
  tattoo = {"TATUOINTI", NIGHT},
}
S.AMENITIES = {
  restaurant = {"RAVINTOLA", FOOD}, cafe = {"KAHVILA", CAFE}, pub = {"PUB", PUB}, bar = {"BAARI", PUB},
  nightclub = {"YÖKERHO", NIGHT}, pharmacy = {"APTEEKKI", GREEN}, bank = {"PANKKI", BLUE},
}

-- The sign for a place's tags, if it gets one: word, colours.
function S.word(tags)
  local cuisine = tags.cuisine or ""
  if tags.amenity == "fast_food" then
    if (tags.brand or tags.name or ""):lower():find("hesburger", 1, true) then return "HÄSBURGER", FOOD end
    if cuisine:find("kebab", 1, true) then return "KEBAB", FOOD end
    if cuisine:find("pizza", 1, true) then return "PIZZERIA", FOOD end
    if cuisine:find("burger", 1, true) then return "BURGERI", FOOD end
    if cuisine:find("sushi", 1, true) then return "SUSHI", FOOD end
    return "GRILLI", FOOD
  end
  if tags.amenity == "restaurant" then
    if cuisine:find("pizza", 1, true) then return "PIZZERIA", FOOD end
    if cuisine:find("sushi", 1, true) then return "SUSHI", FOOD end
  end
  local s = (tags.shop and S.SHOPS[tags.shop]) or (tags.amenity and S.AMENITIES[tags.amenity])
  if s then return s[1], s[2] end
end

-- The plate and its letters, from the wall point (x, y, z) facing (nx, nz).
local function parts(list, x, y, z, nx, nz, word, look)
  local yaw = math.atan(nx, nz)
  local w = (utf8.len(word) * 6 - 1) * LETTER / 7 + 0.5
  local px, pz = x + nx * PLATE_D / 2, z + nz * PLATE_D / 2
  list[#list + 1] = {mesh = "cube", pos = {px, y, pz}, yaw = yaw, size = {w, PLATE_H, PLATE_D}, color = look.bg, emissive = 0.35}
  local tx, tz = x + nx * (PLATE_D + 0.012), z + nz * (PLATE_D + 0.012)
  list[#list + 1] = {text = word, height = LETTER, depth = 0.025, pos = {tx, y - LETTER / 2, tz}, yaw = yaw,
                     color = look.fg, emissive = 0.8}
  return w
end

-- The drawn outlines, gridded, to snap a hit onto.
local GRID = 50
local function footprint_grid()
  local grid = {}
  for _, f in ipairs(roadnet.footprints and roadnet.footprints() or {}) do
    local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(f.pts) do
      x0, z0, x1, z1 = math.min(x0, p[1]), math.min(z0, p[2]), math.max(x1, p[1]), math.max(z1, p[2])
    end
    for i = math.floor((x0 - 3) / GRID), math.floor((x1 + 3) / GRID) do
      for j = math.floor((z0 - 3) / GRID), math.floor((z1 + 3) / GRID) do
        local k = i .. "," .. j
        grid[k] = grid[k] or {}
        table.insert(grid[k], f)
      end
    end
  end
  return grid
end

local function area(pts)
  local a, j = 0, #pts
  for k = 1, #pts do
    a = a + (pts[j][1] + pts[k][1]) * (pts[j][2] - pts[k][2])
    j = k
  end
  return math.abs(a) / 2
end

local function inside(pts, x, z)
  local yes, j = false, #pts
  for k = 1, #pts do
    local a, b = pts[k], pts[j]
    if (a[2] > z) ~= (b[2] > z) and x < (b[1] - a[1]) * (z - a[2]) / (b[2] - a[2]) + a[1] then yes = not yes end
    j = k
  end
  return yes
end

-- The outline walls within `within` of (x, z), nearest first: the point
-- on each, its outward normal, how much wall there is either side of the
-- point, and the outline.
local function walls(grid, x, z, within)
  local out = {}
  for _, f in ipairs(grid[math.floor(x / GRID) .. "," .. math.floor(z / GRID)] or {}) do
    local pts = f.pts
    local j = #pts
    for k = 1, #pts do
      local a, b = pts[j], pts[k]
      local ex, ez = b[1] - a[1], b[2] - a[2]
      local len = math.sqrt(ex * ex + ez * ez)
      if len > 0.5 then
        local t = math.max(0, math.min(len, ((x - a[1]) * ex + (z - a[2]) * ez) / len))
        local qx, qz = a[1] + ex / len * t, a[2] + ez / len * t
        local d = U.dist2d(qx, qz, x, z)
        if d < within then
          -- Outward: away from the inside.
          local nx, nz = ez / len, -ex / len
          if inside(pts, qx + nx * 0.2, qz + nz * 0.2) then nx, nz = -nx, -nz end
          out[#out + 1] = {x = qx, z = qz, nx = nx, nz = nz, left = t, right = len - t, f = f, d = d}
        end
      end
      j = k
    end
  end
  table.sort(out, function(p, q) return p.d < q.d end)
  return out
end

local function fits(w) return w.left >= 1.2 and w.right >= 1.2 and w.f.h >= OVER + 1.2 end
local function over(f)
  return (f.kind == "shop" and f.h < 16 and area(f.pts) > 1500) and BAND or OVER
end

-- The sign's height on outline wall w: over the building's foot, or over
-- the ground in front where that's higher (on a slope).
local function height(w)
  return math.max(w.f.base or -math.huge, U.ground(w.x + w.nx * 0.6, w.z + w.nz * 0.6)) + over(w.f)
end

local KEEP = {building = true}
-- The first building wall from (x, y, z) along (dx, dz), within reach: its
-- id, distance, point and normal.
local function wall_ray(x, y, z, dx, dz, reach)
  local hit, dist, hx, _, hz, nx, _, nz = engine.raycast(x, y, z, dx, 0, dz, reach)
  for _ = 1, 6 do
    if not hit or KEEP[engine.tag(hit)] then break end
    local o = dist + 0.05
    local d2
    hit, d2, hx, _, hz, nx, _, nz = engine.raycast(x + dx * o, y, z + dz * o, dx, 0, dz, reach - o, hit)
    dist = hit and o + d2
  end
  if hit and KEEP[engine.tag(hit)] then return hit, dist, hx, hz, nx, nz end
end

-- Off any street (a pedestrian one, a square): the wall of the place's own
-- outline nearest it with open ground in front, where the door would be.
local function by_outline(grid, p)
  local n = 0
  for _, w in ipairs(walls(grid, p.x, p.z, 6)) do
    if fits(w) and (w.d < 0.01 or inside(w.f.pts, p.x, p.z) or w.d < 3) then
      local y = height(w)
      if not wall_ray(w.x + w.nx * 0.15, y, w.z + w.nz * 0.15, w.nx, w.nz, 8)
         and not roadnet.on_carriageway(w.x + w.nx * 0.5, w.z + w.nz * 0.5, 0.3) then
        return w.x, w.z, y, w.nx, w.nz, true
      end
      n = n + 1
      if n == 4 then break end
    end
  end
  if n > 0 then return nil, "no open wall" end
  -- Not in a drawn outline: the nearest wall round about that faces it.
  local y = U.ground(p.x, p.z) + OVER
  local best
  for k = 0, 7 do
    local a = k * math.pi / 4
    local dx, dz = math.sin(a), math.cos(a)
    local hit, dist, hx, hz, nx, nz = wall_ray(p.x, y, p.z, dx, dz, 25)
    if hit and (not best or dist < best[1]) and nx * -dx + nz * -dz > 0.7 then best = {dist, hx, hz, nx, nz} end
  end
  if not best then return nil, "no wall about" end
  local _, hx, hz, nx, nz = table.unpack(best)
  local w = walls(grid, hx, hz, 2.5)[1] -- a drawn building further off: onto its wall
  if w then
    if not fits(w) then return nil, "small wall" end
    hx, hz, nx, nz, y = w.x, w.z, w.nx, w.nz, height(w)
  end
  if wall_ray(hx + nx * 0.15, y, hz + nz * 0.15, nx, nz, 6) or roadnet.on_carriageway(hx + nx * 0.5, hz + nz * 0.5, 0.3) then
    return nil, "no open wall"
  end
  return hx, hz, w and y or U.ground(hx + nx * 0.6, hz + nz * 0.6) + OVER, nx, nz, w ~= nil
end

-- Where p's sign goes: x, z, height, the wall's normal, whether that's a
-- drawn outline's wall; or nil and why not.
local function site(grid, p)
  local ei, _, cx, cz, d = roadnet.nearest_edge(p.x, p.z, true)
  local e = ei and roadnet.net().edges[ei]
  if not e or d > REACH then return by_outline(grid, p) end
  if e.tunnel or e.height then return nil, "bridge" end
  if d < 1 then return nil, "on the street" end
  local dx, dz = (p.x - cx) / d, (p.z - cz) / d
  local hit, _, hx, hz, nx, nz = wall_ray(cx, U.ground(cx, cz) + OVER + 0.4, cz, dx, dz, d + 12)
  if not hit then return by_outline(grid, p) end
  local w = walls(grid, hx, hz, 2.5)[1]
  if w then
    if not fits(w) then return nil, "small wall" end
    hx, hz, nx, nz = w.x, w.z, w.nx, w.nz
  end
  local l = math.sqrt(nx * nx + nz * nz)
  if l < 0.5 then return nil, "no wall" end
  nx, nz = nx / l, nz / l
  if nx * -dx + nz * -dz < 0.35 then return nil, "wall turned away" end
  if roadnet.on_carriageway(hx + nx * 0.5, hz + nz * 0.5, 0.3) then return nil, "road" end
  if w then return hx, hz, height(w), nx, nz, true end
  return hx, hz, U.ground(hx + nx * 0.6, hz + nz * 0.6) + OVER, nx, nz
end

function S.build()
  S.pending = city.network() ~= nil and quality.tier() > 1
end

local function take_down()
  for _, id in ipairs(S.ids) do
    if engine.exists(id) then engine.despawn(id) end
  end
  S.ids, S.list, S.job, S.why = {}, {}, nil, {}
end
quality.watch(function(tier)
  if tier == 1 then take_down(); S.pending = false
  elseif #S.ids == 0 and city.network() and S.pending == false then S.pending = true end
end)

-- The places to sign, a chunk of the map at a time, the player's first.
local function start()
  local chunks, keys = {}, {}
  for _, p in ipairs(pois.find{road = false}) do
    local word, look = S.word(p.tags)
    if word then
      local k = math.floor(p.x / CHUNK) .. "," .. math.floor(p.z / CHUNK)
      if not chunks[k] then
        chunks[k] = {key = k, x = (math.floor(p.x / CHUNK) + 0.5) * CHUNK, z = (math.floor(p.z / CHUNK) + 0.5) * CHUNK}
        keys[#keys + 1] = chunks[k]
      end
      table.insert(chunks[k], {p = p, word = word, look = look})
    end
  end
  local px, _, pz = U.player_pos()
  for _, c in ipairs(keys) do
    c.d = U.dist2d(c.x, c.z, px, pz)
    table.sort(c, function(a, b) return a.p.x < b.p.x or (a.p.x == b.p.x and a.p.z < b.p.z) end)
  end
  table.sort(keys, function(a, b) return a.d < b.d or (a.d == b.d and a.key < b.key) end)
  return {chunks = keys, ci = 1, i = 1, parts = {}, grid = footprint_grid(), near = {}, places = 0, ms = 0}
end

local function place(job, q)
  local x, z, y, nx, nz, outline = site(job.grid, q.p)
  if not x then S.why[z] = (S.why[z] or 0) + 1 return end
  local ci, cj = math.floor(x / APART), math.floor(z / APART)
  for i = ci - 1, ci + 1 do
    for j = cj - 1, cj + 1 do
      for _, o in ipairs(job.near[i .. "," .. j] or {}) do
        if U.dist2d(o.x, o.z, x, z) < APART then S.why.crowded = (S.why.crowded or 0) + 1 return end
      end
    end
  end
  local s = {x = x, z = z, y = y, yaw = math.atan(nx, nz), word = q.word, name = q.p.name, outline = outline}
  S.list[#S.list + 1] = s
  local k = ci .. "," .. cj
  job.near[k] = job.near[k] or {}
  table.insert(job.near[k], s)
  parts(job.parts, x, y, z, nx, nz, q.word, q.look)
end

-- Up to n more places; true when they're all done. Each chunk's signs are
-- baked into one mesh as soon as it's through.
local PER_TICK = 12
local function step(job, n)
  local t0 = os.clock()
  while n > 0 and job.ci <= #job.chunks do
    local c = job.chunks[job.ci]
    if job.i <= #c then
      place(job, c[job.i])
      job.i, job.places, n = job.i + 1, job.places + 1, n - 1
    end
    if job.i > #c then
      if #job.parts > 0 then
        engine.mesh("shopsigns" .. c.key, job.parts)
        S.ids[#S.ids + 1] = engine.spawn{mesh = "shopsigns" .. c.key, pos = {0, 0, 0}, tag = "sign"}
      end
      job.ci, job.i, job.parts = job.ci + 1, 1, {}
    end
  end
  job.ms = job.ms + (os.clock() - t0) * 1000
  return job.ci > #job.chunks
end

engine.on("tick", function()
  if not S.pending or engine.ticks() <= 1 then return end
  S.job = S.job or start()
  if step(S.job, PER_TICK) then
    local why = {}
    for k, n in pairs(S.why) do why[#why + 1] = k .. " " .. n end
    table.sort(why)
    print(string.format("shop signs: %d for %d places, %d chunks, %.0f ms over %d ticks (none: %s)", #S.list, S.job.places,
                        #S.ids, S.job.ms, math.ceil(S.job.places / PER_TICK), table.concat(why, ", ")))
    S.job, S.pending = nil, false
  end
end)

return S
