-- The story that ties the missions together: three people who call you
-- with work, and Radio Åbo's morning host, who notices.
--   Rauha, who drove the Pöli line 1 for thirty years and now moves things
--     that don't fit on a bus: 01 Joyride -> 09 the bus -> 10 the archipelago.
--   Jonne from Runosmäki, who races: 02 Street Race -> 11 Häsburger Express.
--   Setä ("Uncle"), who runs things from a sauna raft on the Aura:
--     03 Demolition, and 04 Getaway -> 05 -> 06 -> 07 -> 08 the Pansio heist.
--   Aamu-Maija, the voice of Radio Åbo, ties them together and calls the
--     ending once every mission is done.
-- Each mission has a line when it starts (the caller, on the phone) and one
-- when it's passed; those go out at once, whatever the radio said just
-- before (`urgent`), and beat the radio's general lines (weight).
local story = require "lib.story"
local G = require "lib.state"

local ARC = {
  ["01_joyride"] = {
    start = "RAUHA (PHONE): New in town and no wheels? Every car in Turku has an owner who's in no hurry. Borrow one.",
    pass = "RAUHA (PHONE): Neat. Thirty years on the number 1, I know a driver when I see one. Keep the phone on.",
  },
  ["09_foli_transit"] = {
    start = "RAUHA (PHONE): Pöli is short of drivers again. The uniform's in the depot. Nobody checks, trust me.",
    pass = "RAUHA (PHONE): Every stop, nearly on time. Pöli will put it in the newsletter. Now, about a boat...",
  },
  ["10_archipelago_run"] = {
    start = "RAUHA (PHONE): A speedboat at the harbour berths, and a buyer out past Ruissalo. The islands are faster than the roads.",
    pass = "RAUHA (PHONE): Out to the islands and back without a scratch. I'm retiring for real this time. Probably.",
  },
  ["02_checkpoints"] = {
    start = "JONNE (PHONE): Heard you can drive. Runosmäki says you can't. Checkpoints, tonight, prove it.",
    pass = "JONNE (PHONE): OK that was actually fast. Häsburger needs a courier who doesn't stop for anything. I said you.",
  },
  ["11_hesburger_express"] = {
    start = "JONNE (PHONE): Orders are stacking up at Häsburger. Hot when they get there or it's on you.",
    pass = "JONNE (PHONE): Five stars from every customer. Häsburger wants you full time. I told them you're booked.",
  },
  ["03_demolition"] = {
    start = "SETÄ (PHONE): Someone put crates all over my square. Clear them off. Use the car, that's what it's for.",
    pass = "SETÄ (PHONE): Clean. I like clean. Come down to the river some evening, we'll talk.",
  },
  ["04_getaway"] = {
    start = "SETÄ (PHONE): The boys are doing a withdrawal. You wait, they load, you drive. The police are slow on Tuesdays.",
    pass = "SETÄ (PHONE): Everyone home, nobody followed. You've got a future. Not a long one if you talk.",
  },
  ["05_cargo"] = {
    start = "SETÄ (PHONE): A white car with something fragile in the back. Drive it like your grandmother's in it.",
    pass = "SETÄ (PHONE): Not one bottle broken. The customer in Raisio sends his regards.",
  },
  ["06_takedown"] = {
    start = "SETÄ (PHONE): A black car has been asking questions about me. It shouldn't be able to drive afterwards.",
    pass = "SETÄ (PHONE): No more questions. Good. The sauna raft is warm when you want it.",
  },
  ["07_smuggler"] = {
    start = "SETÄ (PHONE): Packages around town, one at a time, then the drop. Don't open them. Really, don't.",
    pass = "SETÄ (PHONE): All delivered. Now the big one. Pansio. I've wanted that armoured car for years.",
  },
  ["08_pansio_heist"] = {
    start = "SETÄ (PHONE): The navy keeps a Sisu Pasi at Pansio and hardly uses it. We will. Gate's weak on the left.",
    pass = "SETÄ (PHONE): An armoured car on my raft. The neighbours will talk. Let them. You're family now.",
  },
}

for id, lines in pairs(ARC) do
  story.add{id = "arc_start_" .. id, on = "mission_started", weight = 10, urgent = true,
            when = function(_, def) return def and def.id == id end, text = lines.start}
  story.add{id = "arc_pass_" .. id, on = "mission_passed", weight = 10, urgent = true,
            when = function(_, def) return def and def.id == id end, text = lines.pass}
end

-- Every mission passed: the ending (it beats the last one's own line).
story.add{id = "arc_end", on = "mission_passed", weight = 20, urgent = true,
          when = function(_, def)
            -- (The story's missions on this map, not a mod's; the one just
            -- passed may not be marked yet.)
            local any = false
            for _, d in ipairs(require("lib.mission").defs) do
              if ARC[d.id] then
                if not ((G.passed or {})[d.id] or (def and d.id == def.id)) then return false end
                any = true
              end
            end
            return any
          end,
          text = "RADIO ÅBO, AAMU-MAIJA: Turku's taxis, buses, boats and kebabs all seem to answer to one new name this year. "
            .. "Rauha, Jonne and a man on a sauna raft won't tell us who. Welcome to Åbo, whoever you are."}

return ARC
