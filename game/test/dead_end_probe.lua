-- Dead-end probe: every junction a road leads into must have a way back
-- out for traffic, or a car arriving there has nowhere to route.
local city = require "lib.city"

engine.on("init", function()
  if not city.network() then print("DEAD_END_PROBE: grid map, nothing to check"); return end
  local sinks, roads = {}, city.roads()
  for _, r in ipairs(roads) do
    local b = r[2]
    if #(city.links(b) or {}) == 0 then sinks[#sinks + 1] = b end
  end
  print(string.format("DEAD_END_PROBE: %d roads, %d lead into a junction with no way out", #roads, #sinks))
  -- Drive traffic's own turn-around through each one.
  local traffic = require "systems.traffic"
  for _, b in ipairs(sinks) do
    for _, a in ipairs(city.links_in(b)) do
      local c = {from = a, to = b}
      local ok, err = pcall(traffic._pick_next, c)
      assert(ok, string.format("traffic can't leave junction %s (from %s): %s", b, a, tostring(err)))
      assert(c.lost, string.format("car at dead end %s (from %s) not marked lost", b, a))
    end
  end
  print("DEAD_END_PROBE: PASSED")
end)
