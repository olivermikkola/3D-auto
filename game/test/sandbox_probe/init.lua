-- A hostile mod: tries every escape we know of and reports what happened.
-- Loaded by the autoplay test; never by the game.
local report = {}
local function blocked(name, fn)
  local ok, res = pcall(fn)
  report[#report + 1] = {name = name, blocked = not ok or res == nil or res == false}
end
local function works(name, fn)
  local ok, res = pcall(fn)
  report[#report + 1] = {name = name, blocked = not (ok and res), expect_ok = true}
end

blocked("os.execute", function() return os.execute end)
blocked("os.getenv", function() return os.getenv end)
blocked("io", function() return io end)
blocked("debug", function() return debug end)
blocked("package", function() return package end)
blocked("dofile/loadfile", function() return dofile or loadfile end)
blocked("require 'os'", function() return require("os").execute end)
blocked("require 'io'", function() return require("io").open end)
blocked("require 'debug'", function() return require("debug").getinfo end)
blocked("bytecode via load", function() return load(string.dump(function() return 1 end)) end)
blocked("path traversal in require", function() return require("..secret") end)
blocked("other mod via require", function() return require("mods.taxi.cab") end)
blocked("own files as trusted code", function() return require("test.sandbox_probe.helper") end)
blocked("trusted loader on mod files", function() return require("lib.mission").load_all("test/sandbox_probe") end)
blocked("obj outside the game", function() return engine.load_obj("x", "../../../../etc/hostname") end)
blocked("list outside the mod", function() return #engine.files("../..") > 0 end)
blocked("string metatable", function() return getmetatable("") end)
blocked("real _G", function() return _G.os and _G.os.execute end)

works("mod-local require", function() return require("helper").answer == 42 end)
works("game modules", function() return require("lib.util").clamp(5, 0, 1) == 1 end)
works("safe os subset", function() return os.time() > 0 and os.clock() >= 0 end)
works("engine API", function() return engine.exists(engine.spawn{mesh = "cube", pos = {0, -50, 0}}) end)
works("own files listed", function() return #engine.files() >= 2 end)
works("string methods", function() return ("abc"):upper() == "ABC" end)

engine.emit("sandbox_report", report)
