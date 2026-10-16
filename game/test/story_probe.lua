-- The city radio picks the fragment that fits best, the same one for the
-- same state, never twice within its cooldown, and never chatters.
-- STORY_TEST=1 MAP=turku auto game --headless 30
local story = require "lib.story"

local function check(ok, what)
  if not ok then engine.quit(); error("STORY TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local heard = {}
engine.on("story", function(text, id) heard[#heard + 1] = {text = text, id = id} end)

local t = 0
engine.on("tick", function()
  t = t + 1
  if t ~= 2 then return end
  local function ctx(event, area, hour, stars, ...)
    return {event = event, area = area, street = "Lemminkäisenkatu", hour = hour or 12, stars = stars or 0, map = "turku", args = {...}}
  end
  story.reset()
  local a = story.pick(ctx("stunt", "Kupittaa", 12, 0, 1.2), 1000)
  local b = story.pick(ctx("stunt", "Kupittaa", 12, 0, 1.2), 1000)
  check(a and b and a.id == b.id, "the same state gives the same pick (" .. (a and a.id or "none") .. ")")
  check(a.id == "stunt_kupittaa", "a fragment for the place beats the general one")
  check(story.pick(ctx("stunt", "Port Arthur", 12, 0, 1.2), 1000).id == "stunt", "elsewhere the general one")
  check(story.pick(ctx("stunt", "Port Arthur", 12, 0, 4.5), 1000).id == "stunt_big", "a long jump gets its own line")
  check(story.pick(ctx("vehicle_enter", "Kupittaa", 1), 1000).id == "night_drive", "night driving after 23:00")
  check(story.pick(ctx("vehicle_enter", "Kupittaa", 15), 1000) == nil, "and nothing for it at three in the afternoon")
  check(story.pick(ctx("wanted_changed", "Kupittaa", 12, 0, 0, 3), 1000).id == "lost_cops", "losing three stars is news")
  check(story.pick(ctx("wanted_changed", "Kupittaa", 12, 1, 1, 0), 1000) == nil, "gaining one isn't (the dispatcher has that)")
  local s = story.text(story.pick(ctx("carjacked", "Kupittaa"), 1000), ctx("carjacked", "Kupittaa"))
  check(s:find("Lemminkäisenkatu", 1, true), "the line names the street: " .. s)

  -- Through the real events: one line, then quiet for the gap, then a
  -- different one (the first is cooling down).
  story.reset()
  engine.emit("stunt", 1.5, 3, 0)
  check(#heard == 1, "a stunt gets a line on the radio: " .. (heard[1] and heard[1].text or "none"))
  engine.emit("explosion", 0, 0, 0)
  check(#heard == 1, "but not another straight after")
  print("STORY TEST PASSED")
  engine.quit()
end)
