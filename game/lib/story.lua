-- A story that reacts: hand-written fragments (game/story/), each with the
-- event it answers and when it fits, and a scorer that picks the best one
-- for what just happened. The scorer is deterministic: the same state gives
-- the same pick, so tests stay stable. Variety comes from cooldowns.
--
--   story.add{id = "...", on = "stunt", text = "..." or function(ctx) return "..." end,
--             weight = 1, cooldown = 120, area = "Kupittaa", hours = {22, 4},
--             stars = {1, 5}, when = function(ctx, ...) return true end}
--
-- ctx: event, area and street (by name, on maps drawn from survey data),
-- hour, stars, map id, and the event's own arguments in ctx.args.
-- A pick goes out as engine.emit("story", text); the HUD shows it like the
-- police radio. At most one every GAP seconds, so it never chatters.
local G = require "lib.state"
local U = require "lib.util"

local S = {fragments = {}, GAP = 20}
local next_at, last_said = 0, {}

function S.add(f)
  assert(f.id and f.on and f.text, "a story fragment needs id, on and text")
  S.fragments[#S.fragments + 1] = f
end

local function in_hours(h, span)
  local a, b = span[1], span[2]
  if a <= b then return h >= a and h < b end
  return h >= a or h < b -- wraps past midnight
end

function S.context(event, ...)
  local ctx = {event = event, args = {...}, stars = require("lib.wanted").stars(),
               hour = require("lib.daynight").hour, map = require("lib.city").map().id}
  local x, _, z = U.player_pos()
  if x and G.city and G.city.network then ctx.street, ctx.area = require("lib.roadnet").where(x, z) end
  return ctx
end

-- Does fragment f fit ctx, and how well: nil, or a score (more specific
-- fragments beat general ones; weight breaks the rest).
function S.score(f, ctx, now)
  if f.on ~= ctx.event then return nil end
  if f.cooldown and last_said[f.id] and now < last_said[f.id] + f.cooldown then return nil end
  local s = f.weight or 1
  if f.map then if f.map ~= ctx.map then return nil end s = s + 1 end
  if f.area then
    if not (ctx.area and ctx.area:find(f.area, 1, true)) then return nil end
    s = s + 3
  end
  if f.hours then if not in_hours(ctx.hour or 12, f.hours) then return nil end s = s + 1 end
  if f.stars then
    if ctx.stars < f.stars[1] or ctx.stars > f.stars[2] then return nil end
    s = s + 1
  end
  if f.when then
    if not f.when(ctx, table.unpack(ctx.args)) then return nil end
    s = s + 1
  end
  return s
end

-- The best fragment for ctx (ties go to the id first in order), or nil.
function S.pick(ctx, now)
  local best, best_s
  for _, f in ipairs(S.fragments) do
    local s = S.score(f, ctx, now or engine.time())
    if s and (not best_s or s > best_s or (s == best_s and f.id < best.id)) then best, best_s = f, s end
  end
  return best
end

function S.text(f, ctx)
  local t = type(f.text) == "function" and f.text(ctx, table.unpack(ctx.args)) or f.text
  return (t:gsub("{area}", ctx.area or "town"):gsub("{street}", ctx.street or ctx.area or "the street"))
end

-- An event happened: say the best fragment for it, if one fits and the
-- last one wasn't just now.
function S.react(event, ...)
  local now = engine.time()
  if now < next_at then return end
  local ctx = S.context(event, ...)
  local f = S.pick(ctx, now)
  if not f then return end
  last_said[f.id], next_at = now, now + S.GAP
  engine.emit("story", S.text(f, ctx), f.id)
  return f
end

-- Forget what was said (tests; a new game).
function S.reset() next_at, last_said = 0, {} end

S.EVENTS = {"stunt", "busted", "wanted_changed", "mission_passed", "carjacked", "explosion", "respawned",
            "vehicle_enter", "purchase", "weather", "cashvan_robbed"}
for _, ev in ipairs(S.EVENTS) do
  engine.on(ev, function(...) S.react(ev, ...) end)
end

return S
