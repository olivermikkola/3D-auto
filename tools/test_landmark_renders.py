#!/usr/bin/env python3
"""Renders Turku's landmarks and checks the pictures, not just the entities.

The slice probes (KAKOLA_TEST and friends) only prove that an entity exists.
Kakola rendered pitch black, Kauppatori's paving sank under the hillside and
Turun linna stood on a four-lane road while they all passed. These checks
look at the middle of a real frame from a fixed camera:

- no landmark may be mostly black (a colour multiplied into near zero), and
- each one has to show its own colour (granite paving, castle plaster, brick)
  over a fair share of the frame, so one that is buried, hidden or placed
  somewhere else fails.

Rendering needs a display, so this is opt-in: RENDER_CHECKS=1. CI runs it on
Linux under xvfb-run with Mesa's software renderer.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")
W, H = 640, 360

# name: eye, target, [(rgb, tolerance, minimum share of the middle of the frame)]
SHOTS = {
    "kakola": ((-1250, 90, 750), (-1450, 25, 950), []),
    "kauppatori": ((-175, 140, -150), (-175, 0, -15), [((226, 215, 203), 20, 0.30)]),
    "turun_linna": ((-2330, 45, 1900), (-2265, 10, 1785), [((114, 108, 100), 16, 0.10)]),
    "tuomiokirkko": ((250, 60, -250), (385, 15, -100), [((100, 41, 28), 20, 0.025)]),
}
MAX_BLACK = 0.12


def read_ppm(path):
    magic, size, _, pixels = path.read_bytes().split(b"\n", 3)
    assert magic == b"P6", path
    w, h = map(int, size.split())
    return w, h, pixels


def middle(w, h, pixels):
    for y in range(h // 4, 3 * h // 4):
        row = pixels[(y * w + w // 4) * 3:(y * w + 3 * w // 4) * 3]
        for i in range(0, len(row), 3):
            yield row[i], row[i + 1], row[i + 2]


def measure(path, colours):
    w, h, pixels = read_ppm(path)
    px = list(middle(w, h, pixels))
    black = sum(1 for p in px if max(p) < 40) / len(px)
    shares = [sum(1 for p in px if all(abs(p[i] - rgb[i]) <= tol for i in range(3))) / len(px) for rgb, tol, _ in colours]
    return black, shares


@unittest.skipUnless(os.environ.get("RENDER_CHECKS") == "1", "set RENDER_CHECKS=1 (needs a display; CI uses xvfb-run)")
class LandmarkRenderTests(unittest.TestCase):
    def render(self, name, eye, target, folder):
        shot = folder / f"{name}.ppm"
        env = os.environ.copy()
        env.update(MAP="turku", SEED="1337", HOUR="14", FOG="300,2500",
                   SHOT_CAM=",".join(str(v) for v in (*eye, *target, 60)))
        game = os.environ.get("RENDER_CHECKS_GAME", "game")  # another checkout's game/ to compare against
        command = [str(BINARY), game, "--screenshot", str(shot), "--frames", "5", "--size", f"{W}x{H}",
                   "--save-dir", str(folder / "save")]
        res = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        return shot

    def test_landmarks_are_visible_and_coloured(self):
        keep = os.environ.get("RENDER_CHECKS_OUT")
        with tempfile.TemporaryDirectory(prefix="auto-landmarks-") as directory:
            folder = Path(keep) if keep else Path(directory)
            folder.mkdir(parents=True, exist_ok=True)
            for name, (eye, target, colours) in SHOTS.items():
                with self.subTest(landmark=name):
                    black, shares = measure(self.render(name, eye, target, folder), colours)
                    print(f"{name}: black={black:.3f} " + " ".join(f"{s:.3f}" for s in shares))
                    self.assertLessEqual(black, MAX_BLACK, f"{name} is {black:.0%} black")
                    for (rgb, _, least), share in zip(colours, shares):
                        self.assertGreaterEqual(share, least, f"{name} shows {share:.1%} of {rgb}, wants {least:.0%}")


if __name__ == "__main__":
    unittest.main()
