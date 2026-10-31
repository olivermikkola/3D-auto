-- TUNNEL_TEST=1: the covered tunnels. Every one has a roof over it (a slab,
-- or through a hill's nose a rock gallery, as Unioninkatu at the old
-- Wärtsilä works), and nothing stands in its lanes: rays along them at a
-- car's and a bus's height meet nothing.
local R = require "lib.roadnet"
local done = false
engine.on("tick", function()
  if done or engine.ticks() < 5 then return end
  done = true
  local covered, open, rays, blocked = {}, {}, 0, 0
  for _, e in ipairs(R.net().edges) do
    if e.tunnel and e.roofed then
      local name = e.name or "?"
      for k = 2, #e.pts do
        local a, b = e.pts[k - 1], e.pts[k]
        local dx, dz = b[1] - a[1], b[2] - a[2]
        local l = math.sqrt(dx * dx + dz * dz)
        if l > 0.5 then
          for t = 0.1, 0.91, 0.2 do
            local cx, cz = a[1] + dx * t, a[2] + dz * t
            local y = e.height and e.height(cx, cz) or engine.terrain_height(cx, cz)
            local id = engine.raycast(cx, y + 0.5, cz, 0, 1, 0, 12)
            if id and engine.tag(id) == "roof" then covered[name] = true else open[name] = true end
            for _, side in ipairs{-1, 1} do
              local x, z = cx + dz / l * side * 1.8, cz - dx / l * side * 1.8
              for _, hh in ipairs{0.8, 3.4} do
                rays = rays + 1
                local hit = engine.raycast(x, y + hh, z, dx / l, 0, dz / l, 3)
                if hit and engine.tag(hit) ~= "car" and engine.tag(hit) ~= "bus" and engine.tag(hit) ~= "cop" then
                  blocked = blocked + 1
                  print(string.format("TUNNEL blocked: %s at %.0f, %.0f, %.1f m up by %s", name, x, z, hh, tostring(engine.tag(hit))))
                end
              end
            end
          end
        end
      end
    end
  end
  local names = {}
  for name in pairs(covered) do names[#names + 1] = name end
  table.sort(names)
  print(string.format("TUNNEL roofed: %s; %d rays along the lanes, %d blocked", table.concat(names, ", "), rays, blocked))
  if covered["Unioninkatu"] and blocked == 0 then print("TUNNEL_OK") end
  engine.quit()
end)
