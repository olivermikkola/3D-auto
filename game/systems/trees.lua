-- Trunks to hit. The aerial photo's trees (lib/roadnet, engine.forest) are
-- baked into chunk meshes, drawn only: a hundred thousand bodies would cost
-- far more than they're worth. So the standing ones near the player get an
-- invisible trunk, tagged "tree" like any other, moved off again once the
-- player is well away (or a lower quality takes the tree down).
--
-- The trunks are a pool made once and moved about, not spawned and
-- despawned as the player goes: entities made in play would shift every
-- later one's id, and traffic (which goes by id order) would play out
-- differently from one build of the map to the next.
local G = require "lib.state"
local roadnet = require "lib.roadnet"

local M = {}
M.NEAR, M.FAR = 80, 140 -- a trunk comes within NEAR m of the player, goes past FAR
M.POOL = 400            -- trunks at most (a dense park has ~250 trees within NEAR)
local EVERY = 0.5       -- s between looks round
local R = 0.4           -- a trunk's radius (mesh::leafy_tree's is 0.2-0.45; a car meets it where it's drawn)
local AWAY = 100000     -- where a trunk not in use waits: far off the map, under it

local pool            -- the trunks' ids
local free = {}       -- pool slots not in use
local trunk = {}      -- tree number (engine.forest_near) -> its pool slot
local built           -- roadnet.forest_built the trunks are of
local wait = 0

local function put_away(slot)
  engine.set_pos(pool[slot], AWAY, -500, AWAY)
  free[#free + 1] = slot
end

-- A new city: the pool, made as the city is (so every entity after it
-- keeps its id), all of it put away.
function M.build()
  built, trunk, free, pool = roadnet.forest_built, {}, {}, {}
  if not roadnet.trees_file then pool = nil return end
  for k = 1, M.POOL do
    pool[k] = engine.spawn{pos = {AWAY, -500, AWAY}, size = {2 * R, 4, 2 * R}, body = "static", visible = false, tag = "tree"}
  end
  for k = M.POOL, 1, -1 do free[#free + 1] = k end
end

-- Give the standing trees within NEAR of (x, z) trunks, and take them off
-- those past FAR or no longer standing.
function M.update(x, z)
  if not pool or built ~= roadnet.forest_built or not engine.exists(pool[1]) then return end
  local keep = {}
  local t = engine.forest_near(x, z, M.FAR)
  for k = 1, #t, 4 do keep[t[k]] = true end
  local gone = {}
  for n in pairs(trunk) do
    if not keep[n] then gone[#gone + 1] = n end
  end
  table.sort(gone) -- (in order: which trunk goes where stays the same run to run)
  for _, n in ipairs(gone) do
    put_away(trunk[n])
    trunk[n] = nil
  end
  for k = 1, #t, 4 do
    local n, tx, tz = t[k], t[k + 1], t[k + 2]
    if not trunk[n] and #free > 0 and (tx - x) ^ 2 + (tz - z) ^ 2 < M.NEAR ^ 2 then
      local slot = table.remove(free)
      engine.set_pos(pool[slot], tx, (engine.terrain_height(tx, tz) or 0) + 2, tz)
      trunk[n] = slot
    end
  end
end

-- How many trunks are standing by a tree.
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
