-- Shared game state. Modules read and write this; the engine never sees it.
return {
  player = nil,     -- entity id while on foot
  vehicle = nil,    -- entity id while driving
  cash = 0,
  cam_yaw = 0, cam_pitch = 0.25,
  city = nil,       -- layout from lib.city
  messages = {},    -- big centered text: {text, until}
}
