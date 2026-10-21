-- City radio: one-liners that answer what you just did, by where and when.
-- Hand-written; lib/story.lua picks the best fit. {area} and {street} are
-- filled in from where you are.
local story = require "lib.story"
local add = story.add

add{id = "stunt", on = "stunt", cooldown = 180,
    text = "RADIO: Reports of a car in the air over {area}. Again."}
add{id = "stunt_kupittaa", on = "stunt", area = "Kupittaa", cooldown = 300,
    text = "RADIO: Kupittaa sports park would like its car back on the ground."}
add{id = "stunt_big", on = "stunt", cooldown = 300, when = function(_, air) return (air or 0) > 3 end,
    text = "RADIO: Witnesses say the car stayed up for whole seconds."}

add{id = "busted", on = "busted", cooldown = 240,
    text = "RADIO: An arrest near {area}. Turku's police are a patient lot."}
add{id = "lost_cops", on = "wanted_changed", cooldown = 240,
    when = function(_, level, old) return level == 0 and (old or 0) >= 2 end,
    text = "RADIO: Police have lost a suspect somewhere around {area}."}

add{id = "mission", on = "mission_passed", cooldown = 300,
    text = "RADIO: Word travels fast in {area}. People are talking about you."}
add{id = "carjack", on = "carjacked", cooldown = 240,
    text = "RADIO: A car on {street} changed hands without the paperwork."}
add{id = "boom", on = "explosion", cooldown = 240,
    text = "RADIO: Black smoke over {area}. Fire crews are on their way."}
add{id = "boom_tori", on = "explosion", area = "Kauppatori", cooldown = 300,
    text = "RADIO: Smoke over Kauppatori. The market stalls are fine, mostly."}
add{id = "hospital", on = "respawned", map = "turku", cooldown = 300,
    text = "RADIO: TYKS discharges a patient who should really be more careful."}
add{id = "night_drive", on = "vehicle_enter", hours = {23, 4}, cooldown = 600,
    text = "RADIO: Quiet night on the roads. Mind the last Föli buses."}
add{id = "rain", on = "weather", cooldown = 300,
    when = function(_, kind, was) return (kind == "rain" or kind == "storm") and was ~= "rain" and was ~= "storm" end,
    text = "RADIO: Rain moving in over {area}. Wet roads: give yourself room to brake."}
add{id = "storm", on = "weather", cooldown = 600, when = function(_, kind) return kind == "storm" end,
    text = "RADIO: A proper autumn downpour over {area}. Stay in if you can. You won't, will you?"}
add{id = "clears", on = "weather", cooldown = 300,
    when = function(_, kind, was) return kind == "clear" and (was == "rain" or was == "storm") end,
    text = "RADIO: The rain has passed. {area} steams gently in the sun."}
add{id = "cashvan", on = "cashvan_robbed", cooldown = 300,
    text = "RADIO: A Lumis cash van robbed on {street}. The bags were not insured for this."}
