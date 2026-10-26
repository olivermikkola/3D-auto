-- Traffic lights that change, and traffic that stops for them. Each
-- junction with lights (lib/roadnet: R.signals) runs two phases: the roads
-- lined up with its `base` heading, then the ones across, each GREEN s of
-- green and AMBER of amber with ALL_RED of red both ways between, offset
-- per junction so a street's lights don't all change at once. The posts
-- near the player show it (their mesh swapped); systems/traffic asks
-- S.state before driving into a junction.
local U = require "lib.util"
local roadnet = require "lib.roadnet"

-- S.off: every light as if it weren't there (the drive sweep checks the
-- roads, not the waiting).
local S = {off = false}
local GREEN, AMBER, ALL_RED = 14, 3, 2
local HALF = GREEN + AMBER + ALL_RED
local CYCLE = 2 * HALF
local SHOWN = 260 -- posts updated within this of the player (m)

-- Which of a junction's two phases a heading belongs to: 0 lined up with
-- its base road, 1 across it.
local function phase_of(ctl, heading)
  return math.abs(math.cos(heading - ctl.base)) >= 0.7071 and 0 or 1
end

-- The light for traffic heading `heading` (radians, as math.atan(dx, dz))
-- into junction j: "green", "amber" or "red"; nil if j has no lights.
function S.state(j, heading)
  local ctl = not S.off and roadnet.signals().junctions[j]
  if not ctl then return nil end
  local t = (engine.time() + ctl.offset) % CYCLE - phase_of(ctl, heading) * HALF
  if t < 0 then t = t + CYCLE end
  if t < GREEN then return "green" elseif t < GREEN + AMBER then return "amber" end
  return "red"
end

-- How far from junction j's middle traffic waits (m), or nil.
function S.stop_line(j)
  local ctl = roadnet.signals().junctions[j]
  return ctl and ctl.stop
end

-- For tests: run junction j's lights from now so that traffic heading
-- `heading` has `state` ("green" or "red") for a good while.
function S.force(j, heading, state)
  local ctl = roadnet.signals().junctions[j]
  local mine = phase_of(ctl, heading) * HALF
  local want = state == "green" and mine + 1 or (mine + HALF + 1) % CYCLE
  ctl.offset = (want - engine.time()) % CYCLE
end

local shown = {} -- post id -> the mesh it shows
local next_update = 0
engine.on("tick", function()
  if S.off or engine.time() < next_update then return end
  next_update = engine.time() + 0.25
  local px, _, pz = U.player_pos()
  if not px then return end
  for _, p in ipairs(roadnet.signals().posts) do
    if math.abs(p.x - px) < SHOWN and math.abs(p.z - pz) < SHOWN and engine.exists(p.id) and engine.tag(p.id) == "signal" then
      local mesh = "signal_" .. S.state(p.junction, p.yaw)
      if shown[p.id] ~= mesh then
        engine.set_mesh(p.id, mesh)
        shown[p.id] = mesh
      end
    end
  end
end)

return S
