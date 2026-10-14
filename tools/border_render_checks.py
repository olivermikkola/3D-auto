#!/usr/bin/env python3
"""Render headless camera checks for borders, crossings, and military gate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target/release/auto"


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
    # 1. Raisio-Turku river/forest border with the wooden footbridge
    # Bridge at (2458, 92) over Raisionjoki
    shots.append(render_shot("punttamaenpolku_footbridge", out, (2490, 14, 125), (2458, 4, 92)))

    # 2. Main road crossing with jersey barriers & roadworks
    # Satakunnantie crossing at (2680, -61)
    shots.append(render_shot("satakunnantie_crossing", out, (2710, 10, -85), (2680, 4, -61)))

    # 3. Pansio military fence + boom barrier + guardhouse
    # Gate at (-348.4, 2583.1)
    shots.append(render_shot("pansio_military_gate", out, (-332, 9, 2570), (-348.4, 3, 2583.1)))

    results_file = out / "border_render_results.json"
    results_file.write_text(json.dumps({"shots": shots, "passed": True}, indent=2) + "\n")
    print("ALL BORDER CAMERA RENDERS COMPLETED SUCCESSFULLY")


if __name__ == "__main__":
    main()
