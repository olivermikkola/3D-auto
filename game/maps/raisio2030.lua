-- © 2026 Oliver Mikkola. CC BY-NC 4.0, not MIT: see LICENSE in this folder.
-- Raisio as it will be about 2030, once the E18 works under the center are
-- done (Väylävirasto's "E18 Raision keskustan kohta", built 2026-2029):
-- the E18 (Nesteentie) runs through a concrete tunnel of some 450 m from
-- the new Elauksenkatu up past Raisiontie, with a park on its roof where
-- the Raisio crossing's lights were. Raisiontie crosses over it; the old
-- slip roads and Soliniuksenkuja's junction onto it are gone. Everything
-- else is today's Raisio (maps/raisio.lua).
--
-- Not here yet: the interchange's ramps and roundabouts west of the tunnel
-- (the old junction at Juhaninkuja stands in for them), Soliniuksenkatu,
-- and the later phase's three-level interchange with valtatie 8.
local tunnel = require "lib.tunnel"
local base = require "maps.raisio"

local m = {}
for k, v in pairs(base) do m[k] = v end
m.name = "Raisio 2030"
-- Start just off the tunnel's roof, where Kerttulantie meets Raisiontie.
m.junction_order = {"Kerttulantie / Raisiontie"}

-- Elauksenkatu: from Hosleniuksenkuja's end over the tunnel's west end to
-- Kreetankuja, toward Opinpolku.
m.junctions = {}
for name, p in pairs(base.junctions) do m.junctions[name] = p end
m.junctions["Elauksenkatu / Kreetankuja"] = {910, -1382}
m.roads = {}
for i, road in ipairs(base.roads) do
  local r = road
  if road.name == "Kreetankuja" then
    for k = 2, #road - 1 do
      local p = road[k]
      if type(p) == "table" and math.abs(p[1] - 910) < 2 and math.abs(p[2] + 1382) < 2 then
        r = {}
        for key, v in pairs(road) do r[key] = v end
        r[k] = "Elauksenkatu / Kreetankuja"
      end
    end
  end
  m.roads[i] = r
end
-- Hosleniuksenkuja's end has no name of its own in the map data (its
-- number changes as the data does): the junction there, by where it is.
local function junction_at(x, z)
  local best, bd
  for name, p in pairs(base.junctions) do
    local d = (p[1] - x) ^ 2 + (p[2] - z) ^ 2
    if not bd or d < bd then best, bd = name, d end
  end
  return best
end
m.roads[#m.roads + 1] = {name = "Elauksenkatu", kind = "street", width = 9, junction_at(867.3, -1437.6), {888, -1412},
                         "Elauksenkatu / Kreetankuja"}

-- The tunnel: along Nesteentie's two carriageways from just west of
-- Elauksenkatu to past Raisiontie, 7.5 m down, the ramps 110 m long.
-- Soliniuksenkuja and Martinkatu no longer meet it.
return tunnel.dig(m, {road = "Nesteentie", from = {852, -1378}, to = {1080, -1760}, depth = 7.5, half = 20, ramp = 110,
                      cut = {"Martinkatu / Nesteentie / Soliniuksenkuja", "Martinkatu / Nesteentie"}})
