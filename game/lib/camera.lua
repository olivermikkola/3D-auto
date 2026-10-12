-- Third-person orbit camera with chase behaviour in cars and wall avoidance.
local G = require "lib.state"
local settings = require "lib.settings"
local input = require "lib.input"
local U = require "lib.util"

local M = {}
local last_look = -10
local eye = nil

engine.on("frame", function(dt)
  local id = G.vehicle or G.player
  if engine.paused() or not id or not engine.exists(id) then return end
  local mx, my = engine.mouse()
  local sens = settings.get("sensitivity") * 0.0005
  if settings.get("invert_y") then my = -my end
  local kx, ky = input.look()
  if settings.get("invert_y") then ky = -ky end
  -- Sticks turn at up to 2.5 rad/s, scaled by the sensitivity setting like the mouse.
  local stick = 2.5 * settings.get("sensitivity") / 5
  if mx ~= 0 or my ~= 0 or kx ~= 0 or ky ~= 0 then last_look = engine.time() end
  G.cam_yaw = G.cam_yaw - mx * sens + kx * stick * dt
  G.cam_pitch = U.clamp(G.cam_pitch + my * sens + ky * stick * 0.6 * dt, -0.2, 1.2)

  local x, y, z = engine.pos(id)
  local dist, height = 6, 1.2
  if G.vehicle then
    dist, height = 10, 1.6
    -- Swing behind the car unless the player looked around recently.
    if engine.time() - last_look > 1.5 then
      local yaw = engine.yaw(id)
      if require("lib.vehicle").speed(id) < -1 then yaw = yaw + math.pi end
      G.cam_yaw = G.cam_yaw + U.angle_diff(G.cam_yaw, yaw) * math.min(1, dt * 3)
      G.cam_pitch = G.cam_pitch + (0.22 - G.cam_pitch) * math.min(1, dt * 2)
    end
  end
  local tx, ty, tz = x, y + height, z
  local fx, fz = U.forward(G.cam_yaw)
  local c = math.cos(G.cam_pitch)
  local dx, dy, dz = -fx * c, math.sin(G.cam_pitch), -fz * c
  -- Pull in if a wall is between the target and the camera.
  local hit, d = engine.raycast(tx, ty, tz, dx, dy, dz, dist, id)
  if hit then dist = math.max(1.0, d - 0.4) end
  local want = {tx + dx * dist, ty + dy * dist, tz + dz * dist}
  if not eye then eye = want end
  local k = math.min(1, dt * 12)
  for i = 1, 3 do eye[i] = eye[i] + (want[i] - eye[i]) * k end
  local fov = settings.get("fov")
  engine.camera(eye[1], eye[2], eye[3], tx, ty, tz, G.vehicle and fov + 7 or fov)
  G.cam_eye, G.cam_target = {eye[1], eye[2], eye[3]}, {tx, ty, tz}
end)

return M
