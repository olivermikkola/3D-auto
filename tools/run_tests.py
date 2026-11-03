#!/usr/bin/env python3
"""Runs tools/test_*.py side by side, one process per file.

The same tests as `python -m unittest discover -s tools -p "test_*.py"`, but
that runs them one after another, which took 25-33 minutes on CI. Headless
runs keep saves in memory (src/main.rs save_store), so the files don't share
anything on disk.

    python tools/run_tests.py            # one worker per CPU
    python tools/run_tests.py --jobs 2   # fewer, e.g. on a quiet evening
    python tools/run_tests.py --only "test_*_sweep.py"   # or --skip the same
    python tools/run_tests.py --shard 2/4   # the second of four even shares (CI)

Prints each file's time; a failing file's full output is printed at the end.
The files in ALONE (they time the game) run last, by themselves.
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
# Run on their own once the rest are done: they time the game, and beside
# three other test files a CI machine stalled 60-70 ms now and then (Windows,
# test_profile_drive: a traffic tick that takes 2-4 ms alone).
ALONE = {"test_profile_drive.py"}
# Seconds each file took on a CI Linux runner (3 November 2026), to split
# them into shares that take about as long. A new file counts as a minute;
# update these now and then, they needn't be exact.
TIMES = {
    "test_aerial.py": 0, "test_ambience.py": 31, "test_ambulance.py": 172,
    "test_archipelago_heist.py": 10, "test_architecture.py": 6, "test_aurajoki.py": 10,
    "test_balconies.py": 10, "test_bike.py": 16, "test_borders.py": 22, "test_bridges.py": 29,
    "test_bus.py": 93, "test_businesses.py": 18, "test_buslines.py": 74, "test_busstops.py": 233,
    "test_carkinds.py": 12, "test_cashvan.py": 28, "test_chunk_streaming.py": 7,
    "test_city_geodata.py": 0, "test_citymodel.py": 0, "test_convoy.py": 25,
    "test_cycle_paths.py": 11, "test_cyclists.py": 39, "test_deck_buildings.py": 11,
    "test_dem.py": 0, "test_fares.py": 208, "test_fire.py": 129, "test_foli_buses.py": 7,
    "test_gps.py": 126, "test_ground_map.py": 0, "test_hansa.py": 56, "test_harbor.py": 11,
    "test_headless_tests.py": 0, "test_heli.py": 29, "test_hideouts.py": 28, "test_kakola.py": 10,
    "test_kauppatori.py": 10, "test_kerbs.py": 14, "test_lamps.py": 1,
    "test_landmark_renders.py": 0, "test_layers.py": 12, "test_lidar.py": 0,
    "test_logomonsilta.py": 32, "test_lookback.py": 0, "test_louhi.py": 111,
    "test_louhi_foot.py": 22, "test_map_missions.py": 24, "test_market.py": 99,
    "test_nightlife.py": 51, "test_offroad_pursuit.py": 101, "test_osm_source.py": 0,
    "test_outline_trim.py": 11, "test_outlines.py": 0, "test_parking.py": 12,
    "test_passages.py": 26, "test_ped_evasion.py": 18, "test_ped_passing.py": 32,
    "test_ped_road.py": 99, "test_phone_quality.py": 0, "test_pois.py": 18,
    "test_police_recovery.py": 0, "test_postcards.py": 0, "test_profile_drive.py": 62,
    "test_profile_gpu.py": 0, "test_quality.py": 11, "test_quays.py": 11, "test_racer.py": 22,
    "test_rail_profile.py": 11, "test_railways.py": 29, "test_render_exit.py": 0,
    "test_road_clear.py": 69, "test_road_direction.py": 7, "test_road_markings.py": 11,
    "test_roadblock.py": 20, "test_shelters.py": 18, "test_shopsigns.py": 12, "test_signals.py": 30,
    "test_sisu_pasi.py": 7, "test_stairs.py": 47, "test_stands.py": 0, "test_story.py": 10,
    "test_stream_walls.py": 12, "test_suurtori.py": 11, "test_templates.py": 93,
    "test_terraces.py": 17, "test_toriparkki.py": 62, "test_touch.py": 0,
    "test_traffic_calm.py": 155, "test_trees.py": 76, "test_tunnels.py": 11,
    "test_turku_corridor.py": 33, "test_vehicle_classes.py": 2, "test_vigilante.py": 75,
    "test_wanted_escape.py": 0, "test_water_stuck.py": 96, "test_waypoint.py": 98,
    "test_weather.py": 16, "test_web_check.py": 0, "test_window_options.py": 0,
}


def shard(files, k, n):
    """The k-th (1-based) of n shares of files, longest first to the least loaded."""
    loads = [[0.0, []] for _ in range(n)]
    for f in sorted(files, key=lambda f: (-TIMES.get(f, 60), f)):
        least = min(loads, key=lambda l: l[0])
        least[0] += TIMES.get(f, 60)
        least[1].append(f)
    return sorted(loads[k - 1][1])


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
    ap.add_argument("--shard", help="K/N: just the K-th of N shares, each about as long (see TIMES)")
    args = ap.parse_args()
    files = sorted(p.name for p in TOOLS.glob("test_*.py")
                   if (not args.only or fnmatch.fnmatch(p.name, args.only))
                   and not (args.skip and fnmatch.fnmatch(p.name, args.skip)))
    if args.shard:
        k, n = (int(v) for v in args.shard.split("/"))
        files = shard(files, k, n)
        print(f"shard {k}/{n}: {len(files)} files, ~{sum(TIMES.get(f, 60) for f in files):.0f} s of tests", flush=True)
    failed = []
    start = time.monotonic()
    def report(name, code, out, secs):
        print(f"{'ok  ' if code == 0 else 'FAIL'} {secs:6.1f} s  {name}", flush=True)
        if code != 0:
            failed.append((name, out))
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for fut in as_completed([pool.submit(run, f) for f in files if f not in ALONE]):
            report(*fut.result())
    for f in files:
        if f in ALONE:
            report(*run(f))
    for name, out in failed:
        print(f"\n===== {name} =====\n{out}")
    print(f"\n{len(files) - len(failed)}/{len(files)} files passed in {time.monotonic() - start:.0f} s "
          f"with {args.jobs} workers")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
