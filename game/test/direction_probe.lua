-- Direction probe: verifies one-way roads and roundabout edges enforce directional routing
local roadnet = require "lib.roadnet"
local city = require "lib.city"

engine.on("init", function()
  local net = roadnet.net()
  assert(net, "roadnet must be loaded")
  
  local oneway_edges = 0
  for _, edge in ipairs(net.edges) do
    if edge.oneway then
      oneway_edges = oneway_edges + 1
      local a, b = edge.a, edge.b
      -- Forward path must exist
      assert(net.paths[a] and net.paths[a][b], string.format("forward path missing for oneway edge %s->%s (%s)", tostring(a), tostring(b), tostring(edge.name)))
      -- Reverse path MUST NOT exist for oneway edge
      assert(not (net.paths[b] and net.paths[b][a]), string.format("reverse path illegally created for oneway edge %s->%s (%s)", tostring(a), tostring(b), tostring(edge.name)))
      -- Reverse link must not exist
      local has_reverse_link = false
      for _, nb in ipairs(net.links[b] or {}) do
        if nb == a then has_reverse_link = true; break end
      end
      assert(not has_reverse_link, string.format("reverse link illegally present for oneway edge %s->%s (%s)", tostring(a), tostring(b), tostring(edge.name)))
    end
  end
  
  assert(oneway_edges > 0, "expected oneway edges on raisio map")
  print(string.format("FOUND %d ONEWAY EDGES; ALL DIRECTION CHECKS PASSED", oneway_edges))
end)
