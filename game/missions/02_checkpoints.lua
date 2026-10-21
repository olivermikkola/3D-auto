-- Street race through checkpoints. One at a time, against the clock. On a
-- map with points of interest the race runs to a landmark (a museum, a
-- castle, a church...) 2-3.5 km by road away, picked per run, with
-- checkpoints at the junctions of the way there (lib/template,
-- docs/MISSION_TEMPLATES.md); the grid maps keep their hand-placed route.
local city = require "lib.city"
local template = require "lib.template"
local U = require "lib.util"
if not city.has("race_start") then return false end

local start = {city.place("race_start")}
local GAP = 300 -- meters by road between checkpoints, about

-- Where it can end: a seed picks the kind among those the map has, then
-- the place.
local FINISHES = {
  {tourism = {"attraction", "museum", "gallery", "zoo", "theme_park"}},
  {historic = {"castle", "church", "manor", "monument"}},
  {amenity = "place_of_worship"},
  {leisure = {"stadium", "marina"}},
}

-- The checkpoints (the finish last) along the way by road, and its length.
local function checkpoints(finish)
  local route = template.route(start[1], start[2], finish)
  if not route then return nil end
  local out, run, total = {}, 0, 0
  for i = 2, #route do
    local pts = city.path(route[i - 1], route[i])
    local l = 0
    for k = 2, #pts do l = l + math.sqrt((pts[k][1] - pts[k - 1][1]) ^ 2 + (pts[k][2] - pts[k - 1][2]) ^ 2) end
    run, total = run + l, total + l
    local x, z = city.pos(route[i])
    -- Not on a bridge or in a tunnel (the marker stands on the ground), nor
    -- right by the finish.
    local level = city.level(route[i])
    local flat = not level or math.abs(level - U.ground(x, z)) < 2
    if run >= GAP and flat and U.dist2d(x, z, finish.road[1], finish.road[2]) > GAP / 2 then
      out[#out + 1] = {x, z}
      run = 0
    end
  end
  out[#out + 1] = {finish.road[1], finish.road[2]}
  return out, total
end

-- The finish, the checkpoints and the time allowed for a seed, or nil.
local function cast(seed)
  local fits = {}
  for _, tags in ipairs(FINISHES) do
    local role = {"finish", name = true, drive_min = 2000, drive_max = 3500,
                  relax = {{drive_min = 1200, drive_max = 5000}, {drive_min = 600, drive_max = false}},
                  weight = function(p) return 1 / (1 + math.abs(p.drive - 2600) / 800) end}
    for k, v in pairs(tags) do role[k] = v end
    local c = template.cast{seed = seed, from = start, roles = {role}}
    if c then fits[#fits + 1] = c.finish end
  end
  local finish = fits[seed % math.max(#fits, 1) + 1]
  if not finish then return nil end
  local cps, length = checkpoints(finish)
  if not cps then return nil end
  -- About 15 m/s (54 km/h) on average through town.
  return finish, cps, math.floor((15 + length / 15) / 5 + 0.5) * 5, length
end

local templated = cast(1) ~= nil
if not templated and not city.has("race") then return false end

return {
  title = "Street Race",
  start = start,
  reward = 600,
  cast = templated and cast or nil, -- for test/template_probe
  run = function(m)
    m:say("You need wheels for this one.")
    m:wait(function() return m:in_car() end)
    local finish, route, seconds
    if templated then finish, route, seconds = cast(template.next_seed()) end
    if not route then route, seconds = city.route("race"), 90 end
    m.stops = route
    m:timer(seconds)
    if finish then U.message("RACE TO " .. finish.name:upper(), 3) end
    for i, n in ipairs(route) do
      local x, z = n[1], n[2]
      local cp = m:marker(x, z, {0.2, 0.8, 1.0})
      if i == #route and finish then
        m:say(string.format("Finish: %s%s", finish.name, m:on_street(x, z)))
      else
        m:say(string.format("Checkpoint %d of %d", i, #route))
      end
      m:wait(function()
        if not m:in_car() then m:fail("YOU LEFT YOUR CAR") end
        return m:near(cp, 6)
      end)
      m:remove(cp)
      engine.emit("checkpoint", i)
      U.message(string.format("%d/%d", i, #route), 1)
    end
  end,
}
