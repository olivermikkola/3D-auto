-- Toriparkki on foot (systems/toriparkki, Oliver's map): through each of the
-- three pavilions' doors on Kauppatori (A, B, C), down the stairs into the
-- car park and back up and out; in at Forum's door on Eerikinkatu and
-- Wiklund's on Kauppiaskatu and along the ways under the streets into the
-- car park and back; from the car park along the way to Hansa and out its
-- door on Aurakatu; then at two stars an officer follows you down through B,
-- and another through Wiklund.
-- TORIPARKKI_FOOT_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local Lh = require "systems.louhi"
local tori = require "systems.toriparkki"
local wanted = require "lib.wanted"
local police = require "systems.police"

local log = {}
local done = false
local function check(ok, what)
  print(string.format("TORIPARKKI_FOOT: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
end
local function finish()
  if done then return end
  done = true
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("TORIPARKKI_FOOT: %d checks, %d failed", #log, bad))
  assert(bad == 0, "Toriparkki's stairs don't work")
  print("ALL TORIPARKKI_FOOT CHECKS PASSED")
  engine.quit()
end

-- Walk toward the next point of the way (in the hall's frame).
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

-- A core's points: out on the street, the door, down, and out the bottom
-- into the car park (along the way under the street, where there is one:
-- its route the other way).
local function pts(C)
  local d = C.door
  local function o(dist) if d.axis == "along" then return {d.at + d.out * dist, d.c} end return {d.c, d.at + d.out * dist} end
  local wm = (C.w0 + C.w1) / 2
  local out = o(5)
  local down = {o(1.5), o(-0.6), {C.ac(C.top - C.dir * 0.4, wm)}, {C.ac(C.foot + C.dir * 0.4, wm)}, {C.ac(C.sm, wm)}}
  if C.mouth then
    local r = C.route.pts
    for i = 3, 1, -1 do down[#down + 1] = r[i] end
  else
    down[#down + 1] = {C.ac(C.sm, C.exit_w + C.exit_out * 2.5)}
  end
  local below = down[#down]
  local up = {}
  for i = #down - 1, 1, -1 do up[#up + 1] = down[i] end
  up[#up + 1] = out
  return out, down, below, up
end

local ci, step, t, sunk, crossed, officer = 1, 0, 0, 0, 0, nil
engine.on("underground_enter", function() crossed = crossed + 1 end)
engine.on("underground_exit", function() crossed = crossed + 1 end)

engine.on("tick", function(dt)
  if done or engine.ticks() < 30 or not G.player or G.vehicle then return end
  t = t + dt
  local x, y, z = engine.pos(G.player)
  local layer = engine.layer(G.player)
  local f = layer == 1 and Lh.area_floor(x, z, 0, y)
  if f then sunk = math.max(sunk, f - y) end
  local C = tori.CORES[ci]
  if step == 0 then
    if ci == 1 then
      local n = 0
      for _, c in ipairs(tori.CORES) do if c.pavilion then n = n + 1 end end
      check(n == 3, string.format("three pavilions with stairs down (%d)", n))
      check(#tori.CORES == 5, string.format("and two at the far ends of the ways under the streets (%d)", #tori.CORES - n))
    end
    local out, down = pts(C)
    local sx, sz = Lh.hall_xz(out[1], out[2])
    engine.set_pos(G.player, sx, U.ground(sx, sz) + 1.4, sz)
    engine.set_vel(G.player, 0, 0, 0)
    go(down)
    step, t, sunk, crossed = 1, 0, 0, 0
  elseif step == 1 then
    local _, _, below = pts(C)
    if there(below) then
      check(layer == 1 and engine.view_layer() == 1, C.unit .. ": through the door and down the stairs: in layer 1")
      check(math.abs(y - (2 + 0.9)) < 0.6, string.format("%s: on the car park's floor (%.2f)", C.unit, y))
      check(sunk < 0.5, string.format("%s: never through the stairs (%.2f m at worst)", C.unit, sunk))
      local _, _, _, up = pts(C)
      go(up)
      step, t = 2, 0
    elseif t > 40 then
      check(false, string.format("%s: down into the car park in 40 s (layer %d, %.1f %.1f %.1f)", C.unit, layer, x, y, z))
      return finish()
    end
  elseif step == 2 then
    local out = pts(C)
    if there(out) then
      check(layer == 0, C.unit .. ": back up and out the door: on the square, layer 0")
      check(crossed == 2, string.format("%s: crossed down and up once each (%d)", C.unit, crossed))
      if ci < #tori.CORES then ci, step = ci + 1, 0 else step = 10 end
      t = 0
    elseif t > 40 then
      check(false, string.format("%s: back out in 40 s (layer %d, %.1f %.1f %.1f)", C.unit, layer, x, y, z))
      return finish()
    end
  elseif step == 10 then
    -- From the car park along the way to Hansa, through its level -1 and up
    -- and out its door on Aurakatu.
    local r = tori.hansa_route
    local sx, sz = Lh.hall_xz(r.pts[1][1], r.pts[1][2])
    engine.set_layer(G.player, 1)
    Lh.took[G.player] = true
    engine.view_layer(1)
    engine.set_pos(G.player, sx, 2 + 1, sz)
    engine.set_vel(G.player, 0, 0, 0)
    local d = r.door
    local w = {}
    for i = 2, #r.pts do w[#w + 1] = r.pts[i] end
    w[#w + 1] = {d.at + d.out * 0.3, d.c}
    w[#w + 1] = {d.at + d.out * 4, d.c}
    go(w)
    step, t, sunk, crossed = 11, 0, 0, 0
  elseif step == 11 then
    local d = tori.hansa_route.door
    if there({d.at + d.out * 4, d.c}, 1.5) then
      check(layer == 0, "from the car park to Hansa and out on Aurakatu: layer 0")
      check(sunk < 0.5, string.format("never through a floor on the way (%.2f m at worst)", sunk))
      ci, step, t = 2, 3, 0
    elseif t > 90 then
      check(false, string.format("to Hansa and out on Aurakatu in 90 s (layer %d, %.1f %.1f %.1f, along %.1f across %.1f)", layer, x, y, z, Lh.hall_ab(x, z)))
      return finish()
    end
  elseif step == 3 then
    -- Wanted, down through B; an officer on the square after you.
    local out, down = pts(C)
    local sx, sz = Lh.hall_xz(out[1], out[2])
    engine.set_layer(G.player, 0)   -- (up top first: after B you're still down there)
    Lh.took[G.player] = nil
    engine.view_layer(0)
    engine.set_pos(G.player, sx, U.ground(sx, sz) + 1.4, sz)
    engine.set_vel(G.player, 0, 0, 0)
    wanted.set(2)
    go(down)
    step, t = 4, 0
  elseif step == 4 then
    wanted.set(2)
    if not officer then
      if layer ~= 1 then
        if t > 40 then check(false, "down through B, wanted") return finish() end
        return
      end
      local out = pts(C)
      local ox, oz = Lh.hall_xz(out[1], out[2])
      officer = engine.spawn{mesh = "officer", pos = {ox, U.ground(ox, oz) + 1.4, oz}, size = {0.7, 1.8, 0.7}, body = "dynamic", mass = 85,
                             friction = 0, step = 0.45, lock_rotation = true, tag = "officer"}
      police.officers[officer] = {cool = 99}
      t = 0
    end
    if engine.exists(officer) and engine.layer(officer) == 1 then
      local _, oy = engine.pos(officer)
      if oy < 2 + 1.5 then
        check(true, string.format("an officer followed you down %s's stairs (%.0f s)", C.unit, t))
        if C.unit == "WIKLUND" then return finish() end
        engine.despawn(officer)
        police.officers[officer] = nil
        officer = nil
        ci, step, t = 5, 3, 0
        return
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
