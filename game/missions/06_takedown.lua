-- Hunt down a black car somewhere in town and wreck it. It runs once hit.
-- On a map with points of interest it pulls away from a real nightclub,
-- bar, pub or hotel 0.4-1.5 km from where you start, picked per run
-- (lib/template, docs/MISSION_TEMPLATES.md); the grid maps keep their
-- hand-placed start.
local G = require "lib.state"
local H = require "lib.health"
local U = require "lib.util"
local city = require "lib.city"
local template = require "lib.template"
local vehicle = require "lib.vehicle"
local traffic = require "systems.traffic"

if not city.has("takedown_start") then return false end
local start = {city.place("takedown_start")}

local ROLES = {
  {"den", amenity = {"nightclub", "bar", "pub", "casino"}, name = true, drive_min = 400, drive_max = 1500,
   relax = {{drive_max = 3000}, {drive_min = 200, drive_max = false}}},
}
local HOTEL = {{"den", tourism = "hotel", name = true, drive_min = 400, drive_max = 3000, relax = {{drive_max = false}}}}

-- Where the target sets off for a seed: a named place (its junction), or nil.
local function cast(seed)
  local c = template.cast{seed = seed, from = start, roles = seed % 4 == 0 and HOTEL or ROLES}
             or template.cast{seed = seed, from = start, roles = ROLES}
  return c and c.den
end

local templated = cast(1) ~= nil
if not templated and not city.has("target_start") then return false end

return {
  title = "Takedown",
  after = "05_cargo",
  start = start,
  reward = 1500,
  cast = templated and cast or nil, -- for test/template_probe
  run = function(m)
    local den = templated and cast(template.next_seed())
    local tx, tz
    if den then tx, tz = city.pos(den.junction) else tx, tz = city.place("target_start") end
    -- Not m:spawn: if you fail, it drives on as ordinary traffic.
    m.target = vehicle.spawn(tx, tz, 0, 6)
    local c = traffic.adopt(m.target, {keep = true})
    -- A red square follows it on the minimap.
    local blip = {id = m.target, color = {1, 0.2, 0.15}}
    G.markers[#G.markers + 1] = blip
    m:defer(function()
      c.keep, c.cruise = nil, nil
      for i, b in ipairs(G.markers) do if b == blip then table.remove(G.markers, i) break end end
    end)
    m:on("damaged", function(id)
      if id == m.target and not c.cruise then
        c.cruise = 21
        U.message("THE TARGET IS RUNNING", 3)
      end
    end)
    m:timer(180)
    m:wait(function()
      if not engine.exists(m.target) then return true end -- blew up
      local hp = H.get(m.target) or 0
      m:say(hp > 0 and string.format("Wreck the black car%s (red on the map). Its health: %d",
                                     den and (" leaving " .. den.name) or "", math.ceil(hp))
            or "It's burning. Stand back!")
      return false
    end)
  end,
}
