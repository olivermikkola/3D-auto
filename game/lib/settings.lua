-- Player settings: kept in the "settings" save, applied the moment they
-- change. The pause menu lists them in this order; other modules read them
-- with settings.get(key).
local M = {}

M.list = {
  {key = "volume", label = "VOLUME", min = 0, max = 100, step = 10, default = 70, fmt = "%d%%"},
  {key = "sensitivity", label = "MOUSE SENSITIVITY", min = 1, max = 10, step = 1, default = 5},
  {key = "invert_y", label = "INVERT MOUSE Y", default = false},
  {key = "fov", label = "FIELD OF VIEW", min = 55, max = 100, step = 5, default = 70},
  {key = "fullscreen", label = "FULLSCREEN", default = false},
  {key = "help", label = "HELP OVERLAY", default = true},
}
local by_key, values = {}, {}
for _, s in ipairs(M.list) do by_key[s.key] = s end

-- Snap a value to its setting's type, range and step; nil if it doesn't fit.
local function fit(s, v)
  if type(s.default) == "boolean" then
    if type(v) == "boolean" then return v end
    return nil
  end
  if type(v) ~= "number" or v ~= v then return nil end
  v = s.min + math.floor((v - s.min) / s.step + 0.5) * s.step
  return math.tointeger(math.max(s.min, math.min(s.max, v)))
end

local function apply(key, v)
  if key == "volume" then engine.volume(v / 100) end
  if key == "fullscreen" then engine.fullscreen(v) end
end

function M.get(key) return values[key] end

-- Change a setting (snapped into range), apply and save it.
function M.set(key, v)
  local s = assert(by_key[key], "unknown setting " .. tostring(key))
  v = fit(s, v)
  if v == nil or v == values[key] then return values[key] end
  values[key] = v
  apply(key, v)
  local ok, err = engine.save("settings", values)
  if not ok then print("settings: " .. err) end
  return v
end

-- Step a number up or down, or flip a switch.
function M.nudge(key, dir)
  local s = by_key[key]
  if type(s.default) == "boolean" then return M.set(key, not values[key]) end
  return M.set(key, values[key] + dir * s.step)
end

function M.text(key)
  local s, v = by_key[key], values[key]
  if type(s.default) == "boolean" then return v and "ON" or "OFF" end
  return string.format(s.fmt or "%d", v)
end

function M.reset()
  for _, s in ipairs(M.list) do M.set(s.key, s.default) end
end

local saved, err = engine.load("settings")
if err then print("settings: " .. err) end
for _, s in ipairs(M.list) do
  local v
  if type(saved) == "table" then v = fit(s, saved[s.key]) end
  if v == nil then v = s.default end
  values[s.key] = v
  apply(s.key, v)
end

return M
