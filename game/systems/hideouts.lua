-- Places to lie low: walk in through the door with the cops after you and
-- you're inside, out of their sight. If none of them saw you go in, they
-- lose you as if you'd left their search area (wanted.escape_time); if one
-- did, they wait you out (wanted.give_up_time). Move to come back out.
-- Turku: Logomo, just past the foot of Logomonsilta's stairs (Oliver's
-- chase: over the bridge and into Logomo to lose the cops).
local G = require "lib.state"
local U = require "lib.util"
local input = require "lib.input"
local wanted = require "lib.wanted"

local H = {list = {}, inside = nil} -- list: {name, x, z, y, nx, nz}; inside: {door, t, seen}

-- Each map's: a name, a spot outside, and a point inside the building; the
-- door goes where a line from the one to the other meets its wall.
local SPOTS = {
  turku = {{name = "LOGOMO", from = {-590.2, -592.8}, to = {-600, -607.8}}},
}

local REACH = 2.2 -- m from the door to go in
local OUT = 1.2   -- m in front of it you come back out

local function door_mesh(name)
  local glass, frame = {0.35, 0.45, 0.5}, {0.12, 0.12, 0.13}
  return {
    {mesh = "cube", pos = {0, 1.35, 0}, size = {3.4, 2.7, 0.12}, color = frame},
    {mesh = "cube", pos = {-0.8, 1.2, 0.08}, size = {1.4, 2.3, 0.04}, color = glass, emissive = 0.35},
    {mesh = "cube", pos = {0.8, 1.2, 0.08}, size = {1.4, 2.3, 0.04}, color = glass, emissive = 0.35},
    {mesh = "cube", pos = {0, 1.2, 0.12}, size = {0.06, 0.5, 0.06}, color = {0.75, 0.75, 0.72}},
    {mesh = "cube", pos = {0, 2.95, 0.3}, size = {3.8, 0.12, 0.7}, color = frame}, -- canopy
    {mesh = "cube", pos = {0, 3.45, 0.08}, size = {#name * 0.55 + 0.6, 0.7, 0.06}, color = {0.1, 0.1, 0.11}},
    {text = name, pos = {0, 3.45, 0.13}, height = 0.5, depth = 0.05, color = {0.95, 0.85, 0.55}, emissive = 0.8},
  }
end

function H.build(map)
  H.list, H.inside = {}, nil
  for _, s in ipairs(SPOTS[map and map.id] or {}) do
    local fx, fz = s.to[1] - s.from[1], s.to[2] - s.from[2]
    local len = math.sqrt(fx * fx + fz * fz)
    fx, fz = fx / len, fz / len
    -- The first building along it (past a bridge's stairs, a lamp, a sign).
    local y = U.ground(s.from[1], s.from[2]) + 1.2
    local hit, d, skip, at, nx, nz = nil, 0, nil, 0, -fx, -fz
    for _ = 1, 8 do
      local t, _, _, _, hx, _, hz
      hit, t, _, _, _, hx, _, hz = engine.raycast(s.from[1] + fx * at, y, s.from[2] + fz * at, fx, 0, fz, len - at, skip)
      if not hit or engine.tag(hit) == "building" then
        d = at + (t or 0)
        if hx then
          local n = math.sqrt(hx * hx + hz * hz)
          if n > 0.5 then nx, nz = hx / n, hz / n end
        end
        break
      end
      skip, at = hit, at + t + 0.05
    end
    if hit and engine.tag(hit) == "building" then
      -- On the wall, facing out of it.
      local x, z = s.from[1] + fx * d + nx * 0.05, s.from[2] + fz * d + nz * 0.05
      local gy = U.ground(x + nx * OUT, z + nz * OUT)
      local key = "door_" .. s.name:lower()
      engine.mesh(key, door_mesh(s.name))
      engine.spawn{mesh = key, pos = {x, gy, z}, yaw = math.atan(nx, nz), tag = "sign"}
      H.list[#H.list + 1] = {name = s.name, x = x, z = z, y = gy, nx = nx, nz = nz}
    else
      print("hideouts: no wall for " .. s.name)
    end
  end
end

-- Inside one (the cops can't see you there)?
function H.hidden() return H.inside ~= nil end

-- Seen going in: a cop had sight of you in the last moment.
local SEEN_WITHIN = 1.5

local function go_in(door)
  local seen = wanted.seen or wanted.unseen_for < SEEN_WITHIN
  H.inside = {door = door, t = 0, seen = seen}
  G.hiding = true
  wanted.hiding = not seen
  engine.set_visible(G.player, false)
  U.message("HIDING IN " .. door.name, 3)
  engine.emit("hiding", door.name)
end

local function come_out(why)
  local door = H.inside.door
  H.inside, G.hiding, wanted.hiding = nil, nil, nil
  if G.player and engine.exists(G.player) then
    engine.set_pos(G.player, door.x + door.nx * OUT, door.y + 1, door.z + door.nz * OUT)
    engine.set_vel(G.player, 0, 0, 0)
    engine.set_visible(G.player, true)
  end
  if why then U.message(why, 3) end
end

engine.on("tick", function(dt)
  if H.inside then
    H.inside.t = H.inside.t + dt
    if not G.player or not engine.exists(G.player) then H.inside, G.hiding, wanted.hiding = nil, nil, nil return end
    local door = H.inside.door
    engine.set_pos(G.player, door.x + door.nx * OUT, door.y + 1, door.z + door.nz * OUT)
    engine.set_vel(G.player, 0, 0, 0)
    if H.inside.t > 1.5 then
      local f, s = input.move()
      if math.abs(f) + math.abs(s) > 0.2 then return come_out() end
    end
    if wanted.stars() == 0 and not H.inside.told then
      H.inside.told = true
      U.message("THEY'VE LOST YOU", 3)
    end
    return
  end
  if G.vehicle or not G.player or wanted.stars() == 0 then return end
  local x, _, z = engine.pos(G.player)
  for _, door in ipairs(H.list) do
    if U.dist2d(x, z, door.x, door.z) < REACH then return go_in(door) end
  end
end)

return H
