#!/usr/bin/env python3
"""Bounded real OpenGL checks on an isolated Xvfb display (software renderer).

This does not qualify the user's GPU, compositor, controller, or Moonlight.
Use a new output directory. No visible desktop window or real player saves.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
ERROR = re.compile(r"\[lua:|FAILED|panicked", re.IGNORECASE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--binary", type=Path, default=ROOT / "target/release/auto")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    binary = args.binary.resolve()
    assert binary.is_file(), binary
    assert shutil.which("xvfb-run"), "xvfb-run is required"
    environment = os.environ.copy()
    for key in ("MAP", "SEED", "AUTO_TEST", "CITY_TEST", "PAD_TEST", "SOAK", "SAVE_TEST",
                "MENU_TEST", "SHOP_TEST", "RELIABILITY_TEST", "MISSION_TEST", "TERRAIN_TEST",
                "SHOT_CAM", "FOG", "HOUR"):
        environment.pop(key, None)
    environment.update(LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe", LP_NUM_THREADS="2")
    cases = []

    def run(name, command, markers, env=None, timeout=60):
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24 -nolisten tcp", *command]
        started = time.monotonic()
        result = subprocess.run(command, cwd=ROOT, env=dict(environment, **(env or {})),
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
        seconds = time.monotonic() - started
        log = output / (name + ".log")
        log.write_text(result.stdout, encoding="utf-8")
        missing = [marker for marker in markers if marker not in result.stdout]
        errors = [line for line in result.stdout.splitlines() if ERROR.search(line)]
        case: dict[str, Any] = dict(name=name, command=command, exit_code=result.returncode, seconds=seconds,
                    log=str(log), missing_markers=missing, errors=errors,
                    passed=result.returncode == 0 and not missing and not errors)
        cases.append(case)
        print(name, "exit", result.returncode, "seconds", round(seconds, 3), flush=True)
        assert case["passed"], result.stdout
        return case

    fixture = output / "frame-fixture"
    (fixture / "lib").mkdir(parents=True)
    shutil.copyfile(ROOT / "game/lib/settings.lua", fixture / "lib/settings.lua")
    (fixture / "main.lua").write_text('''
local frames = 0
if os.getenv("PAUSED_PROBE") == "1" then engine.pause(true) end
engine.on("frame", function()
  frames = frames + 1
  if frames == tonumber(os.getenv("PROBE_FRAMES")) then
    print("FRAME PROBE PASSED frames=" .. frames .. " ticks=" .. engine.ticks())
    engine.quit()
  end
end)
''', encoding="utf-8")
    default = run("default-60fps", [str(binary), str(fixture), "--save-dir", str(output / "default-saves")],
                  ["FRAME PROBE PASSED frames=120"], {"PROBE_FRAMES": "120"})
    assert default["seconds"] >= 1.8, "default render loop was not capped"
    slow = run("explicit-20fps", [str(binary), str(fixture), "--fps", "20", "--save-dir", str(output / "slow-saves")],
               ["FRAME PROBE PASSED frames=60"], {"PROBE_FRAMES": "60"})
    assert slow["seconds"] >= 2.8, "explicit render loop was not capped"
    uncapped = run("explicit-uncapped", [str(binary), str(fixture), "--fps", "0", "--save-dir", str(output / "uncapped-saves")],
                   ["FRAME PROBE PASSED frames=60"], {"PROBE_FRAMES": "60"})
    assert uncapped["seconds"] < slow["seconds"] * 0.75, "--fps 0 did not disable interactive pacing"
    paused = run("paused-cap", [str(binary), str(fixture), "--fps", "20", "--save-dir", str(output / "paused-saves")],
                 ["FRAME PROBE PASSED frames=60 ticks=0"], {"PROBE_FRAMES": "60", "PAUSED_PROBE": "1"})
    assert paused["seconds"] >= 2.8, "pause bypassed render cap"
    timed = run("fixed-frames-bypass", [str(binary), str(fixture), "--fps", "1", "--frames", "60"],
                ["FRAME PROBE PASSED frames=60 ticks=60"], {"PROBE_FRAMES": "60"}, timeout=20)
    assert timed["seconds"] < 15, "--frames unexpectedly used the 1 FPS interactive cap"

    native_command = [sys.executable, "-B", str(ROOT / "tools/native_window_checks.py"),
                      "--binary", str(binary), "--output", str(output / "native-windows")]
    native = subprocess.run(native_command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=60)
    native_log = output / "native-windows.log"
    native_log.write_text(native.stdout + native.stderr)
    assert native.returncode == 0, native.stdout + native.stderr
    cases.append(dict(name="native-fullscreen-and-menu", command=native_command, exit_code=native.returncode,
                      log=str(native_log), passed=True))

    captures = []
    for name, map_name, options, env in [
        ("harbor-fps1", "harbor", ["--fps", "1"], {}),
        ("harbor-fps60", "harbor", ["--fps", "60"], {}),
        ("raisio-release", "raisio", ["--fps", "1"], {}),
    ]:
        shot = output / (name + ".ppm")
        run(name, [str(binary), "game", "--screenshot", str(shot), "--frames", "2", "--size", "960x540", *options],
            ["screenshot:"], {"MAP": map_name, "SEED": "1337", "HOUR": "14", **env}, timeout=120)
        data = shot.read_bytes()
        assert data.startswith(b"P6\n960 540\n255\n"), "unexpected native screenshot format"
        captures.append(dict(name=name, path=str(shot), bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
    assert captures[0]["sha256"] == captures[1]["sha256"], "FPS option changed deterministic screenshot pixels"
    summary = dict(renderer="Xvfb / Mesa llvmpipe (software OpenGL)",
                   limitations=["No hardware GPU performance qualification", "No physical controller or Moonlight test"],
                   cases=cases, captures=captures, passed=True)
    (output / "results.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print("WINDOW RENDER CHECKS PASSED", flush=True)


if __name__ == "__main__":
    main()
