local U = {}

function U.clamp(x, a, b) return x < a and a or (x > b and b or x) end
function U.lerp(a, b, t) return a + (b - a) * t end

-- Smallest signed difference between two angles.
function U.angle_diff(a, b)
  local d = (b - a) % (2 * math.pi)
  if d > math.pi then d = d - 2 * math.pi end
  return d
end

function U.forward(yaw) return math.sin(yaw), math.cos(yaw) end
-- Right-hand side of a forward vector (Y up, right-handed).
function U.right(yaw) return -math.cos(yaw), math.sin(yaw) end

function U.dist2d(ax, az, bx, bz) return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) end

-- Ray-casting test for 2D polygon containment: poly is array of {x, z}
function U.inside_polygon(px, pz, poly)
  local inside = false
  local j = #poly
  for i = 1, #poly do
    local xi, zi = poly[i][1], poly[i][2]
    local xj, zj = poly[j][1], poly[j][2]
    if ((zi > pz) ~= (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi) + xi) then
      inside = not inside
    end
    j = i
  end
  return inside
end

-- The ground's height at (x, z): 0 except on a map with real terrain.
function U.ground(x, z) return require("lib.roadnet").ground(x, z) end

-- Position of whatever the player currently is (person or car).
function U.player_pos()
  local G = require "lib.state"
  local id = G.vehicle or G.player
  if id then return engine.pos(id) end
end

-- Heading (yaw) of whatever the player currently is (person or car).
function U.player_yaw()
  local G = require "lib.state"
  local id = G.vehicle or G.player
  if id then return engine.yaw(id) end
end

function U.message(text, seconds)
  local G = require "lib.state"
  G.messages[#G.messages + 1] = {text = text, till = engine.time() + (seconds or 3)}
end

return U
