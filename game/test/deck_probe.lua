-- DECK_TEST=1: buildings on decks over roads (lib/roadnet's `span`). Tyks'
-- Majakkasairaala stands over Helsinginkatu's tunnel, and nothing a road
-- carries runs into any deck building: rays along every road under one, at
-- a car's and a bus's height, meet no building.
local R = require "lib.roadnet"
local done = false
engine.on("tick", function()
  if done or engine.ticks() < 5 then return end
  done = true
  local decks, majakka = {}, false
  for _, o in ipairs(R.footprints()) do
    if o.deck then
      local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
      for _, p in ipairs(o.pts) do
        x0, z0, x1, z1 = math.min(x0, p[1]), math.min(z0, p[2]), math.max(x1, p[1]), math.max(z1, p[2])
      end
      decks[#decks + 1] = {x0 - 5, z0 - 5, x1 + 5, z1 + 5}
      -- (Majakkasairaala: its middle at about 1352, -121 on Turku.)
      if x0 < 1352 and x1 > 1352 and z0 < -121 and z1 > -121 then majakka = true end
    end
  end
  local samples, blocked = 0, 0
  for _, e in ipairs(R.net().edges) do
    for k = 2, #e.pts do
      local a, b = e.pts[k - 1], e.pts[k]
      local dx, dz = b[1] - a[1], b[2] - a[2]
      local l = math.sqrt(dx * dx + dz * dz)
      for t = 0, 1, 0.1 do
        local x, z = a[1] + dx * t, a[2] + dz * t
        for _, d in ipairs(decks) do
          if l > 0.5 and x > d[1] and x < d[3] and z > d[2] and z < d[4] then
            local y = e.height and e.height(x, z) or engine.terrain_height(x, z)
            samples = samples + 1
            for _, hh in ipairs{1.0, 3.2} do
              local id = engine.raycast(x, y + hh, z, dx / l, 0, dz / l, 4)
              if id and engine.tag(id) == "building" then
                blocked = blocked + 1
                print(string.format("DECK blocked: %s at %.0f, %.0f, %.1f m up", e.name or "a road", x, z, hh))
                break
              end
            end
            break
          end
        end
      end
    end
  end
  print(string.format("DECK %d buildings on decks, Majakkasairaala %s, %d road samples under them, %d blocked",
                      #decks, majakka and "stands" or "MISSING", samples, blocked))
  if majakka and samples > 0 and blocked == 0 then print("DECK_OK") end
  engine.quit()
end)
