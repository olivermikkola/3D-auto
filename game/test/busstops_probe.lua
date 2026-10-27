-- Bus stops probe: people wait at the shelters near the player, in front,
-- looking at the road; Föli buses in traffic pull in by them and let them
-- on, and the stop stays empty a while after.
-- BUSSTOPS_TEST=1 auto game --headless 30000   (MAP=turku)
local G = require "lib.state"
local U = require "lib.util"
local B = require "systems.busstops"
local shelters = require "systems.shelters"
local peds = require "systems.peds"
local traffic = require "systems.traffic"
traffic.BUSES = 2 -- (more buses, so a few stops are made in a few minutes)

local function check(ok, what)
  if not ok then engine.quit(); error("BUSSTOPS TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local function wait(pred, timeout, what)
  local t = engine.time() + timeout
  while not pred() do
    if engine.time() > t then check(false, what .. " (timed out)") end
    coroutine.yield()
  end
end

local function sleep(s)
  local t = engine.time() + s
  wait(function() return engine.time() >= t end, s + 1, "sleep")
end

local function script()
  wait(function() return #shelters.list > 0 end, 5, "shelters are up")
  local id = G.vehicle or G.player
  local x, z = tonumber(os.getenv("BUSSTOPS_AT_X") or "-60"), tonumber(os.getenv("BUSSTOPS_AT_Z") or "150")
  engine.set_pos(id, x, U.ground(x, z) + 1.5, z)
  sleep(3)
  local filled, people, by, facing = 0, 0, 0, 0
  for _, s in ipairs(shelters.list) do
    if s.people then
      filled = filled + 1
      for k, pid in ipairs(s.people) do
        if peds.peds[pid] then
          people = people + 1
          local px, _, pz = engine.pos(pid)
          if U.dist2d(px, pz, s.x, s.z) < 3.5 then by = by + 1 end
          local fx, fz = math.sin(s.yaw), math.cos(s.yaw)
          if math.sin(engine.yaw(pid)) * fx + math.cos(engine.yaw(pid)) * fz > 0.5 then facing = facing + 1 end
        end
      end
    end
  end
  for _, s in ipairs(shelters.list) do
    if s.people and #s.people >= 2 and os.getenv("BUSSTOPS_TRACE") then
      print(string.format("BUSSTOPS_PROBE: %d waiting at %s %.0f,%.0f yaw %.2f", #s.people, s.name or "?", s.x, s.z, s.yaw))
    end
  end
  print(string.format("BUSSTOPS_PROBE: %d shelters filled, %d people, %d by their shelter, %d facing the road", filled, people, by, facing))
  check(filled >= 3 and people >= 3, "people wait at the shelters near the player")
  check(by == people, "by their shelter")
  check(facing >= people * 0.8, "looking at the road")

  local buses_at = {}
  for t = 1, 18 do
    sleep(20)
    local buses = 0
    for _, c in pairs(traffic.cars) do if c.is_bus then buses = buses + 1 end end
    print(string.format("BUSSTOPS_PROBE t=%d: %d buses about, %d stops made, %d got on, %d got off", t * 20, buses, B.stops_made, B.boarded, B.alighted))
    for cid, c in pairs(traffic.cars) do
      if c.doors then buses_at[cid] = (buses_at[cid] or 0) + 1 end
    end
  end
  check(B.stops_made >= 1, string.format("buses stop for them (%d stops)", B.stops_made))
  check(B.boarded >= 1, string.format("and they get on (%d)", B.boarded))
  local stuck = 0
  for _, n in pairs(buses_at) do if n > 1 then stuck = stuck + 1 end end
  check(stuck == 0, "no bus stands at a stop for long")
  print("BUSSTOPS_PROBE: PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
