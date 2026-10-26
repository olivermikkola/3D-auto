-- The graphics quality setting (lib/settings "quality": 1 low, 2 medium,
-- 3 high) for what it sets beyond shadows and view distance: how many cars
-- and people there are, and whether the bus stops have shelters.
local settings = require "lib.settings"

local Q = {}

Q.TRAFFIC = {12, 20, 28} -- cars about (systems/traffic)
Q.PEDS = {20, 40, 60}    -- people about (systems/peds)

function Q.tier() return settings.get("quality") or 2 end

-- The entry for the current tier from a {low, medium, high} list.
function Q.pick(list) return list[Q.tier()] end

-- Call fn(tier) now and whenever it changes.
function Q.watch(fn) settings.watch("quality", fn) end

return Q
