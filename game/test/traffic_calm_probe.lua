-- Traffic left to itself: the player stands about busy spots of town and
-- the probe counts what the traffic does on its own: crashes (by what hit
-- what, and bumps between vehicles at any speed), cars wrecked, explosions.
-- TRAFFIC_CALM_TEST=1 (MAP=turku). With PROFILE_DRIVE, counts during the
-- robot's drive (a chase with PROFILE_DRIVE_WANTED) and checks nothing.
local G = require "lib.state"
local U = require "lib.util"
local SPOTS = {{-150, 60}, {300, -200}, {-60, -250}, {200, 150}}
local SECS = tonumber(os.getenv("TRAFFIC_CALM_SECS") or "") or 60
local n = {booms = 0, killed = 0, damaged = 0}
local pairs_hit, bumps, bumped = {}, {}, {}
-- Bumps (any speed), once per pair a second: a bus nosing into the car
-- ahead at a light is no damage, but it's how cars end up on each other.
engine.on("contact", function(a, b, speed)
  local ta, tb = engine.tag(a) or "?", engine.tag(b) or "?"
  if not ({car = 1, bus = 1, cop = 1})[ta] or not ({car = 1, bus = 1, cop = 1})[tb] then return end
  local key, now = math.min(a, b) .. ":" .. math.max(a, b), engine.time()
  if (bumped[key] or -1) > now then return end
  bumped[key] = now + 1
  local k = ta < tb and ta .. "-" .. tb or tb .. "-" .. ta
  local T = require "systems.traffic"
  local parked = (ta == "car" and not T.cars[a]) or (tb == "car" and not T.cars[b])
  k = k .. (parked and " parked" or "") .. (speed >= 4 and " hard" or "")
  bumps[k] = (bumps[k] or 0) + 1
end)
engine.on("explosion", function() n.booms = n.booms + 1 end)
engine.on("killed", function(id, by)
  local t = engine.tag(id)
  if t == "car" or t == "cop" then
    n.killed = n.killed + 1
    print(string.format("TRAFFIC_CALM: %s killed by %s", t, by and engine.exists(by) and engine.tag(by) or "?"))
  end
end)
engine.on("damaged", function(id, amount, by)
  local a, b = engine.tag(id) or "?", by and engine.exists(by) and engine.tag(by) or "?"
  local k = a .. " by " .. b
  pairs_hit[k] = (pairs_hit[k] or 0) + amount
  n.damaged = n.damaged + amount
end)
local co = coroutine.create(function()
  -- (With PROFILE_DRIVE: wherever the robot drives, for SECS * 4 s.)
  for _, s in ipairs(SPOTS) do
    if not os.getenv("PROFILE_DRIVE") then engine.set_pos(G.player, s[1], U.ground(s[1], s[2]) + 1.5, s[2]) end
    local t = engine.time() + SECS
    while engine.time() < t do coroutine.yield() end
  end
  for k, v in pairs(bumps) do print(string.format("TRAFFIC_CALM: bumps %-14s %5d", k, v)) end
  for k, v in pairs(pairs_hit) do print(string.format("TRAFFIC_CALM: damage %-14s %5.0f", k, v)) end
  print(string.format("TRAFFIC_CALM: %d s at %d spots: %.0f damage, %d cars wrecked, %d explosions",
    SECS * #SPOTS, #SPOTS, n.damaged, n.killed, n.booms))
  if not os.getenv("PROFILE_DRIVE") then
    -- Before buses looked ahead from their nose and low enough to see a
    -- car: 176 bus-car bumps and 267 damage in the four minutes.
    local bus = (bumps["bus-car"] or 0) + (bumps["bus-car hard"] or 0)
    if bus > 80 then error("TRAFFIC_CALM: buses bump into cars " .. bus .. " times", 0) end
    if n.damaged > 120 or n.killed > 0 then error("TRAFFIC_CALM: traffic wrecks itself", 0) end
    print("TRAFFIC_CALM_OK")
  end
  engine.quit()
end)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
