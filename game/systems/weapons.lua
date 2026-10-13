-- Player weapons. Aim with the camera; shots trace from the player's chest
-- to whatever the crosshair is on, so walls and cars are real cover.
-- 1/2/3 or Q pick a weapon; left mouse or F fires.
local G = require "lib.state"
local U = require "lib.util"
local H = require "lib.health"
local FX = require "lib.fx"

local W = {}
W.defs = {
  fists = {name = "FISTS", melee = true, rate = 0.45, damage = 15, range = 1.9},
  pistol = {name = "PISTOL", rate = 0.3, damage = 22, spread = 0.008, sound = "pistol"},
  smg = {name = "SMG", rate = 0.09, damage = 10, spread = 0.03, auto = true, sound = "smg"},
}
W.order = {"fists", "pistol", "smg"}
G.weapon = "pistol"
G.ammo = {pistol = 36, smg = 0}

local cooldown = 0
local held = false

function W.has(w) return w == "fists" or (G.ammo[w] or 0) > 0 end

function W.select(w)
  if W.defs[w] and W.has(w) then G.weapon = w end
end

-- What the crosshair is pointing at, out to 150 m.
function W.aim_point()
  local e, t = G.cam_eye, G.cam_target
  if not e then return end
  local dx, dy, dz = t[1] - e[1], t[2] - e[2], t[3] - e[3]
  local l = math.sqrt(dx * dx + dy * dy + dz * dz)
  dx, dy, dz = dx / l, dy / l, dz / l
  local hit, d = engine.raycast(e[1], e[2], e[3], dx, dy, dz, 150, G.player)
  d = hit and d or 150
  return e[1] + dx * d, e[2] + dy * d, e[3] + dz * d
end

local function report_gunfire(x, z)
  require("systems.peds").scare(x, z, 35)
  -- Gunfire with witnesses around is a crime.
  local wanted = require "lib.wanted"
  if engine.nearest(x, 1, z, 30, "ped") or engine.nearest(x, 1, z, 70, "cop") or engine.nearest(x, 1, z, 50, "officer") then
    if wanted.stars() == 0 then wanted.set(1) end
  end
end

local function melee()
  local x, y, z = engine.pos(G.player)
  local fx, _, fz = engine.forward(G.player)
  for _, tag in ipairs{"ped", "officer"} do
    local id, d = engine.nearest(x + fx, y, z + fz, W.defs.fists.range, tag)
    if id then
      engine.play("punch", {pos = {x, y, z}})
      H.damage(id, W.defs.fists.damage, G.player, fx, 0.3, fz)
      local vx, vy, vz = engine.vel(id)
      if vx then engine.set_vel(id, vx + fx * 3, vy + 1, vz + fz * 3) end
      return true
    end
  end
  engine.play("swing", {pos = {x, y, z}, volume = 0.5})
end

-- Fire the current weapon at a world point. Used by input and by tests.
function W.fire_at(ax, ay, az)
  local def = W.defs[G.weapon]
  if not G.player or G.dead or cooldown > 0 then return false end
  cooldown = def.rate
  if def.melee then return melee() end
  if (G.ammo[G.weapon] or 0) <= 0 then
    engine.play("click")
    return false
  end
  G.ammo[G.weapon] = G.ammo[G.weapon] - 1

  local px, py, pz = engine.pos(G.player)
  local ox, oy, oz = px, py + 0.5, pz
  local dx, dy, dz = ax - ox, ay - oy, az - oz
  local l = math.sqrt(dx * dx + dy * dy + dz * dz) + 1e-6
  local s = def.spread
  dx = dx / l + (math.random() - 0.5) * s * 2
  dy = dy / l + (math.random() - 0.5) * s * 2
  dz = dz / l + (math.random() - 0.5) * s * 2
  engine.set_yaw(G.player, math.atan(dx, dz))
  local mx, my, mz = ox + dx * 0.6, oy + dy * 0.6, oz + dz * 0.6

  local hit, dist, hx, hy, hz = engine.raycast(ox, oy, oz, dx, dy, dz, 150, G.player)
  if not hit then hx, hy, hz = ox + dx * 150, oy + dy * 150, oz + dz * 150 end
  FX.flash(mx, my, mz, 0.3)
  FX.tracer(mx, my, mz, hx, hy, hz)
  engine.play(def.sound, {pos = {px, py, pz}, pitch = 0.95 + math.random() * 0.1})
  if hit then
    local tag = engine.tag(hit)
    if tag == "ped" or tag == "officer" then
      FX.burst(hx, hy, hz, 6, {0.5, 0.02, 0.02}, 3, 0.6, 0.08)
      H.damage(hit, def.damage, G.player, dx, dy, dz)
    elseif tag == "car" or tag == "cop" then
      FX.burst(hx, hy, hz, 5, {1, 0.85, 0.4}, 5, 0.25, 0.05, 1.5)
      H.damage(hit, def.damage * 0.5, G.player, dx, dy, dz)
    else
      FX.burst(hx, hy, hz, 4, {0.6, 0.58, 0.55}, 3, 0.4, 0.06)
      local vx, vy, vz = engine.vel(hit)
      if vx then engine.push(hit, dx * 40, dy * 40, dz * 40, hx, hy, hz) end
    end
  end
  report_gunfire(px, pz)
  engine.emit("gunshot", G.player, hit)
  return true
end

engine.on("key", function(k, down)
  if k == "mouse1" or k == "f" then held = down end
  if not down then return end
  if k == "1" then W.select("fists") elseif k == "2" then W.select("pistol") elseif k == "3" then W.select("smg")
  elseif k == "q" or k == "q_back" then
    -- Next weapon you have (the gamepad's LB goes the other way).
    local i, dir = 1, k == "q" and 1 or -1
    for n, w in ipairs(W.order) do if w == G.weapon then i = n end end
    local was = G.weapon
    for step = 1, #W.order do
      local w = W.order[(i - 1 + dir * step) % #W.order + 1]
      if W.has(w) then G.weapon = w break end
    end
    -- Nothing else to switch to: say why instead of doing nothing.
    if G.weapon == was then U.message("NO AMMO: BUY SOME AT THE GUN SHOP (G)", 2) end
  end
  if (k == "mouse1" or k == "f") and G.player then
    local x, y, z = W.aim_point()
    if x then W.fire_at(x, y, z) end
  end
end)

engine.on("tick", function(dt)
  cooldown = math.max(0, cooldown - dt)
  if not W.has(G.weapon) then G.weapon = "fists" end
  if held and W.defs[G.weapon].auto and G.player and cooldown == 0 then
    local x, y, z = W.aim_point()
    if x then W.fire_at(x, y, z) end
  end
end)

return W
