#!/usr/bin/env python3
"""Pack one drive recording (game/test/drive_record.lua) into a small .npz.

usage: drive_dataset.py OUT.rgb OUT.log OUT.npz [--size 128] [--scale 2]

Keeps only frames with both a REC line and a picture, and averages each
picture down by --scale.
"""
import argparse
from pathlib import Path

import numpy as np

COLS = "frame tick x y z yaw speed throttle steer hit cut".split()


def read_log(path):
    rows = [line.split(",")[1:] for line in Path(path).read_text().splitlines() if line.startswith("REC,")]
    if not rows:
        raise SystemExit(f"{path}: no REC lines")
    return np.array(rows, dtype=np.float64)


def pack(rgb, log, out, size, scale):
    state = read_log(log)
    frames = state[:, 0].astype(np.int64)
    if np.any(np.diff(frames) != 1):
        raise SystemExit("frame numbers are not consecutive")
    if len(np.unique(np.diff(state[:, 1]))) > 1:  # the game paused itself, or something like it
        raise SystemExit(f"frames are not evenly spaced in game time: tick steps {np.unique(np.diff(state[:, 1]))}")
    raw = np.memmap(rgb, dtype=np.uint8, mode="r")
    drawn = raw.size // (size * size * 3)
    if frames[0] > drawn:
        raise SystemExit(f"{drawn} pictures, but the log starts at frame {frames[0]}")
    if frames[-1] > drawn:  # a run stopped early loses the frames it hadn't written yet
        print(f"keeping frames up to {drawn} of {frames[-1]}: the rest have no picture")
        state = state[frames <= drawn]
        frames = frames[frames <= drawn]
    # REC frame n is the n-th picture drawn, counting from one.
    small = np.empty((len(frames), size // scale, size // scale, 3), dtype=np.uint8)
    side = size * size * 3
    for i, n in enumerate(frames):
        pic = raw[(n - 1) * side : n * side].reshape(size, size, 3).astype(np.float32)
        small[i] = pic.reshape(size // scale, scale, size // scale, scale, 3).mean((1, 3)).round()
    np.savez_compressed(out, frames=small, state=state.astype(np.float32), columns=np.array(COLS))
    print(f"{out}: {len(frames)} frames, {Path(out).stat().st_size / 1e6:.1f} MB, cuts {int(state[:, 10].sum())}, "
          f"hard hits {(state[:, 9] > 3).sum()}, mean speed {state[:, 6].mean():.1f} m/s")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("rgb")
    p.add_argument("log")
    p.add_argument("out")
    p.add_argument("--size", type=int, default=128)
    p.add_argument("--scale", type=int, default=2)
    a = p.parse_args()
    pack(a.rgb, a.log, a.out, a.size, a.scale)


if __name__ == "__main__":
    main()
