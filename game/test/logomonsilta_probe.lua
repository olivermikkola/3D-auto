-- Logomonsilta on foot: the player runs from the station end's stairs up
-- into the tube, along it over the railway yard and down Logomo's end,
-- then back, and down to a platform; each run must get there, never
-- dropping off the deck on the way (out through the glass, through the
-- floor). LOGOMONSILTA_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local landmarks = require "systems.landmarks"

local T = landmarks.LOGOMONSILTA
local over = {T.stairs[1][2]}
for i = 1, #T.deck do over[#over + 1] = T.deck[i] end
over[#over + 1] = T.stairs[2][2]
local back = {}
for i = #over, 1, -1 do back[#back + 1] = over[i] end
local platform = {T.stairs[1][2], T.deck[1], T.deck[2], T.deck[3], T.deck[4], T.deck[5], T.deck[6], T.sides[1][2], T.stairs[3][2]}
local RUNS = {{"over to Logomo", over}, {"back to the station", back}, {"down to a platform", platform}}

local run, k, failed = nil, 0, 0

input.move = function()
  if not run or run.at or not G.player then return 0, 0 end
  local x, _, z = engine.pos(G.player)
  local p = run.way[run.i]
  local dx, dz = p[1] - x, p[2] - z
  local d = math.sqrt(dx * dx + dz * dz)
  if d < 1.5 and run.i < #run.way then run.i = run.i + 1 end
  if d < 1e-3 then return 0, 0 end
  dx, dz = dx / d, dz / d
  local fx, fz = U.forward(G.cam_yaw)
  local rx, rz = U.right(G.cam_yaw)
  return dx * fx + dz * fz, dx * rx + dz * rz
end
input.running = function() return run ~= nil end

local function start()
  k = k + 1
  local r = RUNS[k]
  if not r then
    print(string.format("LOGOMONSILTA: %d runs, %d failed", #RUNS, failed))
    assert(failed == 0, "a run over Logomonsilta didn't get there")
    print("ALL LOGOMONSILTA CHECKS PASSED")
    engine.quit()
    return
  end
  local a = r[2][1]
  engine.set_pos(G.player, a[1], U.ground(a[1], a[2]) + 1.2, a[2])
  engine.set_vel(G.player, 0, 0, 0)
  local len = 0
  for i = 2, #r[2] do len = len + U.dist2d(r[2][i - 1][1], r[2][i - 1][2], r[2][i][1], r[2][i][2]) end
  run = {name = r[1], way = r[2], i = 2, t = 0, limit = len / 3 + 8, low = math.huge, deck = 0}
end

engine.on("tick", function(dt)
  if G.vehicle or not G.player or engine.ticks() < 30 then return end
  if not run then return start() end
  run.t = run.t + dt
  local x, y, z = engine.pos(G.player)
  -- Up on the deck (past the stairs): how far below its floor it got.
  local up = run.i > 3 and run.i < #run.way - 1
  if up then
    run.deck = math.max(run.deck, y)
    run.low = math.min(run.low, y - run.deck)
  end
  local e = run.way[#run.way]
  local d = U.dist2d(x, z, e[1], e[2])
  if d < 1.5 and not run.at then run.at = run.t end
  if (run.at and (engine.grounded(G.player) or run.t > run.at + 1)) or run.t > run.limit then
    local ok = run.at ~= nil and math.abs(y - 0.9 - U.ground(e[1], e[2])) < 1.2 and run.low > -2 and run.deck > U.ground(e[1], e[2]) + 6
    print(string.format("LOGOMONSILTA: %s %s: %s in %.1f s, highest %.1f m over the end, worst drop %.1f m", ok and "ok" or "FAIL",
                        run.name, run.at and "there" or string.format("%.1f m short (at point %d of %d)", d, run.i, #run.way), run.t,
                        run.deck - U.ground(e[1], e[2]), run.low))
    if not ok then failed = failed + 1 end
    run = nil
  end
end)
