-- Hunt down a black car somewhere in town and wreck it. It runs once hit.
local G = require "lib.state"
local H = require "lib.health"
local U = require "lib.util"
local city = require "lib.city"
local vehicle = require "lib.vehicle"
local traffic = require "systems.traffic"

if not city.has("takedown_start", "target_start") then return false end

return {
  title = "Takedown",
  after = "05_cargo",
  start = {city.place("takedown_start")},
  reward = 1500,
  run = function(m)
    local tx, tz = city.place("target_start")
    -- Not m:spawn: if you fail, it drives on as ordinary traffic.
    m.target = vehicle.spawn(tx, tz, 0, 6)
    local c = traffic.adopt(m.target, {keep = true})
    -- A red square follows it on the minimap.
    local blip = {id = m.target, color = {1, 0.2, 0.15}}
    G.markers[#G.markers + 1] = blip
    m:defer(function()
      c.keep, c.cruise = nil, nil
      for i, b in ipairs(G.markers) do if b == blip then table.remove(G.markers, i) break end end
    end)
    m:on("damaged", function(id)
      if id == m.target and not c.cruise then
        c.cruise = 21
        U.message("THE TARGET IS RUNNING", 3)
      end
    end)
    m:timer(180)
    m:wait(function()
      if not engine.exists(m.target) then return true end -- blew up
      local hp = H.get(m.target) or 0
      m:say(hp > 0 and string.format("Wreck the black car (red on the map). Its health: %d", math.ceil(hp))
            or "It's burning. Stand back!")
      return false
    end)
  end,
}
