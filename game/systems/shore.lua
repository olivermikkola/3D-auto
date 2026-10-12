-- The sea, the bay and the river stop you like a wall: drive or walk into
-- water (anywhere but a bridge) and you're put back where it was dry. Only
-- maps with surveyed water have any.
local G = require "lib.state"
local roadnet = require "lib.roadnet"

local dry = {} -- id -> last dry {x, y, z}

engine.on("tick", function()
  if not (G.city and G.city.network) then return end
  for _, id in ipairs{G.vehicle or G.player} do
    if engine.exists(id) then
      local x, y, z = engine.pos(id)
      if not roadnet.wet(x, z) then
        dry[id] = {x, y, z}
      elseif dry[id] then
        local d = dry[id]
        engine.set_pos(id, d[1], math.max(y, d[2]), d[3])
        local vx, vy, vz = engine.vel(id)
        engine.set_vel(id, -vx * 0.2, vy, -vz * 0.2)
      end
    end
  end
end)
