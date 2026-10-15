-- Probe checking Vanha Suurtori & Tuomiokirkko 500m slice:
-- Cathedral compound, steps, Brinkkalan talo with peace balcony, and Porthan monument.
local suurtori = require "systems.suurtori"

engine.on("init", function()
  assert(suurtori.cathedral_id and engine.exists(suurtori.cathedral_id), "Tuomiokirkko cathedral entity missing")
  assert(engine.mesh_of(suurtori.cathedral_id) == "tuomiokirkko_cathedral", "wrong mesh for cathedral")
  print("TUOMIOKIRKKO_CATHEDRAL_OK id=" .. suurtori.cathedral_id)

  assert(suurtori.brinkkala_id and engine.exists(suurtori.brinkkala_id), "Brinkkalan talo entity missing")
  assert(engine.mesh_of(suurtori.brinkkala_id) == "brinkkala_facade", "wrong mesh for Brinkkala")
  print("BRINKKALA_BALCONY_OK id=" .. suurtori.brinkkala_id)

  assert(suurtori.porthan_id and engine.exists(suurtori.porthan_id), "Porthan monument missing")
  print("PORTHAN_MONUMENT_OK id=" .. suurtori.porthan_id)

  assert(suurtori.plaza_id and engine.exists(suurtori.plaza_id), "Suurtori plaza slab missing")
  print("SUURTORI_PLAZA_OK id=" .. suurtori.plaza_id)

  print("ALL SUURTORI CHECKS PASSED")
  engine.quit()
end)
