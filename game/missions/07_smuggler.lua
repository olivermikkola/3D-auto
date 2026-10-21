-- Collect packages across town. Every one turns up the heat; lose the cops
-- before you make the drop. On a map with points of interest the packages
-- wait behind real places (a pub's back door, a kiosk, a car wash, a
-- garage) and go to a marina or ferry terminal, picked per run
-- (lib/template, docs/MISSION_TEMPLATES.md); the grid maps keep their
-- hand-placed route and drop.
local city = require "lib.city"
local template = require "lib.template"
local U = require "lib.util"
local wanted = require "lib.wanted"

if not city.has("smuggle_drop") then return false end
local home = {city.place("smuggle_drop")}

-- 400 m to 1.1 km by road between pickups, 700 m liked best.
local function hop(from, tags)
  local role = {from = from, name = true, drive_min = 400, drive_max = 1100,
                relax = {{drive_max = 2500}, {drive_min = 250, drive_max = false}},
                weight = function(p) return 1 / (1 + math.abs(p.drive - 700) / 400) end}
  for k, v in pairs(tags) do role[k] = v end
  return role
end

local PICKUPS = {
  hop(home, {"first", amenity = {"pub", "bar", "nightclub"}}),
  hop("first", {"second", shop = {"kiosk", "convenience"}}),
  hop("second", {"third", amenity = {"car_wash", "fuel"}}),
  hop("third", {"fourth", shop = {"car_repair", "tyres", "car"}}),
}
-- Where it all goes: by the water, 0.6-2 km on from the last pickup. A
-- marina's middle is out on its jetties, so its street may be further off.
local DROPS = {{leisure = "marina"}, {amenity = "ferry_terminal"}}

-- The four pickups, the drop and the time allowed for a seed, or nil.
local function cast(seed)
  local c = template.cast{seed = seed, from = home, roles = PICKUPS}
  if not c then return nil end
  local fits = {}
  for _, tags in ipairs(DROPS) do
    local role = {"drop", from = {c.fourth.x, c.fourth.z}, name = true, drive_min = 600, drive_max = 2000,
                  road_dist = 250, relax = {{drive_max = 4000}, {drive_min = false, drive_max = false}}}
    for k, v in pairs(tags) do role[k] = v end
    local d = template.cast{seed = seed, from = home, roles = {role}}
    if d then fits[#fits + 1] = d.drop end
  end
  local drop = fits[seed % math.max(#fits, 1) + 1]
  if not drop then return nil end
  local stops = {c.first, c.second, c.third, c.fourth}
  local drive = drop.drive
  for _, p in ipairs(stops) do drive = drive + p.drive end
  -- Driving at about 13 m/s, plus a minute to shake the cops.
  return stops, drop, math.floor((60 + drive / 13) / 10 + 0.5) * 10
end

local templated = cast(1) ~= nil
if not templated and not city.has("smuggle") then return false end

return {
  title = "Smuggler's Run",
  after = "06_takedown",
  start = home,
  reward = 2000,
  cast = templated and cast or nil, -- for test/template_probe
  run = function(m)
    local stops, drop, seconds
    if templated then stops, drop, seconds = cast(template.next_seed()) end
    if not stops then
      stops, seconds = {}, 240
      for _, n in ipairs(city.route("smuggle")) do stops[#stops + 1] = {road = {n[1], n[2]}} end
    end
    m.stops = {}
    for i, p in ipairs(stops) do m.stops[i] = p.road end
    m:timer(seconds)
    for i, p in ipairs(stops) do
      local x, z = p.road[1], p.road[2]
      local pkg = m:spawn{mesh = "crate", pos = {x, 0.6 + U.ground(x, z), z}, size = 0.9, color = {0.75, 0.55, 0.3}}
      local marker = m:marker(x, z, {1, 0.5, 0.1})
      m:say(string.format("Pick up package %d of %d%s%s.", i, #stops, p.name and (" behind " .. p.name) or "",
                          m:on_street(x, z)))
      m:wait(function() return m:near(marker, 5) end)
      m:remove(marker)
      m:remove(pkg)
      engine.play("pickup")
      U.message(string.format("PACKAGE %d/%d", i, #stops), 2)
      wanted.set(math.min(3, math.max(wanted.stars(), i - 1)))
    end

    local dx, dz = table.unpack(drop and drop.road or home)
    m.goal = {dx, dz}
    local marker = m:marker(dx, dz, {0.2, 1, 0.4})
    local where = (drop and (" at " .. drop.name) or "") .. m:on_street(dx, dz)
    m:wait(function()
      local hot = wanted.stars() > 0
      m:say(hot and "Lose the cops, then make the drop." or ("Make the drop" .. where .. "."))
      return not hot and m:near(marker, 6)
    end)
  end,
}
