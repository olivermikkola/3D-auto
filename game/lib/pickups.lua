-- Glowing pickups around town: health, pistol ammo, and an SMG. They spin,
-- and come back 30 seconds after you take them.
local G = require "lib.state"
local U = require "lib.util"
local H = require "lib.health"
local city = require "lib.city"

local P = {spots = {}}
local KINDS = {
  health = {color = {0.2, 1, 0.3}, give = function() if H.player.hp >= H.player.max then return false end H.heal_player(50) return "+50 HEALTH" end},
  ammo = {color = {1, 0.85, 0.2}, give = function() G.ammo.pistol = G.ammo.pistol + 24 return "+24 PISTOL AMMO" end},
  smg = {color = {0.3, 0.6, 1}, give = function()
    G.ammo.smg = G.ammo.smg + 90
    G.weapon = "smg"
    return "SMG +90"
  end},
}

function P.build()
  engine.mesh("pickup_health", {
    {mesh = "cube", size = {0.7, 0.22, 0.22}, color = {1, 1, 1}},
    {mesh = "cube", size = {0.22, 0.7, 0.22}, color = {1, 1, 1}},
  })
  engine.mesh("pickup_box", {{mesh = "cube", size = {0.6, 0.4, 0.4}, color = {1, 1, 1}}})
end

function P.place(kind, x, z)
  local s = {kind = kind, x = x, z = z}
  P.spots[#P.spots + 1] = s
  return s
end

local function show(s)
  local k = KINDS[s.kind]
  s.id = engine.spawn{mesh = s.kind == "health" and "pickup_health" or "pickup_box", pos = {s.x, 1.0 + U.ground(s.x, s.z), s.z}, scale = 1,
                      color = k.color, glow = 0.8, tag = "pickup"}
end

function P.start()
  for _, s in ipairs(city.pickup_spots()) do P.place(s[1], s[2], s[3]) end
  for _, s in ipairs(P.spots) do show(s) end
end

engine.on("frame", function()
  local t = engine.time()
  for _, s in ipairs(P.spots) do
    if s.id then
      engine.set_yaw(s.id, t * 2)
      s.g = s.g or U.ground(s.x, s.z)
      engine.set_pos(s.id, s.x, s.g + 1.0 + math.sin(t * 3) * 0.15, s.z)
    end
  end
end)

engine.on("tick", function()
  local x, _, z = U.player_pos()
  if not x or G.dead then return end
  local now = engine.time()
  for _, s in ipairs(P.spots) do
    if s.id and U.dist2d(x, z, s.x, s.z) < 1.6 then
      local msg = KINDS[s.kind].give()
      if msg then
        engine.despawn(s.id)
        s.id, s.back = nil, now + 30
        engine.play("pickup")
        U.message(msg, 1.5)
        engine.emit("pickup", s.kind)
      end
    elseif not s.id and s.back and now >= s.back then
      show(s)
    end
  end
end)

return P
