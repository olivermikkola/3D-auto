-- Night out probe: by night people stand about outside the bars and clubs
-- near the player, on the pavement (not the road, not in a wall), more
-- after midnight than at nine; by day there's no one, and at four they go
-- home.
-- NIGHTLIFE_TEST=1 auto game --headless 6000   (MAP=turku)
local G = require "lib.state"
local U = require "lib.util"
local daynight = require "lib.daynight"
local roadnet = require "lib.roadnet"
local N = require "systems.nightlife"
local peds = require "systems.peds"

local function check(ok, what)
  if not ok then engine.quit(); error("NIGHTLIFE TEST FAILED: " .. what, 0) end
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

-- The player out of sight of every venue for a moment and back, so the
-- crowds are set for the hour.
local AT = {-150, 60} -- by Kauppatori, among the bars
local function step_away_and_back()
  local id = G.vehicle or G.player
  engine.set_pos(id, AT[1] + 400, U.ground(AT[1] + 400, AT[2]) + 1.5, AT[2])
  sleep(3)
  engine.set_pos(id, AT[1], U.ground(AT[1], AT[2]) + 1.5, AT[2])
  engine.set_vel(id, 0, 0, 0)
  sleep(3)
end

local function out()
  local n, crowds = 0, 0
  for _, v in ipairs(N.venues) do
    local k = 0
    for _, id in ipairs(v.people or {}) do if peds.peds[id] then k = k + 1 end end
    n = n + k
    if k > 0 then crowds = crowds + 1 end
  end
  return n, crowds
end

local function script()
  check(#N.venues >= 50, string.format("%d bars, pubs and clubs", #N.venues))
  daynight.set_hour(14)
  step_away_and_back()
  check(out() == 0, "nobody out by day")

  daynight.set_hour(21.5)
  step_away_and_back()
  local early = out()
  daynight.set_hour(0.5)
  step_away_and_back()
  local late, crowds = out()
  for _, v in ipairs(N.venues) do
    if os.getenv("NIGHTLIFE_LIST") and v.people and #v.people > 0 then
      print(string.format("NIGHTLIFE_PROBE: %d outside %s (%s) %.0f,%.0f, spots from %.0f,%.0f facing %.2f", #v.people, v.name or "?",
        v.kind, v.x, v.z, v.spots[1][1], v.spots[1][2], v.spots[1][3]))
    end
  end
  print(string.format("NIGHTLIFE_PROBE: %d out at 21:30, %d at 00:30 outside %d places", early, late, crowds))
  check(early > 0, "people out at half past nine")
  check(late > early, "more after midnight")
  check(crowds >= 3, "outside several places")
  local bad = 0
  for _, v in ipairs(N.venues) do
    for _, id in ipairs(v.people or {}) do
      local x, _, z = engine.pos(id)
      if roadnet.on_carriageway(x, z, 0.2) then bad = bad + 1 end
    end
  end
  check(bad == 0, "on the pavement, not the road")
  sleep(30)
  local still, moved = 0, 0
  for _, v in ipairs(N.venues) do
    for _, id in ipairs(v.people or {}) do
      local p = peds.peds[id]
      local x, _, z = engine.pos(id)
      if p and p.until_t then still = still + 1 end
      -- Standing somewhere other than by the door. (Not anyone a crash in
      -- the street sent running, on their way back: the market probe
      -- checks they come back.)
      if p and p.state == "browse" and p.until_t and U.dist2d(x, z, v.spots[p.k][1], v.spots[p.k][2]) > 12 then moved = moved + 1 end
    end
  end
  check(moved == 0, "they stay by the door")
  check(still > late * 0.5, string.format("mostly standing about (%d)", still))

  -- One shoved off their spot (a car nudging through) walks back to it.
  local who
  for _, v in ipairs(N.venues) do
    for _, id in ipairs(v.people or {}) do
      local p = peds.peds[id]
      if not who and p and p.state == "browse" and p.until_t then who = {id = id, p = p} end
    end
  end
  check(who ~= nil, "someone standing by a door")
  local x, y, z = engine.pos(who.id)
  local pushed = {x + 5, z}
  if roadnet.on_carriageway(x + 5, z, 0.5) then pushed = {x - 5, z} end
  engine.set_pos(who.id, pushed[1], y, pushed[2])
  sleep(12)
  local s = who.p.spots[who.p.k]
  local bx, _, bz = engine.pos(who.id)
  check(who.p.state ~= "browse" or U.dist2d(bx, bz, s[1], s[2]) < 1.5,
        string.format("one shoved 5 m off their spot walks back (%.1f m from it)", U.dist2d(bx, bz, s[1], s[2])))

  daynight.set_hour(4.5)
  step_away_and_back()
  check(out() == 0, "home by half past four")
  print("NIGHTLIFE_PROBE: PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
