-- Hansa's lower floor (docs/UNDERGROUND.md, piece 4): on foot from Louhi's
-- hall into Hansa's level -1, along it past the shops, up the stairs to the
-- ground floor and out the door on Aurakatu (Hansa Aurakatu 12a). Layer 1,
-- as Louhi; laid out in Louhi's hall frame (systems/louhi: along, across),
-- which Hansakortteli is squared to: its north wall at 51 m across, its
-- Aurakatu side at -9 m along.
--
-- From OpenStreetMap: Louhi's way toward Hansa leaves the hall's west end
-- (ways 1193257264/5); level -1 has Stadium (node 6927766765), Partioaitta
-- (way 1275345953) and the lifts (ways 1276168764/5); its stairs up to the
-- ground floor are at -48 along (ways 1410336414/5); the door on Aurakatu
-- is node 5107508754. The corridors between are the game's.
local U = require "lib.util"

local M = {}

local HF = 2.2   -- level -1's floor (Aurakatu, the ground floor, is at ~5.7)
local CEIL = 4.0

-- The rectangles (along a0..a1, across c0..c1).
local T1 = {a0 = -113.2, a1 = -97.65, c0 = 11.6, c1 = 14.0}  -- out of the hall's west end
local T2 = {a0 = -113.2, a1 = -110.8, c0 = 11.6, c1 = 58}    -- and up to Hansa
local C1 = {a0 = -116, a1 = -40, c0 = 58, c1 = 70}           -- level -1, past the shops
local C2 = {a0 = -52, a1 = -44, c0 = 70, c1 = 80}            -- to the stairs
local C4 = {a0 = -44, a1 = -9.1, c0 = 96.5, c1 = 105}        -- the ground floor to the door

function M.plan(Lh)
  M.Lh = Lh
  local door = {axis = "along", at = -9.1, out = 1, c = 100.8, name = "Hansa"}
  local x, z = Lh.hall_xz(door.at + 0.8, door.c)
  door.ys = U.ground(x, z)
  local G0 = door.ys
  local n = math.max(2, math.ceil((G0 - HF) / 0.17))
  local top = C2.c1 + n * 0.29
  M.G0, M.n, M.top, M.door = G0, n, top, door
  local A = Lh.AREAS
  A[#A + 1] = {a0 = T1.a0, a1 = T1.a1, c0 = T1.c0, c1 = T1.c1, y0 = Lh.HALL_Y}
  A[#A + 1] = {a0 = T2.a0, a1 = T2.a1, c0 = T2.c0, c1 = T2.c1, y0 = Lh.HALL_Y, y1 = HF, axis = "across"}
  A[#A + 1] = {a0 = C1.a0, a1 = C1.a1, c0 = C1.c0, c1 = C1.c1, y0 = HF}
  A[#A + 1] = {a0 = C2.a0, a1 = C2.a1, c0 = C2.c0, c1 = C2.c1, y0 = HF}
  A[#A + 1] = {a0 = C2.a0, a1 = C2.a1, c0 = C2.c1, c1 = top, y0 = HF, y1 = G0, axis = "across"}
  A[#A + 1] = {a0 = C2.a0, a1 = C2.a1, c0 = top, c1 = C4.c1, y0 = G0}
  A[#A + 1] = {a0 = C4.a0, a1 = C4.a1, c0 = C4.c0, c1 = C4.c1, y0 = G0}
  Lh.DOORS[#Lh.DOORS + 1] = door
  Lh.ROUTES[#Lh.ROUTES + 1] = {pts = {{-95, 12.8}, {-112, 12.8}, {-112, 64}, {-48, 64}, {-48, top + 1}, {-48, 100.8}, {-9.6, 100.8}},
                               w = 8, door = door}
  Lh.GAPS.west[#Lh.GAPS.west + 1] = {T1.c0, T1.c1}
end

local TILE, TILE2, WALL, WALL2 = {0.78, 0.76, 0.72}, {0.7, 0.68, 0.64}, {0.86, 0.85, 0.82}, {0.74, 0.73, 0.7}
local STRIP, GLASS, FRAME, BAND = {1, 0.98, 0.94}, {0.55, 0.62, 0.66}, {0.3, 0.31, 0.33}, {0.14, 0.15, 0.17}

function M.build(Lh)
  local k = Lh.kit()
  local box, slab, slab_x = k.box, k.slab, k.slab_x
  local y2, G0, top = Lh.HALL_Y, M.G0, M.top
  -- Walls from one point to another along (or across), floor to h above.
  local function wall_a(a0, a1, c, y, h, color) box((a0 + a1) / 2, c, y + h / 2, a1 - a0, 0.5, h, color or WALL, true) end
  local function wall_c(c0, c1, a, y, h, color) box(a, (c0 + c1) / 2, y + h / 2, 0.5, c1 - c0, h, color or WALL, true) end

  -- Out of the hall: a corridor 2.4 m wide, 3 m high, concrete like Louhi.
  local CONC = {0.55, 0.55, 0.53}
  slab(T1.a0, T1.a1 + 0.5, y2, y2, (T1.c0 + T1.c1) / 2, 2.9, 0.6, TILE2, true)
  wall_a(T1.a0 - 0.5, T1.a1, T1.c0 - 0.25, y2, 3, CONC)
  wall_a(T2.a1, T1.a1, T1.c1 + 0.25, y2, 3, CONC)
  slab(T1.a0 - 0.5, T1.a1, y2 + 3.3, y2 + 3.3, (T1.c0 + T1.c1) / 2, 3.4, 0.3, CONC, true)
  slab(T1.a0, T1.a1, y2 + 2.98, y2 + 2.98, (T1.c0 + T1.c1) / 2, 0.25, 0.04, STRIP, false, 1)
  -- and up to Hansa (hardly: level -1 is 0.2 m higher)
  slab_x(T2.c0, T2.c1 + 0.5, y2, HF, (T2.a0 + T2.a1) / 2, 2.9, 0.6, TILE2, true)
  wall_c(T1.c0 - 0.5, T2.c1, T2.a0 - 0.25, y2, CEIL + 0.5, CONC)
  wall_c(T1.c1, T2.c1, T2.a1 + 0.25, y2, CEIL + 0.5, CONC)
  slab_x(T1.c0 - 0.5, T2.c1, y2 + 3.3, HF + 3.3, (T2.a0 + T2.a1) / 2, 3.4, 0.3, CONC, true)
  slab_x(T2.c0, T2.c1, y2 + 2.98, HF + 2.98, (T2.a0 + T2.a1) / 2, 0.25, 0.04, STRIP, false, 1)

  -- Level -1: the floor, the ceiling and its lights, the walls.
  local ca, cc = (C1.a0 + C1.a1) / 2, (C1.c0 + C1.c1) / 2
  box(ca, cc, HF - 0.3, C1.a1 - C1.a0 + 1, C1.c1 - C1.c0 + 1, 0.6, TILE, true)
  box(ca, cc, HF + CEIL + 0.2, C1.a1 - C1.a0 + 1, C1.c1 - C1.c0 + 1, 0.4, WALL2, true)
  for a = C1.a0 + 4, C1.a1 - 4, 6 do box(a, cc, HF + CEIL - 0.03, 3, 0.4, 0.06, STRIP, false, 1) end
  wall_a(C1.a0 - 0.5, T2.a0, C1.c0 - 0.25, HF, CEIL)
  wall_a(T2.a1, C1.a1 + 0.5, C1.c0 - 0.25, HF, CEIL)
  wall_a(C1.a0 - 0.5, C2.a0, C1.c1 + 0.25, HF, CEIL)
  -- (open where the way from Toriparkki comes in: systems/toriparkki, Lh.HANSA_LINK)
  local link = Lh.HANSA_LINK
  if link then
    if link[1] > C2.a1 then wall_a(C2.a1, link[1], C1.c1 + 0.25, HF, CEIL) end
    if link[2] < C1.a1 + 0.5 then wall_a(link[2], C1.a1 + 0.5, C1.c1 + 0.25, HF, CEIL) end
  else
    wall_a(C2.a1, C1.a1 + 0.5, C1.c1 + 0.25, HF, CEIL)
  end
  wall_c(C1.c0, C1.c1, C1.a0 - 0.25, HF, CEIL)
  wall_c(C1.c0, C1.c1, C1.a1 + 0.25, HF, CEIL)

  -- Shop fronts: glass between frames, lit from inside, the name over.
  local function front(a0, a1, c, face, name)
    local inward = face == "-c" and -1 or 1 -- (which way into the corridor)
    local cg = c + inward * 0.06
    box((a0 + a1) / 2, cg, HF + 1.4, a1 - a0, 0.06, 2.8, GLASS, false, 0.35)
    for a = a0, a1 + 0.01, (a1 - a0) / math.max(1, math.floor((a1 - a0) / 2.5)) do
      box(a, c + inward * 0.1, HF + 1.4, 0.12, 0.12, 2.8, FRAME)
    end
    box((a0 + a1) / 2, c + inward * 0.08, HF + 3.25, a1 - a0, 0.1, 0.7, BAND)
    if name then k.text((a0 + a1) / 2, c + inward * 0.14, HF + 3.25, face, name, 0.42, {0.98, 0.97, 0.94}, 0.7) end
  end
  -- The far side (across 70): the lifts, Stadium, Partioaitta as OSM has
  -- them along; the near side, shops without names.
  front(-92, -76, C1.c1, "-c", "STADIUM")
  front(-70, -56, C1.c1, "-c", "PARTIOAITTA")
  front(-112, -104, C1.c1, "-c")
  for _, r in ipairs{{-106, -96}, {-92, -82}, {-78, -66}, {-62, -50}} do front(r[1], r[2], C1.c0, "+c") end
  -- the lifts: two steel doors
  for _, a in ipairs{-101.5, -98.5} do
    box(a, C1.c1 - 0.05, HF + 1.1, 1.2, 0.1, 2.2, {0.62, 0.64, 0.66})
  end
  box(-100, C1.c1 - 0.06, HF + 2.6, 4, 0.06, 0.5, BAND)
  k.text(-100, C1.c1 - 0.1, HF + 2.6, "-c", "HISSIT", 0.3, nil, 0.6)
  box(-112, C1.c0 - 0.25, HF + 3.5, 3, 0.5, 1.3, WALL, true) -- over the way in from Louhi
  -- Signs: the way to Louhi, the way up to Aurakatu, HANSA at the far end.
  box(-112, C1.c0 + 0.06, HF + 3.1, 2.4, 0.06, 0.5, {0.1, 0.3, 0.75})
  k.text(-112, C1.c0 + 0.1, HF + 3.1, "+c", "LOUHI P", 0.3, nil, 0.4)
  box(-48, C1.c1 - 0.06, HF + 3.4, 8, 0.06, 0.5, BAND)
  k.text(-48, C1.c1 - 0.1, HF + 3.4, "-c", "AURAKATU", 0.34, {0.98, 0.97, 0.94}, 0.7)
  if link then
    box((link[1] + link[2]) / 2, C1.c1 + 0.2, HF + 3.0, 3.6, 0.06, 0.5, {0.1, 0.3, 0.75})
    k.text((link[1] + link[2]) / 2, C1.c1 + 0.16, HF + 3.0, "-c", "TORIPARKKI", 0.28, nil, 0.4)
  end
  k.text(C1.a0 + 0.1, (C1.c0 + C1.c1) / 2, HF + 2.6, "+a", "HANSA", 1.1, {0.95, 0.8, 0.3}, 0.8)

  -- Up to the ground floor: the stairs, 8 m wide, steps over a ramp.
  local sa = (C2.a0 + C2.a1) / 2
  local w = C2.a1 - C2.a0
  slab_x(C2.c0 - 0.5, C2.c1, HF, HF, sa, w + 0.6, 0.6, TILE, true)
  local rise = (G0 - HF) / M.n
  for i = 0, M.n - 1 do
    box(sa, C2.c1 + (i + 0.5) * 0.29, HF + (i + 1) * rise - 0.3, w, 0.3, 0.6, i % 2 == 0 and TILE2 or TILE)
  end
  slab_x(C2.c1, top, HF, G0, sa, w, 0.4, TILE2, true)
  slab_x(top, C4.c1 + 0.5, G0, G0, sa, w + 0.6, 0.6, TILE, true)
  local hi = G0 + CEIL -- (the ground floor's ceiling, over the stairs too)
  wall_c(C1.c1, C4.c1 + 0.5, C2.a0 - 0.25, HF, hi - HF)
  wall_c(C1.c1, C4.c0, C2.a1 + 0.25, HF, hi - HF)
  box(sa, C1.c1 + 0.25, (HF + CEIL + hi) / 2, w, 0.5, hi - HF - CEIL, WALL) -- over the way in from level -1
  box(sa, (C2.c0 + C4.c1) / 2, hi + 0.2, w + 1, C4.c1 - C2.c0 + 1, 0.4, WALL2, true)
  for c = C2.c0 + 3, C4.c1 - 3, 6 do box(sa, c, hi - 0.03, 0.4, 3, 0.06, STRIP, false, 1) end
  for _, side in ipairs{-1, 1} do
    slab_x(C2.c1, top, HF + 0.9, G0 + 0.9, sa + side * (w / 2 - 0.1), 0.06, 0.06, FRAME)
  end
  -- The ground floor's corridor out to Aurakatu.
  local da = (C4.a0 + C4.a1) / 2
  local dc = (C4.c0 + C4.c1) / 2
  box(da, dc, G0 - 0.3, C4.a1 - C4.a0 + 1, C4.c1 - C4.c0 + 1, 0.6, TILE, true)
  box(da, dc, hi + 0.2, C4.a1 - C4.a0 + 1, C4.c1 - C4.c0 + 1, 0.4, WALL2, true)
  for a = C4.a0 + 3, C4.a1 - 3, 6 do box(a, dc, hi - 0.03, 3, 0.4, 0.06, STRIP, false, 1) end
  wall_a(C2.a0 - 0.5, C4.a1 + 0.5, C4.c1 + 0.25, G0, CEIL)
  wall_a(C4.a0 - 0.25, C4.a1 + 0.5, C4.c0 - 0.25, G0, CEIL)
  wall_c(C4.c0 - 0.5, C4.c1 + 0.5, C4.a1 + 0.25, G0, CEIL)
  front(-36, -24, C4.c0, "+c")
  front(-34, -18, C4.c1, "-c")
  -- the door out: daylight in its glass
  box(C4.a1 - 0.02, M.door.c, G0 + 1.1, 0.04, 1.4, 2.2, {0.85, 0.88, 0.9}, false, 1)

  -- In one mesh, its solids in layer 1; the lamps.
  local ox, oz = Lh.hall_xz(-60, 70)
  local o = {ox, HF, oz}
  local baked = {}
  for i, p in ipairs(k.parts) do
    local q = {}
    for key, val in pairs(p) do q[key] = val end
    q.pos = {p.pos[1] - o[1], p.pos[2] - o[2], p.pos[3] - o[3]}
    baked[i] = q
  end
  engine.mesh("hansa_minus1", baked)
  engine.spawn{mesh = "hansa_minus1", pos = o, layer = Lh.LAYER, tag = "building"}
  for _, p in ipairs(k.solids) do
    engine.spawn{mesh = "cube", pos = p.pos, yaw = p.yaw, pitch = p.pitch, size = p.size, visible = false, body = "static", tag = "wall",
                 layer = Lh.LAYER}
  end
  local function lamp(a, c, y)
    local x, z = Lh.hall_xz(a, c)
    engine.light{pos = {x, y, z}, color = {1, 0.96, 0.9}, intensity = 1.1, radius = 16, layer = Lh.LAYER}
  end
  lamp(-112, 30, HF + 2.6)
  for a = C1.a0 + 8, C1.a1 - 4, 16 do lamp(a, (C1.c0 + C1.c1) / 2, HF + CEIL - 0.4) end
  lamp(sa, 85, hi - 0.5)
  lamp(-30, dc, hi - 0.5)
  -- Up top, Hansa's door on Aurakatu.
  Lh.street_door(M.door, "HANSA")
end

return M
