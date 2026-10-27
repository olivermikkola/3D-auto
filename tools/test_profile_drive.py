#!/usr/bin/env python3
"""Profile drive: a robot drives the player's car across each map for a
minute, with two stars from 10 s in (PROFILE=1 PROFILE_DRIVE=1), and no
single Lua handler call may take long enough to stutter the game.

Placing a police car used to search the whole road network (Turku ~110 ms
per car, every 1.5 s while wanted): a frozen picture all through a chase."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")

# Milliseconds for one handler call. Driving through Turku the slowest is
# ~10 ms on the Beelink (pedestrians, police); a slower CI machine gets
# room to spare.
SLOWEST_MS = 60


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class ProfileDriveTests(unittest.TestCase):
    def test_maps(self):
        for name in ("turku", "raisio"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", PROFILE="1", PROFILE_DRIVE="1",
                           PROFILE_DRIVE_SECS="70", PROFILE_DRIVE_WANTED="10")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "6000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", timeout=900)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertNotIn("[lua:", out)
                m = re.search(r"PROFILE_DRIVE: drove ([\d.]+) km .* up to (\d+) police cars", out)
                self.assertTrue(m, out)
                # (Only that it drove: how far depends on where the police
                # box it in, which differs from machine to machine.)
                self.assertGreater(float(m[1]), 0.1, "the robot didn't drive: " + out[-2000:])
                self.assertGreater(int(m[2]), 0, "no police came")
                # Not the first two seconds: loading, and the first frame
                # building the HUD's map (~24 ms here, 104 on a CI Mac).
                reports = [m.start() for m in re.finditer(r"^profile: \d", out, re.M)]
                later = out[reports[1]:] if len(reports) > 1 else ""
                slow = [(float(ms), what) for ms, what in re.findall(r"slowest Lua: ([\d.]+) ms (.*)", later)]
                self.assertTrue(slow, out)
                # One stray slow call is let off (a CI machine's hiccup: a
                # frame of the HUD once took 90 ms on Windows, never here);
                # the police search took over 100 ms with every car placed.
                # And slow for this machine: four times the run's typical
                # slowest call. A CI Mac is ~5x slower all round (the HUD's
                # frame 87 ms there, 10 here), which isn't a stutter we
                # made; one call far above the rest is.
                typical = sorted(s[0] for s in slow)[len(slow) // 2]
                limit = max(SLOWEST_MS, 4 * typical)
                over = sorted((s for s in slow if s[0] >= limit), reverse=True)
                self.assertLessEqual(len(over), 1, f"slow handler calls over {limit:.0f} ms (typical {typical:.1f}): {over}")


if __name__ == "__main__":
    unittest.main()
