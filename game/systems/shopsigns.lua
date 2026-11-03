-- Shop signs: a lettered plate over the door of every shop, café, pub and
-- pharmacy the map knows (OpenStreetMap shop=* and amenity=*, lib/pois),
-- on the wall of its building that faces the street. A shop's says what the
-- place is, in Finnish (PARTURI, KAHVILA, APTEEKKI...); the one chain that
-- gets its parody brand is the burger one. A place the town knows by its own
-- name has that up instead (S.name): its bars, pubs, restaurants and cafés
-- that aren't a chain's, its schools, theatres, museums and hotels, and the
-- places known beyond their street (a Wikidata entry in the map).
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

local S = {list = {}, ids = {}, why = {}, missed = {}} -- list: {x, z, y, yaw, word}; ids: the baked chunks

local LETTER = 0.42  -- letter height
local PLATE_H = 0.72
local PLATE_D = 0.1
local OVER = 3.55    -- the plate's middle, over the ground: above the shop windows (render.rs: to 3.15 m), below the first floor's
local ON_BOX = 3.15  -- on a box building: under its floor's band (lib/city building_mesh, 3.6 m up)
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
-- Places that go by their own name: the tag's value, and the sign's look.
local SCHOOL = {bg = {0.9, 0.9, 0.86}, fg = {0.1, 0.2, 0.45}}
local KNOWN = {bg = {0.1, 0.1, 0.12}, fg = {0.95, 0.78, 0.35}}
S.NAMED = {
  amenity = {bar = PUB, pub = PUB, nightclub = NIGHT, restaurant = FOOD, cafe = CAFE, school = SCHOOL,
             college = SCHOOL, university = SCHOOL, music_school = SCHOOL, library = SCHOOL, theatre = KNOWN,
             cinema = KNOWN, arts_centre = KNOWN, concert_hall = KNOWN},
  tourism = {museum = KNOWN, gallery = KNOWN, hotel = BLUE},
}
-- Known beyond their street: these get their name too (not a statue or a
-- park: there's no wall of its own to put it on).
S.KNOWN = {
  amenity = {courthouse = KNOWN, townhall = KNOWN, hospital = GREEN, fire_station = FOOD, marketplace = MARKET},
  shop = {mall = KNOWN, department_store = KNOWN},
  leisure = {sports_centre = BLUE, stadium = BLUE, ice_rink = BLUE, sports_hall = BLUE, swimming_pool = BLUE},
}
local LINE = 22 -- letters a line, two lines at most
-- Letters the sign's font has (ASCII and ä, ö, å; lower case is drawn as
-- upper): the rest of a name's, as near as they come, or dropped.
local NEAR = {["é"] = "e", ["É"] = "E", ["è"] = "e", ["ü"] = "u", ["Ü"] = "U", ["á"] = "a", ["ø"] = "ö",
              ["’"] = "'", ["‘"] = "'", ["´"] = "'", ["–"] = "-", ["—"] = "-", ["“"] = '"', ["”"] = '"'}
local KEEP_LETTER = {["ä"] = true, ["Ä"] = true, ["ö"] = true, ["Ö"] = true, ["å"] = true, ["Å"] = true}

-- A name as the sign's lines (one or two), or nil when it won't fit.
function S.lines(name)
  name = name:gsub("[\xC2-\xF4][\x80-\xBF]+", function(c) return KEEP_LETTER[c] and c or NEAR[c] or "" end)
  name = name:gsub("%s+", " "):match("^%s*(.-)%s*$")
  if name == "" then return nil end
  if utf8.len(name) <= LINE then return {name} end
  local words = {}
  for w in name:gmatch("%S+") do words[#words + 1] = w end
  -- The split that leaves the longer line shortest.
  local best, worst
  for k = 1, #words - 1 do
    local a, b = table.concat(words, " ", 1, k), table.concat(words, " ", k + 1)
    local m = math.max(utf8.len(a), utf8.len(b))
    if m <= LINE and (not worst or m < worst) then best, worst = {a, b}, m end
  end
  if best then return best end
  -- "Turun ammattikorkeakoulu, ICT-City": the part that fits.
  local first, rest = name:match("^(.-),%s*(.+)$")
  if first then return S.lines(utf8.len(first) <= LINE * 2 and first or rest) end
end

-- The place's own name for its sign, if it goes by one: lines, colours.
function S.name(tags)
  if not tags.name or tags.brand then return end
  local look
  for k, by in pairs(S.NAMED) do look = look or (tags[k] and by[tags[k]]) end
  if not look and tags.wikidata then
    for k, by in pairs(S.KNOWN) do look = look or (tags[k] and by[tags[k]]) end
  end
  if not look then return end
  local lines = S.lines(tags.name)
  if lines then return lines, look end
end

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

-- How wide and tall a plate is for these lines.
local GAP = LETTER * 0.5
local function plate(lines)
  local n = 0
  for _, l in ipairs(lines) do n = math.max(n, utf8.len(l)) end
  return (n * 6 - 1) * LETTER / 7 + 0.5, PLATE_H + (#lines - 1) * (LETTER + GAP)
end

-- The plate and its letters, from the wall point (x, y, z) facing (nx, nz).
local function parts(list, x, y, z, nx, nz, lines, look)
  local yaw = math.atan(nx, nz)
  local w, h = plate(lines)
  local px, pz = x + nx * PLATE_D / 2, z + nz * PLATE_D / 2
  list[#list + 1] = {mesh = "cube", pos = {px, y, pz}, yaw = yaw, size = {w, h, PLATE_D}, color = look.bg, emissive = 0.35}
  local tx, tz = x + nx * (PLATE_D + 0.012), z + nz * (PLATE_D + 0.012)
  for k, line in ipairs(lines) do
    local ly = y + ((#lines + 1) / 2 - k) * (LETTER + GAP) - LETTER / 2
    list[#list + 1] = {text = line, height = LETTER, depth = 0.025, pos = {tx, ly, tz}, yaw = yaw, color = look.fg, emissive = 0.8}
  end
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
local function outline_walls(f, x, z, within, out)
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
        out[#out + 1] = {x = qx, z = qz, nx = nx, nz = nz, left = t, right = len - t, f = f, d = d, tx = ex / len, tz = ez / len}
      end
    end
    j = k
  end
  table.sort(out, function(p, q) return p.d < q.d end)
  return out
end

local function walls(grid, x, z, within)
  local out = {}
  for _, f in ipairs(grid[math.floor(x / GRID) .. "," .. math.floor(z / GRID)] or {}) do
    outline_walls(f, x, z, within, out)
  end
  table.sort(out, function(p, q) return p.d < q.d end)
  return out
end

local function fits(w) return w.left >= 1.2 and w.right >= 1.2 and w.f.h >= OVER + 1.2 end

-- Whether a plate `half` wide either side of t along outline wall w (from
-- its first corner) keeps clear of the wall's balconies: a block of flats'
-- sunny walls have them every third 2.7 m bay, mirrored about the middle
-- (roadnet's balconies), and nothing to stop a ray.
local function off_balconies(w, t, half)
  local len = w.left + w.right
  if not w.f.balconies or len <= 6 or w.nx * roadnet.SUNNY[1] + w.nz * roadnet.SUNNY[2] <= 0.2 then return true end
  local nb = math.max(1, math.floor(len / 2.7 + 0.5))
  local bay = len / nb
  for k = 0, nb - 1 do
    if math.min(k, nb - 1 - k) % 3 == 1 and math.abs(t - (k + 0.5) * bay) < bay * 0.46 + half + 0.1 then return false end
  end
  return true
end
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

-- The outline p is in, or (in the notch of an L, a yard) the nearest one.
local function own_outline(grid, p)
  for _, f in ipairs(grid[math.floor(p.x / GRID) .. "," .. math.floor(p.z / GRID)] or {}) do
    if inside(f.pts, p.x, p.z) then return f.h >= OVER + 1.2 and f or nil end
  end
  for _, w in ipairs(walls(grid, p.x, p.z, 15)) do
    if w.f.h >= OVER + 1.2 then return w.f end -- (not the shed in front)
  end
end

-- A named place's wall on outline f that faces the street (rx, rz), with
-- room for a plate half as wide as `half` (slid along the wall, off its
-- corners), open in front, clear of other signs (free(x, z)): the nearest
-- to the street.
local function street_wall(f, rx, rz, half, free)
  local need = math.max(1.2, half)
  if f.h < OVER + 1.2 then return nil, "small wall" end
  local n = 0
  for _, w in ipairs(outline_walls(f, rx, rz, 80, {})) do
    local len = w.left + w.right
    -- (Slid along it: off its corners, and between its balconies.)
    local t = len >= need * 2 and math.max(need, math.min(len - need, w.left))
    if t and not off_balconies(w, t, half) then
      local nb, best = math.max(1, math.floor(len / 2.7 + 0.5)), nil
      for k = 0, nb - 1 do
        local c = math.max(need, math.min(len - need, (k + 0.5) * len / nb))
        if off_balconies(w, c, half) and (not best or math.abs(c - w.left) < math.abs(best - w.left)) then best = c end
      end
      t = best
    end
    if t and (rx - w.x) * w.nx + (rz - w.z) * w.nz > 0 then
      w.x, w.z = w.x + w.tx * (t - w.left), w.z + w.tz * (t - w.left)
      w.left, w.right = t, len - t
      local y = height(w)
      if free(w.x, w.z) and not wall_ray(w.x + w.nx * 0.15, y, w.z + w.nz * 0.15, w.nx, w.nz, 8)
         and not roadnet.on_carriageway(w.x + w.nx * 0.5, w.z + w.nz * 0.5, 0.3) then
        return w.x, w.z, y, w.nx, w.nz, true
      end
      n = n + 1
      if n == 8 then break end
    end
  end
  return nil, "no open wall"
end

-- Off any street (a pedestrian one, a square): the wall of the place's own
-- outline nearest it with open ground in front, where the door would be.
-- Deep inside a big one (a campus's point in its middle): its wall nearest
-- the street (rx, rz).
local function by_outline(grid, p, rx, rz, half, free)
  local n = 0
  if rx and half and #walls(grid, p.x, p.z, 6) == 0 then
    local own = own_outline(grid, p)
    if own then
      local x, z, y, nx, nz, outline = street_wall(own, rx, rz, half, free)
      if x then return x, z, y, nx, nz, outline end
    end
  end
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
  return hx, hz, w and y or U.ground(hx + nx * 0.6, hz + nz * 0.6) + ON_BOX, nx, nz, w ~= nil
end

-- Where p's sign goes: x, z, height, the wall's normal, whether that's a
-- drawn outline's wall; or nil and why not.
-- (half: a named place's plate's half width; it may go further along its
-- building for a wall that has room.)
local function site(grid, p, half, free)
  local ei, _, cx, cz, d = roadnet.nearest_edge(p.x, p.z, true)
  local e = ei and roadnet.net().edges[ei]
  if not e or d > REACH then return by_outline(grid, p, e and cx, e and cz, half, free) end
  if e.tunnel or e.height then return nil, "bridge" end
  if d < 1 then return nil, "on the street" end
  if half then -- its own building first, not a low one in front of it
    local own = own_outline(grid, p)
    if own then
      local x, z, y, nx, nz, outline = street_wall(own, cx, cz, half, free)
      if x then return x, z, y, nx, nz, outline end
    end
  end
  local dx, dz = (p.x - cx) / d, (p.z - cz) / d
  local hit, _, hx, hz, nx, nz = wall_ray(cx, U.ground(cx, cz) + OVER + 0.4, cz, dx, dz, d + 12)
  if not hit then return by_outline(grid, p, cx, cz, half, free) end
  local w = walls(grid, hx, hz, 2.5)[1]
  if w and half and not (fits(w) and w.left >= half and w.right >= half) then return street_wall(w.f, cx, cz, half, free) end
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
  return hx, hz, U.ground(hx + nx * 0.6, hz + nz * 0.6) + ON_BOX, nx, nz
end

function S.build()
  S.pending = city.network() ~= nil and quality.tier() > 1
end

local function take_down()
  for _, id in ipairs(S.ids) do
    if engine.exists(id) then engine.despawn(id) end
  end
  S.ids, S.list, S.job, S.why, S.missed = {}, {}, nil, {}, {}
end
quality.watch(function(tier)
  if tier == 1 then take_down(); S.pending = false
  elseif #S.ids == 0 and city.network() and S.pending == false then S.pending = true end
end)

-- The places to sign, a chunk of the map at a time, the player's first.
local function start()
  local chunks, keys = {}, {}
  for _, p in ipairs(pois.find{road = false}) do
    local word, look = S.name(p.tags)
    local named = word ~= nil
    if not word then
      word, look = S.word(p.tags)
      word = word and {word}
    end
    if word then
      local k = math.floor(p.x / CHUNK) .. "," .. math.floor(p.z / CHUNK)
      if not chunks[k] then
        chunks[k] = {key = k, x = (math.floor(p.x / CHUNK) + 0.5) * CHUNK, z = (math.floor(p.z / CHUNK) + 0.5) * CHUNK}
        keys[#keys + 1] = chunks[k]
      end
      table.insert(chunks[k], {p = p, word = word, look = look, named = named})
    end
  end
  local px, _, pz = U.player_pos()
  for _, c in ipairs(keys) do
    c.d = U.dist2d(c.x, c.z, px, pz)
    -- The places known beyond their street first, then the other names: a
    -- shop's sign doesn't crowd out the school's in the same building.
    local function rank(q) return q.p.tags.wikidata and 0 or q.named and 1 or 2 end
    table.sort(c, function(a, b)
      local ra, rb = rank(a), rank(b)
      if ra ~= rb then return ra < rb end
      return a.p.x < b.p.x or (a.p.x == b.p.x and a.p.z < b.p.z)
    end)
  end
  table.sort(keys, function(a, b) return a.d < b.d or (a.d == b.d and a.key < b.key) end)
  return {chunks = keys, ci = 1, i = 1, parts = {}, grid = footprint_grid(), near = {}, places = 0, ms = 0, ticks = 0}
end

-- Whether a plate w wide at (x, z) keeps clear of the signs already up:
-- APART from each, or more for wide ones (not overlapping a name's plate).
local function clear(job, x, z, w)
  local ci, cj = math.floor(x / APART), math.floor(z / APART)
  for i = ci - 2, ci + 2 do
    for j = cj - 2, cj + 2 do
      for _, o in ipairs(job.near[i .. "," .. j] or {}) do
        if U.dist2d(o.x, o.z, x, z) < math.max(APART, (o.w + w) / 2 + 0.5) then return false end
      end
    end
  end
  return true
end

-- Why a place got no sign (named places by name too: S.missed).
local function miss(q, why)
  S.why[why] = (S.why[why] or 0) + 1
  if q.named then S.missed[q.p.name] = why end
end

local function place(job, q)
  local w, h = plate(q.word)
  local x, z, y, nx, nz, outline = site(job.grid, q.p, q.named and w / 2 or nil, function(cx, cz) return clear(job, cx, cz, w) end)
  if not x then return miss(q, z) end
  if outline then
    local on = walls(job.grid, x, z, 0.3)[1]
    if on and not off_balconies(on, on.left, w / 2) then return miss(q, "balconies") end
  end
  y = y + (h - PLATE_H) / 2 -- (two lines grow up, off the shop windows)
  -- One flat wall behind it, top to bottom (not a low box building's top
  -- with a taller one behind).
  -- Nothing built in front of it (a shop podium before a tower's wall).
  local front = engine.raycast(x + nx * 0.05, y - h / 2 + 0.05, z + nz * 0.05, nx, 0, nz, 1.5)
  local hidden = front and engine.tag(front) == "building"
  for _, f in ipairs(job.grid[math.floor(x / GRID) .. "," .. math.floor(z / GRID)] or {}) do
    hidden = hidden or (f.base + f.h > y - h / 2 and inside(f.pts, x + nx * 0.4, z + nz * 0.4))
  end
  if hidden then return miss(q, "hidden") end
  if not outline then
    local top, dt = engine.raycast(x + nx * 0.5, y + h / 2 + 0.1, z + nz * 0.5, -nx, 0, -nz, 0.9)
    local foot, df = engine.raycast(x + nx * 0.5, y - h / 2 - 0.1, z + nz * 0.5, -nx, 0, -nz, 0.9)
    if not top or engine.tag(top) ~= "building" or not foot or math.abs(dt - df) > 0.1 then return miss(q, "low wall") end
  end
  -- A long name's plate: wall behind both its ends too, not hung past a corner.
  if w > 3 then
    local ax, az = nz, -nx
    for _, side in ipairs{-1, 1} do
      local ex, ez = x + ax * side * (w / 2 - 0.2), z + az * side * (w / 2 - 0.2)
      local back, d = engine.raycast(ex + nx * 0.5, y, ez + nz * 0.5, -nx, 0, -nz, outline and 12 or 1.5)
      if not back or engine.tag(back) ~= "building" or (not outline and d > 1.2) then
        return miss(q, "past the corner")
      end
    end
  end
  if not clear(job, x, z, w) then return miss(q, "crowded") end
  local ci, cj = math.floor(x / APART), math.floor(z / APART)
  local s = {x = x, z = z, y = y, w = w, h = h, yaw = math.atan(nx, nz), word = table.concat(q.word, " "), name = q.p.name,
             named = q.named, outline = outline}
  S.list[#S.list + 1] = s
  local k = ci .. "," .. cj
  job.near[k] = job.near[k] or {}
  table.insert(job.near[k], s)
  parts(job.parts, x, y, z, nx, nz, q.word, q.look)
end

-- Up to n more places; true when they're all done. Each chunk's signs are
-- baked into one mesh as soon as it's through.
-- (A still picture, test/shot, wants them all up in its first frames.)
local PER_TICK = os.getenv("SHOT_CAM") and math.huge or 12
local function step(job, n)
  local t0 = os.clock()
  job.ticks = job.ticks + 1
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
                        #S.ids, S.job.ms, S.job.ticks, table.concat(why, ", ")))
    S.job, S.pending = nil, false
  end
end)

return S
