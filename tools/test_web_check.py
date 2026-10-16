"""Exercise web_check's CLI without requiring a browser for prerequisite tests."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import web_check


class WebCheckTests(unittest.TestCase):
    def test_report_rejects_allocated_memory_without_game_ready(self):
        report = web_check.make_report([
            {"elapsed_s": 1.0, "wasm_bytes": 65536, "log": "Loading…", "ready": False}
        ])
        self.assertFalse(report["ok"])
        self.assertEqual(report["wasm_peak_bytes"], 65536)

    def test_ready_clean_game_reports_all_samples_and_peak(self):
        samples = [
            {"elapsed_s": 1, "wasm_bytes": 65536, "log": "Loading…", "ready": False},
            {"elapsed_s": 2, "wasm_bytes": 131072, "log": "map=starter seed=1337", "ready": True},
        ]
        report = web_check.make_report(samples)
        self.assertTrue(report["ok"])
        self.assertEqual(report["wasm_peak_bytes"], 131072)
        self.assertEqual(report["samples"], samples)
        self.assertEqual(report["errors"], [])

    def test_runtime_error_cannot_be_a_successful_baseline(self):
        report = web_check.make_report([
            {"elapsed_s": 1, "wasm_bytes": 65536, "log": "map=starter seed=1337\nerror: broken", "ready": True}
        ])
        self.assertFalse(report["ok"])

    def test_ready_marker_without_wasm_memory_is_not_success(self):
        report = web_check.make_report([
            {"elapsed_s": 1, "wasm_bytes": 0, "log": "map=starter seed=1337", "ready": True}
        ])
        self.assertFalse(report["ok"])

    def test_chromium_backend_is_exposed_by_cli(self):
        result = subprocess.run([sys.executable, str(ROOT / "tools/web_check.py"), "--help"], capture_output=True, text=True)
        self.assertIn("--browser", result.stdout)
        self.assertIn("chromium", result.stdout)

    @unittest.skipUnless(os.environ.get("WEB_CHECK_INTEGRATION") == "1", "requires Playwright Chromium")
    def test_real_browser_runtime_error_returns_failure_report(self):
        import json
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as tmp:
            dist = Path(tmp)
            (dist / "index.html").write_text('''<div id="log">map=starter seed=1337</div>
<script>var wasm_memory = new WebAssembly.Memory({initial:1});
setTimeout(() => {throw new Error("baseline-runtime-regression")}, 20);</script>''')
            (dist / "gl.js").write_text("")
            (dist / "auto.wasm").write_bytes(b"\\0asm\\1\\0\\0\\0")
            result = subprocess.run([
                sys.executable, str(ROOT / "tools/web_check.py"), "--browser", "chromium",
                "--dist", str(dist), "--wait", "1", "--report", str(dist / "report.json")
            ], capture_output=True, text=True, timeout=30)
            report = json.loads((dist / "report.json").read_text())
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertFalse(report["ok"])
        self.assertTrue(any("baseline-runtime-regression" in e for e in report["page_errors"]))

    def test_missing_build_fails_before_driver_start(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR")) as tmp:
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/web_check.py"), "--dist", tmp,
                 "--geckodriver", "deliberately-absent-geckodriver"],
                capture_output=True, text=True, timeout=10,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing browser build", result.stderr)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
