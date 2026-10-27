-- Market day probe: Kauppatori has rows of stalls, and by day people browse
-- them: they turn up while the player is near, walk from stall to stall and
-- stand at each looking at it, on the square (not sunk in it or fallen
-- off); a car horn sends them running and they come back to browse; after
-- closing time they go home.
-- MARKET_TEST=1 auto game --headless 3000   (MAP=turku)
local G = require "lib.state"
local U = require "lib.util"
local daynight = require "lib.daynight"
local quality = require "lib.quality"
local K = require "systems.kauppatori"
local peds = require "systems.peds"

local function check(ok, what)
  if not ok then engine.quit(); error("MARKET TEST FAILED: " .. what, 0) end
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

local function shoppers()
  local list = {}
  for id in pairs(K.shoppers) do list[#list + 1] = id end
  return list
end

local function move_player(x, z)
  local id = G.vehicle or G.player
  engine.set_pos(id, x, U.ground(x, z) + 1.5, z)
  engine.set_vel(id, 0, 0, 0)
end

local function script()
  check(#K.stalls >= 80, string.format("%d market stalls", #K.stalls))
  check(#K.spots == 2 * #K.stalls, "two places to stand in front of each")
  -- Every place to stand is open: no stall, pavilion or wall in it.
  local blocked = 0
  for _, s in ipairs(K.spots) do
    local hit = engine.raycast(s[1], s[4] + 2.5, s[2], 0, -1, 0, 2.3)
    if hit and engine.tag(hit) ~= "ped" then blocked = blocked + 1 end
  end
  check(blocked == 0, string.format("nothing stands where people stand (%d blocked)", blocked))

  -- By day, with the player on the square's edge.
  daynight.set_hour(12)
  move_player(-240, -60)
  local want = quality.pick(K.SHOPPERS)
  wait(function() return #shoppers() >= want end, 30, "the market fills up")
  check(#shoppers() == want, string.format("%d people at the market", #shoppers()))
  sleep(40)
  local standing, on_square, facing = 0, 0, 0
  for _, id in ipairs(shoppers()) do
    local p = peds.peds[id]
    local x, y, z = engine.pos(id)
    local s = K.spots[p.k]
    if math.abs(y - 0.9 - s[4]) < 0.4 then on_square = on_square + 1 end
    if p.until_t and U.dist2d(x, z, s[1], s[2]) < 0.8 then
      standing = standing + 1
      if math.abs(U.angle_diff(engine.yaw(id), s[3])) < 0.5 then facing = facing + 1 end
    end
  end
  if os.getenv("MARKET_TRACE") then
    for _, id in ipairs(shoppers()) do
      local p = peds.peds[id]
      local x, y, z = engine.pos(id)
      local vx, _, vz = engine.vel(id)
      print(string.format("TRACE %s k=%d d=%.1f v=%.2f stuck=%.1f y-top=%.2f wait=%s", p.state, p.k, U.dist2d(x, z, p.tx, p.tz),
        math.sqrt(vx * vx + vz * vz), p.stuck, y - K.spots[p.k][4], tostring(p.until_t and math.floor(p.until_t - engine.time()))))
    end
  end
  local n = #shoppers()
  print(string.format("MARKET_PROBE: %d of %d standing at a stall, %d facing it, %d on the square", standing, n, facing, on_square))
  check(on_square == n, "everyone is on the square, feet on its top")
  check(standing >= n * 0.4, "most are stood at a stall")
  check(facing >= standing * 0.8, "looking at the stall")
  -- Some have moved on to another stall.
  local moved = 0
  local at = {}
  for _, id in ipairs(shoppers()) do at[id] = peds.peds[id].k end
  sleep(60)
  for id, k in pairs(at) do
    if peds.peds[id] and peds.peds[id].k ~= k then moved = moved + 1 end
  end
  check(moved >= n * 0.3, string.format("they go from stall to stall (%d of %d moved on)", moved, n))
  check(peds.count() <= quality.pick(quality.PEDS), "the market doesn't eat into the walkers on the streets")

  -- A fright: they run, then come back to browse.
  local x, _, z = engine.pos(shoppers()[1])
  peds.scare(x, z, 30)
  local fled = 0
  for _, id in ipairs(shoppers()) do if peds.peds[id].state == "flee" then fled = fled + 1 end end
  check(fled > 0, string.format("a fright sends them running (%d)", fled))
  sleep(8)
  local back = 0
  for _, id in ipairs(shoppers()) do if peds.peds[id].state == "browse" then back = back + 1 end end
  check(back == #shoppers(), "and they come back to browse")

  -- Closing time: those out of sight go home; no new ones come.
  daynight.set_hour(19)
  move_player(-240, -60 - 45)
  wait(function() return #shoppers() == 0 end, 5, "after closing they go home")
  sleep(3)
  check(#shoppers() == 0, "no one comes after closing")
  print("MARKET_PROBE: PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
