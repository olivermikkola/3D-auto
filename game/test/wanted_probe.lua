-- Losing the cops takes time out of sight, more the more stars: outside the
-- search area 3 s at one star and 25 s at five; hidden inside it, they give
-- up after 30 s at one star and 70 s at five. Being seen starts it over.
-- WANTED_TEST=1 MAP=starter auto game --headless 10
local wanted = require "lib.wanted"

local function check(ok, what)
  if not ok then engine.quit(); error("WANTED TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local DT = 1 / 60
-- Seconds of ticks until the level clears, the player standing at distance d
-- from where they were last seen; nil after `limit` seconds.
local function time_to_lose(stars, d, limit, seen_at)
  wanted.clear()
  wanted.set(stars)
  wanted.center = {0, 0, 0}
  for k = 1, math.floor(limit / DT) do
    if seen_at and k == math.floor(seen_at / DT) then
      wanted.seen, wanted.unseen_for = true, 0
    elseif wanted.unseen(DT, d, 0) then
      return k * DT
    end
  end
end

local t = 0
engine.on("tick", function()
  t = t + 1
  if t ~= 2 then return end
  -- All in one tick, so the police's own tick can't interleave.
  local far = 1000
  local one, five = time_to_lose(1, far, 120), time_to_lose(5, far, 120)
  check(one and math.abs(one - 3) < 0.1, string.format("1 star: lost after %.1f s out of sight, outside the area", one or -1))
  check(five and math.abs(five - 25) < 0.1, string.format("5 stars: lost after %.1f s", five or -1))
  local prev = one
  for s = 2, 5 do
    local secs = time_to_lose(s, far, 120)
    check(secs and secs > prev, string.format("%d stars take longer than %d: %.1f s", s, s - 1, secs or -1))
    prev = secs
  end
  local inside = time_to_lose(5, 10, 120)
  check(inside and math.abs(inside - 70) < 0.1, string.format("5 stars, hidden inside the area: they give up after %.1f s", inside or -1))
  local reset = time_to_lose(3, far, 120, 10)
  check(reset and math.abs(reset - 24) < 0.2,
        string.format("3 stars, seen again at 10 s: lost %.1f s in, the clock started over", reset or -1))
  check(time_to_lose(5, far, 10) == nil, "5 stars, 10 s of straight driving out of sight is not enough")
  wanted.clear()
  print("WANTED TEST PASSED")
  engine.quit()
end)
