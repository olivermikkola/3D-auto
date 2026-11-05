#!/usr/bin/env python3
"""Render visual postcards of Kauppatori Torikahvila and Aurajoki Riverboats."""
import os
from pathlib import Path
import subprocess
import shutil

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")
OUT_DIR = Path("/home/olivermikkola/.gemini/antigravity-cli/brain/acb9ed57-803a-4ad8-bb89-bae64559ce49/images")
OUT_DIR.mkdir(parents=True, exist_ok=True)

SHOTS = [
    {
        "name": "torikahvila_morning",
        "eye": (-184.0, 10.0, -32.0),
        "target": (-194.3, 7.8, -45.3),
        "hour": "10",
        "fov": 60,
    },
    {
        "name": "svarte_rudolf_evening",
        "eye": (-148.0, 4.5, 422.0),
        "target": (-158.8, 2.4, 432.4),
        "hour": "21.5",
        "fov": 60,
    },
    {
        "name": "donna_sundeck_dusk",
        "eye": (-316.5, 2.7, 531.0),
        "target": (-324.0, 1.9, 527.5),
        "hour": "20.5",
        "fov": 60,
    },
    {
        "name": "majland_gangway_day",
        "eye": (-752.5, 2.8, 698.0),
        "target": (-746.5, 1.8, 704.5),
        "hour": "14",
        "fov": 60,
    },
]

def render_shot(shot):
    name = shot["name"]
    ppm_path = OUT_DIR / f"{name}.ppm"
    png_path = OUT_DIR / f"{name}.png"

    env = os.environ.copy()
    cam_str = f"{shot['eye'][0]},{shot['eye'][1]},{shot['eye'][2]},{shot['target'][0]},{shot['target'][1]},{shot['target'][2]},{shot['fov']}"
    env.update(
        MAP="turku",
        SEED="1337",
        HOUR=shot["hour"],
        SHOT_CAM=cam_str,
    )

    cmd = [
        "xvfb-run", "-a",
        str(BINARY), "game",
        "--screenshot", str(ppm_path),
        "--frames", "10",
        "--size", "1024x576",
    ]

    print(f"Rendering {name}...")
    res = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
    if res.returncode != 0:
        print(f"Failed to render {name}: {res.stderr}")
        return False

    if ppm_path.exists():
        # Convert ppm to png via convert or ffmpeg
        if shutil.which("convert"):
            subprocess.run(["convert", str(ppm_path), str(png_path)], check=True)
            ppm_path.unlink()
            print(f"Saved {png_path}")
            return True
        elif shutil.which("ffmpeg"):
            subprocess.run(["ffmpeg", "-y", "-i", str(ppm_path), str(png_path)], capture_output=True, check=True)
            ppm_path.unlink()
            print(f"Saved {png_path}")
            return True
        else:
            print(f"Saved {ppm_path} (no convert/ffmpeg found)")
            return True
    return False

if __name__ == "__main__":
    for s in SHOTS:
        render_shot(s)
