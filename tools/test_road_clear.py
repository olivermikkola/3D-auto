#!/usr/bin/env python3
"""Nothing stands in the carriageway (no tree, lamp, bench, quay wall or barrier), nor in the river.

Decorations placed by hand (the Aurajoki promenade, the slices) used to land
on the streets: 208 of them on Turku's, most along the riverside streets.
They looked fine from above and broke driving. game/test/road_clear_probe.lua
also casts a ray down every lane at bumper height; what it still hits is the
edges of bridge decks where two roads at different heights meet, capped here
at today's count until that is fixed so it can only go down.
"""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")

# map: obstacles a lane ray may still hit (deck edges, see above)
MAX_OBSTACLES = {"raisio": 6, "turku": 21}
# map: things still standing in the water, capped at today's count so it can
# only go down (Raisio's are fences along its shores; Turku's promenade had
# 283 lamps, benches, bollards and quay walls in the Aurajoki).
MAX_WET = {"raisio": 383, "turku": 1}


class RoadClearTests(unittest.TestCase):
    def test_nothing_stands_in_the_carriageway(self):
        for city, obstacles in MAX_OBSTACLES.items():
            with self.subTest(map=city):
                env = os.environ.copy()
                env.update(MAP=city, SEED="1337", ROAD_CLEAR_TEST="1", ROAD_CLUTTER_MAX="0",
                           ROAD_CLEAR_MAX=str(obstacles), ROAD_WET_MAX=str(MAX_WET[city]))
                res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True,
                                     text=True, timeout=1200)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out[-4000:])
                self.assertIn("ROAD CLEAR CHECK DONE", res.stdout, out[-4000:])


if __name__ == "__main__":
    unittest.main()
