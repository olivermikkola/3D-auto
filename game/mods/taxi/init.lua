-- Taxi: a side job, added as a mod. It brings its own car model, sound, and
-- mission; nothing in the base game knows it exists.
local mission = require "lib.mission"
local prefabs = require "lib.prefabs"
local vehicle = require "lib.vehicle"
local city = require "lib.city"
local cab = require "cab" -- this mod's own module (mods/taxi/cab.lua)

engine.on("init", function()
  local parts = prefabs.car_parts({0.98, 0.78, 0.1})
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.82, -0.3}, size = {0.7, 0.22, 0.3}, color = {1, 0.95, 0.6}, emissive = 1}
  engine.mesh("taxi", parts)
  engine.synth("fare", {wave = "sine", notes = {1568, 2093}, note_len = 0.09, volume = 0.35})

  -- The cab waits at the curb by the parking lot.
  local x, z = city.block_center(4, 3)
  cab.id = vehicle.spawn(x + 22, z - 10, 0, nil, "taxi")
end)

mission.register(require "job")
