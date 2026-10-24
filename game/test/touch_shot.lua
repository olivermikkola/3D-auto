-- Screenshots of the touch controls: TOUCH_SHOT=foot|car|menu|settings|map with
-- --screenshot out.ppm --frames 90 --size 844x390 (a phone held sideways).
-- A thumb rests on the left stick so it shows too.
local G = require "lib.state"
local touch = require "lib.touch"
local vehicle = require "lib.vehicle"

local what = os.getenv("TOUCH_SHOT")
local function t(phase, id, x, y) engine.emit("touch", phase, id, x, y) end
local function tap(label)
  local x, y = touch.button_center(label)
  if x then t("start", 9, x, y); t("end", 9, x, y) end
end

local frame = 0
engine.on("frame", function()
  frame = frame + 1
  if frame == 2 then
    local px, _, pz = engine.pos(G.player)
    if what == "car" then vehicle.spawn(px + 3, pz, 0, 2) end
    t("start", 1, 120, engine.screen() and select(2, engine.screen()) - 110)
  elseif frame == 20 and what == "car" then tap("CAR")
  elseif frame == 40 and what ~= "foot" and what ~= "car" then tap("II")
  elseif frame == 45 and (what == "settings" or what == "map") then
    local menu = require "lib.menu"
    local want = string.upper(what)
    for i, r in pairs(menu.layout().rows) do
      if menu.items()[i].label == want then
        t("start", 8, r.x + 20, r.y + 10); t("end", 8, r.x + 20, r.y + 10)
        break
      end
    end
  elseif frame == 55 and what == "settings" then
    -- A drag up the page: scrolls it down.
    t("start", 8, 400, 330)
    for y = 330, 150, -10 do t("move", 8, 400, y) end
    t("end", 8, 400, 150)
  elseif frame == 50 then
    local _, h = engine.screen()
    t("move", 1, 150, h - 140)
  end
end)
