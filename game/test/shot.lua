-- Pin the camera for docs screenshots and overviews:
-- SHOT_CAM="eye_x,eye_y,eye_z,target_x,target_y,target_z[,fov]" auto game --screenshot out.ppm
-- FOG="near,far" pushes the fog back for wide shots.
-- SHOT_CAM_GROUND=1 reads both heights as metres above the ground under them
-- (tools/postcards.py), so a spot stays at eye level when the terrain changes.
-- SHOT_CAM_SNAP=1 moves the eye onto the middle of the nearest street and
-- looks along it, the way that's nearer the target, so a street-level shot
-- never stares into a wall after the map changes.
local v = {}
for n in os.getenv("SHOT_CAM"):gmatch("[^,]+") do v[#v + 1] = tonumber(n) end
engine.on("init", function()
  if os.getenv("SHOT_CAM_SNAP") == "1" then
    local roadnet = require "lib.roadnet"
    local e, i, cx, cz = roadnet.nearest_edge(v[1], v[3])
    if e then
      local pts = roadnet.net().edges[e].pts
      local a, b = pts[i - 1], pts[i]
      local dx, dz = b[1] - a[1], b[2] - a[2]
      local len = math.sqrt(dx * dx + dz * dz)
      dx, dz = dx / len, dz / len
      if dx * (v[4] - v[1]) + dz * (v[6] - v[3]) < 0 then dx, dz = -dx, -dz end
      local reach = math.sqrt((v[4] - v[1]) ^ 2 + (v[6] - v[3]) ^ 2)
      v[1], v[3] = cx, cz
      v[4], v[6] = cx + dx * reach, cz + dz * reach
    end
  end
  if os.getenv("SHOT_CAM_GROUND") == "1" then
    v[2] = v[2] + require("lib.roadnet").ground(v[1], v[3])
    v[5] = v[5] + require("lib.roadnet").ground(v[4], v[6])
  end
  -- (where it ended up, for tools/reference.py to look from the same spot)
  print(string.format("SHOT_CAM_FINAL=%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%g", v[1], v[2], v[3], v[4], v[5], v[6], v[7] or 60))
  local fog = os.getenv("FOG")
  if fog then
    local a, b = fog:match("([^,]+),([^,]+)")
    engine.fog(tonumber(a), tonumber(b))
  end
end)
engine.on("frame", function() engine.camera(v[1], v[2], v[3], v[4], v[5], v[6], v[7] or 60) end)
