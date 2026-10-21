-- Rob the bank, then shake a three-star pursuit. On a map with points of
-- interest the bank is a real one (amenity=bank), picked per run from the
-- ones a short drive away (lib/template, docs/MISSION_TEMPLATES.md); the
-- grid maps keep their hand-placed bank.
local city = require "lib.city"
local template = require "lib.template"

local start
if city.has("getaway_start") then
  start = {city.place("getaway_start")}
elseif city.has("lot") then
  local lx, lz = city.place("lot")
  start = {lx + 13, lz - 9}
end
if not start then return false end

-- 250 m to 2.5 km by road from where you get your car (banks keep
-- together in a city's centre: Turku's nine are 0.3-0.6 km from the start).
local ROLES = {
  {"bank", amenity = "bank", name = true, drive_min = 250, drive_max = 2500,
   relax = {{drive_max = 4000}, {drive_min = 100, drive_max = false}},
   weight = function(p) return 1 / (1 + math.abs(p.drive - 800) / 600) end},
}

-- The bank for a seed, or nil on a map without one to rob.
local function cast(seed)
  local c = template.cast{seed = seed, from = start, roles = ROLES}
  return c and c.bank
end

local templated = cast(1) ~= nil
if not templated and not city.has("bank") then return false end

return {
  title = "Getaway",
  start = start,
  reward = 1200,
  cast = templated and cast or nil, -- for test/template_probe
  run = function(m)
    local bank = templated and cast(template.next_seed())
    local bx, bz, name
    if bank then
      bx, bz, name = bank.road[1], bank.road[2], bank.name
    else
      bx, bz = city.place("bank")
    end
    m.goal = {bx, bz}
    m:say("Get a fast car and drive to " .. (name or "the bank") .. m:on_street(bx, bz) .. ".")
    m:wait(function() return m:in_car() end)
    local marker = m:marker(bx, bz, {0.3, 1, 0.4})
    m:wait(function() return m:near(marker, 5) end)

    m:say("Stay in the marker while the crew loads the cash...")
    local t = 0
    m:wait(function()
      t = m:near(marker, 6) and t + 1 / 60 or 0
      return t > 3
    end)
    m:remove(marker)

    m:wanted(3)
    m:say("Lose the cops! Get out of the red circle unseen.")
    m:wait(function() return m:stars() == 0 end)
  end,
}
