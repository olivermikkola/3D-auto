#!/usr/bin/env python3
"""Open the browser build (web/dist) in a headless Firefox and report what it did.

Serves web/dist on a local port, drives Firefox through geckodriver (WebDriver over
plain HTTP, so no Python packages are needed), waits, then prints the lines the game
logged on the page and saves a screenshot. No window opens.

    python3 tools/web_check.py --query "map=starter" --wait 20 --shot /tmp/web.png

Needs firefox and geckodriver on PATH (or --geckodriver).
"""
import argparse
import base64
import functools
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def log_message(self, *args):
        pass


def call(base, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read() or b"{}").get("value")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dist", type=Path, default=ROOT / "web" / "dist")
    ap.add_argument("--query", default="", help="the page's query string, e.g. map=raisio&hour=12")
    ap.add_argument("--wait", type=float, default=20, help="seconds to let the game run")
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--shot", type=Path, help="save a PNG screenshot here")
    ap.add_argument("--geckodriver", default=shutil.which("geckodriver") or str(Path.home() / "tools" / "geckodriver"))
    a = ap.parse_args()

    port = free_port()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=str(a.dist)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    dport = free_port()
    driver = subprocess.Popen([a.geckodriver, "--port", str(dport)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base = f"http://127.0.0.1:{dport}"
    try:
        for _ in range(100):
            try:
                urllib.request.urlopen(base + "/status", timeout=1)
                break
            except OSError:
                time.sleep(0.1)
        w, h = (int(v) for v in a.size.split("x"))
        caps = {"capabilities": {"alwaysMatch": {"browserName": "firefox", "moz:firefoxOptions": {
            "args": ["-headless", f"--width={w}", f"--height={h}"],
            "prefs": {"webgl.force-enabled": True, "dom.webgpu.enabled": False}}}}}
        session = call(base, "POST", "/session", caps)["sessionId"]
        s = f"/session/{session}"
        try:
            call(base, "POST", s + "/url", {"url": f"http://127.0.0.1:{port}/index.html?log=1&{a.query}"})
            t0 = time.time()
            time.sleep(a.wait)
            log = call(base, "POST", s + "/execute/sync", {"script": "return document.getElementById('log').textContent", "args": []})
            mem = call(base, "POST", s + "/execute/sync", {"script": "return wasm_memory ? wasm_memory.buffer.byteLength : 0", "args": []})
            print(f"--- page log after {time.time() - t0:.0f} s; wasm memory {mem / 2**20:.0f} MB ---")
            print(log)
            if a.shot:
                png = call(base, "GET", s + "/screenshot")
                a.shot.write_bytes(base64.b64decode(png))
                print(f"screenshot: {a.shot}")
        finally:
            call(base, "DELETE", s)
    finally:
        driver.terminate()
        server.shutdown()


if __name__ == "__main__":
    sys.exit(main())
