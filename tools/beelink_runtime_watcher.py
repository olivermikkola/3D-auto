#!/usr/bin/env python3
"""Beelink runtime watcher & game checker for 3D-auto.

1. Supervises the 3D-auto game process on DISPLAY=:0 (fullscreen 1080p, MAP=turku).
2. Watches GitHub origin/main for newly merged PRs.
3. When Oliver pushes a merge:
   - Pulls fast-forward main.
   - Rebuilds cargo release if Rust code changed.
   - Runs a quick headless sanity check.
   - Relaunches/reloads the game on DISPLAY=:0 so the latest merged PR is live on screen.
"""

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
BINARY = REPO_DIR / "target" / "release" / "auto"
GAME_DIR = REPO_DIR / "game"
LOG_FILE = REPO_DIR / "target" / "runtime_watcher.log"
POLL_INTERVAL = 10  # seconds between remote checks

running_proc = None
shutdown_requested = False


def log(msg: str):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] [WATCHER] {msg}"
    print(line, flush=True)
    try:
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def get_local_main_sha() -> str:
    res = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )
    return res.stdout.strip()


def get_remote_main_sha() -> str:
    res = subprocess.run(
        ["git", "ls-remote", "origin", "refs/heads/main"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        timeout=15,
    )
    if res.returncode == 0 and res.stdout.strip():
        return res.stdout.strip().split()[0]
    return ""


def is_game_running() -> bool:
    global running_proc
    if running_proc is not None and running_proc.poll() is None:
        return True
    # Check system-wide for existing auto process running the game
    res = subprocess.run(["pgrep", "-f", f"{BINARY}.*{GAME_DIR}"], capture_output=True, text=True)
    return res.returncode == 0 and len(res.stdout.strip().splitlines()) > 0


def stop_game():
    global running_proc
    log("Stopping current game process...")
    if running_proc is not None:
        try:
            running_proc.terminate()
            running_proc.wait(timeout=5)
        except Exception:
            try:
                running_proc.kill()
            except Exception:
                pass
        running_proc = None

    # Clean up any orphan auto game process
    subprocess.run(["pkill", "-f", f"{BINARY}.*{GAME_DIR}"], capture_output=True)
    time.sleep(1)


def start_game():
    global running_proc
    if is_game_running():
        log("Game is already running.")
        return

    env = os.environ.copy()
    env["DISPLAY"] = ":0"
    env["WAYLAND_DISPLAY"] = env.get("WAYLAND_DISPLAY", "wayland-0")
    env["MAP"] = "turku"

    if "XAUTHORITY" not in env or not os.path.exists(env["XAUTHORITY"]):
        user_run = Path(f"/run/user/{os.getuid()}")
        for auth_file in user_run.glob(".mutter-Xwaylandauth*"):
            env["XAUTHORITY"] = str(auth_file)
            break
        if "XAUTHORITY" not in env:
            gdm_auth = Path(f"/run/user/{os.getuid()}/gdm/Xauthority")
            if gdm_auth.exists():
                env["XAUTHORITY"] = str(gdm_auth)

    cmd = [
        str(BINARY),
        str(GAME_DIR),
        "--fullscreen",
        "--size",
        "1920x1080",
    ]
    log(f"Launching game: {' '.join(cmd)} on DISPLAY=:0")
    running_proc = subprocess.Popen(
        cmd,
        cwd=REPO_DIR,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    log(f"Game launched with PID {running_proc.pid}")


def check_and_apply_updates():
    local_sha = get_local_main_sha()
    remote_sha = get_remote_main_sha()

    if not remote_sha or remote_sha == local_sha:
        return False

    log(f"New commit detected on origin/main: {local_sha[:8]} -> {remote_sha[:8]}")

    # Fetch and fast-forward main
    fetch_res = subprocess.run(["git", "fetch", "origin", "main", "--quiet"], cwd=REPO_DIR, capture_output=True, text=True)
    if fetch_res.returncode != 0:
        log(f"git fetch failed: {fetch_res.stderr}")
        return False

    merge_res = subprocess.run(["git", "merge", "origin/main", "--ff-only"], cwd=REPO_DIR, capture_output=True, text=True)
    if merge_res.returncode != 0:
        log(f"git merge --ff-only failed: {merge_res.stderr}")
        return False

    # Check what changed
    diff_res = subprocess.run(
        ["git", "diff", "--name-only", local_sha, remote_sha],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
    )
    changed_files = diff_res.stdout.splitlines()
    rust_changed = any(f.startswith("src/") or f in ("Cargo.toml", "Cargo.lock") for f in changed_files)

    if rust_changed:
        log("Rust kernel modified. Building release binary...")
        build_res = subprocess.run(["cargo", "build", "--release", "--locked"], cwd=REPO_DIR, capture_output=True, text=True)
        if build_res.returncode != 0:
            log(f"Build failed: {build_res.stderr}")
            return False
        log("Build complete.")

    # Quick headless sanity smoke check
    log("Running headless smoke verification (30 ticks)...")
    smoke_env = os.environ.copy()
    smoke_env["MAP"] = "turku"
    smoke_res = subprocess.run(
        [str(BINARY), str(GAME_DIR), "--headless", "30"],
        cwd=REPO_DIR,
        env=smoke_env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if smoke_res.returncode != 0:
        log(f"Smoke check FAILED (code {smoke_res.returncode}): {smoke_res.stdout} {smoke_res.stderr}")
        return False

    log("Smoke check PASSED. Relaunching game on DISPLAY=:0...")
    stop_game()
    start_game()
    log(f"Successfully updated and reloaded game to {remote_sha[:8]}")
    return True


def sig_handler(signum, frame):
    global shutdown_requested
    log(f"Received signal {signum}, initiating clean shutdown...")
    shutdown_requested = True
    stop_game()
    sys.exit(0)


def main():
    signal.signal(signal.SIGTERM, sig_handler)
    signal.signal(signal.SIGINT, sig_handler)

    log("3D-auto Beelink Runtime Watcher & Game Checker started.")
    log(f"Current local main HEAD: {get_local_main_sha()[:8]}")

    # Ensure game is running on startup
    if not is_game_running():
        start_game()
    else:
        log("Existing game process already running on DISPLAY=:0.")

    last_poll = 0
    while not shutdown_requested:
        now = time.monotonic()
        if now - last_poll >= POLL_INTERVAL:
            last_poll = now
            try:
                check_and_apply_updates()
            except Exception as e:
                log(f"Error checking updates: {e}")

            # Game Checker health verification
            if not is_game_running():
                log("Game process was not detected running. Restarting...")
                start_game()

        time.sleep(1)


if __name__ == "__main__":
    main()
