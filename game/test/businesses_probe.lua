-- Businesses probe: a grill, a kiosk and a taxi firm stand by real places;
-- you can't buy one without the money; once bought it's yours, its till
-- fills as time passes and R empties it into your cash; the taxi firm adds
-- its cut to a fare; it's all in the save, and the next session starts at
-- the one you were last at.
-- BUSINESS_TEST=1 auto game --headless 3000   (MAP=turku)
local G = require "lib.state"
local U = require "lib.util"
local B = require "systems.businesses"
local shop = require "lib.shop"
local progress = require "lib.progress"

local function check(ok, what)
  if not ok then engine.quit(); error("BUSINESS TEST FAILED: " .. what, 0) end
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

local function go(b)
  engine.set_pos(G.player, b.x, U.ground(b.x, b.z) + 1.2, b.z)
  engine.set_vel(G.player, 0, 0, 0)
  sleep(0.5)
end

local function script()
  check(#B.list == 3, string.format("%d businesses", #B.list))
  for _, b in ipairs(B.list) do
    print(string.format("BUSINESS_PROBE: %s at %s (%.1f, %.1f), $%d", b.name, b.place or "?", b.x, b.z, b.price))
    check(not require("lib.roadnet").on_carriageway(b.x, b.z, 0.5), b.name .. " stands off the road")
  end
  local grill, taxi = B.by_id.grill, B.by_id.taxi

  G.cash = 100
  go(grill)
  check(shop.current() == grill.zone, "standing at the grill")
  shop.current().use()
  check(not B.owned("grill") and G.cash == 100, "can't buy it without the money")

  G.cash = grill.price + 50
  shop.current().use()
  check(B.owned("grill") and G.cash == 50, "bought: it's yours and the money's gone")
  check(G.home == "grill", "and it's home")

  sleep(12)
  local till = G.businesses.grill
  local want = grill.hourly * 12 * 24 / require("lib.daynight").DAY_LENGTH
  check(till > want * 0.8 and till < want * 1.2, string.format("the till fills as time passes ($%.2f in 12 s)", till))
  G.businesses.grill = 123.6
  shop.current().use()
  check(G.cash == 50 + 123 and G.businesses.grill < 1, "R empties the till into your cash")

  G.businesses.grill = 1e9
  sleep(0.2)
  check(G.businesses.grill <= grill.hourly * B.TILL_HOURS, "a till holds a day's takings at most")

  G.cash = taxi.price
  go(taxi)
  shop.current().use()
  check(B.owned("taxi") and G.home == "taxi", "bought the taxi firm")
  local before = G.cash
  engine.emit("fare_paid", 80, 20, "somewhere")
  check(G.cash == before + 25, string.format("the firm's cut of a $100 fare ($%d)", G.cash - before))

  check(progress.save(), "saved")
  local saved = engine.load("progress")
  check(saved.businesses and saved.businesses.grill and saved.businesses.taxi and not saved.businesses.kiosk, "the save has what you own")
  check(saved.home == "taxi", "and where you were last")

  -- Next session: on foot somewhere else, then home.
  engine.set_pos(G.player, 0, U.ground(0, 0) + 30, 0)
  check(B.go_home(), "a new session starts at home")
  local x, _, z = engine.pos(G.player)
  check(U.dist2d(x, z, taxi.x, taxi.z) < 1, "at the taxi firm")
  print("BUSINESS_PROBE: PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
