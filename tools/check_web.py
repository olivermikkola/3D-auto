#!/usr/bin/env python3
"""Render the actual WASM map and verify keyboard camera movement in Chromium."""
import functools
import io
import os
from PIL import Image
import http.server
from pathlib import Path
import threading
from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parent.parent
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
    functools.partial(Handler, directory=str(root / "web/dist")))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, executable_path=os.environ.get("CHROMIUM_PATH"), args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        page = browser.new_page(viewport={"width": 960, "height": 640})
        errors, logs = [], []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda msg: logs.append(msg.text))
        page.goto(f"http://127.0.0.1:{server.server_port}/?log=1")
        page.wait_for_function("document.getElementById('log').textContent.includes('map=example buildings=15')", timeout=60000)
        page.evaluate("() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))")
        rendered = page.locator('canvas').screenshot()
        colors = Image.open(io.BytesIO(rendered)).convert('RGB').getcolors(960*640)
        assert colors and len(colors) > 20, 'Map geometry did not render'
        page.locator('canvas').click(position={"x": 480, "y": 320})
        before = page.locator('canvas').screenshot()
        page.keyboard.down('d')
        # Poll until the rendered image changes after input.
        for _ in range(120):
            page.evaluate("() => new Promise(requestAnimationFrame)")
            after = page.locator('canvas').screenshot()
            if after != before:
                break
        else:
            raise AssertionError('Camera did not respond to keyboard input')
        page.keyboard.up('d')
        page.screenshot(path=str(root / 'web-map.png'))
        assert page.title() == '3D-auto: Map Example'
        assert not errors, errors
        assert not any('stack traceback' in line or 'Lua error' in line for line in logs), logs
        browser.close()
        print('BROWSER DEMO PASSED: WASM startup, rendered pixels and keyboard orbit')
finally:
    server.shutdown()
    server.server_close()
