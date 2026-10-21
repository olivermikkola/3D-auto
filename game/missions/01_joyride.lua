-- The tutorial: steal a car and bring it to a garage across town. On a map
-- with points of interest the garage is a real car repair shop, picked per
-- run from the ones a short drive away (lib/template,
-- docs/MISSION_TEMPLATES.md); the grid maps keep their hand-placed garage.
local city = require "lib.city"
local template = require "lib.template"
if not city.has("lot") then return false end

local lx, lz = city.place("lot")
local start = {lx - 13, lz - 9}

-- 600 m to 2.5 km by road: far enough to learn the car, short enough for
-- a first mission.
local ROLES = {
  {"garage", shop = {"car_repair", "tyres"}, name = true, drive_min = 600, drive_max = 2500,
   relax = {{drive_max = 3000}, {drive_min = 300, drive_max = false}},
   weight = function(p) return 1 / (1 + math.abs(p.drive - 1300) / 600) end},
}

-- The garage for a seed and the time allowed (about 12 m/s with time to
-- find the car), or nil on a map without one.
local function cast(seed)
  local c = template.cast{seed = seed, from = start, roles = ROLES}
  if c then return c.garage, math.floor((40 + c.garage.drive / 12) / 5 + 0.5) * 5 end
end

local templated = cast(1) ~= nil
if not templated and not city.has("joyride_garage") then return false end -- this map has no garage for it

return {
  title = "Joyride",
  start = start,
  reward = 250,
  cast = templated and cast or nil, -- for test/template_probe
  run = function(m)
    m:say("Steal a car. Walk up to one and press E.")
    m:wait(function() return m:in_car() end)

    local garage, seconds = templated and cast(template.next_seed())
    local gx, gz, name
    if garage then
      gx, gz, name = garage.road[1], garage.road[2], garage.name
    else
      gx, gz = city.place("joyride_garage")
    end
    m.goal = {gx, gz}
    local marker = m:marker(gx, gz)
    m:say("Drive it to " .. (name or "the garage") .. m:on_street(gx, gz) .. " before the owner notices.")
    m:timer(seconds or 75)
    m:wait(function() return m:near(marker, 5) end)

    m:say("Park it. Stop the car.")
    m:wait(function()
      return m:in_car() and math.abs(require("lib.vehicle").speed(require("lib.state").vehicle)) < 1
    end)
  end,
}
