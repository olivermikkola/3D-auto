-- Physics toy: knock every crate off the plaza.
local G = require "lib.state"
local city = require "lib.city"
local U = require "lib.util"

if not city.has("plaza") then return false end

local px, pz = city.place("plaza")

return {
  title = "Demolition",
  start = {px + 15, pz - 21},
  reward = 400,
  run = function(m)
    local crates = {}
    for i = 0, 3 do
      for j = 0, 2 do
        for k = 0, 1 do
          crates[#crates + 1] = m:spawn{mesh = "crate", pos = {px - 3 + i * 1.6, 0.8 + k * 1.05 + U.ground(px - 3 + i * 1.6, pz - 2 + j * 1.6), pz - 2 + j * 1.6},
                                        size = 1, body = "dynamic", mass = 40, friction = 0.5, tag = "crate"}
        end
      end
    end
    for a = 0, 7 do
      local ang = a / 8 * math.pi * 2
      m:spawn{mesh = "cone", pos = {px + math.cos(ang) * 14, 0.6 + U.ground(px + math.cos(ang) * 14, pz + math.sin(ang) * 14), pz + math.sin(ang) * 14}, size = {0.6, 0.8, 0.6},
              body = "dynamic", mass = 5, tag = "cone"}
    end
    m:say("Smash every crate off the plaza. Bring a car.")
    m:timer(60)
    local half = 18
    m:wait(function()
      local left = 0
      for _, id in ipairs(crates) do
        local x, _, z = engine.pos(id)
        if math.abs(x - px) < half and math.abs(z - pz) < half then left = left + 1 end
      end
      m:say(string.format("Crates left on the plaza: %d", left))
      return left == 0
    end)
  end,
}
