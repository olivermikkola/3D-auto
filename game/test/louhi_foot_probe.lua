-- Louhi on foot (systems/louhi, docs/UNDERGROUND.md piece 3): from
-- Kauppatori through the stair house's door, down the stairs into the hall,
-- and back up and out onto the square; then at two stars an officer on the
-- square follows you down.
-- LOUHI_FOOT_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local Lh = require "systems.louhi"
local wanted = require "lib.wanted"
local police = require "systems.police"

local log = {}
local function check(ok, what)
  print(string.format("LOUHI_FOOT: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
end
local function finish()
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("LOUHI_FOOT: %d checks, %d failed", #log, bad))
  assert(bad == 0, "Louhi's stairs don't work")
  print("ALL LOUHI_FOOT CHECKS PASSED")
  engine.quit()
end

-- Walk toward the next point of the way, whatever the camera's heading.
local way, wi
input.move = function()
  if not way or not G.player then return 0, 0 end
  local x, _, z = engine.pos(G.player)
  local p = way[wi]
  local dx, dz = p[1] - x, p[2] - z
  local d = math.sqrt(dx * dx + dz * dz)
  if d < 0.8 and wi < #way then wi = wi + 1 end
  if d < 0.3 then return 0, 0 end
  dx, dz = dx / d, dz / d
  local fx, fz = U.forward(G.cam_yaw)
  local rx, rz = U.right(G.cam_yaw)
  return dx * fx + dz * fz, dx * rx + dz * rz
end
local function go(pts)
  way, wi = {}, 1
  for _, p in ipairs(pts) do way[#way + 1] = {Lh.hall_xz(p[1], p[2])} end
end
local function there(p, r)
  local x, _, z = engine.pos(G.player)
  local tx, tz = Lh.hall_xz(p[1], p[2])
  return U.dist2d(x, z, tx, tz) < (r or 1.2)
end

local step, t, sunk, crossed, officer = 0, 0, 0, 0, nil
local S, W2, IN_HALL

engine.on("underground_enter", function() crossed = crossed + 1 end)
engine.on("underground_exit", function() crossed = crossed + 1 end)

engine.on("tick", function(dt)
  if engine.ticks() < 30 or not G.player then return end
  if G.vehicle then return end
  t = t + dt
  local x, y, z = engine.pos(G.player)
  local layer = engine.layer(G.player)
  -- Never through the stairs' floor.
  local f = layer == 1 and Lh.area_floor(x, z, 0)
  if f then sunk = math.max(sunk, f - y) end
  if step == 0 then
    S = Lh.STAIRS
    check(Lh.built and S ~= nil, "the stairs are built")
    W2 = Lh.HALL.wid / 2
    check(S and S.ys > Lh.HALL_Y + 4 and S.ys < 12, string.format("they climb from the hall to the square at %.1f m", S and S.ys or 0))
    IN_HALL = {S.foot + 1.5, W2 - 8}
    -- On the square, 6 m out from the door.
    local sx, sz = Lh.hall_xz(S.door - 6, S.dc)
    engine.set_pos(G.player, sx, U.ground(sx, sz) + 1.2, sz)
    engine.set_vel(G.player, 0, 0, 0)
    go{{S.door - 1.5, S.dc}, {S.door + 0.5, S.dc}, {S.top - 0.3, S.mid}, {S.foot + 1.5, S.mid}, {S.foot + 1.5, W2 - 2}, IN_HALL}
    step, t = 1, 0
  elseif step == 1 then
    if there(IN_HALL) then
      check(layer == 1, "through the door, down the stairs: in layer 1")
      check(engine.view_layer() == 1, "and so is the view")
      check(math.abs(y - (Lh.HALL_Y + 0.9)) < 0.6, string.format("on the hall's floor (%.2f)", y))
      check(sunk < 0.5, string.format("never through the stairs (%.2f m at worst)", sunk))
      go{{S.foot + 1.5, W2 - 2}, {S.foot + 1.5, S.mid}, {S.top - 0.3, S.mid}, {S.door + 0.2, S.dc}, {S.door - 1.5, S.dc}, {S.door - 6, S.dc}}
      step, t = 2, 0
    elseif t > 40 then
      check(false, string.format("down into the hall in 40 s (at layer %d, %.1f %.1f %.1f)", layer, x, y, z))
      return finish()
    end
  elseif step == 2 then
    if there({S.door - 6, S.dc}) then
      check(layer == 0, "back up the stairs and out the door: on the square, layer 0")
      check(math.abs(y - (U.ground(x, z) + 0.9)) < 0.6, "on the ground")
      check(crossed == 2, string.format("crossed down and up once each (%d)", crossed))
      -- Wanted, and down you go; once you're through the door, an officer
      -- on the square after you.
      wanted.set(2)
      go{{S.door - 1.5, S.dc}, {S.door + 0.5, S.dc}, {S.top - 0.3, S.mid}, {S.foot + 1.5, S.mid}, {S.foot + 1.5, W2 - 2}, IN_HALL}
      step, t = 3, 0
    elseif t > 40 then
      check(false, string.format("back out in 40 s (at layer %d, %.1f %.1f %.1f)", layer, x, y, z))
      return finish()
    end
  elseif step == 3 then
    wanted.set(2)
    if not officer then
      if layer ~= 1 then return end
      local ox, oz = Lh.hall_xz(S.door - 14, S.dc + 3)
      officer = engine.spawn{mesh = "officer", pos = {ox, U.ground(ox, oz) + 1, oz}, size = {0.7, 1.8, 0.7}, body = "dynamic", mass = 85,
                             friction = 0, step = 0.45, lock_rotation = true, tag = "officer"}
      police.officers[officer] = {cool = 99}
      t = 0
    end
    if engine.exists(officer) and engine.layer(officer) == 1 then
      -- (Down the stairs, in the hall or at its door: within shot of you,
      -- they stop and shoot.)
      local ox, oy, oz = engine.pos(officer)
      local along, across = Lh.hall_ab(ox, oz)
      if oy < Lh.HALL_Y + 1.5 and along > S.foot - 1 and (across < W2 or U.dist2d(ox, oz, x, z) < 20) then
        check(true, string.format("an officer followed you down the stairs to the hall (%.0f s)", t))
        return finish()
      end
    end
    if t > 60 or not engine.exists(officer) then
      local ox, oy, oz = engine.pos(officer)
      check(false, string.format("an officer follows you down in 60 s (officer at layer %s, %s %s %s)",
                                 tostring(engine.layer(officer)), tostring(ox), tostring(oy), tostring(oz)))
      return finish()
    end
  end
end)
