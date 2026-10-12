-- Pin the camera for docs screenshots and overviews:
-- SHOT_CAM="eye_x,eye_y,eye_z,target_x,target_y,target_z[,fov]" auto game --screenshot out.ppm
-- FOG="near,far" pushes the fog back for wide shots.
local v = {}
for n in os.getenv("SHOT_CAM"):gmatch("[^,]+") do v[#v + 1] = tonumber(n) end
engine.on("init", function()
  local fog = os.getenv("FOG")
  if fog then
    local a, b = fog:match("([^,]+),([^,]+)")
    engine.fog(tonumber(a), tonumber(b))
  end
end)
engine.on("frame", function() engine.camera(v[1], v[2], v[3], v[4], v[5], v[6], v[7] or 60) end)
