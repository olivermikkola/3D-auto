-- Streamed chunks (lib/roadnet streams: the buildings' walls): built near
-- the player, none far off; gone when the player has gone 3 km, back when
-- they return, and the city's mesh memory doesn't grow with the travelling.
-- STREAM_TEST=1 auto game --headless 2000   (MAP=turku)
local G = require "lib.state"
local U = require "lib.util"
local roadnet = require "lib.roadnet"

local function check(ok, what)
  if not ok then engine.quit(); error("STREAM TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local function wait(pred, timeout, what)
  local t = engine.time() + timeout
  while not pred() do
    if engine.time() > t then check(false, what .. " (timed out)") end
    coroutine.yield()
  end
end

local CHUNK = 300
local function walls() for _, s in ipairs(roadnet.streams()) do if s.name == "outline" then return s end end end

-- Built chunks: how many, and the farthest from (x, z) in chunks.
local function built(x, z)
  local n, far = 0, 0
  for k, id in pairs(walls().live) do
    if id then
      n = n + 1
      local ci, cj = k:match("([^,]+),([^,]+)")
      far = math.max(far, math.abs(tonumber(ci) - math.floor(x / CHUNK)), math.abs(tonumber(cj) - math.floor(z / CHUNK)))
    end
  end
  return n, far
end

local function move_player(x, z)
  local id = G.vehicle or G.player
  engine.set_pos(id, x, U.ground(x, z) + 1.5, z)
  engine.set_vel(id, 0, 0, 0)
end

local function script()
  local s = walls()
  check(s ~= nil, "the walls are streamed")
  local total = 0
  for _ in pairs(s.chunks) do total = total + 1 end
  local x, _, z = U.player_pos()
  local n, far = built(x, z)
  print(string.format("STREAM_PROBE: %d of %d chunks with buildings built at the start, farthest %d away", n, total, far))
  check(n > 0 and n < total, "some built, not all")
  check(far <= 5, "none far off")
  local home = {}
  for k, id in pairs(s.live) do if id then home[k] = true end end
  local meshes0 = engine.stats().meshes

  -- 3 km away (on a street, so on dry land).
  local e = roadnet.net().edges
  local best
  for _, ed in ipairs(e) do
    local p = ed.pts[1]
    local d = U.dist2d(p[1], p[2], x, z)
    if d > 3000 and d < 4000 and (not best or d < best[3]) then best = {p[1], p[2], d} end
  end
  move_player(best[1], best[2])
  wait(function()
    for k in pairs(home) do if s.live[k] then return false end end
    local n2 = built(best[1], best[2])
    return n2 > 0
  end, 20, "the walls by the start go and those here are built")
  local _, far2 = built(best[1], best[2])
  check(far2 <= 5, "none far off here either")

  move_player(x, z)
  wait(function()
    for k in pairs(home) do if s.live[k] == nil then return false end end
    return true
  end, 30, "back at the start, its walls are built again")
  check(engine.stats().meshes <= meshes0 + 200, string.format("meshes don't pile up (%d -> %d)", meshes0, engine.stats().meshes))
  print("STREAM_PROBE: PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if engine.ticks() < 3 or coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
