-- Mission 11: Häsburger Express
-- Fast courier rush: pick up hot meals at a Häsburger and get them to three
-- customers across town before they go cold. The places are the map's own:
-- the restaurant is the real Hesburger nearest the start lot, and the
-- customers (a school or library, a sports ground, a hotel or museum) are
-- picked from the map's points of interest, different ones each time it's
-- played (lib/template, docs/MISSION_TEMPLATES.md). A map without a
-- Hesburger doesn't have the mission.
local city = require "lib.city"
local pois = require "lib.pois"
local template = require "lib.template"
local U = require "lib.util"

local lot = {city.place("lot")}
local shop = pois.find{amenity = "fast_food", brand = "Hesburger", from = lot, limit = 1}[1]
if not shop then return false end

-- 400 m to 1.6 km by road between stops, 900 m liked best.
local function hop(from, tags)
  local role = {from = from, name = true, drive_min = 400, drive_max = 1600,
                relax = {{drive_max = 3000}, {drive_min = 250, drive_max = false}},
                weight = function(p) return 1 / (1 + math.abs(p.drive - 900) / 500) end}
  for k, v in pairs(tags) do role[k] = v end
  return role
end

local ROLES = {
  hop({shop.x, shop.z}, {"first", amenity = {"school", "college", "university", "library", "townhall", "community_centre"}}),
  hop("first", {"second", leisure = {"pitch", "sports_centre", "stadium", "track"}}),
  hop("second", {"third", tourism = {"hotel", "hostel", "museum", "attraction", "gallery"}}),
}

-- The three customers for a seed, and how long the run gets: about as
-- tight as the old hand-placed run (150 s for ~2.5 km).
local function cast(seed)
  local c, why = template.cast{seed = seed, from = {shop.x, shop.z}, roles = ROLES}
  if not c then return nil, why end
  local drive = c.first.drive + c.second.drive + c.third.drive
  return {c.first, c.second, c.third}, math.floor((30 + drive / 16) / 10 + 0.5) * 10
end

local start = shop.road or {shop.x, shop.z}

return {
  title = "Häsburger Express",
  after = "02_checkpoints",
  start = {start[1], start[2]},
  reward = 1200,
  cast = cast, -- for test/template_probe
  run = function(m)
    local drops, seconds = cast(template.next_seed())
    if not drops then
      U.message("NO CUSTOMERS TODAY", 3)
      return
    end
    m:timer(seconds)
    m:say("Rush courier orders from Häsburger to hungry customers across town!")
    engine.play("star")

    for i, drop in ipairs(drops) do
      local dx, dz = drop.road[1], drop.road[2]
      local marker = m:marker(dx, dz, {0.95, 0.2, 0.1}) -- Häsburger red marker
      m:say(string.format("Order (%d/%d): Deliver to %s%s!", i, #drops, drop.name, m:on_street(dx, dz)))

      m:wait(function()
        return m:near(marker, 10)
      end)

      m:remove(marker)
      engine.play("pickup")
      U.message(string.format("ORDER DELIVERED: %s (+400$)", drop.name), 2)
    end

    U.message("ALL HÄSBURGER ORDERS DELIVERED ON TIME!", 4)
  end,
}
