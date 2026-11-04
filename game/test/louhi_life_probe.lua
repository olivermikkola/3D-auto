-- Louhi's cars coming and going (systems/louhi_life): you stand in a free
-- bay in the hall for six minutes; cars back out and drive away up the
-- tunnel, others come down and park, none gets stuck or tips over, nobody
-- runs into you, and the P1 sign's number is the free bays all along.
-- LOUHI_LIFE_TEST=1 MAP=turku
local G = require "lib.state"
local Lh = require "systems.louhi"
local life = require "systems.louhi_life"

local log = {}
local function check(ok, what)
  print(string.format("LOUHI_LIFE: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
end
local done = false
local function finish()
  if done then return end
  done = true
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("LOUHI_LIFE: %d checks, %d failed", #log, bad))
  assert(bad == 0, "Louhi's cars don't come and go")
  print("ALL LOUHI_LIFE CHECKS PASSED")
  engine.quit()
end

local t, start, stand = 0, nil, nil
local seen = {}      -- state -> times entered
local last = {}      -- id -> state
local still = {}     -- id -> seconds moving-state without moving
local wrong_sign, parked_after_in = 0, 0
local nearest = math.huge

engine.on("tick", function(dt)
  if done or engine.ticks() < 30 or not G.player or not Lh.built then return end
  if G.vehicle then return end
  if not start then
    -- In the middle row's first free bay well clear of the way in: stand there.
    for i, b in ipairs(Lh.bays) do
      if not life.occ[i] and math.abs(b.across) < 3 and b.along > Lh.mouth_along + 20 then stand = b break end
    end
    check(stand ~= nil, "a free bay to stand in")
    check(#life.cars == life.N, string.format("%d cars that come and go (%d)", life.N, #life.cars))
    local x, z = Lh.hall_xz(stand.along, stand.across)
    engine.set_layer(G.player, Lh.LAYER)
    Lh.took[G.player] = true
    engine.set_pos(G.player, x, Lh.HALL_Y + 1, z)
    engine.set_vel(G.player, 0, 0, 0)
    engine.view_layer(Lh.LAYER)
    start = {x, z}
    return
  end
  t = t + dt
  engine.set_vel(G.player, 0, 0, 0)
  local px, _, pz = engine.pos(G.player)
  for _, c in ipairs(life.cars) do
    if last[c.id] ~= c.state then
      seen[c.state] = (seen[c.state] or 0) + 1
      if c.state == "parked" and last[c.id] == "parking" then parked_after_in = parked_after_in + 1 end
      print(string.format("LOUHI_LIFE: %.0f s car %d %s -> %s", t, c.id, tostring(last[c.id]), c.state))
      last[c.id] = c.state
    end
    if life.moving[c.id] then
      local x, _, z = engine.pos(c.id)
      local sp = math.abs(require("lib.vehicle").speed(c.id))
      still[c.id] = sp < 0.2 and (still[c.id] or 0) + dt or 0
      if engine.layer(c.id) == Lh.LAYER then
        nearest = math.min(nearest, math.sqrt((x - px) ^ 2 + (z - pz) ^ 2))
      end
      if still[c.id] > 25 then
        check(false, string.format("car %d stuck 25 s (%s, at %.1f %.1f)", c.id, c.state, x, z))
        return finish()
      end
    end
  end
  if life.free_count() ~= life.shown() then wrong_sign = wrong_sign + 1 end
  if t > 360 then
    check(#life.cars == life.N, string.format("all %d still at it: none taken, tipped or wrecked (%d)", life.N, #life.cars))
    check((seen.backing or 0) >= 2, string.format("cars backed out of their bays (%d)", seen.backing or 0))
    check((seen.away or 0) >= 2, string.format("and went away up the tunnel (%d)", seen.away or 0))
    check((seen["in"] or 0) >= 1, string.format("cars came down the tunnel (%d)", seen["in"] or 0))
    check(parked_after_in >= 1, string.format("and parked in a free bay (%d)", parked_after_in))
    check(wrong_sign == 0, string.format("the sign showed the free bays all along (%d ticks wrong)", wrong_sign))
    local x, _, z = engine.pos(G.player)
    check(math.sqrt((x - start[1]) ^ 2 + (z - start[2]) ^ 2) < 0.5, "nobody pushed you out of your bay")
    check(nearest > 1.8, string.format("none drove into you (nearest %.1f m)", nearest))
    return finish()
  end
end)
