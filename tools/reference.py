#!/usr/bin/env python3
"""Reference: the game from straight above next to Turku's aerial photo.

A visual pass needs something true to look at. The aerial photo (Turun
ilmakuva 2022, true ortho, tools/aerial.py) shows where the buildings,
streets, trees and squares really are; the game is rendered looking straight
down on the same square, north up, at the same scale. Each picture is

    photo | game | photo and game blended

so a building that is missing, a street off its line or a park without its
trees shows at a glance.

    python3 tools/reference.py --out /tmp/ref                 # every postcard spot
    python3 tools/reference.py --out /tmp/ref --only kauppatori
    python3 tools/reference.py --out /tmp/ref --at -250,-80 --size 400

The square is centred on the spot's `look` point (tools/postcards.py). The
game's camera is high and narrow (near orthographic), so only tall buildings
lean a little away from the middle.
"""
import argparse
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aerial  # noqa: E402
import postcards  # noqa: E402

PX = 700
HEIGHT = 900  # the eye, metres over the ground


def render_top(binary, game, cx, cz, size, path, hour=13):
    fov = math.degrees(2 * math.atan(size / 2 / HEIGHT))
    env = os.environ.copy()
    env.update(MAP="turku", SEED="1337", HOUR=str(hour), FOG=f"{HEIGHT + 400},{HEIGHT + 900}", SHOT_NO_HUD="1",
               SHOT_CAM=f"{cx},{HEIGHT},{cz},{cx},0,{cz - 0.01},{fov:.3f}")
    command = [str(binary), str(game), "--screenshot", str(path), "--frames", "5",
               "--size", f"{PX}x{PX}", "--save-dir", str(path.parent / "save")]
    if sys.platform.startswith("linux") and shutil.which("xvfb-run"):
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x800x24"] + command
    res = subprocess.run(command, cwd=game.parent, env=env, capture_output=True, text=True, timeout=900)
    if res.returncode != 0 or not path.exists():
        raise RuntimeError(f"render failed\n{res.stdout[-2000:]}\n{res.stderr[-2000:]}")
    return path


def photo(cx, cz, size):
    """The aerial photo of the square as a PIL image, north up."""
    import numpy as np
    from PIL import Image
    a = aerial.Aerial("turku", (60.45150, 22.27000), (cx - size, cz - size, cx + size, cz + size))
    t = (np.arange(PX) + 0.5) / PX * size - size / 2
    X, Z = np.meshgrid(cx + t, cz + t)
    p = np.nan_to_num(a.pixels(X.ravel(), Z.ravel()).reshape(PX, PX, 3))
    return Image.fromarray((np.clip(p, 0, 1) * 255).astype(np.uint8))


def main(argv=None):
    from PIL import Image
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--only", help="comma-separated postcard spot names")
    ap.add_argument("--at", action="append", default=[], metavar="X,Z", help="a square centred here (game metres)")
    ap.add_argument("--size", type=float, default=360, help="the square's side in metres")
    ap.add_argument("--binary", type=Path, default=postcards.BINARY)
    args = ap.parse_args(argv)
    squares = {}
    for at in args.at:
        x, z = (float(v) for v in at.split(","))
        squares[f"at_{x:g}_{z:g}"] = (x, z)
    if not args.at or args.only:
        for n in (args.only.split(",") if args.only else postcards.SPOTS):
            sp = postcards.SPOTS[n]
            squares[n] = (sp["look"][0], sp["look"][2])
    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="reference-") as tmp:
        for name, (x, z) in squares.items():
            game = Image.open(render_top(args.binary, postcards.ROOT / "game", x, z, args.size, Path(tmp) / f"{name}.ppm")).convert("RGB")
            real = photo(x, z, args.size)
            row = Image.new("RGB", (PX * 3, PX))
            row.paste(postcards.label(real.copy(), f"{name}  aerial 2022"), (0, 0))
            row.paste(postcards.label(game.copy(), f"game  {args.size:g} m"), (PX, 0))
            row.paste(postcards.label(Image.blend(real, game, 0.5), "blend"), (PX * 2, 0))
            row.save(args.out / f"{name}.png", optimize=True)
            print(f"{name}: {args.out / (name + '.png')}", flush=True)


if __name__ == "__main__":
    main()
