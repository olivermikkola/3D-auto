"""The browser build keeps its saves and makes sound.

Serves web/dist, opens the starter map in headless Chromium and checks that:
the game writes a save to localStorage (hiding the help writes help_seen), a
save put there before a reload is read back (cash shows), and the mixer the
page plays from gives sound while WebAudio runs.

    python3 tools/web_saves_sound.py [--dist web/dist] [--shot out.png]
"""
import argparse
import functools
import http.server
import json
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAVE = "-- auto save data: plain Lua table syntax, read as data and never run.\nreturn {version = 1, cash = 4321}"


def wait_ready(page, timeout):
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        if page.evaluate("/map=\\S+ seed=\\d+/.test(document.getElementById('log').textContent)"):
            return True
        time.sleep(0.5)
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dist", default=str(ROOT / "web" / "dist"))
    ap.add_argument("--shot", help="screenshot after the reload")
    ap.add_argument("--wait", type=float, default=90, help="seconds to wait for the map to load")
    a = ap.parse_args()
    from playwright.sync_api import sync_playwright

    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    handler = functools.partial(Quiet, directory=a.dist)
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{srv.server_port}/index.html?log=1&map=starter&seed=1337&hour=12"
    fails, errors = [], []

    def check(ok, what):
        print(("ok   " if ok else "FAIL ") + what)
        if not ok:
            fails.append(what)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=[
            "--disable-gpu", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--disable-dev-shm-usage",
            "--autoplay-policy=no-user-gesture-required"])
        page = browser.new_context(viewport={"width": 1280, "height": 720}).new_page()
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(url)
        check(wait_ready(page, a.wait), "the starter map loads")

        # Writing: hiding the help is remembered.
        page.click("#glcanvas")
        page.keyboard.press("F1")
        time.sleep(1.5)
        check(page.evaluate("localStorage.getItem('gta/help_seen')") is not None, "hiding the help writes gta/help_seen")

        # Sound: WebAudio runs, and the game's mix isn't silence.
        state = page.evaluate("audio ? audio.state : 'none'")
        check(state == "running", f"WebAudio is running ({state})")
        peak = page.evaluate("""() => { const n = 4096; let peak = 0;
            for (let k = 0; k < 10; k++) {
              const a = new Float32Array(wasm_memory.buffer, wasm_exports.auto_audio_mix(n), 2 * n);
              for (const x of a) peak = Math.max(peak, Math.abs(x));
            }
            return peak; }""")
        check(0.001 < peak <= 1.0, f"the mix has sound (peak {peak:.4f})")

        # Reading: a save put there before the game starts comes back. (Put
        # there from another page of the site, not the running game's: it
        # saves its own progress a couple of seconds after a change, and
        # that sometimes landed over this one before the reload.)
        page.goto(url.replace("index.html", "manifest.webmanifest").split("?")[0])
        page.evaluate(f"localStorage.setItem('gta/progress', {json.dumps(SAVE)})")
        page.goto(url)
        check(wait_ready(page, a.wait), "the map loads again after a reload")
        time.sleep(3)
        if a.shot:
            page.screenshot(path=a.shot)
        saved = page.evaluate("localStorage.getItem('gta/progress')") or ""
        check("cash = 4321" in saved, "the progress save is still there after the reload")
        log = page.evaluate("document.getElementById('log').textContent")
        check("progress:" not in log, "the game read the progress save without complaint")
        check(not errors and "panic" not in log, f"no page errors or panics {errors}")
        browser.close()
    srv.shutdown()
    if fails:
        print(f"{len(fails)} check(s) failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
