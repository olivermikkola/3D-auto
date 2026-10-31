-- QUAY_TEST=1 (MAP=turku): the river's stone quays. On the paving behind
-- each wall the ground (what a car or a walker stands on) is the quay's
-- top, not the 10 m grid's slope down into the river; in front of it, the
-- grid is under the water (it rose out of it, 2 m out, at 1 in 4 points;
-- here 4 m out, past where the quay's ground eases back to the grid);
-- and out in front of the wall is the river (so a car that goes over is
-- put back on the quay), and on the quay is not.
local R = require "lib.roadnet"
local done = false
engine.on("tick", function()
  if done or engine.ticks() < 5 then return end
  done = true
  local n, off, wet_ground, worst, dry_out, wet_in = 0, 0, 0, 0, 0, 0
  local quays = (R.net() and R.net().map or {}).quays or {}
  -- Every quay's points by 10 m square: out in front of a corner is the
  -- quay round it, and that's ground.
  local cells = {}
  for qi, q in ipairs(quays) do
    for k = 2, #q - 3, 4 do
      local key = math.floor(q[k] / 10) .. "," .. math.floor(q[k + 1] / 10)
      cells[key] = cells[key] or {}
      table.insert(cells[key], {q[k], q[k + 1], qi, k})
    end
  end
  local function other_quay(x, z, qi, k)
    for i = -1, 1 do
      for j = -1, 1 do
        for _, c in ipairs(cells[(math.floor(x / 10) + i) .. "," .. (math.floor(z / 10) + j)] or {}) do
          if (c[3] ~= qi or math.abs(c[4] - k) > 16) and (c[1] - x) ^ 2 + (c[2] - z) ^ 2 < 8 * 8 then return true end
        end
      end
    end
  end
  for qi, q in ipairs(quays) do
    local pts = {}
    for k = 2, #q - 3, 4 do pts[#pts + 1] = {q[k], q[k + 1], q[k + 2], q[k + 3]} end
    for i = 2, #pts - 1 do
      local p, a, b = pts[i], pts[i - 1], pts[i + 1]
      local dx, dz = b[1] - a[1], b[2] - a[2]
      local l = math.sqrt(dx * dx + dz * dz)
      local rx, rz = dz / l, -dx / l
      n = n + 1
      -- On the paving, a metre in from the wall (where it's a metre wide).
      if p[4] >= 1.5 then
        local x, z = p[1] + rx * 1.5, p[2] + rz * 1.5
        local y = engine.terrain_height(x, z)
        if y and not R.on_carriageway(x, z, 1) then
          worst = math.max(worst, math.abs(y - p[3]))
          if math.abs(y - p[3]) > 0.2 then off = off + 1 end
        end
      end
      -- Two metres out is the river (where shore puts a car that went
      -- over back on the quay), a metre in is not.
      if not R.wet(p[1] - rx * 2, p[2] - rz * 2) and not R.on_carriageway(p[1] - rx * 2, p[2] - rz * 2, 8)
         and not other_quay(p[1] - rx * 2, p[2] - rz * 2, qi, 4 * i - 2) then
        dry_out = dry_out + 1
        if os.getenv("QUAY_VERBOSE") then 
          local e, _, _, _, d = R.nearest_edge(p[1] - rx * 2, p[2] - rz * 2)
          print("QUAY dry out", p[1] - rx * 2, p[2] - rz * 2, R.water_at(p[1] - rx * 2, p[2] - rz * 2), e and R.net().edges[e].kind, e and R.net().edges[e].width, d)
        end
      end
      if p[4] >= 1 and R.wet(p[1] + rx, p[2] + rz) then wet_in = wet_in + 1 end
      -- Four metres out in front of the wall (not at a bridge's head, nor
      -- round a corner).
      local x, z = p[1] - rx * 4, p[2] - rz * 4
      local g = engine.terrain_height(x, z)
      if g and g > q[1] + 0.05 and not R.on_carriageway(x, z, 8) and not other_quay(x, z, qi, 4 * i - 2) then
        wet_ground = wet_ground + 1
        if os.getenv("QUAY_VERBOSE") then print("QUAY wet ground", p[1], p[2], p[4], g) end
      end
    end
  end
  print(string.format("QUAY %d points: %d off the quay's top (worst %.2f m), %d with ground out of the water in front, "
                      .. "%d dry 2 m out, %d wet on the quay", n, off, worst, wet_ground, dry_out, wet_in))
  -- (At a sharp bend in the bank a piece of the quay's ground reaches
  -- round the corner: 17 of 1905 in Turku.)
  if n > 100 and off == 0 and wet_ground <= n / 50 and dry_out <= n / 50 and wet_in == 0 then print("QUAY_OK") end
  engine.quit()
end)
