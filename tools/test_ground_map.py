#!/usr/bin/env python3
"""tools/ground_map.py: the file the engine's ground map reads, its runs
and copies from the row above, read back as the engine reads them."""
import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
try:
    import numpy as np
    import ground_map
except ImportError:  # pragma: no cover
    np = None


def read(path):
    """As Engine::load_ground_map."""
    b = path.read_bytes()
    assert b[:4] == b"GRND"
    w, h, x0, z0, step, n = struct.unpack("<HHfffB", b[4:21])
    off = 21 + 3 * n
    idx = []
    for k in range(off, len(b), 2):
        length, i = b[k] + 1, b[k + 1]
        if i == ground_map.COPY:
            at = len(idx)
            idx.extend(idx[at - w + j] for j in range(length))
        else:
            idx.extend([i] * length)
    return (w, h, x0, z0, step), np.array(idx, np.uint8).reshape(h, w)


@unittest.skipIf(np is None, "needs numpy")
class GroundMapTests(unittest.TestCase):
    def test_write_reads_back(self):
        rng = np.random.default_rng(3)
        idx = np.repeat(rng.integers(0, 30, (40, 1)), 600, axis=1).astype(np.uint8)  # long runs
        idx[10:20] = idx[9]                                                        # rows as above
        idx[25, 100:400] = 7
        idx[30] = rng.integers(0, 30, 600)                                         # noise
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "g.bin"
            size = ground_map.write(p, -12.0, 34.0, 2.0, [(1, 2, 3)] * 30, idx)
            head, back = read(p)
        self.assertEqual(head, (600, 40, -12.0, 34.0, 2.0))
        self.assertTrue((back == idx).all())
        self.assertLess(size, 600 * 40 / 4, "runs and copies pack it")


if __name__ == "__main__":
    unittest.main()
