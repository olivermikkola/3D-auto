-- Real police tick -> vehicle.drive -> physics -> arrest, on Harbor's graph.
-- The scene is isolated; no driving, sight, routing or arrest calls are mocked.
-- Run from repository root via tools/test_police_recovery.py.
package.path = "game/?.lua;" .. package.path
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
city.use("harbor")
local vehicle = require "lib.vehicle"
local police = require "systems.police"
local wanted = require "lib.wanted"
local obstructed = os.getenv("POLICE_OBSTACLE") ~= "0"
local start, cop, wall, target, busts = 0, nil, nil, nil, 0
local recovered, routed, contact = false, false, false
local function check(ok, what)
  if not ok then engine.quit(); error("POLICE RECOVERY FAILED: " .. what, 0) end
end
engine.on("busted", function() busts = busts + 1 end)
engine.on("contact", function(a, b)
  if (a == cop and b == wall) or (a == wall and b == cop) then contact = true end
end)
engine.on("init", function()
  math.randomseed(5)
  require("lib.prefabs").build()
  require("lib.sfx").build()
  police.build()
  engine.spawn{pos = {0, -0.5, 0}, size = {1000, 1, 1000}, body = "static", tag = "ground"}
  local ax, az = city.node(0, 0)
  local bx, bz = city.node(1, 1)
  G.spawn, G.cash = {bx, 1.2, bz}, 1000
  require("lib.player").spawn(bx, 1.2, bz, 0)
  target = G.player
  local yaw = math.atan(bx - ax - 15, bz - az - 10)
  -- The car starts within sight range, heading squarely into a fence. Its
  -- low top leaves the sight ray clear. Both graph roads around it are open.
  if obstructed then
    wall = engine.spawn{pos = {(ax + bx) / 2, 0.75, (az + bz) / 2}, size = {38, 1.5, 2},
                        yaw = yaw, body = "static", tag = "wall"}
  end
  cop = vehicle.spawn(ax + 15, az + 10, yaw, 1, "cop", "cop")
  police.cops[cop] = {id = cop, stuck = 0, reverse = 0,
                     red = engine.spawn{mesh = "beacon"}, blue = engine.spawn{mesh = "beacon"}}
  wanted.set(1)
  start = engine.time()
end)
engine.on("tick", function()
  if not cop then return end
  if busts == 1 then
    check(not obstructed or (contact and recovered and routed), "fence contact must lead to road recovery before arrest")
    check(obstructed or not recovered, "unobstructed chase must not detour")
    check(wanted.stars() == 0 and police.count() == 0, "arrest clears wanted and cops")
    print(string.format("POLICE RECOVERY PASSED: obstacle=%s arrest=%.2fs contact=%s routed=%s", tostring(obstructed),
                        engine.time() - start, tostring(contact), tostring(routed)))
    engine.quit()
    return
  end
  check(police.cops[cop] and engine.exists(cop) and police.count() == 1, "original cop must not be recycled or replaced")
  check(G.player == target, "same stationary player must remain until arrested")
  local px, _, pz = engine.pos(target)
  local cx, _, cz = engine.pos(cop)
  -- Contact with the arriving car may physically nudge the idle player.
  if U.dist2d(cx, cz, px, pz) > 7 then
    check(U.dist2d(px, pz, G.spawn[1], G.spawn[3]) < 0.1, "player must not move to help the chase")
  end
  local c = police.cops[cop]
  if c.roads_until and c.roads_until > engine.time() then
    recovered = true
    if c.goal then
      check(c.route and c.route[c.ri] == c.goal, "recovery follows its selected route waypoint")
      local a, b = city.nearest(table.unpack(c.route[1])), city.nearest(table.unpack(c.route[#c.route]))
      local linked = false
      for _, n in ipairs(city.links(a)) do if n == b then linked = true end end
      check(linked, "recovery must use an actual Harbor road edge")
      routed = true
    end
  end
  check(engine.time() - start <= 30, string.format("stationary reachable player arrested within 30s (recovered=%s)", tostring(recovered)))
end)
