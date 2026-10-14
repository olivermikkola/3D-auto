-- © 2026 Oliver Mikkola. CC BY-NC 4.0, not MIT: see LICENSE in this folder.
-- Raisio about 1980: the centre as the 1970s built it, in two levels, cars
-- on the ground and people up on concrete. The market square (where
-- Torikuja is now, north of Raisiontie) has kiosks and stalls, a raised
-- deck on round columns runs round it in front of the shops, and concrete
-- footbridges with solid parapets lead off it over Raisiontie to Tasala
-- and over Kerttulantie and Nesteentie: Keonsilta (1978), of which only the
-- stretch over Nesteentie still stands. The 2000s took it all down,
-- narrowed Raisiontie and strung the lanterns over it; none of that is here,
-- nor the flats and the glass cube built since. Sources: Raision
-- kotiseutukuvat in digi.kirjastot.fi (Raision keskusta, Raision tori,
-- Ylikulkusillat), the Keskikaupungin osayleiskaava, fi.wikipedia
-- Varppeenseutu.
--
-- Everything else is today's Raisio (maps/raisio.lua): the roads, Tasala's
-- 1980s blocks south of Raisiontie, the rest of town.
local base = require "maps.raisio"

local m = {}
for k, v in pairs(base) do m[k] = v end
m.name = "Raisio 1980"
m.string_lights = nil -- the lanterns came with the 2000s

-- Not yet built: the flats and houses where the square and its deck were,
-- Raision Lasikuutio (2009), Raisiontori 2 (2016), and the flats where
-- Keonsilta came down to the centre.
local gone = {
  {770, -1862, 975, -1762},
  {950, -1732, 964, -1718},
  {735, -1732, 752, -1715},
  {1028, -1805, 1060, -1786},
}
m.footprints = {}
for _, f in ipairs(base.footprints) do
  local keep = true
  for _, r in ipairs(gone) do
    if f[1] > r[1] and f[1] < r[3] and f[2] > r[2] and f[2] < r[4] then keep = false end
  end
  if keep then m.footprints[#m.footprints + 1] = f end
end
-- The square's west side: two floors of shops behind the deck, flat
-- roofed; and the grill kiosk on the square.
m.footprints[#m.footprints + 1] = {782, -1804, 16, 66, 0, 6.8, "shop", "Raision ostoskeskus"}
m.footprints[#m.footprints + 1] = {900, -1790, 12, 6, 0, 3.4, "shop", "Grilli-kioski"}

-- The square, the deck round its west, north and east sides, and the
-- market in the middle.
m.squares = {{797, -1832, 938, -1764}}
m.decks = {
  {790, -1832, 797, -1766, open = "w"},  -- west, along the shops
  {790, -1839, 945, -1832, open = "n"},  -- north, in front of the shops there
  {938, -1832, 945, -1766},              -- east, over Kerttulantie's side
}
m.market = {{845, -1795, 4, 2}}

-- The footbridges: from the deck over Raisiontie to Tasala (two), a ramp
-- down into the square, and Keonsilta east over Kerttulantie and
-- Nesteentie, in place of the stretch of it that still stands.
m.footbridges = {}
for _, b in ipairs(base.footbridges) do
  if not (math.abs(b[2][1] - 1137.1) < 1 and math.abs(b[2][2] + 1717.8) < 1) then m.footbridges[#m.footbridges + 1] = b end
end
for _, b in ipairs{
  {5, {793.5, -1766}, {793.5, -1704}, up = {true, false}, concrete = true},
  {5, {941.5, -1766}, {941.5, -1704}, up = {true, false}, concrete = true},
  {4, {868, -1832}, {868, -1808}, up = {true, false}, concrete = true},
  {4, {945, -1800}, {1056.6, -1771}, {1137.1, -1717.8}, up = {true, false}, concrete = true},
} do m.footbridges[#m.footbridges + 1] = b end

m.looks = {
  {782, -1804, 10, {color = {0.9, 0.89, 0.85}, floors = 2}},  -- the shops, white panels and dark window bands
  {900, -1790, 4, {color = {0.95, 0.95, 0.93}, floors = 1}},  -- the kiosk
}
for _, l in ipairs(base.looks) do m.looks[#m.looks + 1] = l end

m.labels = {{x = 868, z = -1805, letter = "T", name = "Raision tori"}}
for _, l in ipairs(base.labels or {}) do m.labels[#m.labels + 1] = l end

return m
