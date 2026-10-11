-- Every sound in the game is synthesized at load: no audio files needed.
-- Engines are looping voices whose pitch follows speed; one-shots react to
-- the event bus (contacts, missions, stunts).
local G = require "lib.state"
local vehicle = require "lib.vehicle"

local S = {}

function S.build()
  engine.synth("engine", {wave = "saw", freq = 55, dur = 0.5, loop = true, volume = 0.35, lowpass = 0.35})
  engine.synth("crash", {wave = "noise", freq = 3000, freq_end = 300, dur = 0.45, release = 0.35, volume = 0.9, lowpass = 0.6})
  engine.synth("thud", {wave = "noise", freq = 800, freq_end = 200, dur = 0.15, release = 0.12, volume = 0.6, lowpass = 0.3})
  engine.synth("horn", {wave = "square", freq = 330, dur = 0.5, attack = 0.01, release = 0.05, volume = 0.25, lowpass = 0.4})
  engine.synth("jump", {wave = "square", freq = 220, freq_end = 520, dur = 0.12, volume = 0.2, lowpass = 0.5})
  engine.synth("door", {wave = "noise", freq = 1200, dur = 0.08, release = 0.06, volume = 0.5, lowpass = 0.4})
  engine.synth("ding", {wave = "sine", freq = 1320, dur = 0.35, release = 0.3, volume = 0.5})
  engine.synth("pass", {wave = "square", notes = {523, 659, 784, 1046, 784, 1046}, note_len = 0.11, volume = 0.25, lowpass = 0.5})
  engine.synth("fail", {wave = "square", notes = {392, 330, 262, 196}, note_len = 0.18, volume = 0.25, lowpass = 0.5})
  engine.synth("siren", {wave = "square", notes = {740, 990}, note_len = 0.45, attack = 0.02, release = 0.02, volume = 0.12, lowpass = 0.35})
  engine.synth("star", {wave = "square", freq = 880, freq_end = 1320, dur = 0.12, volume = 0.2, lowpass = 0.6})
  engine.synth("stunt", {wave = "triangle", notes = {659, 784, 988, 1319}, note_len = 0.07, volume = 0.4})
end

-- One looping engine voice per car within earshot.
local voices = {}

local function update_engines()
  local px, py, pz = engine.camera_pos()
  local cars = engine.find("car")
  for _, id in ipairs(engine.find("cop")) do cars[#cars + 1] = id end
  for _, id in ipairs(cars) do
    local x, y, z = engine.pos(id)
    local near = (x - px) ^ 2 + (z - pz) ^ 2 < 70 ^ 2
    local v = voices[id]
    if near and not v then
      v = engine.play("engine", {loop = true, follow = id, volume = 0})
      voices[id] = v
    elseif not near and v then
      engine.stop(v)
      voices[id], v = nil, nil
    end
    if v then
      local speed = math.abs(vehicle.speed(id))
      local mine = id == G.vehicle
      local rev = mine and engine.key("w") and 0.25 or 0
      local air = mine and not vehicle.on_wheels(id) and 0.35 or 0 -- free-spinning wheels
      engine.set_voice(v, {pitch = 0.7 + speed / vehicle.MAX_SPEED * 1.6 + rev + air, volume = mine and 0.8 or 0.35})
    end
  end
  for id, v in pairs(voices) do
    if not engine.exists(id) then engine.stop(v); voices[id] = nil end
  end
end

engine.on("frame", update_engines)

engine.on("contact", function(a, b, speed)
  if speed < 4 then return end
  local ta, tb = engine.tag(a), engine.tag(b)
  if ta ~= "car" and tb ~= "car" and ta ~= "crate" and tb ~= "crate" then return end
  local x, y, z = engine.pos(ta == "car" and a or b)
  local loud = math.min(1, speed / 15)
  engine.play(speed > 8 and "crash" or "thud", {pos = {x, y, z}, volume = loud, pitch = 0.8 + math.random() * 0.4})
end)

engine.on("key", function(k, down)
  if not down then return end
  if k == "h" and G.vehicle then engine.play("horn", {follow = G.vehicle}) end
  if k == "space" and G.player and engine.grounded(G.player) then engine.play("jump", {volume = 0.6}) end
  if k == "e" then engine.play("door", {volume = 0.7}) end
end)

engine.on("mission_passed", function() engine.play("pass") end)
engine.on("mission_failed", function() engine.play("fail") end)
engine.on("checkpoint", function() engine.play("ding") end)
engine.on("stunt", function() engine.play("stunt") end)
engine.on("wanted_changed", function(new, old) if new > old then engine.play("star", {volume = 0.7}) end end)
engine.on("busted", function() engine.play("fail") end)

return S
