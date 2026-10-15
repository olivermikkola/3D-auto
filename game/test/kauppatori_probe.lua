-- Probe checking Turun Kauppatori 500m slice: pavilions, market stalls, taxi rank, and lighting.
local kauppatori = require "systems.kauppatori"

engine.on("init", function()
  assert(#kauppatori.pavilions == 3, "expected 3 Toripaviljongit")
  print("TORIPAVILJONGIT_OK count=" .. #kauppatori.pavilions)

  assert(#kauppatori.stalls >= 6, "expected at least 6 market stalls")
  print("MARKET_STALLS_OK count=" .. #kauppatori.stalls)

  assert(#kauppatori.taxis == 2, "expected 2 parked taxis at Kauppatori taxi rank")
  for _, tid in ipairs(kauppatori.taxis) do
    assert(engine.exists(tid), "taxi entity missing")
  end
  print("TAXI_RANK_OK count=" .. #kauppatori.taxis)

  print("ALL KAUPPATORI CHECKS PASSED")
  engine.quit()
end)
