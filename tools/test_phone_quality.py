"""A phone starts on the low graphics preset once; after that its choice stands.

web/index.html adds phone=1 (PHONE=1 to the game) on a touch screen;
lib/settings.lua then sets quality LOW the first time, phones that played
before included, and remembers it did ("phone_low").
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


def run(save_dir, phone):
    env = os.environ.copy()
    env.pop("PHONE", None)
    env.update(MAP="starter", SEED="1337")
    if phone:
        env["PHONE"] = "1"
    res = subprocess.run([str(BINARY), "game", "--headless", "10", "--save-dir", str(save_dir)],
                         cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)
    assert res.returncode == 0, res.stdout + res.stderr


def setting(save_dir, key):
    """The saved value; a game that never changed a setting saved none (MEDIUM)."""
    path = Path(save_dir) / "settings.lua"
    if not path.exists():
        return {"quality": "2", "shadows": "true", "volume": "70"}[key]
    return re.search(rf"\b{key} = (\w+)", path.read_text(encoding="utf-8")).group(1)


@unittest.skipUnless(BINARY.exists(), "build the game first: cargo build --release")
class PhoneQualityTests(unittest.TestCase):
    def test_a_phone_starts_low_once(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, phone=True)
            self.assertEqual(setting(d, "quality"), "1")
            self.assertEqual(setting(d, "shadows"), "false")
            # The player picks HIGH in the menu: the next start keeps it.
            path = Path(d) / "settings.lua"
            path.write_text(path.read_text(encoding="utf-8").replace("quality = 1", "quality = 3"), encoding="utf-8")
            run(d, phone=True)
            self.assertEqual(setting(d, "quality"), "3")

    def test_a_phone_that_played_before_goes_low(self):
        with tempfile.TemporaryDirectory() as d:
            # Settings saved on medium before this change (volume turned down).
            (Path(d) / "settings.lua").write_text("return {quality = 2, shadows = true, view = 100, volume = 40}\n", encoding="utf-8")
            run(d, phone=True)
            self.assertEqual(setting(d, "quality"), "1")
            self.assertEqual(setting(d, "volume"), "40")

    def test_a_computer_keeps_medium(self):
        with tempfile.TemporaryDirectory() as d:
            run(d, phone=False)
            self.assertEqual(setting(d, "quality"), "2")


if __name__ == "__main__":
    unittest.main()
