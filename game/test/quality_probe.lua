-- Graphics quality probe: the one switch sets shadows, view distance, how
-- many cars and people, and the bus shelters; each setting it sets is
-- still free to change; reset brings back medium, the game as it was.
-- QUALITY_TEST=1 auto game --headless 2000
local settings = require "lib.settings"
local quality = require "lib.quality"
local traffic = require "systems.traffic"
local shelters = require "systems.shelters"
local city = require "lib.city"

local function check(ok, what)
  if not ok then engine.quit(); error("QUALITY TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end
local function wait(pred, timeout, what)
  local t = engine.time() + timeout
  while not pred() do
    if engine.time() > t then check(false, what .. " (timed out)") end
    coroutine.yield()
  end
end

local function script()
  local map = city.map().id or "?"
  wait(function() return shelters.pending == false end, 5, "shelters go up")
  check(quality.tier() == 2 and settings.text("quality") == "MEDIUM", "medium to start with")
  check(settings.get("shadows") == true and settings.get("view") == 100, "with shadows and the full view")
  check(traffic.target == 20 and quality.pick(quality.PEDS) == 40, "20 cars and 40 people, as before")
  check(#shelters.list > 100 and #engine.find("shelter") == #shelters.list, "and shelters at the bus stops")

  settings.set("quality", 1)
  check(settings.text("quality") == "LOW", "low")
  check(settings.get("shadows") == false and settings.get("view") == 70, "no shadows and a shorter view")
  check(traffic.target == 12 and quality.pick(quality.PEDS) == 20, "fewer cars and people")
  check(#shelters.list == 0 and #engine.find("shelter") == 0, "no shelters")

  settings.set("quality", 3)
  check(settings.get("shadows") == true and settings.get("view") == 150, "high: shadows and a longer view")
  check(traffic.target == 28 and quality.pick(quality.PEDS) == 60, "more cars and people")
  wait(function() return #shelters.list > 100 end, 2, "the shelters are back")

  settings.set("view", 120)
  check(settings.get("view") == 120 and quality.tier() == 3, "the view is still yours to change")
  settings.reset()
  check(quality.tier() == 2 and settings.get("view") == 100 and settings.get("shadows") == true and traffic.target == 20,
    "reset: medium again")
  print("QUALITY_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
