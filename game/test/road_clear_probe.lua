-- Is the road clear to drive? A ray down each lane of every road, at bumper
-- height above the asphalt, end to end: whatever it hits (a lamp, a pylon, a
-- planter, a building) stands in the carriageway. Prints a count per tag and
-- the places, so a fix can be measured; ROAD_CLEAR_MAX fails the run if more
-- than that many remain.
--
-- Then the same for what a ray at bumper height can miss: anything standing
-- in the carriageway (a tree or a lamp you drive through, a bench, a sign),
-- by where it stands. ROAD_CLUTTER_MAX fails the run past that many.
-- ROAD_CLEAR_DEBUG=1 lists nearby road heights for each hit.
local roadnet = require "lib.roadnet"

-- Things that have no business on the asphalt.
local CLUTTER = {"tree", "lamp", "prop", "wall", "scenery", "landmark", "fountain", "fence", "barrier", "stall",
                 "crate", "cone", "container", "shop", "building", "garage", "guardhouse"}
local MOVING = {car = true, ped = true, player = true, bus = true, boat = true, cop = true, pickup = true}

engine.on("init", function()
  local NET = roadnet.net()
  assert(NET, "ROAD_CLEAR_TEST needs a road network")
  local counts, hits, seen, lanes = {}, {}, {}, 0
  for ei, e in ipairs(NET.edges) do
    if not e.tunnel then
      local function y(x, z) return (e.height and e.height(x, z) or roadnet.ground(x, z)) + 0.7 end
      for i = 2, #e.pts do
        local a, b = e.pts[i - 1], e.pts[i]
        local dx, dz = b[1] - a[1], b[2] - a[2]
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 1 then
          local rx, rz = -dz / len, dx / len
          for _, side in ipairs{-0.25, 0.25} do
            local o = side * e.width
            lanes = lanes + 1
            -- In 10 m steps, so the ray follows the road's grade.
            local n = math.max(1, math.ceil(len / 10))
            for k = 0, n - 1 do
              local x0, z0 = a[1] + dx * k / n + rx * o, a[2] + dz * k / n + rz * o
              local x1, z1 = a[1] + dx * (k + 1) / n + rx * o, a[2] + dz * (k + 1) / n + rz * o
              local y0, y1 = y(x0, z0), y(x1, z1)
              local sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
              local sl = math.sqrt(sx * sx + sy * sy + sz * sz)
              local id, dist, hx, hy, hz = engine.raycast(x0, y0, z0, sx, sy, sz, sl)
              if id and not seen[id] then
                local tag = engine.tag(id) or "?"
                if not MOVING[tag] then
                  seen[id] = true
                  counts[tag] = (counts[tag] or 0) + 1
                  local _, ty = engine.pos(id)
                  if os.getenv("ROAD_CLEAR_DEBUG") then
                    for oi, o in ipairs(NET.edges) do
                      for j = 2, #o.pts do
                        local p, q = o.pts[j - 1], o.pts[j]
                        local ux, uz = q[1] - p[1], q[2] - p[2]
                        local l2 = ux * ux + uz * uz
                        local t = l2 > 0 and math.max(0, math.min(1, ((hx - p[1]) * ux + (hz - p[2]) * uz) / l2)) or 0
                        local d = math.sqrt((hx - p[1] - ux * t) ^ 2 + (hz - p[2] - uz * t) ^ 2)
                        if d < o.width / 2 + 4 then
                          print(string.format("  near %s%s%s d=%.1f w=%.1f h=%.2f", o.name or oi, o.deck and " deck" or "",
                                              o.inferred and " inferred" or "", d, o.width,
                                              (o.height or roadnet.ground)(p[1] + ux * t, p[2] + uz * t)))
                        end
                      end
                    end
                  end
                  hits[#hits + 1] = string.format("%-10s %8.1f %8.1f  on %s%s, its surface %.1f, the thing at %.1f", tag, hx, hz,
                                                  e.name or ("edge " .. ei), e.height and " (a deck)" or "", y0 - 0.7, ty or hy)
                end
              end
            end
          end
        end
      end
    end
  end
  local tags, total = {}, 0
  for t, c in pairs(counts) do tags[#tags + 1] = t; total = total + c end
  table.sort(tags, function(p, q) return counts[p] > counts[q] end)
  print(string.format("ROAD_CLEAR lanes=%d obstacles=%d", lanes, total))
  for _, t in ipairs(tags) do print(string.format("ROAD_CLEAR tag %-10s %d", t, counts[t])) end
  for _, h in ipairs(hits) do print("ROAD_CLEAR at " .. h) end

  local clutter, cc = {}, 0
  for _, tag in ipairs(CLUTTER) do
    for _, id in ipairs(engine.find(tag)) do
      local x, y, z = engine.pos(id)
      local ei = x and roadnet.on_carriageway(x, z, 0, y)
      if ei then
        cc = cc + 1
        clutter[tag] = (clutter[tag] or 0) + 1
        print(string.format("ROAD_CLUTTER at %-10s %8.1f %6.1f %8.1f  %s %s on %s", tag, x, y, z, engine.mesh_of(id) or "-",
                            engine.exists(id) and "" or "?", NET.edges[ei].name))
      end
    end
  end
  print(string.format("ROAD_CLUTTER total=%d", cc))
  for _, t in ipairs(CLUTTER) do
    if clutter[t] then print(string.format("ROAD_CLUTTER tag %-10s %d", t, clutter[t])) end
  end
  local max = tonumber(os.getenv("ROAD_CLEAR_MAX") or "")
  if max then assert(total <= max, string.format("%d obstacles in the carriageway, at most %d allowed", total, max)) end
  max = tonumber(os.getenv("ROAD_CLUTTER_MAX") or "")
  if max then assert(cc <= max, string.format("%d things stand in the carriageway, at most %d allowed", cc, max)) end
  print("ROAD CLEAR CHECK DONE")
  engine.quit()
end)
