-- Wanted level: 0-5 stars. Crimes raise it; systems.police enforces it.
-- Missions and mods can call wanted.set/add directly.
local G = require "lib.state"
local U = require "lib.util"

local W = {level = 0, heat = 0, seen = true, center = {0, 0}, unseen_for = 0}

local function changed(old)
  if W.level ~= old then engine.emit("wanted_changed", W.level, old) end
end

function W.stars() return W.level end

function W.set(n)
  local old = W.level
  W.level = U.clamp(math.floor(n), 0, 5)
  W.heat = math.max(W.heat, W.level)
  if W.level > 0 and old == 0 then
    -- Fresh pursuit starts where the player is.
    local x, y, z = U.player_pos()
    if x then W.center = {x, z, y} end
    W.seen, W.unseen_for = true, 0
  end
  changed(old)
end

function W.add(n) W.set(math.min(5, W.level + n)) end

function W.clear()
  local old = W.level
  W.level, W.heat, W.unseen_for = 0, 0, 0
  changed(old)
end

-- Fractional heat for small crimes; every whole point is a star.
function W.heat_up(amount)
  W.heat = math.min(5, W.heat + amount)
  if math.floor(W.heat) > W.level then W.set(W.heat) end
end

-- Radius of the search area the player must escape, in meters.
function W.radius() return 40 + 25 * W.level end

-- Seconds out of sight it takes to lose the cops once outside the search
-- area: 3 at one star, 25 at five. Hidden anywhere, they give up after
-- 30 s at one star, 70 s at five.
function W.escape_time() return 3 + 5.5 * (math.max(W.level, 1) - 1) end
function W.give_up_time() return 30 + 10 * (math.max(W.level, 1) - 1) end

-- One tick in which no cop sees the player at px, pz. True when that was
-- enough to lose them (the level is cleared).
function W.unseen(dt, px, pz)
  W.seen = false
  W.unseen_for = W.unseen_for + dt
  local outside = U.dist2d(px, pz, W.center[1], W.center[2]) > W.radius()
  if (outside and W.unseen_for > W.escape_time()) or W.unseen_for > W.give_up_time() then
    W.clear()
    return true
  end
  return false
end

-- ---- crimes ------------------------------------------------------------

engine.on("carjacked", function() if W.level < 1 then W.set(1) end end)

local recent = {}
engine.on("contact", function(a, b, speed)
  local me = G.vehicle
  -- Only crashes the player causes: their car has to be the one moving.
  if not me or (a ~= me and b ~= me) or speed < 6 then return end
  if math.abs(require("lib.vehicle").speed(me)) < 5 then return end
  local other = a == me and b or a
  local now = engine.time()
  if (recent[other] or 0) > now then return end
  recent[other] = now + 1.5
  if engine.tag(other) == "cop" then
    W.add(1)
  elseif engine.tag(other) == "car" and speed > 10 then
    W.heat_up(0.4)
  end
end)

return W
