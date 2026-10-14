#!/usr/bin/env python3
"""Observe real fullscreen entry/menu exit on private Xvfb/xfwm4 only.

HOME/XDG and D-Bus are isolated before the display/window manager starts.
Software OpenGL evidence, not qualification of the user's GPU or desktop.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--inside", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    binary, output = args.binary.resolve(), args.output.resolve()
    if not args.inside:
        output.mkdir(parents=True, exist_ok=False)
        for name in ("xvfb-run", "xfwm4", "xprop", "xwininfo", "xdotool", "dbus-run-session"):
            assert shutil.which(name), f"required native-window tool missing: {name}"
        home = output / "home"
        for name in ("config", "cache", "data", "runtime", "tmp"):
            (home / name).mkdir(parents=True, mode=0o700)
        environment = os.environ.copy()
        environment.update(HOME=str(home), XDG_CONFIG_HOME=str(home / "config"),
                           XDG_CACHE_HOME=str(home / "cache"), XDG_DATA_HOME=str(home / "data"),
                           XDG_RUNTIME_DIR=str(home / "runtime"), TMPDIR=str(home / "tmp"),
                           LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe", LP_NUM_THREADS="2",
                           NO_AT_BRIDGE="1", GIO_USE_VFS="local", GTK_MODULES="")
        environment.pop("SESSION_MANAGER", None)
        command = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24 -nolisten tcp",
                   "dbus-run-session", "--", sys.executable, "-B", str(Path(__file__).resolve()),
                   "--inside", "--binary", str(binary), "--output", str(output)]
        result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=50)
        (output / "native-window.log").write_text(result.stdout + result.stderr)
        print(result.stdout + result.stderr)
        assert result.returncode == 0, "native window qualification failed; see native-window.log"
        return

    assert os.environ.get("DISPLAY") and os.environ.get("DBUS_SESSION_BUS_ADDRESS")
    snapshots, cases = [], []

    def query(command):
        result = subprocess.run(command, capture_output=True, text=True, timeout=3)
        return result.returncode, result.stdout + result.stderr

    def wait_until(predicate, description, child=None):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            if child is not None and child.poll() is not None:
                break
            time.sleep(0.03)
        raise AssertionError(description)

    def snapshot(window):
        _, state = query(["xprop", "-id", window, "_NET_WM_STATE"])
        _, geometry = query(["xwininfo", "-id", window])
        width = re.search(r"Width:\s+(\d+)", geometry)
        height = re.search(r"Height:\s+(\d+)", geometry)
        return {"window": window, "state": state, "width": int(width[1]) if width else 0,
                "height": int(height[1]) if height else 0}

    with (output / "wm.log").open("w") as log:
        wm = subprocess.Popen(["xfwm4", "--compositor=off", "--vblank=off"], stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_until(lambda: "window id #" in query(["xprop", "-root", "_NET_SUPPORTING_WM_CHECK"])[1],
                       "private window manager did not initialize", wm)
            for name, flags, saved in (("launch-fullscreen", ["--fullscreen"], "false"),
                                       ("saved-fullscreen", [], "true")):
                case = output / name
                game, saves = case / "game", case / "saves"
                game.mkdir(parents=True)
                shutil.copytree(ROOT / "game/lib", game / "lib")
                (game / "maps").mkdir()
                shutil.copyfile(ROOT / "game/maps/harbor.lua", game / "maps/harbor.lua")
                (game / "main.lua").write_text(f'assert(engine.save("settings", {{fullscreen={saved}}}))\n' + '''
local settings = require "lib.settings"
local city = require "lib.city"
city.use("harbor")
local menu = require "lib.menu"
assert(engine.fullscreen() and settings.get("fullscreen"))
local toggled = false
local function key(k, down)
  if k == "f" and down and not toggled then
    toggled = true
    menu.show("settings")
    menu.go("settings")
    for i, item in ipairs(menu.items()) do
      if item.setting == "fullscreen" then menu.sel = i; menu.press(); break end
    end
    assert(not engine.fullscreen() and not settings.get("fullscreen"))
    print("MENU WINDOWED PASSED")
  elseif k == "q" and down then
    print("NATIVE WINDOW CHECK PASSED")
    engine.quit()
  end
end
engine.on("key", key)
engine.on("menu_key", key)
''')
                command = [str(binary), str(game), "--size", "640x360", "--save-dir", str(saves), *flags]
                child_log = case / "game.log"
                with child_log.open("w") as stream:
                    child = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
                    try:
                        window = wait_until(lambda: query(["xdotool", "search", "--onlyvisible", "--name", "^auto$"])[1].strip(),
                                            "game did not create its native window", child).splitlines()[0]
                        full = wait_until(lambda: (s if "_NET_WM_STATE_FULLSCREEN" in s["state"] and
                                                  s["width"] == 1280 and s["height"] == 720 else None)
                                          if (s := snapshot(window)) else None,
                                          "game boolean did not become a native fullscreen window", child)
                        snapshots.append(dict(case=name, phase="fullscreen", **full))
                        subprocess.run(["xdotool", "windowfocus", "--sync", window, "key", "f"], check=True, timeout=3)
                        windowed = wait_until(lambda: (s if "_NET_WM_STATE_FULLSCREEN" not in s["state"] and
                                                       "MENU WINDOWED PASSED" in child_log.read_text() else None)
                                              if (s := snapshot(window)) else None,
                                              "menu did not remove native fullscreen state", child)
                        snapshots.append(dict(case=name, phase="windowed", **windowed))
                        subprocess.run(["xdotool", "windowfocus", "--sync", window, "key", "q"], check=True, timeout=3)
                        code = child.wait(timeout=5)
                        text = child_log.read_text()
                        assert code == 0 and "NATIVE WINDOW CHECK PASSED" in text and "[lua:" not in text, text
                        cases.append(dict(name=name, command=command, exit=code, log=str(child_log)))
                    finally:
                        if child.poll() is None:
                            child.terminate()
                            try:
                                child.wait(timeout=3)
                            except subprocess.TimeoutExpired:
                                child.kill()
                                child.wait()
                print(name, "native fullscreen entry and menu exit PASSED", flush=True)
        finally:
            wm.terminate()
            try:
                wm.wait(timeout=3)
            except subprocess.TimeoutExpired:
                wm.kill()
                wm.wait()
            (output / "observations.json").write_text(json.dumps({"snapshots": snapshots, "cases": cases}, indent=2) + "\n")
    assert len(cases) == 2
    (output / "results.json").write_text(json.dumps({"passed": True, "cases": cases, "snapshots": snapshots}, indent=2) + "\n")


if __name__ == "__main__":
    main()
