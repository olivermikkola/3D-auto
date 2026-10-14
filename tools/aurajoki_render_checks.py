#!/usr/bin/env python3
"""Render camera checks for Aurajoki bridges and the Föri cable ferry."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


def render_shot(name, output_dir, eye, target, map_name="turku"):
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
    # 1. Tuomiokirkkosilta across the Aurajoki
    shots.append(render_shot("aurajoki_cathedral_bridge", out, (320, 14, -130), (265, 4, -85)))

    # 2. The Föri cable ferry crossing Aurajoki
    shots.append(render_shot("fori_cable_ferry", out, (-1160, 6, 1205), (-1205, 0.45, 1145)))

    results_file = out / "aurajoki_render_results.json"
    results_file.write_text(json.dumps({"shots": shots, "passed": True}, indent=2) + "\n")
    print("ALL AURAJOKI CAMERA RENDERS COMPLETED SUCCESSFULLY")


if __name__ == "__main__":
    main()
