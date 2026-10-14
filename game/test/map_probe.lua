-- Headless probe testing Pause Menu Map Viewer and direct 'M' key map navigation
local menu = require "lib.menu"
local map_viewer = require "lib.map_viewer"

engine.on("init", function()
  print("MAP_PROBE: starting map viewer test")

  -- 1. Open pause menu and navigate to map page
  menu.show()
  assert(menu.open and engine.paused(), "menu should be open and paused")
  menu.go("map")
  assert(menu.page == "map", "menu should be on map page")
  assert(map_viewer.inited, "map viewer should be initialized")

  -- 2. Test panning and zooming keys
  local start_x, start_z = map_viewer.pan_x, map_viewer.pan_z
  local start_zoom = map_viewer.zoom

  map_viewer.key("w")
  assert(map_viewer.pan_z < start_z, "pan_z should have moved north")
  map_viewer.key("d")
  assert(map_viewer.pan_x > start_x, "pan_x should have moved east")
  map_viewer.key("+")
  assert(map_viewer.zoom > start_zoom, "zoom should have increased")
  map_viewer.key("-")
  map_viewer.key("space")
  print("MAP_PROBE: navigation keys verified")

  -- 3. Return back
  menu.back()
  assert(menu.page == "main", "back should return to main pause page")
  menu.close()
  assert(not menu.open and not engine.paused(), "menu should be closed")

  -- 4. Direct 'M' key toggle
  engine.emit("key", "m", true)
  assert(menu.open and menu.page == "map", "'M' key should open map viewer directly")
  engine.emit("key", "m", true)
  assert(not menu.open and not engine.paused(), "'M' key should toggle map viewer closed")

  print("ALL MAP VIEWER CHECKS PASSED")
  engine.quit()
end)
