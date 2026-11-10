-- A small procedural map example using only the engine API.
local map = require "maps.example"
local angle, distance = 0.72, 180
local drag
local buildings, park_x, park_z = {}, 0, 0
local function box(pos, size, color, tag)
  return engine.spawn{mesh="cube", pos=pos, size=size, color=color, tag=tag, body="static"}
end
engine.on("init", function()
  engine.lighting{sky={0.74, 0.83, 0.87}, sky_top={0.34, 0.56, 0.69},
    sun={-0.5, 0.8, 0.35}, ambient={0.48, 0.53, 0.57}, shadows=true}
  engine.fog(350, 700)
  box({8, -1, 0}, {220, 2, 200}, {0.69, 0.72, 0.65}, "ground")
  box({map.canal_x, 0.02, 0}, {map.canal_width, 0.08, 200}, {0.23, 0.48, 0.58}, "water")
  local offset = (map.blocks - 1) * map.spacing / 2
  for i=0,map.blocks do
    local p = i * map.spacing - offset - map.spacing/2
    box({p, 0.04, 0}, {map.road_width, 0.08, map.blocks*map.spacing+map.road_width}, {0.29, 0.33, 0.35}, "road")
    box({0, 0.05, p}, {map.blocks*map.spacing+map.road_width, 0.08, map.road_width}, {0.29, 0.33, 0.35}, "road")
  end
  for i=0,map.blocks-1 do
    for j=0,map.blocks-1 do
      local x, z = i*map.spacing-offset, j*map.spacing-offset
      if i==1 and j==2 then
        park_x, park_z = x, z
        box({x, 0.14, z}, {21, 0.2, 21}, {0.42, 0.59, 0.39}, "park")
        for n=1,4 do
          local tx, tz = x + (n%2)*10-5, z + math.floor((n-1)/2)*10-5
          box({tx, 1.5, tz}, {0.8, 3, 0.8}, {0.42, 0.34, 0.25}, "tree")
          engine.spawn{mesh="sphere", pos={tx, 4, tz}, size={5, 6, 5}, color={0.28, 0.48, 0.32}, tag="tree"}
        end
      else
        local h = 9 + ((i*7+j*3)%5)*5
        local color = ({ {0.78,0.63,0.48}, {0.69,0.74,0.74}, {0.80,0.78,0.68} })[(i+j)%3+1]
        local id = box({x,h/2+0.1,z}, {map.building_width,h,map.building_width}, color, "building")
        buildings[#buildings+1] = {id=id,x=x,z=z,height=h}
        box({x,h+0.3,z}, {map.building_width+0.6,0.5,map.building_width+0.6}, {0.34,0.39,0.41}, "roof")
      end
    end
  end
  -- A footbridge and quays show how ordinary geometry composes a map.
  box({map.canal_x, 1, 0}, {map.canal_width+4, 0.5, 5}, {0.81,0.78,0.68}, "bridge")
  for _, side in ipairs{-1,1} do
    box({map.canal_x+side*(map.canal_width/2+2),0.15,0}, {4,0.3,190}, {0.78,0.77,0.70}, "quay")
  end
  print("map=example buildings=" .. #buildings)
end)
engine.on("tick", function()
  if os.getenv("ENGINE_SMOKE")=="1" and engine.ticks()==3 then
    assert(#buildings==15, "map buildings were not constructed")
    for _, b in ipairs(buildings) do
      assert(engine.exists(b.id), "building disappeared")
      local id, _, _, y = engine.raycast(b.x,60,b.z,0,-1,0,70)
      assert(id and engine.tag(id)=="roof" and y>b.height, "roof not present in collision world")
    end
    local id = engine.raycast(park_x,20,park_z,0,-1,0,30)
    assert(id and engine.tag(id)=="park", "park surface missing")
    local bridge = engine.raycast(map.canal_x,20,0,0,-1,0,30)
    assert(bridge and engine.tag(bridge)=="bridge", "bridge surface missing")
    local water = engine.raycast(map.canal_x,20,30,0,-1,0,30)
    assert(water and engine.tag(water)=="water", "canal surface missing")
    print("ENGINE DEMO PASSED: buildings, roofs, park, bridge and canal collision queries")
  end
end)
engine.on("key", function(k, down)
  if not down then return end
  if k=="escape" then engine.quit() end
  if k=="r" then angle,distance=0.72,180 end
end)
engine.on("touch", function(phase,id,x,y)
  if phase=="start" then
    local w,h=engine.screen()
    if y>h-64 and x>w-132 then
      distance=math.max(90,math.min(280,distance+(x>w-66 and 15 or -15)))
    elseif not drag then drag={id=id,x=x} end
  elseif drag and drag.id==id then
    if phase=="move" then angle=angle+(x-drag.x)*0.008; drag.x=x
    else drag=nil end
  end
end)
engine.on("frame", function(dt)
  if engine.key("a") or engine.key("left") then angle=angle-dt*0.7 end
  if engine.key("d") or engine.key("right") then angle=angle+dt*0.7 end
  if engine.key("w") or engine.key("up") then distance=math.max(90,distance-dt*65) end
  if engine.key("s") or engine.key("down") then distance=math.min(280,distance+dt*65) end
  engine.camera(8+math.sin(angle)*distance, distance*0.72, math.cos(angle)*distance, 8,0,0,45)
  local w,h=engine.screen()
  engine.rect(16,16,engine.text_width("3D-AUTO / MAP EXAMPLE",18)+24,64,0.10,0.16,0.19,0.91)
  engine.text("3D-AUTO / MAP EXAMPLE",28,28,18,0.95,0.94,0.86,1)
  engine.text("PROCEDURAL GEOMETRY",28,54,12,0.72,0.81,0.82,1)
  engine.rect(16,h-42,400,26,0.10,0.16,0.19,0.91)
  engine.text("A/D ORBIT   W/S ZOOM   R RESET",28,h-35,12,0.86,0.89,0.87,1)
  for n,label in ipairs{"+","-"} do
    local x=w-132+(n-1)*66
    engine.rect(x,h-64,56,48,0.10,0.16,0.19,0.91)
    engine.text(label,x+19,h-52,24,0.95,0.94,0.86,1)
  end
end)
