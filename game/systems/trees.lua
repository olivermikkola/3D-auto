-- Trunks to hit. The photo's trees (lib/roadnet R.trees) are baked into
-- the engine's forest, drawn only: a hundred thousand bodies would cost far
-- more than they're worth. So the ones standing near the player get an
-- invisible trunk, tagged "tree" like any other, and lose it again once
-- the player is well away.
local G = require "lib.state"
local roadnet = require "lib.roadnet"

local M = {}
M.NEAR, M.FAR = 80, 140 -- a trunk comes within NEAR m of the player, goes past FAR
local CELL = 40
local EVERY = 0.5          -- s between looks round

local cells           -- "i,j" -> the trees (their numbers in roadnet.trees) in that square
local indexed         -- the roadnet.trees they're of
local trunk = {}      -- tree number -> its body's id
local wait = 0

local function index()
  cells = {}
  local T = roadnet.trees
  for n = 1, #T.x do
    local k = math.floor(T.x[n] / CELL) .. "," .. math.floor(T.z[n] / CELL)
    cells[k] = cells[k] or {}
    table.insert(cells[k], n)
  end
end

-- The trunk's thickness: the crown's (mesh::leafy_tree), a little more so
-- a car meets it where it's drawn.
local function put(T, n)
  local r = 0.15 + 0.025 * T.d[n]
  local y = engine.terrain_height(T.x[n], T.z[n]) or 0
  trunk[n] = engine.spawn{pos = {T.x[n], y + 2, T.z[n]}, size = {2 * r, 4, 2 * r}, body = "static", visible = false, tag = "tree"}
end

-- Give the standing trees within NEAR of (x, z) trunks, and take them off
-- those past FAR or no longer standing (a lower quality).
function M.update(x, z)
  local T = roadnet.trees
  if not T then return end
  if indexed ~= roadnet.trees then -- a new map: its trees are new (ids only grow, so despawning old ones is safe)
    for _, id in pairs(trunk) do engine.despawn(id) end
    trunk, indexed = {}, roadnet.trees
    index()
  end
  for n, id in pairs(trunk) do
    if not T.on[n] or (T.x[n] - x) ^ 2 + (T.z[n] - z) ^ 2 > M.FAR ^ 2 then
      engine.despawn(id)
      trunk[n] = nil
    end
  end
  local near = M.NEAR
  for i = math.floor((x - near) / CELL), math.floor((x + near) / CELL) do
    for j = math.floor((z - near) / CELL), math.floor((z + near) / CELL) do
      for _, n in ipairs(cells[i .. "," .. j] or {}) do
        if T.on[n] and not trunk[n] and (T.x[n] - x) ^ 2 + (T.z[n] - z) ^ 2 < near ^ 2 then put(T, n) end
      end
    end
  end
end

-- How many trunks are up.
function M.count()
  local n = 0
  for _ in pairs(trunk) do n = n + 1 end
  return n
end

engine.on("tick", function(dt)
  wait = wait - dt
  if wait > 0 then return end
  wait = EVERY
  local id = G.vehicle or G.player
  if id and engine.exists(id) then
    local x, _, z = engine.pos(id)
    M.update(x, z)
  end
end)

return M
