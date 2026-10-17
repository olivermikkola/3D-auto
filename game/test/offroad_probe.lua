-- Cops after a player standing off the road: in a park, a yard, behind a
-- block. At spots 20-60 m from the nearest road, how long until a cop is
-- out of its car or within 15 m, from three stars and a clean start?
-- OFFROAD_TEST=1 MAP=turku auto game --headless 40000
-- OFFROAD_SPOTS=n (default 8) and OFFROAD_LIMIT=s (default 45) to taste.
local G = require "lib.state"
local U = require "lib.util"
local P = require "systems.police"
local wanted = require "lib.wanted"
local roadnet = require "lib.roadnet"

local N = tonumber(os.getenv("OFFROAD_SPOTS") or "8")
local LIMIT = tonumber(os.getenv("OFFROAD_LIMIT") or "45")
-- OFFROAD_ONLY=4,8 runs just those spots; OFFROAD_TRACE=1 prints the cops every 5 s.
local ONLY = os.getenv("OFFROAD_ONLY")
local TRACE = os.getenv("OFFROAD_TRACE")

-- Spots on open ground off the roads, spread over the middle of the map:
-- every 130 m on a grid, kept if the nearest road of any kind is 20-60 m
-- off and straight down from 60 m up meets the terrain (no roof, no water).
local function spots()
  local out = {}
  for gz = -1300, 1300, 130 do
    for gx = -1300, 1300, 130 do
      local _, _, _, _, d = roadnet.nearest_edge(gx, gz)
      local g = engine.terrain_height(gx, gz)
      if d and d >= 20 and d <= 60 and g and g > 0.5 then
        local hit = engine.raycast(gx, g + 60, gz, 0, -1, 0, 70)
        if hit and engine.tag(hit) == "terrain" then out[#out + 1] = {gx, gz} end
      end
    end
  end
  -- An even spread of N of them.
  local pick = {}
  for k = 1, math.min(N, #out) do pick[k] = out[math.floor((k - 0.5) * #out / math.min(N, #out)) + 1] end
  if ONLY then
    local only = {}
    for k in ONLY:gmatch("%d+") do only[#only + 1] = pick[tonumber(k)] end
    return only
  end
  return pick
end

local list, i, start, times, phase = nil, 0, 0, {}, 0
local function next_spot()
  i = i + 1
  if i > #list then
    local reached, sum = 0, 0
    for _, t in ipairs(times) do if t then reached, sum = reached + 1, sum + t end end
    print(string.format("OFFROAD %d of %d reached within %d s, %.1f s on average", reached, #list, LIMIT,
                        reached > 0 and sum / reached or 0))
    print("OFFROAD DONE")
    engine.quit()
    return
  end
  local x, z = list[i][1], list[i][2]
  if G.vehicle then G.vehicle = nil end
  engine.set_pos(G.player, x, 1.2 + U.ground(x, z), z)
  wanted.clear(); P.clear(); wanted.set(3)
  start = engine.time()
end

engine.on("tick", function()
  if phase == 0 then
    if engine.ticks() < 30 then return end
    list, phase = spots(), 1
    print(string.format("OFFROAD %d spots", #list))
    next_spot()
    return
  end
  if i > #list then return end
  local px, _, pz = U.player_pos()
  local near = P.officer_count() > 0
  for id in pairs(P.cops) do
    local x, _, z = engine.pos(id)
    if x and U.dist2d(x, z, px, pz) < 15 then near = true end
  end
  local t = engine.time() - start
  if TRACE and engine.ticks() % 300 == 0 then
    for id, c in pairs(P.cops) do
      local x, y, z = engine.pos(id)
      if x then
        print(string.format("  t=%4.1f cop %d (%.0f, %.1f, %.0f) d=%.0f goal=%s sees=%s stuck=%.1f wedged=%.1f", t, id, x, y, z,
                            U.dist2d(x, z, px, pz), c.goal and string.format("(%.0f,%.0f)", c.goal[1], c.goal[2]) or "-",
                            tostring(c.sees), c.stuck or 0, c.wedged or 0))
      end
    end
  end
  if near or t > LIMIT or wanted.stars() == 0 then
    times[i] = near and t or false
    print(string.format("OFFROAD spot %d (%.0f, %.0f): %s", i, list[i][1], list[i][2],
                        near and string.format("reached in %.1f s", t) or (wanted.stars() == 0 and "lost them" or "not reached")))
    next_spot()
  end
end)
