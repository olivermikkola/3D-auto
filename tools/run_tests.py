#!/usr/bin/env python3
"""Runs tools/test_*.py side by side, one process per file.

The same tests as `python -m unittest discover -s tools -p "test_*.py"`, but
that runs them one after another, which took 25-33 minutes on CI. Headless
runs keep saves in memory (src/main.rs save_store), so the files don't share
anything on disk.

    python tools/run_tests.py            # one worker per CPU
    python tools/run_tests.py --jobs 2   # fewer, e.g. on a quiet evening
    python tools/run_tests.py --only "test_*_sweep.py"   # or --skip the same

Prints each file's time; a failing file's full output is printed at the end.
"""
import argparse
import fnmatch
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent


def run(name):
    start = time.monotonic()
    res = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tools", "-p", name],
                         cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return name, res.returncode, res.stdout + res.stderr, time.monotonic() - start


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--only", help="just the files matching this pattern")
    ap.add_argument("--skip", help="leave out the files matching this pattern")
    args = ap.parse_args()
    files = sorted(p.name for p in TOOLS.glob("test_*.py")
                   if (not args.only or fnmatch.fnmatch(p.name, args.only))
                   and not (args.skip and fnmatch.fnmatch(p.name, args.skip)))
    failed = []
    start = time.monotonic()
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for fut in as_completed([pool.submit(run, f) for f in files]):
            name, code, out, secs = fut.result()
            print(f"{'ok  ' if code == 0 else 'FAIL'} {secs:6.1f} s  {name}", flush=True)
            if code != 0:
                failed.append((name, out))
    for name, out in failed:
        print(f"\n===== {name} =====\n{out}")
    print(f"\n{len(files) - len(failed)}/{len(files)} files passed in {time.monotonic() - start:.0f} s "
          f"with {args.jobs} workers")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
