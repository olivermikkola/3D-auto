-- The chase as the player meets it: with PROFILE_DRIVE (a robot driving
-- round town, wanted from PROFILE_DRIVE_WANTED s), notes each new police
-- car: how far from the player, whether it saw them in its first second,
-- and whether it came up behind them; and how long the stars lasted.
-- CHASE_TEST=1 PROFILE_DRIVE=1 PROFILE_DRIVE_WANTED=10 PROFILE_DRIVE_STARS=3 MAP=turku
-- (PROFILE_DRIVE_SPEED=26 to drive like a player; CHASE_TRACE=1: every 5 s.)
local G = require "lib.state"
local U = require "lib.util"
local P = require "systems.police"
local wanted = require "lib.wanted"
local known, n, seen1, behind, near, t, lost = {}, 0, 0, 0, 0, 0, {}
local wanted_t, seen_t = 0, 0
engine.on("tick", function(dt)
  t = t + dt
  local car = G.vehicle
  if not car then return end
  if wanted.stars() > 0 then
    wanted_t = wanted_t + dt
    if wanted.seen then seen_t = seen_t + dt end
  end
  local px, _, pz = engine.pos(car)
  local vx, _, vz = engine.vel(car)
  local v = math.sqrt(vx * vx + vz * vz)
  for id, c in pairs(P.cops) do
    if not known[id] then
      local x, _, z = engine.pos(id)
      local d = U.dist2d(x, z, px, pz)
      known[id] = {t = t}
      n = n + 1
      if d < 100 then near = near + 1 end
      if v > 3 and ((x - px) * vx + (z - pz) * vz) / (d * v) < -0.5 then behind = behind + 1 end
      print(string.format("CHASE: cop %d at %.0f m, %s", n, d, v > 3 and (((x - px) * vx + (z - pz) * vz) / (d * v) < -0.5 and "behind" or "ahead/side") or "player still"))
    elseif not known[id].done and t - known[id].t > 1 then
      known[id].done = true
      if c.sees then seen1 = seen1 + 1 end
    end
  end
end)
engine.on("wanted_changed", function(new, old)
  if new == 0 then lost[#lost + 1] = t end
  if os.getenv("CHASE_TRACE") then print(string.format("CHASE: %.0f s, %d -> %d stars", t, old or -1, new)) end
end)

engine.on("busted", function() print(string.format("CHASE: busted at %.0f s", t)) end)
local next_trace = 0
engine.on("tick", function()
  if not os.getenv("CHASE_TRACE") or t < next_trace or not G.vehicle then return end
  next_trace = t + 5
  local px, _, pz = engine.pos(G.vehicle)
  local nearest = math.huge
  for id in pairs(P.cops) do
    local x, _, z = engine.pos(id)
    if x then nearest = math.min(nearest, U.dist2d(x, z, px, pz)) end
  end
  print(string.format("CHASE: %3.0f s, %d stars, %s, unseen %.0f s, %.0f m from where seen, nearest cop %.0f m, %.1f m/s",
    t, wanted.stars(), wanted.seen and "seen" or "hidden", wanted.unseen_for, U.dist2d(px, pz, wanted.center[1], wanted.center[2]), nearest,
    (function() local vx, _, vz = engine.vel(G.vehicle); return math.sqrt(vx * vx + vz * vz) end)()))
end)
local P2 = {}
function P2.report() -- (printed by test/profile_drive at the end)
  print(string.format("CHASE: %d cops spawned, %d within 100 m, %d saw the player in their first second, %d behind; seen %.0f of %.0f s wanted, lost them %d times",
    n, near, seen1, behind, seen_t, wanted_t, #lost))
end
_G.__chase_report = P2.report
return P2
