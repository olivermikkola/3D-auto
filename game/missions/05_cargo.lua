-- Deliver a car full of something breakable. Every knock costs condition.
-- On a map with points of interest the cargo is a real shop's (antiques,
-- second-hand, furnishings: the one nearest the old pickup) and it goes to
-- a museum or gallery, a theatre or arts centre, or another dealer, picked
-- per run (lib/template, docs/MISSION_TEMPLATES.md). The grid maps
-- keep their hand-placed pickup and drop.
local G = require "lib.state"
local H = require "lib.health"
local city = require "lib.city"
local pois = require "lib.pois"
local roadnet = require "lib.roadnet"
local template = require "lib.template"
local vehicle = require "lib.vehicle"

local MIN = 60 -- condition below this and the cargo is ruined

local near = city.has("cargo_pickup") and {city.place("cargo_pickup")} or (city.has("lot") and {city.place("lot")})
local shop = near and pois.find{shop = {"antiques", "second_hand", "interior_decoration", "furniture"}, name = true,
                                from = near, limit = 1}[1]

-- Where it goes: any kind of place the map has one of (a seed picks the
-- kind among those that fit, then the place).
local DROPS = {
  {tourism = {"museum", "gallery"}},
  {amenity = {"arts_centre", "theatre"}},
  {shop = {"antiques", "art", "jewelry", "second_hand", "interior_decoration"}},
}

-- The drop for a seed and the time allowed: 1-2.5 km by road, careful
-- driving (slower than the courier runs).
local function cast(seed)
  local fits = {}
  for _, tags in ipairs(DROPS) do
    local role = {"drop", name = true, drive_min = 1000, drive_max = 2500,
                  relax = {{drive_max = 4000}, {drive_min = 500, drive_max = false}},
                  weight = function(p) return 1 / (1 + math.abs(p.drive - 1600) / 700) end}
    for k, v in pairs(tags) do role[k] = v end
    local c = template.cast{seed = seed, from = {shop.x, shop.z}, roles = {role}, avoid = {[template.key(shop)] = true}}
    if c then fits[#fits + 1] = c.drop end
  end
  local d = fits[seed % math.max(#fits, 1) + 1]
  if d then return d, math.floor((30 + d.drive / 12) / 10 + 0.5) * 10 end
end

local cx, cz, yaw
if shop and cast(1) then
  -- The car waits on the shop's street, a few metres along it.
  local e, i = roadnet.nearest_edge(shop.road[1], shop.road[2], true)
  local p = roadnet.net().edges[e].pts
  local dx, dz = p[i][1] - p[i - 1][1], p[i][2] - p[i - 1][2]
  local l = math.sqrt(dx * dx + dz * dz)
  cx, cz, yaw = shop.road[1] + dx / l * 10, shop.road[2] + dz / l * 10, math.atan(dx, dz)
else
  shop = nil
  if not city.has("cargo_pickup", "cargo_drop") then return false end
  cx, cz, yaw = city.place("cargo_pickup")
  yaw = 0
end

return {
  title = "Fragile Cargo",
  after = "04_getaway",
  start = shop and {shop.road[1], shop.road[2]} or {cx - 8, cz - 8},
  reward = 900,
  cast = shop and cast or nil, -- for test/template_probe
  run = function(m)
    -- Clear the spot (a dented car from your last try, a parked one).
    for _, id in ipairs(engine.find("car")) do
      local x, _, z = engine.pos(id)
      if id ~= G.vehicle and (x - cx) ^ 2 + (z - cz) ^ 2 < 36 then engine.despawn(id) end
    end
    -- Not m:spawn: the car stays in town (with you in it) when the mission ends.
    m.car = vehicle.spawn(cx, cz, yaw, 5)
    local van = m:marker(cx, cz, {0.3, 1, 0.4})
    m:say(shop and ("Get in the white car outside " .. shop.name .. ". Gently.") or "Get in the white car. Gently.")
    m:wait(function()
      if not engine.exists(m.car) then m:fail("THE CARGO IS GONE") end
      return G.vehicle == m.car
    end)
    m:remove(van)

    local dx, dz, name, seconds = nil, nil, nil, 110
    if shop then
      local d
      d, seconds = cast(template.next_seed())
      dx, dz, name = d.road[1], d.road[2], d.name
    else
      dx, dz = city.place("cargo_drop")
    end
    m.goal = {dx, dz}
    local drop = m:marker(dx, dz)
    local where = (name and " to " .. name or "") .. m:on_street(dx, dz)
    m:timer(seconds)
    m:wait(function()
      if G.vehicle ~= m.car then m:fail("YOU LEFT THE CARGO") end
      local hp = H.get(m.car) or 0
      if hp < MIN then m:fail("THE CARGO IS RUINED") end
      m:say(string.format("Deliver it%s and stop. Cargo: %d%%", where, math.floor((hp - MIN) / (H.VEHICLE_HP - MIN) * 100 + 0.5)))
      return m:near(drop, 6) and math.abs(vehicle.speed(m.car)) < 1
    end)
  end,
}
