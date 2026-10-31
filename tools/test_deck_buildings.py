#!/usr/bin/env python3
"""Buildings on decks over roads: Tyks' Majakkasairaala stands over
Helsinginkatu's tunnel, and no road under a deck building runs into it."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class DeckTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", DECK_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "600"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("DECK_OK", out, out[-3000:])

    def test_importer_keeps_majakka(self):
        text = (ROOT / "game" / "maps" / "turku_osm.lua").read_text(encoding="utf-8")
        line = next((l for l in text.splitlines() if '"TYKS Majakkasairaala"' in l), "")
        self.assertIn("span = true", line, "Majakkasairaala left out or not on a deck")


if __name__ == "__main__":
    unittest.main()
