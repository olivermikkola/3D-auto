#!/usr/bin/env python3
"""Postcards: Turku from the same spots before and after a change.

A visual change is judged by looking at it. Each postcard is a fixed camera
in a place Oliver knows well; rendering the same spots from two versions of
the game and putting them side by side shows what a PR did to the city.

    python3 tools/postcards.py --out /tmp/pc                 # this checkout
    python3 tools/postcards.py --out /tmp/pc --before origin/main
    python3 tools/postcards.py --out /tmp/pc --only kauppatori,aurajoki

With --publish NAME the pictures also go to the repo's `postcards` branch
under NAME/ (git plumbing, the checkout isn't touched) and the tool prints
markdown to paste into a PR, with links pinned to that commit.

With --before REF the tool checks REF out into a temporary worktree and renders
its game/ with the same binary (a Rust change shows only in "after"). It writes
<name>.png per spot (before above after when --before is given) and sheet.png
with all of them.

Rendering needs a display: on Linux it always runs through xvfb-run.
Heights are metres above the ground under the eye and the target
(SHOT_CAM_GROUND in game/test/shot.lua), so a spot survives terrain changes.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")

# eye and look: x, metres above the ground there, z. Turku's x runs east and z
# south of the map origin (tools/osm_import.py). street: the eye moves onto
# the nearest street and looks along it (SHOT_CAM_SNAP), towards `look`.
SPOTS = {
    "ylioppilaskyla": dict(eye=(1000, 1.7, -1210), look=(1150, 1.7, -1330), fov=70, hour=14, street=True,
                           about="Ylioppilaskylä at street level"),
    "ylioppilaskyla_above": dict(eye=(780, 70, -1000), look=(1130, 0, -1330), fov=60, hour=14,
                                 about="Ylioppilaskylä from above: the student village's shapes"),
    "aurajoki": dict(eye=(-250, 7, 466), look=(114, 0, 226), fov=65, hour=14,
                     about="Up the Aurajoki towards Kirjastosilta"),
    "aurajoki_night": dict(eye=(-250, 7, 466), look=(114, 0, 226), fov=65, hour=22,
                           about="The same river at night"),
    "kauppatori": dict(eye=(-250, 1.7, -80), look=(-100, 1.7, 30), fov=70, hour=12, street=True,
                       about="A street along Kauppatori"),
    "kakolanmaki": dict(eye=(-1150, 45, 690), look=(-1470, 15, 940), fov=60, hour=14,
                        about="Kakolanmäki: the old prison on its hill"),
    "logomo": dict(eye=(-430, 25, -470), look=(-680, 0, -640), fov=65, hour=14,
                   about="The railway yard and Logomo"),
    "puolalanmaki": dict(eye=(-380, 1.7, -100), look=(-450, 10, -290), fov=70, hour=14, street=True,
                         about="Up towards Puolalanmäki and the art museum"),
    "puolalanmaki_above": dict(eye=(-250, 60, -120), look=(-480, 10, -280), fov=60, hour=14,
                               about="Puolalanmäki from above: the museum and Puolalanpuisto"),
    "kupittaa": dict(eye=(1200, 40, 420), look=(1080, 0, 680), fov=60, hour=14,
                     about="Kupittaa: the campus and the park beyond"),
    "tyks": dict(eye=(1180, 60, 40), look=(1360, 10, -130), fov=60, hour=14,
                 about="Tyks: T-sairaala and Majakkasairaala over Helsinginkatu"),
}
SIZE = (960, 540)


def render(binary, game, name, spot, folder, cwd):
    eye, target, fov, hour = spot["eye"], spot["look"], spot["fov"], spot["hour"]
    shot = folder / f"{name}.ppm"
    env = os.environ.copy()
    env.update(MAP="turku", SEED="1337", HOUR=str(hour), FOG="300,2500", SHOT_CAM_GROUND="1", SHOT_NO_HUD="1", SHOT_CAM_SNAP="1" if spot.get("street") else "0",
               SHOT_CAM=",".join(str(v) for v in (*eye, *target, fov)))
    command = [str(binary), str(game), "--screenshot", str(shot), "--frames", "5",
               "--size", f"{SIZE[0]}x{SIZE[1]}", "--save-dir", str(folder / "save")]
    # Always an invisible display on Linux, even with DISPLAY set: no window
    # pops up on whoever's desktop this runs.
    if sys.platform.startswith("linux") and shutil.which("xvfb-run"):
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x800x24"] + command
    res = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=900)
    if res.returncode != 0 or not shot.exists():
        raise RuntimeError(f"{name}: render failed\n{res.stdout[-2000:]}\n{res.stderr[-2000:]}")
    return shot


def label(img, text):
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 8 + 7 * len(text), 18), fill=(0, 0, 0))
    d.text((4, 3), text, fill=(255, 255, 255))
    return img


def git(*args, data=None):
    return subprocess.run(["git", *args], cwd=ROOT, input=data, capture_output=True, check=True).stdout.decode().strip()


def publish(folder, name, files, about):
    """Commit files to the postcards branch under name/ and push; returns markdown."""
    blobs = "".join(f"100644 blob {git('hash-object', '-w', str(folder / f))}\t{f}\n" for f in files)
    sub = git("mktree", data=blobs.encode())
    parent = None
    try:
        git("fetch", "-q", "origin", "postcards")
        parent = git("rev-parse", "FETCH_HEAD")
    except subprocess.CalledProcessError:
        pass  # the first postcards ever: a branch with no history
    entries = []
    if parent:
        entries = [line for line in git("ls-tree", parent).splitlines() if not line.endswith("\t" + name)]
    entries.append(f"040000 tree {sub}\t{name}")
    root = git("mktree", data=("\n".join(entries) + "\n").encode())
    commit = git("commit-tree", root, *(["-p", parent] if parent else []), "-m", f"Postcards: {name}")
    git("push", "-q", "origin", f"{commit}:refs/heads/postcards")
    url = git("remote", "get-url", "origin").removesuffix(".git").replace("git@github.com:", "https://github.com/")
    raw = url.replace("https://github.com/", "https://raw.githubusercontent.com/") + f"/{commit}/{name}"
    lines = [f"**{about.get(f[:-4], f[:-4])}**\n\n![{f[:-4]}]({raw}/{f})\n" for f in files if f != "sheet.png"]
    return "\n".join(lines)


def main(argv=None):
    from PIL import Image
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--before", help="git ref to render for comparison, e.g. origin/main")
    ap.add_argument("--only", help="comma-separated spot names")
    ap.add_argument("--binary", type=Path, default=BINARY)
    ap.add_argument("--publish", metavar="NAME", help="push the pictures to the postcards branch under NAME/ and print markdown")
    ap.add_argument("--survey", action="store_true",
                    help="look straight down on each spot from 300 m, north up (for placing spots)")
    args = ap.parse_args(argv)
    names = args.only.split(",") if args.only else list(SPOTS)
    spots = SPOTS
    if args.survey:
        spots = {n: dict(eye=(sp["eye"][0], 300, sp["eye"][2]), look=(sp["eye"][0], 0, sp["eye"][2] - 1), fov=60, hour=14)
                 for n, sp in SPOTS.items()}
    for n in names:
        if n not in spots:
            ap.error(f"no spot {n!r}; have {', '.join(SPOTS)}")
    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="postcards-") as tmp:
        tmp = Path(tmp)
        base = None
        if args.before:
            base = tmp / "before"
            subprocess.run(["git", "worktree", "add", "-q", "--detach", str(base), args.before], cwd=ROOT, check=True)
            cache = ROOT / "tools" / "osm_cache"
            if cache.exists() and not (base / "tools" / "osm_cache").exists():
                (base / "tools" / "osm_cache").symlink_to(cache.resolve())
        try:
            tiles = []
            (tmp / "after").mkdir()
            (tmp / "bef").mkdir()
            for n in names:
                after = Image.open(render(args.binary, ROOT / "game", n, spots[n], tmp / "after", ROOT)).convert("RGB")
                img = label(after, f"{n}  after" if base else n)
                if base:
                    before = label(Image.open(render(args.binary, base / "game", n, spots[n], tmp / "bef", base)).convert("RGB"),
                                   f"{n}  before ({args.before})")
                    both = Image.new("RGB", (SIZE[0], SIZE[1] * 2))
                    both.paste(before, (0, 0))
                    both.paste(img, (0, SIZE[1]))
                    img = both
                img.save(args.out / f"{n}.png", optimize=True)
                tiles.append(img)
                print(f"{n}: {args.out / (n + '.png')}", flush=True)
            cols = 3
            tw, th = tiles[0].width // 2, tiles[0].height // 2
            sheet = Image.new("RGB", (tw * cols, th * ((len(tiles) + cols - 1) // cols)))
            for i, t in enumerate(tiles):
                sheet.paste(t.resize((tw, th)), ((i % cols) * tw, (i // cols) * th))
            sheet.save(args.out / "sheet.png", optimize=True)
            print(f"sheet: {args.out / 'sheet.png'}")
            if args.publish:
                files = [f"{n}.png" for n in names] + ["sheet.png"]
                print(publish(args.out, args.publish, files, {n: sp["about"] for n, sp in SPOTS.items()}))
        finally:
            if base:
                subprocess.run(["git", "worktree", "remove", "--force", str(base)], cwd=ROOT)


if __name__ == "__main__":
    main()
