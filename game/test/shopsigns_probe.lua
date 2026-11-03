-- Shop signs probe: most of the map's shops, cafés and pubs get a sign,
-- every one flat on a building's wall (not floating, not inside it),
-- facing out, off the carriageway, at shop-sign height; and in Turku the
-- places Oliver asked for by name have theirs up, with that name.
-- SIGNS_TEST=1 auto game --headless 600
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local pois = require "lib.pois"
local S = require "systems.shopsigns"

local function check(ok, what)
  if not ok then engine.quit(); error("SIGNS TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local done = false
engine.on("tick", function()
  if done or S.pending ~= false then return end
  done = true
  local places = 0
  for _, p in ipairs(pois.find{road = false}) do
    if S.name(p.tags) or S.word(p.tags) then places = places + 1 end
  end
  print(string.format("SIGNS_PROBE %s: %d signs for %d places", city.map().id or "?", #S.list, places))
  check(places > 800, "the map has its shops")
  check(#S.list >= places * 0.6, string.format("most have a sign (%d of %d)", #S.list, places))
  local named, by_name = 0, {}
  for _, s in ipairs(S.list) do
    if s.named then named = named + 1; by_name[s.name] = s end
  end
  print(string.format("SIGNS_PROBE %d with the place's own name", named))
  if city.map().id == "turku" then
    check(named > 150, "the town's own names up")
    for _, want in ipairs{"Luostarivuoren lyseon lukio", "EduCity", "Panimoravintola Koulu", "Uusi Apteekki", "Proffan kellari",
                          "Turun klassillinen lukio", "Forum Marinum"} do
      local s = by_name[want]
      check(s ~= nil, want .. (s and string.format(" (at %.0f, %.0f: %s)", s.x, s.z, s.word) or ": " .. tostring(S.missed[want])))
    end
  end
  local floating, buried, on_road, high = {}, {}, {}, {}
  for _, s in ipairs(S.list) do
    local nx, nz = math.sin(s.yaw), math.cos(s.yaw)
    -- The wall right behind the plate: a ray from in front of it, back.
    -- (A drawn outline's sign is on the outline, its boxes further in.)
    local hit, d = engine.raycast(s.x + nx * 0.5, s.y, s.z + nz * 0.5, -nx, 0, -nz, s.outline and 12 or 1.5)
    if not hit or engine.tag(hit) ~= "building" or (not s.outline and d > 1.2) then floating[#floating + 1] = s end
    -- Nothing of the building in front of it.
    local front = engine.raycast(s.x + nx * 0.02, s.y - 0.3, s.z + nz * 0.02, nx, 0, nz, 1.5)
    if front and engine.tag(front) == "building" then buried[#buried + 1] = s end
    if roadnet.on_carriageway(s.x + nx * 0.5, s.z + nz * 0.5, 0) then on_road[#on_road + 1] = s end
    local over = s.y - U.ground(s.x + nx * 0.6, s.z + nz * 0.6)
    if over < 2.6 or over > 6 then high[#high + 1] = s; s.name = (s.name or "?") .. string.format(" %.1f m up", over) end
  end
  local function where(l)
    return l[1] and string.format(" (%d, first %s %s at %.0f, %.0f)", #l, l[1].word, l[1].name or "?", l[1].x, l[1].z) or ""
  end
  check(#floating <= #S.list * 0.03, "on a wall" .. where(floating))
  check(#buried <= #S.list * 0.03, "facing out of it" .. where(buried))
  check(#on_road == 0, "none over a carriageway" .. where(on_road))
  check(#high <= #S.list * 0.05, "at shop-sign height" .. where(high))
  print("SIGNS TEST PASSED")
  engine.quit()
end)
