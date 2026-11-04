-- Hansa's lower floor (systems/hansa, docs/UNDERGROUND.md piece 4): from
-- Louhi's hall on foot out its west end, into Hansa's level -1, along it,
-- up the stairs and out the door on Aurakatu; back in and down to Louhi;
-- then at two stars an officer on Aurakatu follows you in and down.
-- HANSA_TEST=1 MAP=turku
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local Lh = require "systems.louhi"
local Hs = require "systems.hansa"
local wanted = require "lib.wanted"
local police = require "systems.police"

local log = {}
local function check(ok, what)
  print(string.format("HANSA: %s %s", ok and "ok" or "FAIL", what))
  log[#log + 1] = ok
end
local function finish()
  local bad = 0
  for _, ok in ipairs(log) do if not ok then bad = bad + 1 end end
  print(string.format("HANSA: %d checks, %d failed", #log, bad))
  assert(bad == 0, "Hansa's lower floor doesn't work")
  print("ALL HANSA CHECKS PASSED")
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
input.running = function() return way ~= nil end
local function go(pts)
  way, wi = {}, 1
  for _, p in ipairs(pts) do way[#way + 1] = {Lh.hall_xz(p[1], p[2])} end
end
local function there(p, r)
  local x, _, z = engine.pos(G.player)
  local tx, tz = Lh.hall_xz(p[1], p[2])
  return U.dist2d(x, z, tx, tz) < (r or 1.2)
end

local step, t, sunk, officer = 0, 0, 0, nil
local IN_HALL, OUT, INSIDE
local crossed = 0
engine.on("underground_enter", function() crossed = crossed + 1 end)
engine.on("underground_exit", function() crossed = crossed + 1 end)

engine.on("tick", function(dt)
  if engine.ticks() < 30 or not G.player or G.vehicle then return end
  t = t + dt
  local x, y, z = engine.pos(G.player)
  local layer = engine.layer(G.player)
  local f = layer == 1 and Lh.area_floor(x, z, 0, y)
  if f then sunk = math.max(sunk, f - y) end
  local top = Hs.top
  local WAY = {{-112, 12.8}, {-112, 64}, {-48, 64}, {-48, top + 1}, {-48, 100.8}, {-12, 100.8}, {-6.5, 100.8}}
  if step == 0 then
    check(Lh.built and Hs.door ~= nil, "Hansa's lower floor is built")
    check(Hs.G0 > 4 and Hs.G0 < 8, string.format("its door on Aurakatu, the street at %.1f m", Hs.G0 or 0))
    IN_HALL = {-90, 10}
    OUT = {-3, 100.8}
    -- In the hall, by its west end, on foot.
    local sx, sz = Lh.hall_xz(IN_HALL[1], IN_HALL[2])
    engine.set_layer(G.player, 1)
    Lh.took[G.player] = true
    engine.set_pos(G.player, sx, Lh.HALL_Y + 1, sz)
    engine.set_vel(G.player, 0, 0, 0)
    local pts = {{-95, 12.8}}
    for _, p in ipairs(WAY) do pts[#pts + 1] = p end
    pts[#pts + 1] = OUT
    go(pts)
    step, t = 1, 0
  elseif step == 1 then
    if there(OUT) then
      check(layer == 0, string.format("through Hansa and out the door on Aurakatu: up top (%.0f s)", t))
      check(engine.view_layer() == 0, "and so is the view")
      check(math.abs(y - (U.ground(x, z) + 0.9)) < 0.6, "on the street")
      check(sunk < 0.5, string.format("never through a floor (%.2f m at worst)", sunk))
      local back = {}
      for i = #WAY, 1, -1 do back[#back + 1] = WAY[i] end
      back[#back + 1] = {-95, 12.8}
      back[#back + 1] = IN_HALL
      table.insert(back, 1, {-8.4, 100.8})
      go(back)
      step, t = 2, 0
    elseif t > 90 then
      check(false, string.format("out on Aurakatu in 90 s (layer %d, %.1f %.1f %.1f; at point %d)", layer, x, y, z, wi))
      return finish()
    end
  elseif step == 2 then
    if there(IN_HALL) then
      check(layer == 1 and math.abs(y - (Lh.HALL_Y + 0.9)) < 0.6, string.format("back in and down in Louhi's hall (%.0f s)", t))
      check(crossed == 2, string.format("out and in once each (%d)", crossed))
      wanted.set(2)
      way = nil
      step, t = 3, 0
    elseif t > 90 then
      check(false, string.format("back down in 90 s (layer %d, %.1f %.1f %.1f; at point %d)", layer, x, y, z, wi))
      return finish()
    end
  elseif step == 3 then
    wanted.set(2)
    if not officer then
      local ox, oz = Lh.hall_xz(OUT[1] + 6, OUT[2] + 4)
      officer = engine.spawn{mesh = "officer", pos = {ox, U.ground(ox, oz) + 1, oz}, size = {0.7, 1.8, 0.7}, body = "dynamic", mass = 85,
                             friction = 0, step = 0.45, lock_rotation = true, tag = "officer"}
      police.officers[officer] = {cool = 99}
      t = 0
    end
    if engine.exists(officer) and engine.layer(officer) == 1 then
      local ox, oy, oz = engine.pos(officer)
      if U.dist2d(ox, oz, x, z) < 25 and math.abs(oy - y) < 2 then
        check(true, string.format("an officer followed you in at Aurakatu and down to Louhi (%.0f s)", t))
        return finish()
      end
    end
    if t > 120 or not engine.exists(officer) then
      local ox, oy, oz = engine.pos(officer)
      local oa, oc = Lh.hall_ab(ox or 0, oz or 0)
      check(false, string.format("an officer follows you down in 120 s (layer %s, along %.1f across %.1f, y %s)",
                                 tostring(engine.layer(officer)), oa, oc, tostring(oy)))
      return finish()
    end
  end
end)
