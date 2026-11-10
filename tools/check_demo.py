#!/usr/bin/env python3
"""Load the example through the real engine and verify its collision scene."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
binary = root / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")
run = subprocess.run([str(binary), "game", "--headless", "120"], cwd=root,
                     env={**os.environ, "ENGINE_SMOKE": "1"}, text=True,
                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
print(run.stdout, end="")
if run.returncode or "ENGINE DEMO PASSED:" not in run.stdout or any(
        s in run.stdout.lower() for s in ("stack traceback", "panicked", "lua error")):
    sys.exit("Engine demo verification failed")
