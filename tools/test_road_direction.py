import unittest
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class RoadDirectionTests(unittest.TestCase):
    def test_oneway_roads_only_route_in_valid_direction(self):
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["DIRECTION_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "10"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL DIRECTION CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
