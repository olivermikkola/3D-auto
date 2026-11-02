-- Föli's bus lines on the map's own streets (maps/<map>_bus.lua, made by
-- tools/foli_lines.py from Föli's open timetable data): the junctions each
-- line runs through in order, for traffic's buses to drive (systems/traffic),
-- and a bus for each with its number and where it's going on its boards.
--
--   L.at(a, b)        -- a line running junction a to b, and where on it: line, k (deterministic)
--   L.near(x, z, r)   -- the line streets with an end within r of (x, z): {a, b, line, k}, ...
--   L.mesh(line)      -- the line's bus's mesh name
--
-- A line is {line = "6", to = "Naantali", color, trips, js = {junction ids}};
-- one that doesn't run on this map's streets as built (a renamed junction)
-- is left out, and said so.
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"

local L = {}
local data -- {map, lines, on = {["a>b"] = line * 4096 + k}} (one number a street: no table each)

local function linked(a, b)
  for _, n in ipairs(city.links(a) or {}) do
    if n == b then return true end
  end
end

local function load()
  local map = city.map()
  if data and data.map == map then return data end
  data = {map = map, lines = {}, on = {}}
  local net = roadnet.net()
  local ok, lines = pcall(require, "maps." .. tostring(map.id) .. "_bus")
  if not (ok and type(lines) == "table" and net) then return data end
  local broken = 0
  for _, d in ipairs(lines) do
    local js = {}
    for i, name in ipairs(d) do
      js[i] = net.id[name]
      if not js[i] or (i > 1 and not linked(js[i - 1], js[i])) then js = nil; break end
    end
    if js and #js > 1 then
      local line = {line = d.line, to = d.to, color = d.color, trips = d.trips, js = js}
      data.lines[#data.lines + 1] = line
      local n = #data.lines
      for k = 1, #js - 1 do
        -- The busiest line takes a street several share (ties: the first).
        local key = js[k] .. ">" .. js[k + 1]
        local had = data.on[key]
        if not had or data.lines[had // 4096].trips < d.trips then data.on[key] = n * 4096 + k end
      end
    else
      broken = broken + 1
    end
  end
  print(string.format("bus lines: %d on the map's streets%s", #data.lines,
                      broken > 0 and string.format(" (%d don't fit them: run tools/foli_lines.py again)", broken) or ""))
  return data
end

function L.lines() return load().lines end

-- The line that runs from junction a to b, and the street's number on it.
function L.at(a, b)
  local v = load().on[a .. ">" .. b]
  if v then return load().lines[v // 4096], v % 4096 end
end

-- The rest of `line` after its k-th street: the junctions to plan.
function L.after(line, k)
  return {table.unpack(line.js, k + 2)}
end

-- The streets of every line with an end within r of (x, z), in a fixed order.
function L.near(x, z, r)
  local out = {}
  for i, line in ipairs(load().lines) do
    for k = 1, #line.js - 1 do
      local a, b = line.js[k], line.js[k + 1]
      local v = load().on[a .. ">" .. b]
      if v == i * 4096 + k then
        local ax, az = city.pos(a)
        local bx, bz = city.pos(b)
        if U.dist2d(ax, az, x, z) < r or U.dist2d(bx, bz, x, z) < r then out[#out + 1] = {a, b, line, k} end
      end
    end
  end
  return out
end

-- What a board can show: the font's letters, as many as fit.
local function board_text(s, n)
  s = s:gsub("[\xC2-\xF4][\x80-\xBF]+", function(c)
    return (c == "ä" or c == "Ä" or c == "ö" or c == "Ö" or c == "å" or c == "Å") and c or ""
  end)
  local out, len = {}, 0
  for _, c in utf8.codes(s) do
    if len == n then break end
    out[#out + 1] = utf8.char(c)
    len = len + 1
  end
  return table.concat(out):match("^(.-)%s*$")
end

-- The line's bus: Föli's, its boards showing the line and where it's going
-- (front), the line (back, and by the doors on the right).
local LED, BOARD = {1.0, 0.62, 0.1}, {0.05, 0.05, 0.06}
function L.mesh(line)
  local name = "bus " .. line.line .. ">" .. line.to
  if L.made and L.made[name] then return name end
  local P = require "lib.prefabs"
  if not P.BUS_PARTS then return "bus" end
  local parts = {}
  for i, p in ipairs(P.BUS_PARTS) do
    if i ~= P.BUS_BOARD then parts[#parts + 1] = p end
  end
  local H = 0.17 -- letter height
  local y = 1.85 - 1.075 -- (the prefab's parts sit 1.075 m lower than drawn)
  local function board(x, z, yaw, text, w)
    local nx, nz = math.sin(yaw), math.cos(yaw)
    parts[#parts + 1] = {mesh = "cube", pos = {x, y, z}, yaw = yaw, size = {w, 0.3, 0.06}, color = BOARD}
    parts[#parts + 1] = {text = text, height = H, depth = 0.02, pos = {x + nx * 0.04, y - H / 2, z + nz * 0.04}, yaw = yaw,
                         color = LED, emissive = 1}
  end
  board(0, 5.88, 0, board_text(line.line .. " " .. line.to, 14), 2.3)
  board(0, -5.9, math.pi, board_text(line.line, 4), 0.7)
  board(-1.32, 3.6, -math.pi / 2, board_text(line.line, 4), 0.7) -- the right side, by the front door
  engine.mesh(name, parts)
  L.made = L.made or {}
  L.made[name] = true
  return name
end

return L
