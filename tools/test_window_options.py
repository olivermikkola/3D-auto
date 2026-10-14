"""Exercise launch flags through the real binary, without opening a window."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class WindowOptionsTests(unittest.TestCase):
    def run_game(self, lua, *options):
        self.assertTrue(BINARY.is_file(), "build with cargo build --release before these tests")
        with tempfile.TemporaryDirectory(prefix="auto-launch-") as directory:
            folder = Path(directory)
            game = folder / "game"
            game.mkdir()
            (game / "main.lua").write_text(lua, encoding="utf-8")
            (game / "lib").mkdir()
            shutil.copyfile(ROOT / "game" / "lib" / "settings.lua", game / "lib" / "settings.lua")
            saves = folder / "saves"
            saves.mkdir()
            command = [str(BINARY), str(game), "--save-dir", str(saves), *options]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
            return result

    def test_help_documents_fullscreen(self):
        result = subprocess.run([str(BINARY), "--help"], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--fullscreen", result.stdout)
        self.assertIn("--fps N", result.stdout)

    def test_fullscreen_launch_overrides_saved_windowed_setting(self):
        result = self.run_game('''
assert(engine.save("settings", {fullscreen = false}))
local settings = require "lib.settings"
assert(engine.fullscreen(), "--fullscreen must survive settings initialization")
assert(settings.get("fullscreen"), "menu must show the effective fullscreen state")
assert(engine.load("settings").fullscreen == false, "launch flag must not rewrite saved settings")
settings.set("fullscreen", false)
assert(not engine.fullscreen(), "menu must still be able to leave fullscreen")
assert(not settings.get("fullscreen"))
print("FULLSCREEN LAUNCH PASSED")
''', "--fullscreen", "--headless", "1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("FULLSCREEN LAUNCH PASSED", result.stdout)

    def test_fullscreen_state_survives_headless_reload(self):
        result = self.run_game('''
local settings = require "lib.settings"
if not engine.load("reload_probe") then
  assert(settings.get("fullscreen"), "fullscreen enabled at first load")
  assert(engine.save("reload_probe", true))
  engine.on("frame", function() engine.reload() end)
else
  assert(settings.get("fullscreen") and engine.fullscreen(), "fullscreen must survive reload")
  print("FULLSCREEN RELOAD PASSED")
  engine.quit()
end
''', "--fullscreen", "--headless", "3")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("FULLSCREEN RELOAD PASSED", result.stdout)

    def test_saved_fullscreen_still_applies_without_launch_flag(self):
        result = self.run_game('''
assert(engine.save("settings", {fullscreen = true}))
local settings = require "lib.settings"
assert(engine.fullscreen() and settings.get("fullscreen"))
print("SAVED FULLSCREEN PASSED")
''', "--headless", "1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SAVED FULLSCREEN PASSED", result.stdout)

    def test_fps_accepts_zero_and_rejects_invalid_values(self):
        for value in ("0", "30", "60", "144"):
            with self.subTest(value=value):
                result = self.run_game('print("FPS OPTION PASSED")', "--fps", value, "--headless", "1")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("FPS OPTION PASSED", result.stdout)
        for value in ("-1", "nan", "1.5", "4294967296"):
            with self.subTest(value=value):
                result = self.run_game('error("must not reach game")', "--fps", value, "--headless", "1")
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("bad fps", result.stderr)

    def test_fps_requires_a_value(self):
        result = self.run_game('error("must not reach game")', "--fps")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("--fps needs a value", result.stderr)


if __name__ == "__main__":
    unittest.main()
