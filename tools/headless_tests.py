#!/usr/bin/env python3
"""Headless acceptance: exit zero AND completion markers AND no Lua errors.

Run from the repository root. Output directories must be new: restart fixtures
are preserved there, never in the real player's save directory.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Any

DEFAULT_SEEDS = [0, *range(1, 13), 13, 17, 42, 99, 1337, 2026]


def seeded_cases(maps, seeds, suite):
    maps, seeds = list(dict.fromkeys(maps)), list(dict.fromkeys(seeds))
    suites = ["autoplay", "reliability"] if suite == "full" else [suite]
    return [(map_name, seed, kind) for map_name in maps for seed in seeds for kind in suites]


TEST_ENV = ("MAP", "SEED", "AUTO_TEST", "CITY_TEST", "PAD_TEST", "SOAK",
            "SAVE_TEST", "MENU_TEST", "SHOP_TEST", "GARAGE_TEST", "RELIABILITY_TEST", "MISSION_TEST")
ERROR = re.compile(r"\[lua:|FAILED", re.IGNORECASE)


def assess(exit_code, text, markers):
    missing = [marker for marker in markers if marker not in text]
    errors = [line for line in text.splitlines() if ERROR.search(line)]
    return exit_code == 0 and not missing and not errors, missing, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default="target/release/auto" + (".exe" if os.name == "nt" else ""))
    parser.add_argument("--game", default="game")
    parser.add_argument("--output", required=True)
    parser.add_argument("--maps", nargs="+", default=["manhattan", "harbor"])
    parser.add_argument("--seeds", nargs="+", type=int, default=DEFAULT_SEEDS)
    parser.add_argument("--jobs", type=int, default=3, help="bounded concurrent seed runs (1-4)")
    parser.add_argument("--suite", choices=["full", "autoplay", "reliability"], default="full")
    parser.add_argument("--soak", action="store_true", help="include 300 simulated seconds per map")
    parser.add_argument("--timeout", type=int, default=300, help="seconds before one run counts as hung")
    args = parser.parse_args()
    if not 1 <= args.jobs <= 4:
        parser.error("--jobs must be between 1 and 4")
    args.maps = list(dict.fromkeys(args.maps))
    args.seeds = list(dict.fromkeys(args.seeds))
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    binary = str(Path(args.binary).resolve())
    results = []

    def run(name, env, ticks, markers, save_dir=None):
        command = [binary, args.game, "--headless", str(ticks)]
        if save_dir is not None:
            command += ["--save-dir", str(save_dir)]
        environment = os.environ.copy()
        for key in TEST_ENV:
            environment.pop(key, None)
        environment.update(env)
        start = time.monotonic()
        try:
            process = subprocess.run(command, env=environment, text=True, encoding="utf-8", errors="replace",
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=args.timeout)
            code, text = process.returncode, process.stdout
        except subprocess.TimeoutExpired as error:
            code = 124
            text = error.stdout or ""
            if isinstance(text, bytes):
                text = text.decode(errors="replace")
        log = output / (name + ".log")
        log.write_text(text, encoding="utf-8")
        passed, missing, errors = assess(code, text, markers)
        result: dict[str, Any] = dict(name=name, command=command, cwd=str(Path.cwd()), env=env, exit_code=code,
                      seconds=round(time.monotonic() - start, 3), log=str(log),
                      required_markers=markers, missing_markers=missing, errors=errors, passed=passed)
        results.append(result)
        print(f"{'PASS' if passed else 'FAIL'} {name} (exit {code}, {result['seconds']}s)", flush=True)
        if not passed:
            print(text, flush=True)
        return result

    expected = seeded_cases(args.maps, args.seeds, args.suite)

    def seed_case(case):
        map_name, seed, kind = case
        env = {"MAP": map_name, "SEED": str(seed),
               "AUTO_TEST" if kind == "autoplay" else "RELIABILITY_TEST": "1"}
        markers = [f"map={map_name} seed={seed}"]
        markers += ["AUTOPLAY PASSED", "GARAGE PASSED"] if kind == "autoplay" else ["RELIABILITY PASSED"]
        return run(f"{map_name}-{kind}-{seed}", env, 9000 if kind == "autoplay" else 4000, markers)

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        seeded_results = list(pool.map(seed_case, expected))
    for map_name in args.maps:
        env = {"MAP": map_name}
        if args.suite != "full":
            continue
        for kind, ticks, marker in [("CITY", 2400, "CITY TEST PASSED"),
                                    ("PAD", 3000, "PAD TEST PASSED"),
                                    ("MISSION", 6000, "MISSION TEST PASSED")]:
            run(f"{map_name}-{kind.lower()}", dict(env, **{kind + "_TEST": "1"}), ticks, [marker])
        if args.soak:
            run(f"{map_name}-soak", dict(env, SOAK="1"), 18000, ["SOAK PASSED: 300 simulated seconds"])
        for kind, phases, ticks in [("SAVE", 3, 600), ("MENU", 2, 900), ("SHOP", 2, 900)]:
            save_dir = output / f"{map_name}-{kind.lower()}-saves"
            save_dir.mkdir()
            for phase in range(1, phases + 1):
                if kind == "SAVE" and phase == 3:
                    (save_dir / "progress.lua").write_text("return { cash = ", encoding="utf-8")
                marker = f"{kind} TEST PASSED" if phase == phases else f"{kind} TEST PHASE {phase} PASSED"
                result = run(f"{map_name}-{kind.lower()}-{phase}", dict(env, **{kind + "_TEST": str(phase)}),
                             ticks, [marker], save_dir)
                if kind == "SAVE" and phase == 3:
                    bad = save_dir / "progress.lua.bad"
                    result["corrupt_save_preserved"] = bad.is_file() and bad.read_bytes() == b"return { cash = "
                    result["corrupt_save_hex"] = bad.read_bytes().hex() if bad.is_file() else None
                    result["passed"] = result["passed"] and result["corrupt_save_preserved"]
    results.sort(key=lambda result: result["name"])
    assert len({r["name"] for r in results}) == len(results), "duplicate case names"
    actual = [(r["env"]["MAP"], int(r["env"]["SEED"]),
               "autoplay" if "AUTO_TEST" in r["env"] else "reliability") for r in seeded_results]
    assert len(actual) == len(set(actual)) and set(actual) == set(expected), "seed pair coverage mismatch"
    summary = dict(total=len(results), passed=sum(r["passed"] for r in results),
                   failed=sum(not r["passed"] for r in results), cases=results,
                   seed_coverage={"seeds": args.seeds, "maps": args.maps, "expected": expected,
                                  "actual": actual, "unique_pairs": len(set(actual))})
    (output / "results.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"{summary['passed']}/{summary['total']} passed; results: {output / 'results.json'}")
    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
