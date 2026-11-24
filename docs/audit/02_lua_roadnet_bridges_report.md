# KAT-Coder Audit Report: 02_lua_roadnet_bridges

**Generated:** 2026-10-15 18:12:14
**Elapsed Time:** 563.3s
**Tokens:** 42154 (Prompt: 40654, Output: 1500)

## Reasoning Trace

```
Let me analyze this codebase carefully for the three issues mentioned:

1. Bridge elevation ramps overlapping adjacent roads
2. Bridge collision boxes and clearance maintenance
3. Table churn and GC hotspots

Let me go through the code systematically.

## 1. Bridge Elevation Ramps Overlapping Adjacent Roads

Looking at the bridge building code (around line 700-750):

```lua
for ei, e in ipairs(NET.edges) do
    local parts = {}
    local walk = e.kind ~= "highway"
    local hf = GROUND and (e.deck or e.over) and deck_height(e) or nil
    e.height = hf
    if hf then
      if walk then strip(parts, e.pts, e.width + 2 * SIDEWALK, 0.05, PAVE, true, hf) end
    else
      kerbs(parts, ei, e)
    end
    strip(parts, e.pts, e.width, 0.08, ROAD, true, hf)
    dashes(parts, e.pts, 0.09, hf)
    if hf then
      local wide = e.width + (walk and 2 * SIDEWALK or 1)
      for i = 2, #e.pts do
        local ax, az, bx, bz = e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2]
        local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
        local yaw = math.atan(bx - ax, bz - az)
        local rx, rz = math.cos(yaw), -math.sin(yaw)
        local n = math.max(1, math.ceil(len / 6))
        for k = 0, n - 1 do
          local t0, t1 = k / n, (k + 1) / n
          local h0, h1 = hf(ax + (bx - ax) * t0, az + (bz - az) * t0), hf(ax + (bx - ax) * t1, az + (bz - az) * t1)
          local mx, mz, mh, pitch = ax + (bx - ax) * (t0 + t1) / 2, az + (bz - az) * (t0 + t1) / 2, (h0 + h1) / 2, -math.atan(h1 - h0, len / n)
          kit.static{pos = {mx, mh - 0.5, mz}, yaw = yaw, pitch = pitch, size = {wide, 1, len / n + 0.05}, visible = false,
                     tag = "bridge", abs = true}
          parts[#parts + 1] = {mesh = "cube", pos = {mx, mh - 0.7, mz}, yaw = yaw, pitch = pitch, size = {wide, 1.2, len / n + 0.05},
                               color = {0.55, 0.55, 0.53}, abs = true}
          for _, side in ipairs(e.over and {} or {-1, 1}) do -- over a tunnel, the roof is the ground
            rails[#rails + 1] = {mx + rx * side * wide / 2, mh + 0.5, mz + rz * side * wide / 2, yaw, pitch, len / n + 0.05, ei}
          end
        end
      end
      for i = 2, #e.pts do -- where piers could go, under each bend and the middle of each stretch
        for _, f in ipairs{0, 0.5} do
          local x, z = e.pts[i - 1][1] + (e.pts[i][1] - e.pts[i - 1][1]) * f, e.pts[i - 1][2] + (e.pts[i][2] - e.pts[i - 1][2]) * f
          piers[#piers + 1] = {x, z, hf(x, z), ei}
        end
      end
    end
    bake("road" .. ei, parts, 0)
    for i = 2, #e.pts do
      add_seg(H, e.pts[i - 1][1], e.pts[i - 1][2], e.pts[i][1], e.pts[i][2], e.width / 2 + (walk and SIDEWALK or 1.5), ei, e.width)
    end
  end
```

I see the issue. The bridge deck is built with `strip()` which creates cubes along the road path. But the approach ramps (where the bridge transitions from ground level to deck height) are not explicitly handled. The `deck_height` function computes the deck height as a straight line between endpoints (plus a lift for water clearance), but there's no ramp geometry - the bridge just starts at full height at its endpoints.

Wait, let me re-read. The `deck_height` function returns a height function. When `e.over` is true (bridge over a tunnel), it uses `e.prof` (the road's own height profile). When it's a regular bridge over water/ground, it computes a straight line from end to end with a lift for water clearance.

The problem is: when a bridge connects to a ground-level road at a junction, the bridge deck starts at the junction's height (which is the ground height at that point), but the approach ramp isn't modeled. The bridge just starts at full elevation immediately.

Actually wait - looking more carefully at `deck_height`:
- For `own` (e.over, bridge over tunnel): it uses the road's own height profile
- For regular bridges: it computes a straight line from ha to hb with a lift for water clearance

So the bridge deck is a straight line from one end to the other. If the road leading to the bridge is graded (has heights), the bridge doesn't ramp up - it just starts at the junction height. This means:
1. At the junction, the bridge deck is at the same height as the ground road
2. But as you move along the bridge, it rises (or falls) linearly
3. This creates a ramp effect, but it's the entire bridge span, not just an approach

Actually, I think the issue is different. Let me re-read the comment:
"Approach slabs clipping into perpendicular or parallel surface lanes"

The problem is that when a bridge spans over another road, the bridge deck's collision box (the invisible `tag = "bridge"` cube) extends the full width of the bridge including sidewalks. If there's a perpendicular
```

## Findings & Actionable Recommendations

*(No direct content, see reasoning trace)*