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

  -- The cab waits at the curb at the map's taxi rank (by the lot if it has none).
  local x, z
  if city.has("taxi_rank") then x, z = city.place("taxi_rank") else x, z = city.place("lot") end
  cab.id = vehicle.spawn(x, z, -math.pi / 2, nil, "taxi")
end)

mission.register(require "job")
