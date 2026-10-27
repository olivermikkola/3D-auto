-- Player settings: kept in the "settings" save, applied the moment they
-- change. The pause menu lists them in this order; other modules read them
-- with settings.get(key).
local M = {}

M.list = {
  {key = "volume", label = "VOLUME", min = 0, max = 100, step = 10, default = 70, fmt = "%d%%"},
  {key = "sensitivity", label = "MOUSE SENSITIVITY", min = 1, max = 10, step = 1, default = 5},
  {key = "invert_y", label = "INVERT CAMERA Y", default = false},
  {key = "fov", label = "FIELD OF VIEW", min = 55, max = 100, step = 5, default = 70},
  {key = "fullscreen", label = "FULLSCREEN", default = false},
  -- Keep the controls on screen. Off by default: they show on the very
  -- first start, and F1 brings them back. (A new key: the old "help" was
  -- saved as on by everyone who ever changed any setting.)
  {key = "help_on", label = "HELP OVERLAY", default = false},
  -- One switch for slower and faster machines (a phone, a gaming PC): sets
  -- shadows and view distance below (each still yours to change after),
  -- and how many cars and people there are and the street furniture
  -- (lib/quality). MEDIUM is the game as it was before the switch.
  {key = "quality", label = "GRAPHICS QUALITY", min = 1, max = 3, step = 1, default = 2, names = {"LOW", "MEDIUM", "HIGH"},
   preset = {{shadows = false, view = 70}, {shadows = true, view = 100}, {shadows = true, view = 150}}},
  -- For slower GPUs: no shadow pass, and a shorter view (a share of the
  -- map's own fog distance; nothing past it is drawn). Faster ones can see
  -- twice as far (measured cheap on a Radeon 890M: docs/ROADMAP.md).
  {key = "shadows", label = "SHADOWS", default = true},
  {key = "view", label = "VIEW DISTANCE", min = 40, max = 200, step = 10, default = 100, fmt = "%d%%"},
  -- Clouds and rain now and then (lib/weather); off keeps it clear.
  {key = "weather", label = "WEATHER", default = true},
  -- On a town shown as a radar, up is the way you're looking (as in GTA);
  -- off, up is north.
  {key = "radar_turns", label = "RADAR TURNS WITH YOU", default = true},
}
local by_key, values, watchers = {}, {}, {}
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
  if key == "shadows" then engine.lighting{shadows = v} end
  for _, fn in ipairs(watchers[key] or {}) do fn(v) end
end

function M.get(key) return values[key] end

-- Call fn(value) now and whenever the setting changes.
function M.watch(key, fn)
  watchers[key] = watchers[key] or {}
  table.insert(watchers[key], fn)
  fn(values[key])
end

-- Change a setting (snapped into range), apply and save it.
function M.set(key, v)
  local s = assert(by_key[key], "unknown setting " .. tostring(key))
  v = fit(s, v)
  if v == nil or v == values[key] then return values[key] end
  values[key] = v
  apply(key, v)
  local ok, err = engine.save("settings", values)
  if not ok then print("settings: " .. err) end
  for k, pv in pairs(s.preset and s.preset[v] or {}) do M.set(k, pv) end
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
  if s.names then return s.names[v] end
  return string.format(s.fmt or "%d", v)
end

function M.reset()
  for _, s in ipairs(M.list) do M.set(s.key, s.default) end
end

local startup_fullscreen = engine.fullscreen()
local saved, err = engine.load("settings")
if err then print("settings: " .. err) end
for _, s in ipairs(M.list) do
  local v
  if type(saved) == "table" then v = fit(s, saved[s.key]) end
  if v == nil then v = s.default end
  -- A fullscreen launch overrides saved windowed mode for this session only.
  -- Keep values in sync so the menu can still switch back to windowed mode.
  if s.key == "fullscreen" and startup_fullscreen then v = true end
  values[s.key] = v
  apply(s.key, v)
end

return M
