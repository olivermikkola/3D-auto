-- Hiding in Logomo (systems/hideouts): wanted, the player walks in through
-- the door. Gone in unseen, the cops lose them in seconds; moving brings
-- them back out by the door, seen again; gone in with a cop watching, the
-- cops wait them out instead (wanted.give_up_time).
-- HIDEOUT_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local wanted = require "lib.wanted"
local H = require "systems.hideouts"

local step, t, door, walking, moving = 0, 0, nil, false, false -- steps: 1 in unseen, 2 inside, 4 out, 5 in seen, 6 inside
local log = {}
local function check(ok, what)
  print(string.format("HIDEOUT: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
end

input.move = function()
  if moving then return 1, 0 end
  if not walking or not G.player or not door then return 0, 0 end
  local x, _, z = engine.pos(G.player)
  local dx, dz = door.x - x, door.z - z
  local d = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
  dx, dz = dx / d, dz / d
  local fx, fz = U.forward(G.cam_yaw)
  local rx, rz = U.right(G.cam_yaw)
  return dx * fx + dz * fz, dx * rx + dz * rz
end

-- Wanted, standing 6 m out from the door, and walking to it; `watched`: a
-- cop has just seen them.
local function approach(watched)
  engine.set_pos(G.player, door.x + door.nx * 6, door.y + 1.2, door.z + door.nz * 6)
  engine.set_vel(G.player, 0, 0, 0)
  wanted.set(1)
  wanted.center = {door.x, door.z, door.y}
  walking, t = true, 0
  step = step + 1
  return watched
end

local watched, still
engine.on("tick", function(dt)
  if G.vehicle or not G.player or engine.ticks() < 30 then return end
  t = t + dt
  if step == 0 then
    door = H.list[1]
    assert(door, "no hideout on this map")
    check(door.name == "LOGOMO", "the door is Logomo's")
    watched = approach(false)
  -- (Who saw them is decided as they reach the door: police.lua's own tick
  -- may have spotted them on the way.)
  elseif not H.hidden() and step % 2 == 1 and t < 8 then
    wanted.seen = watched
    wanted.unseen_for = watched and 0 or 2
  elseif step == 1 then
    walking = false
    check(H.hidden(), "walked in through the door")
    check(H.hidden() and wanted.hiding == true, "in unseen: as good as away")
    step, t = 2, 0
  elseif step == 2 then
    if wanted.stars() == 0 or t > 20 then
      check(wanted.stars() == 0 and t < 3 + 3, string.format("lost the cops after %.1f s inside", t))
      moving, step, t = true, 4, 0
    end
  elseif step == 4 then
    if not H.hidden() or t > 4 then
      moving = false
      local x, _, z = engine.pos(G.player)
      check(not H.hidden() and U.dist2d(x, z, door.x, door.z) < 4, "came back out by the door on moving")
      t = 0
      watched = approach(true) -- step 5
      step = 5
    end
  elseif step == 5 then
    walking = false
    check(H.hidden() and not wanted.hiding, "walked in with a cop watching")
    step, t = 6, 0
  elseif step == 6 then
    if t > 12 and not still then
      still = true
      check(wanted.stars() > 0, "seen going in: still wanted after 12 s")
    end
    if wanted.stars() == 0 or t > wanted.give_up_time() + 10 then
      check(wanted.stars() == 0 and t > 12, string.format("they gave up after %.1f s (give-up time %d s)", t, wanted.give_up_time()))
      local bad = 0
      for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
      print(string.format("HIDEOUT: %d checks, %d failed", #log, bad))
      assert(bad == 0, "hiding in Logomo doesn't work")
      print("ALL HIDEOUT CHECKS PASSED")
      engine.quit()
    end
  end
end)
