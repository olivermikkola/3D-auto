-- Businesses to buy: a kebab grill, a kiosk and a taxi firm, each at a real
-- place of its kind near the centre. Once yours it earns while you play,
-- into its till (up to a day's worth); walk up and press R to empty it. The
-- one you were last at is where the next session starts. The taxi firm also
-- puts a quarter on every fare.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local pois = require "lib.pois"
local roadnet = require "lib.roadnet"
local shop = require "lib.shop"

local B = {list = {}, by_id = {}}
-- Earnings are per hour of game time (an hour is two minutes of play).
B.KINDS = {
  {id = "grill", name = "KEBAB-GRILLI", price = 3000, hourly = 40, find = {amenity = "fast_food", cuisine = {"kebab", "kebab;pizza", "pizza;kebab"}}},
  {id = "kiosk", name = "Ä-KIOSKI", price = 6000, hourly = 90, find = {shop = "kiosk"}},
  {id = "taxi", name = "TAKSI ÅBO", price = 15000, hourly = 150, fares = 0.25, find = {amenity = "taxi"}},
}
B.TILL_HOURS = 24 -- a till holds at most this many hours' takings
B.APART = 300     -- m between any two
local GREEN, GREY, SALE = {0.35, 0.95, 0.45}, {0.75, 0.75, 0.7}, {1, 0.82, 0.3}

-- G.businesses ({id = till} for each one owned) and G.home (the one you
-- were last at) are saved with the rest of the progress (lib/progress).

local function hours_per_second() return 24 / require("lib.daynight").DAY_LENGTH end

function B.owned(id) return G.businesses[id] ~= nil end

-- Where to stand for place p: on the pavement in front of it, between the
-- kerb of the nearest street and the place. Also which way is the place.
local function front(p)
  local ei, _, rx, rz = roadnet.nearest_edge(p.x, p.z, true)
  if not ei then return p.x, p.z, 1, 0 end
  local e = roadnet.net().edges[ei]
  local dx, dz = p.x - rx, p.z - rz
  local d = math.sqrt(dx * dx + dz * dz)
  if d < 1e-3 then return p.x, p.z, 1, 0 end
  local out = math.min(d - 0.5, e.width / 2 + 2.2)
  return rx + dx / d * out, rz + dz / d * out, dx / d, dz / d
end

-- Its sign on a post: the name, and the price until it's yours.
local function sign_mesh(name, title, under, color)
  -- (A letter is 6/7 of its height wide, gap included.)
  local wide = math.max(utf8.len(title) * 0.36, utf8.len(under) * 0.22) * 6 / 7 + 0.5
  local parts = {
    {mesh = "cube", pos = {0, 1.5, 0}, size = {0.12, 3.0, 0.12}, color = {0.2, 0.2, 0.22}},
    {mesh = "cube", pos = {0, 3.3, 0}, size = {wide, 1.1, 0.08}, color = {0.06, 0.18, 0.1}},
    {mesh = "cube", pos = {0, 3.3, 0}, size = {wide + 0.12, 1.22, 0.05}, color = {0.85, 0.85, 0.8}},
  }
  for _, side in ipairs{-1, 1} do
    parts[#parts + 1] = {text = title, height = 0.36, depth = 0.02, pos = {0, 3.5, side * 0.05}, yaw = side > 0 and 0 or math.pi,
                         color = color, emissive = 0.8}
    parts[#parts + 1] = {text = under, height = 0.22, depth = 0.02, pos = {0, 3.02, side * 0.05}, yaw = side > 0 and 0 or math.pi,
                         color = {0.95, 0.95, 0.9}, emissive = 0.6}
  end
  engine.mesh(name, parts)
end

local function prompt(b)
  if not B.owned(b.id) then
    return string.format("R: BUY %s $%d (EARNS $%d AN HOUR)", b.name, b.price, b.hourly)
  end
  local till = math.floor(G.businesses[b.id])
  return till > 0 and string.format("%s: R TO TAKE $%d FROM THE TILL", b.name, till) or (b.name .. ": YOURS. THE TILL IS EMPTY")
end

local function use(b)
  if not B.owned(b.id) then
    if require("lib.wanted").stars() > 0 then return U.message("NOT WITH THE COPS ON YOU", 2) end
    if not shop.pay(b.price) then return end
    G.businesses[b.id] = 0
    G.home = b.id
    U.message(b.name .. " IS YOURS", 4)
    engine.emit("business_bought", b.id, b.name)
  else
    local till = math.floor(G.businesses[b.id])
    if till <= 0 then return U.message("THE TILL IS EMPTY", 2) end
    G.businesses[b.id] = G.businesses[b.id] - till
    G.cash = G.cash + till
    engine.play("buy", {ui = true})
    U.message(string.format("+$%d FROM %s", till, b.name), 3)
    engine.emit("business_collected", b.id, till)
  end
  require("lib.progress").touch()
end

function B.build()
  B.list, B.by_id = {}, {}
  if not roadnet.net() then return end
  local cx, cz = city.place("lot")
  for _, k in ipairs(B.KINDS) do
    local q = {from = {cx, cz}}
    for key, v in pairs(k.find) do q[key] = v end
    -- The nearest of its kind that isn't next door to another of yours.
    local p
    for _, c in ipairs(pois.find(q)) do
      local apart = true
      for _, o in ipairs(B.list) do if U.dist2d(c.x, c.z, o.x, o.z) < B.APART then apart = false end end
      if apart then p = c break end
    end
    if p then
      local x, z, fx, fz = front(p)
      local b = {id = k.id, name = k.name, price = k.price, hourly = k.hourly, fares = k.fares, place = p.name, x = x, z = z}
      sign_mesh("business_" .. k.id .. "_sale", k.name, string.format("FOR SALE $%d", k.price), SALE)
      sign_mesh("business_" .. k.id .. "_own", k.name, "YOURS", GREEN)
      -- At the back of the pad, toward the place, its faces along the street.
      local sx, sz = x + fx * 1.9, z + fz * 1.9
      b.sign = engine.spawn{mesh = "business_" .. k.id .. (B.owned(k.id) and "_own" or "_sale"), pos = {sx, U.ground(sx, sz), sz},
                            yaw = math.atan(fx, fz), tag = "prop"}
      b.zone = shop.add{name = k.name, x = x, z = z, hw = 1.6, hd = 1.6, letter = "$", color = B.owned(k.id) and GREEN or GREY,
                        prompt = function() return prompt(b) end, use = function() use(b) end}
      local y = U.ground(x, z)
      b.pad = engine.spawn{mesh = "plane", pos = {x, y + 0.12, z}, size = {3, 1, 3}, color = {GREEN[1], GREEN[2], GREEN[3], 0.5}, tag = "prop"}
      B.list[#B.list + 1] = b
      B.by_id[b.id] = b
    end
  end
  B.go_home()
end

-- A new session starts at the business you were last at.
function B.go_home()
  local home = G.home and B.by_id[G.home]
  if home and B.owned(home.id) and G.player and not G.vehicle then
    engine.set_pos(G.player, home.x, U.ground(home.x, home.z) + 1.2, home.z)
    engine.set_vel(G.player, 0, 0, 0)
    return true
  end
end

-- The tills fill while you play (saved once a minute).
local since_save = 0
engine.on("tick", function(dt)
  local rate = hours_per_second() * dt
  local any = false
  for _, b in ipairs(B.list) do
    local till = G.businesses[b.id]
    if till then G.businesses[b.id], any = math.min(b.hourly * B.TILL_HOURS, till + b.hourly * rate), true end
    b.zone.color = till and GREEN or GREY
    if (till ~= nil) ~= (b.shown == "own") then
      b.shown = till and "own" or "sale"
      engine.set_mesh(b.sign, "business_" .. b.id .. "_" .. b.shown)
    end
  end
  since_save = since_save + dt
  if any and since_save > 60 then
    since_save = 0
    require("lib.progress").touch()
  end
  -- The one you're at is where you'll start next time.
  local here = shop.current()
  for _, b in ipairs(B.list) do
    if here == b.zone and B.owned(b.id) and G.home ~= b.id then
      G.home = b.id
      require("lib.progress").touch()
    end
  end
end)

-- The taxi firm's share of every fare.
engine.on("fare_paid", function(base, tip)
  local amount = (base or 0) + (tip or 0)
  for _, b in ipairs(B.list) do
    if b.fares and B.owned(b.id) and amount > 0 then
      local extra = math.floor(amount * b.fares + 0.5)
      G.cash = G.cash + extra
      U.message(string.format("+$%d %s'S CUT", extra, b.name), 2)
    end
  end
end)

return B
