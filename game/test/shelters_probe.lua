-- Bus shelters probe: most of the map's bus stops get one, every one off
-- the carriageway (a car keeps its lane past it), with its back free of
-- walls, and level.
-- SHELTERS_TEST=1 auto game --headless 600
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local pois = require "lib.pois"
local S = require "systems.shelters"

local function check(ok, what)
  if not ok then engine.quit(); error("SHELTERS TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local done = false
engine.on("tick", function()
  if done or S.pending ~= false then return end
  done = true
  local map = city.map().id or "?"
  local stops = #pois.find{highway = "bus_stop", road = false}
  print(string.format("SHELTERS_PROBE %s: %d shelters at %d stops", map, #S.list, stops))
  check(stops > 100, "the map has its bus stops")
  check(#S.list >= stops * 0.6, string.format("most stops have a shelter (%d of %d)", #S.list, stops))
  local on_road, walled, tilted = {}, {}, {}
  for _, s in ipairs(S.list) do
    local fx, fz = math.sin(s.yaw), math.cos(s.yaw) -- toward the road
    local ax, az = fz, -fx
    for _, c in ipairs{{-1.8, 0.65}, {1.8, 0.65}, {-1.8, -0.65}, {1.8, -0.65}} do
      local x, z = s.x + ax * c[1] + fx * c[2], s.z + az * c[1] + fz * c[2]
      local ei, _, _, _, d = roadnet.nearest_edge(x, z)
      if ei and d < roadnet.net().edges[ei].width / 2 + 1 then on_road[#on_road + 1] = s break end
    end
    local _, y = engine.pos(s.id)
    local hit, d = engine.raycast(s.x, y, s.z, -fx, 0, -fz, 0.65 + 0.15, s.id)
    if hit and engine.tag(hit) ~= "ped" then walled[#walled + 1] = s end
    if math.abs(U.ground(s.x, s.z) + 1.25 - y) > 0.05 then tilted[#tilted + 1] = s end
  end
  local function where(l) return l[1] and string.format(" (%s at %.0f, %.0f)", l[1].name or "?", l[1].x, l[1].z) or "" end
  check(#on_road == 0, "none on a carriageway" .. where(on_road))
  check(#walled == 0, "none backed into a wall" .. where(walled))
  check(#tilted == 0, "each stands on the ground" .. where(tilted))
  print(string.format("SHELTERS_PROBE %s: PASSED", map))
  engine.quit()
end)
