-- Föli lines probe: Turku has its lines on its streets (lib/buslines), and
-- traffic's buses drive them: each on a line keeps to that line's streets,
-- junction after junction, while it has some of it left.
-- BUSLINES_TEST=1 MAP=turku auto game --headless 7200
local buslines = require "lib.buslines"
local T = require "systems.traffic"

local function check(ok, what)
  if not ok then engine.quit(); error("BUSLINES TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local function on_its_line(c)
  local js = c.line.js
  for k = 1, #js - 1 do
    if js[k] == c.from and js[k + 1] == c.to then return true end
  end
end

local t, seen, buses, samples, off = 0, {}, 0, 0, {}
engine.on("tick", function(dt)
  t = t + dt
  if t < 20 or math.floor((t - dt) / 2) == math.floor(t / 2) then return end
  for id, c in pairs(T.cars) do
    if c.is_bus then
      if not seen[id] then seen[id] = {lines = {}}; buses = buses + 1 end
      if c.line then
        seen[id].lines[c.line.line .. ">" .. c.line.to] = true
        samples = samples + 1
        if not on_its_line(c) then off[#off + 1] = string.format("%s>%s at junctions %d>%d", c.line.line, c.line.to, c.from, c.to) end
      end
    end
  end
  if t < 110 then return end
  local lines, on = #buslines.lines(), 0
  local names = {}
  for _, s in pairs(seen) do
    if next(s.lines) then on = on + 1 end
    for k in pairs(s.lines) do names[k] = true end
  end
  local list = {}
  for k in pairs(names) do list[#list + 1] = k end
  table.sort(list)
  print(string.format("BUSLINES_PROBE %d lines on the map; %d buses, %d of them on a line (%s); %d samples", lines, buses, on,
                      table.concat(list, ", "), samples))
  check(lines >= 140, "Föli's lines on Turku's streets")
  check(buses > 0 and on >= buses * 0.6, "most buses run a line")
  check(#off == 0, "each on its own line's streets" .. (off[1] and " (" .. #off .. ", first " .. off[1] .. ")" or ""))
  print("BUSLINES TEST PASSED")
  engine.quit()
end)
