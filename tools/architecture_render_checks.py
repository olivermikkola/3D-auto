#!/usr/bin/env python3
"""Render camera checks for Finnish glazed balconies and commercial glass facades."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


def render_shot(name, output_dir, eye, target, map_name="raisio"):
    shot = output_dir / f"{name}.ppm"
    env = os.environ.copy()
    env["MAP"] = map_name
    env["SEED"] = "1337"
    env["HOUR"] = "14"
    env["FOG"] = "80,450"
    env["SHOT_CAM"] = f"{eye[0]},{eye[1]},{eye[2]},{target[0]},{target[1]},{target[2]},65"
    env.update(LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe", LP_NUM_THREADS="2")

    command = [
        "xvfb-run", "-a", "-s", "-screen 0 960x540x24 -nolisten tcp",
        str(BINARY), "game", "--screenshot", str(shot), "--frames", "3", "--size", "960x540"
    ]
    started = time.monotonic()
    res = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=90)
    duration = time.monotonic() - started
    assert res.returncode == 0, f"Render failed for {name}: {res.stdout}"
    assert shot.is_file(), f"Screenshot not created for {name}"
    data = shot.read_bytes()
    assert data.startswith(b"P6\n960 540\n255\n"), "Invalid PPM format"
    sha = hashlib.sha256(data).hexdigest()
    print(f"PASS {name}: {len(data)} bytes, sha256={sha[:12]}, time={duration:.2f}s")
    return {"name": name, "path": str(shot), "bytes": len(data), "sha256": sha, "duration": duration}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)

    shots = []
    # 1. Glazed balconies along apartment buildings
    shots.append(render_shot("balcony_flats", out, (820, 24, -1750), (850, 16, -1780)))

    # 2. Commercial street-level glass facades
    shots.append(render_shot("glass_commercial_facade", out, (925, 20, -1710), (955, 12, -1725)))

    results_file = out / "architecture_render_results.json"
    results_file.write_text(json.dumps({"shots": shots, "passed": True}, indent=2) + "\n")
    print("ALL ARCHITECTURE CAMERA RENDERS COMPLETED SUCCESSFULLY")


if __name__ == "__main__":
    main()
