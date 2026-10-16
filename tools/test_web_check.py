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
