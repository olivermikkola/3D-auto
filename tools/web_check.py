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
import re
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


def make_report(samples):
    """Wasm allocation is a high-water mark, not JS heap or total browser RSS."""
    errors = [s["log"] for s in samples if re.search(r"error:|panic|RuntimeError|unreachable", s["log"], re.I)]
    return {
        "ok": bool(samples) and bool(samples[-1]["ready"]) and samples[-1]["wasm_bytes"] > 0 and not errors,
        "errors": errors,
        "wasm_peak_bytes": max((s["wasm_bytes"] for s in samples), default=0),
        "samples": samples,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dist", type=Path, default=ROOT / "web" / "dist")
    ap.add_argument("--query", default="", help="the page's query string, e.g. map=raisio&hour=12")
    ap.add_argument("--wait", type=float, default=20, help="measurement window in seconds from navigation start (maximum 300)")
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--report", type=Path, help="write machine-readable measurements (also on runtime failure)")
    ap.add_argument("--firefox", help="explicit Firefox binary, e.g. a non-snap installation")
    ap.add_argument("--shot", type=Path, help="save a PNG screenshot here")
    ap.add_argument("--geckodriver", default=shutil.which("geckodriver") or str(Path.home() / "tools" / "geckodriver"))
    a = ap.parse_args()
    missing = [name for name in ("index.html", "gl.js", "auto.wasm") if not (a.dist / name).is_file()]
    if missing:
        ap.error(f"missing browser build in {a.dist}: {', '.join(missing)}; run web/build.sh first")

    try:
        w, h = (int(v) for v in a.size.split("x"))
        if w <= 0 or h <= 0 or not 0 < a.wait <= 300:
            raise ValueError()
    except ValueError:
        ap.error("--size must be positive WxH and --wait must be in (0, 300]")
    port = free_port()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=str(a.dist)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    dport = free_port()
    driver = None
    try:
        driver = subprocess.Popen([a.geckodriver, "--port", str(dport)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        base = f"http://127.0.0.1:{dport}"
        for _ in range(100):
            try:
                with urllib.request.urlopen(base + "/status", timeout=1):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("geckodriver did not become ready within 10 seconds")
        caps = {"capabilities": {"alwaysMatch": {"browserName": "firefox", "moz:firefoxOptions": {
            "args": ["-headless", f"--width={w}", f"--height={h}"],
            "prefs": {"webgl.force-enabled": True, "dom.webgpu.enabled": False}}}}}
        if a.firefox:
            caps["capabilities"]["alwaysMatch"]["moz:firefoxOptions"]["binary"] = a.firefox
        session_data = call(base, "POST", "/session", caps)
        s = f"/session/{session_data['sessionId']}"
        try:
            call(base, "POST", s + "/timeouts", {"pageLoad": 60000, "script": 10000})
            t0 = time.monotonic()
            call(base, "POST", s + "/url", {"url": f"http://127.0.0.1:{port}/index.html?log=1&{a.query}"})
            samples = []
            while True:
                sample = call(base, "POST", s + "/execute/sync", {"script": """
                    const log = document.getElementById('log')?.textContent || '';
                    return {log, ready: /map=\\S+ seed=\\d+/.test(log),
                        wasm_bytes: typeof wasm_memory !== 'undefined' && wasm_memory ? wasm_memory.buffer.byteLength : 0};
                    """, "args": []})
                sample["elapsed_s"] = round(time.monotonic() - t0, 3)
                samples.append(sample)
                if time.monotonic() - t0 >= a.wait:
                    break
                time.sleep(max(0, min(1, a.wait - (time.monotonic() - t0))))
            report = make_report(samples)
            report.update({"query": a.query, "size": a.size, "browser": session_data["capabilities"].get("browserVersion"),
                           "memory_metric": "WebAssembly linear allocation; excludes JS heap and GPU; observed after navigation",
                           "dist": str(a.dist.resolve())})
            if a.report:
                a.report.parent.mkdir(parents=True, exist_ok=True)
                a.report.write_text(json.dumps(report, indent=2) + "\n")
            print(f"--- wasm allocation {report['wasm_peak_bytes'] / 2**20:.1f} MiB; ready={report['ok']} ---")
            print(samples[-1]["log"])
            if a.shot:
                png = call(base, "GET", s + "/screenshot")
                a.shot.parent.mkdir(parents=True, exist_ok=True)
                a.shot.write_bytes(base64.b64decode(png))
                print(f"screenshot: {a.shot}")
            return 0 if report["ok"] else 1
        finally:
            call(base, "DELETE", s)
    finally:
        if driver is not None:
            driver.terminate()
            try:
                driver.wait(timeout=5)
            except subprocess.TimeoutExpired:
                driver.kill()
                driver.wait(timeout=5)
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
