"""Real headless police/physics regression with an isolated obstacle scene."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class PoliceRecoveryTests(unittest.TestCase):
    def run_chase(self, obstructed):
        with tempfile.TemporaryDirectory(prefix="police-", dir=ROOT / "target") as tmp:
            game = Path(tmp)
            shutil.copyfile(ROOT / "game/test/police_recovery/main.lua", game / "main.lua")
            shutil.copytree(ROOT / "game/assets", game / "assets")
            env = os.environ.copy()
            env["POLICE_OBSTACLE"] = "1" if obstructed else "0"
            result = subprocess.run([str(BINARY), str(game), "--headless", "2000"],
                                    cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("[lua:", output)
            self.assertIn("POLICE RECOVERY PASSED", output)
            print(output.strip())

    def test_obstructed_chase_arrests_stationary_reachable_player(self):
        self.run_chase(True)

    def test_clear_chase_does_not_detour(self):
        self.run_chase(False)


if __name__ == "__main__":
    unittest.main()
