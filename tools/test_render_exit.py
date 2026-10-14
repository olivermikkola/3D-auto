"""Public rendered-binary exit contract on an isolated software-GL display."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target/release/auto"


@unittest.skipUnless(os.name == "posix" and shutil.which("xvfb-run"), "isolated Xvfb required")
class RenderExitTests(unittest.TestCase):
    def run_render(self, lua, *flags):
        with tempfile.TemporaryDirectory(prefix="auto-render-exit-") as directory:
            folder = Path(directory)
            (folder / "main.lua").write_text(lua, encoding="utf-8")
            environment = os.environ.copy()
            environment.update(LIBGL_ALWAYS_SOFTWARE="1", GALLIUM_DRIVER="llvmpipe", LP_NUM_THREADS="2")
            command = ["xvfb-run", "-a", "-s", "-screen 0 640x360x24 -nolisten tcp",
                       str(BINARY), str(folder), "--frames", "3", "--size", "320x180", *flags]
            return subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=20)

    def test_frame_error_after_success_marker_exits_nonzero(self):
        result = self.run_render('''
engine.on("frame", function()
  print("EARLY SUCCESS MARKER")
  error("deliberate rendered frame failure")
end)
''')
        self.assertIn("EARLY SUCCESS MARKER", result.stdout)
        self.assertIn("[lua:frame]", result.stderr)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_load_failure_exits_nonzero(self):
        result = self.run_render('error("deliberate rendered load failure")')
        self.assertIn("[lua:load]", result.stderr)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_quit_handler_failure_exits_nonzero(self):
        result = self.run_render('engine.on("quit", function() error("deliberate quit failure") end)')
        self.assertIn("[lua:quit]", result.stderr)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_clean_fixed_run_exits_zero(self):
        result = self.run_render('engine.on("quit", function() print("CLEAN RENDER PASSED") end)')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CLEAN RENDER PASSED", result.stdout)


if __name__ == "__main__":
    unittest.main()
