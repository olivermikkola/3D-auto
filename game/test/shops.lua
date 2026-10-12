-- The gun shop, Pay 'n' Spray and car dealer, and what they save. CI runs:
--   SHOP_TEST=1 auto game --headless 900 --save-dir DIR   buy ammo, a car, a respray; quit
--   SHOP_TEST=2 ...                                       ammo and the car (in its new color) came back
-- Steps count frames: buying happens in menus, which pause the game.
local G = require "lib.state"
local shop = require "lib.shop"
local menu = require "lib.menu"
local wanted = require "lib.wanted"
local vehicle = require "lib.vehicle"
local gunshop = require "systems.gunshop"
local paint = require "systems.paintshop"
local dealer = require "systems.dealer"
local phase = tonumber(os.getenv("SHOP_TEST"))

local function check(ok, what)
  if not ok then engine.quit(); error("SHOP TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end
local function key(k) engine.emit(menu.open and "menu_key" or "key", k, true) end
local function pick(label)
  for i, item in ipairs(menu.items()) do
    if item.label == label then
      menu.sel = i
      return key("enter")
    end
  end
  error("no menu item " .. label)
end
local function near(id, x, z, r)
  local ex, _, ez = engine.pos(id)
  return ex and math.abs(ex - x) < r and math.abs(ez - z) < r
end
local function drive(id)
  if G.player then engine.despawn(G.player) end
  G.player, G.vehicle = nil, id
end
local function park_in_bay(id)
  engine.set_pos(id, paint.x, 0.95, paint.z)
  engine.orient(id, 0)
  engine.set_vel(id, 0, 0, 0)
  engine.set_angvel(id, 0, 0, 0)
end

local steps = {}

if phase == 1 then
  steps[30] = function()
    check(#shop.list == 3, "three shops open for business")
    check(G.cash == 0 and G.ammo.pistol == 36 and G.ammo.smg == 0 and G.owned_car == nil, "a new game: no cash, starting ammo, no car")

    -- Gun shop, on foot.
    engine.set_pos(G.player, gunshop.x, 1.1, gunshop.z)
    check(shop.current() and shop.current().name == "GUN SHOP", "standing at the gun shop counter")
    key("r")
    check(menu.open and menu.page == "gunshop" and engine.paused(), "R opens the gun shop (and pauses)")
    pick("PISTOL AMMO (+24)")
    check(G.ammo.pistol == 36 and G.cash == 0, "no cash, no ammo")
    G.cash = 1000
    pick("PISTOL AMMO (+24)")
    check(G.ammo.pistol == 60 and G.cash == 940, "pistol ammo: +24 for $60")
    pick("SMG (+90 ROUNDS)")
    check(G.ammo.smg == 90 and G.cash == 690, "the SMG: 90 rounds for $250")
    key("escape")
    check(not menu.open and not engine.paused(), "Esc leaves the shop")

    -- Car dealer, on foot.
    engine.set_pos(G.player, dealer.x + 0.6, 1.1, dealer.z)
    check(shop.current() and shop.current().name == "CAR DEALER", "standing at the dealer's booth")
    key("r")
    pick("YELLOW CAR")
    check(G.cash == 90 and not menu.open, "a car costs $600 and buying closes the menu")
    check(dealer.car and engine.mesh_of(dealer.car) == "car3", "it's the yellow one")
    check(near(dealer.car, dealer.space[1], dealer.space[2], 1), "delivered to your space")
    check(G.owned_car and G.owned_car.color == 3, "and recorded as yours")
    G.cash = 2000

    -- Drive it into the spray shop; it needs a moment to settle on its wheels.
    drive(dealer.car)
    engine.set_pos(dealer.car, gunshop.x, 1, gunshop.z)
    check(shop.current() == nil, "the gun shop doesn't serve drivers")
    park_in_bay(dealer.car)
  end
  steps[120] = function()
    local car = dealer.car
    check(shop.current() and shop.current().name == "PAY 'N' SPRAY", "parked in the spray bay")
    wanted.set(2)
    wanted.seen = true
    key("r")
    check(not menu.open and G.cash == 2000, "no respray while the cops are watching")
    wanted.seen = false
    key("r")
    check(menu.open and menu.page == "paintshop", "out of sight, R opens the paint menu")
    pick("WHITE")
    check(engine.mesh_of(car) == "car5", "the car is white now")
    check(wanted.stars() == 0, "and the wanted level is gone")
    check(G.cash == 1700, "a 2-star respray costs $300")
    check(G.owned_car.color == 5, "your car's new color is remembered")
    key("r")
    pick("WHITE")
    check(G.cash == 1700 and menu.open, "the color it already is costs nothing")
    key("escape")
    check(not menu.open, "Esc leaves the spray shop")

    local cop = vehicle.spawn(paint.x + 30, paint.z, 0, 1, nil, "cop")
    drive(cop)
    park_in_bay(cop)
    engine.set_pos(car, dealer.space[1], 0.95, dealer.space[2])
  end
  steps[200] = function()
    key("r")
    check(not menu.open and paint.refusal(G.vehicle) == "WE DON'T PAINT COP CARS", "no cop cars")
    G.cash = 777
    print("SHOP TEST PHASE 1 PASSED")
    engine.quit()
  end
elseif phase == 2 then
  steps[30] = function()
    check(G.cash == 777, "cash came back")
    check(G.ammo.pistol == 60 and G.ammo.smg == 90, "ammo came back")
    check(G.owned_car and G.owned_car.color == 5, "you still own a car")
    check(dealer.car and engine.mesh_of(dealer.car) == "car5", "it's back, still white")
    check(near(dealer.car, dealer.space[1], dealer.space[2], 1), "parked in your space")
    require("lib.progress").reset()
    check(G.owned_car == nil and G.ammo.pistol == 36 and G.ammo.smg == 0, "a new game takes the car and ammo back")
    print("SHOP TEST PASSED")
    engine.quit()
  end
end

local n = 0
engine.on("frame", function()
  n = n + 1
  if steps[n] then steps[n]() end
end)
