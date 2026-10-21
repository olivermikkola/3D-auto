-- Mission template probe: the example story of docs/MISSION_TEMPLATES.md
-- cast at 50 seeds. Every version must keep its conditions, the same seed
-- must give the same places, and the count of different versions is printed.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local mission = require "lib.mission"
local template = require "lib.template"

local SEEDS = 50

local STORY = {
  {"pickup", amenity = "place_of_worship", max_dist = 2000, relax = {{max_dist = 4000}}},
  {"hideout", leisure = "pitch", from = "pickup", min_dist = 3000, max_dist = 6000,
   relax = {{min_dist = 1500}, {min_dist = 800}}},
  {"drop", shop = "supermarket", from = "hideout", drive_min = 1000, relax = {{drive_min = 500}}},
}

engine.on("init", function()
  local map = city.map().id or city.map().name
  if not city.network() then
    local cast, why = template.cast{seed = 1, from = {0, 0}, roles = STORY}
    assert(not cast and why:match("^pickup"), "a grid map has no places to cast")
    print("TEMPLATE_PROBE: grid map, nothing to cast")
    print("TEMPLATE_PROBE: PASSED")
    return
  end
  local t0 = os.clock()
  local from = {city.place("lot")}
  local ok, versions, relaxed, fails, seen = 0, 0, {}, {}, {}
  local first
  for seed = 1, SEEDS do
    local cast, info = template.cast{seed = seed, from = from, roles = STORY}
    if cast then
      ok = ok + 1
      local a, b, c = cast.pickup, cast.hideout, cast.drop
      local function d(p, q) return math.sqrt((p.x - q[1]) ^ 2 + (p.z - q[2]) ^ 2) end
      assert(a.tags.amenity == "place_of_worship" and b.tags.leisure == "pitch" and c.tags.shop == "supermarket", "tags")
      assert(d(a, from) <= 4000 + 1e-6, "pickup too far")
      assert(d(b, {a.x, a.z}) >= 800 - 1e-6 and d(b, {a.x, a.z}) <= 6000 + 1e-6, "hideout distance")
      assert(c.drive >= 500 and c.drive < math.huge, "drop by road")
      assert(template.drive(b.x, b.z, c) == c.drive, "drive distance repeatable")
      local key = template.key(a) .. "|" .. template.key(b) .. "|" .. template.key(c)
      if not seen[key] then seen[key], versions = true, versions + 1 end
      for role, step in pairs(info) do relaxed[role] = (relaxed[role] or 0) + 1 end
      local again = template.cast{seed = seed, from = from, roles = STORY}
      assert(template.key(again.drop) == template.key(c) and template.key(again.pickup) == template.key(a), "same seed, other places")
      first = first or string.format("seed 1: %s -> %s -> %s (%.0f m by road)",
        a.name or "?", b.name or ("pitch at " .. template.key(b)), c.name or "?", c.drive)
    else
      fails[#fails + 1] = info
    end
  end
  -- Avoiding: with the first version's places avoided, another is picked.
  local c1 = template.cast{seed = 1, from = from, roles = STORY}
  if c1 then
    local c2 = template.cast{seed = 1, from = from, roles = STORY, avoid = {[template.key(c1.pickup)] = true}}
    assert(c2 and template.key(c2.pickup) ~= template.key(c1.pickup), "an avoided place picked while others fit")
  end
  -- Relaxing: a condition nothing meets gives way, step by step.
  local far, info = template.cast{seed = 1, from = from, roles = {
    {"far", shop = "supermarket", min_dist = 1e6, relax = {{min_dist = 1e5}, {min_dist = false}}}}}
  assert(far and info.far == 2, "relax steps")
  local none, why = template.cast{seed = 1, from = from, roles = {{"x", amenity = "no_such_thing"}}}
  assert(not none and why:match("^x: "), "a role nothing fits")
  local r = {}
  for role, n in pairs(relaxed) do r[#r + 1] = role .. " " .. n end
  table.sort(r)
  print(string.format("TEMPLATE_PROBE %s: %d/%d seeds cast, %d different versions, relaxed: %s", map, ok, SEEDS, versions,
    #r > 0 and table.concat(r, ", ") or "none"))
  if first then print("TEMPLATE_PROBE " .. map .. ": " .. first) end
  if #fails > 0 then print("TEMPLATE_PROBE " .. map .. ": first failure: " .. fails[1]) end
  print(string.format("TEMPLATE_PROBE %s: %.0f ms", map, (os.clock() - t0) * 1000))

  -- Häsburger Express: how many of 50 seeds give a playable run, and one played.
  local hes
  for _, d in ipairs(mission.defs) do if d.id == "11_hesburger_express" then hes = d end end
  assert(hes and hes.cast, "Häsburger Express is on a map with a Hesburger")
  local playable, runs, shortest, longest = 0, {}, math.huge, 0
  for seed = 1, SEEDS do
    local drops, seconds = hes.cast(seed)
    if drops then
      assert(#drops == 3 and drops[1].name and drops[2].name and drops[3].name, "three named customers")
      for _, p in ipairs(drops) do assert(p.road and p.drive < math.huge, "a customer cars can reach") end
      playable = playable + 1
      runs[drops[1].name .. "|" .. drops[2].name .. "|" .. drops[3].name] = true
      shortest, longest = math.min(shortest, seconds), math.max(longest, seconds)
    end
  end
  local different = 0
  for _ in pairs(runs) do different = different + 1 end
  print(string.format("TEMPLATE_PROBE %s: Häsburger Express: %d/%d seeds playable, %d different runs, timer %d-%d s",
    map, playable, SEEDS, different, shortest, longest))
  assert(playable == SEEDS, "every seed gives a playable run")

  -- Getaway and Fragile Cargo: a real place for every seed, and how many
  -- different ones.
  for _, id in ipairs{"04_getaway", "05_cargo"} do
    local def
    for _, d in ipairs(mission.defs) do if d.id == id then def = d end end
    assert(def and def.cast, id .. " is cast from the map's places")
    local ok2, places, lo, hi = 0, {}, math.huge, 0
    for seed = 1, SEEDS do
      local p = def.cast(seed)
      if p then
        assert(p.name and p.road and p.drive < math.huge, id .. ": a named place cars can reach")
        ok2 = ok2 + 1
        places[p.name] = true
        lo, hi = math.min(lo, p.drive), math.max(hi, p.drive)
      end
    end
    local n = 0
    for _ in pairs(places) do n = n + 1 end
    print(string.format("TEMPLATE_PROBE %s: %s: %d/%d seeds playable, %d different places, %.0f-%.0f m by road",
      map, def.title, ok2, SEEDS, n, lo, hi))
    assert(ok2 == SEEDS, id .. ": every seed gives a playable run")
  end

  -- Play it: unlock, walk into the start marker, then onto each red marker.
  G.passed["02_checkpoints"] = true
  for _, d in ipairs(mission.defs) do if d.id == "02_checkpoints" then d.passed = true end end
  mission.show_start_markers()
  local passed, cash0, delivered, step = false, G.cash, 0, 0
  engine.on("mission_passed", function(def) if def == hes then passed = true end end)
  local function put(x, z)
    engine.set_pos(G.player, x, 1.2 + U.ground(x, z), z)
    engine.set_vel(G.player, 0, 0, 0)
  end
  engine.on("tick", function()
    step = step + 1
    if passed then
      assert(G.cash == cash0 + hes.reward, "the reward is paid")
      print(string.format("TEMPLATE_PROBE %s: Häsburger Express played, %d customers, passed", map, delivered))
      print("TEMPLATE_PROBE: PASSED")
      engine.quit()
      return
    end
    assert(step < 2000, "Häsburger Express didn't finish")
    if not G.mission then put(hes.start[1], hes.start[2]); return end
    assert(G.mission.def == hes, "another mission started")
    local mk = G.markers[#G.markers]
    if mk and engine.exists(mk.id) and step % 10 == 0 then
      local x, _, z = engine.pos(mk.id)
      put(x, z)
      delivered = delivered + 1
    end
  end)
end)
