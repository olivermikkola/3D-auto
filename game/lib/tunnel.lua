-- Cut-and-cover tunnels for maps drawn from survey data: a stretch of a
-- named road sunk into a trench and roofed over, the way Raisio's E18 goes
-- under the center. tunnel.dig(map, spec) returns a copy of the map with
--   * the road (spec.road, by name) lowered along the tunnel's axis from
--     spec.from to spec.to by spec.depth meters, climbing back to the
--     ground over spec.ramp meters beyond each end, within spec.half
--     meters of the axis;
--   * its junctions there split from the streets that met it at grade:
--     those now cross over it (`over`: a deck at their own surveyed
--     heights), and stubs that only led onto it are cut back to where
--     they leave the trench (and so are any that met it at a junction in
--     spec.cut, closed for good);
--   * no buildings standing in the trench;
--   * the spec in map.tunnels, for the builder's roof, walls and lights.
-- Roads take {name = ..., heights = {...}} as tools/osm_import.py writes
-- them: heights evenly spaced end to end.
local T = {}

local function smooth(t) t = math.max(0, math.min(1, t)) return t * t * (3 - 2 * t) end

-- Where (x, z) is along the axis (u from spec.from) and across it (v).
local function frame(spec)
  local ax, az, bx, bz = spec.from[1], spec.from[2], spec.to[1], spec.to[2]
  local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
  local ux, uz = (bx - ax) / len, (bz - az) / len
  return len, function(x, z)
    local dx, dz = x - ax, z - az
    return dx * ux + dz * uz, dx * -uz + dz * ux
  end
end

-- How far down the road is at u: all the way under the roof, easing back
-- up over the ramps.
function T.dip(spec, len, u)
  local ramp = spec.ramp or 100
  if u < 0 then return spec.depth * smooth(1 + u / ramp) end
  if u > len then return spec.depth * smooth(1 - (u - len) / ramp) end
  return spec.depth
end

function T.dig(base, spec)
  local map = {}
  for k, v in pairs(base) do map[k] = v end
  local len, uv = frame(spec)
  local ramp = spec.ramp or 100
  local function sunk(x, z, pad) -- how deep the trench is at (x, z), 0 outside it
    local u, v = uv(x, z)
    if math.abs(v) > spec.half + (pad or 0) or u < -ramp or u > len + ramp then return 0 end
    return T.dip(spec, len, u)
  end
  local junctions = {}
  for name, p in pairs(base.junctions) do junctions[name] = p end
  local function at(p) if type(p) == "string" then return junctions[p] else return p end end

  -- The road itself: lowered sample by sample, and onto junctions of its
  -- own wherever it's down in the trench.
  local roads = {}
  for i, road in ipairs(base.roads) do
    local r = road
    if road.name == spec.road and road.heights and #road.heights >= 2 then
      local pts, cum = {}, {0}
      for k = 1, #road do
        pts[k] = at(road[k])
        if k > 1 then cum[k] = cum[k - 1] + math.sqrt((pts[k][1] - pts[k - 1][1]) ^ 2 + (pts[k][2] - pts[k - 1][2]) ^ 2) end
      end
      local n, total = #road.heights, cum[#cum]
      local hs, deepest, k = {}, 0, 2
      for m = 1, n do
        local s = total * (m - 1) / (n - 1)
        while k < #pts and cum[k] < s do k = k + 1 end
        local f = (s - cum[k - 1]) / math.max(cum[k] - cum[k - 1], 1e-6)
        local x, z = pts[k - 1][1] + (pts[k][1] - pts[k - 1][1]) * f, pts[k - 1][2] + (pts[k][2] - pts[k - 1][2]) * f
        -- Down by how far along the tunnel it is (where it bends away
        -- out on a ramp it still climbs back smoothly).
        local u, v = uv(x, z)
        local d = (math.abs(v) < spec.half + 60 and u > -ramp and u < len + ramp) and T.dip(spec, len, u) or 0
        hs[m], deepest = road.heights[m] - d, math.max(deepest, d)
      end
      if deepest > 0.5 then
        r = {}
        for key, v in pairs(road) do r[key] = v end
        r.heights, r.tunnel = hs, true
        for p = 1, #road do
          local q = road[p]
          if type(q) == "string" and sunk(junctions[q][1], junctions[q][2]) > 1 then
            r[p] = q .. " (tunnel)"
            junctions[r[p]] = junctions[q]
          end
        end
      end
    end
    roads[i] = r
  end

  -- Everything else that reaches into the trench crosses over it, or is
  -- cut back where it only led onto the road below.
  local function crosses(road)
    for k = 2, #road do
      local a, b = at(road[k - 1]), at(road[k])
      local l = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
      for s = 0, l, 4 do
        if sunk(a[1] + (b[1] - a[1]) * s / l, a[2] + (b[2] - a[2]) * s / l) > 0.5 then return true end
      end
    end
    return false
  end
  local cut_at = {}
  for _, name in ipairs(spec.cut or {}) do cut_at[name] = true end
  local changed = true
  while changed do
    changed = false
    local degree = {}
    for _, r in ipairs(roads) do
      if r and not r.tunnel then
        for _, e in ipairs{r[1], r[#r]} do
          if type(e) == "string" then degree[e] = (degree[e] or 0) + 1 end
        end
        for k = 2, #r - 1 do if type(r[k]) == "string" then degree[r[k]] = (degree[r[k]] or 0) + 2 end end
      end
    end
    for i, r in ipairs(roads) do
      if r and not r.tunnel and crosses(r) then
        local lo, hi = 1, #r
        local function dead(e)
          return type(e) == "string" and (degree[e] == 1 or cut_at[e]) and sunk(junctions[e][1], junctions[e][2], 8) > 0
        end
        local function wet(e) return type(e) ~= "string" and sunk(e[1], e[2], 8) > 0 end
        while hi - lo >= 1 and dead(r[lo]) do
          lo = lo + 1
          while lo <= hi and wet(r[lo]) do lo = lo + 1 end
        end
        while hi - lo >= 1 and dead(r[hi]) do
          hi = hi - 1
          while hi >= lo and wet(r[hi]) do hi = hi - 1 end
        end
        local cut = lo > 1 or hi < #r
        if cut then
          changed = true
          if hi - lo < 1 then
            roads[i] = false
          else
            local c = {}
            for key, v in pairs(r) do if type(key) ~= "number" then c[key] = v end end
            for k = lo, hi do c[k - lo + 1] = r[k] end
            c.heights = r.heights and T.resample(r, lo, hi, at)
            roads[i] = c
          end
        elseif not r.over then
          local c = {}
          for key, v in pairs(r) do c[key] = v end
          c.over, c.bridge = true, true
          roads[i] = c
        end
      end
    end
  end
  map.roads = {}
  for _, r in ipairs(roads) do if r then map.roads[#map.roads + 1] = r end end
  -- Only the junctions some road still meets at.
  map.junctions = {}
  for _, r in ipairs(map.roads) do
    for k = 1, #r do
      if type(r[k]) == "string" then map.junctions[r[k]] = junctions[r[k]] end
    end
  end

  -- No buildings in the trench.
  map.footprints = {}
  for _, f in ipairs(base.footprints or {}) do
    if sunk(f[1], f[2], math.max(f[3], f[4]) / 2 + 4) == 0 then map.footprints[#map.footprints + 1] = f end
  end

  map.tunnels = {}
  for _, t in ipairs(base.tunnels or {}) do map.tunnels[#map.tunnels + 1] = t end
  map.tunnels[#map.tunnels + 1] = spec
  return map
end

-- A road's surveyed heights for the stretch from point lo to point hi,
-- evenly spaced again (about every 10 m).
function T.resample(road, lo, hi, at)
  local pts, cum = {}, {0}
  for k = 1, #road do
    pts[k] = at(road[k])
    if k > 1 then cum[k] = cum[k - 1] + math.sqrt((pts[k][1] - pts[k - 1][1]) ^ 2 + (pts[k][2] - pts[k - 1][2]) ^ 2) end
  end
  local hs, step = road.heights, math.max(cum[#cum], 1e-3) / (#road.heights - 1)
  local function h(s)
    local u = math.max(0, s / step)
    local k = math.min(math.floor(u), #hs - 2)
    return hs[k + 1] + (hs[k + 2] - hs[k + 1]) * math.min(u - k, 1)
  end
  local s0, s1 = cum[lo], cum[hi]
  local n = math.max(1, math.floor((s1 - s0) / 10 + 0.5))
  local out = {}
  for m = 0, n do out[m + 1] = h(s0 + (s1 - s0) * m / n) end
  return out
end

T.frame = frame
return T
