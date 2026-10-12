import unittest
from headless_tests import assess, seeded_cases, DEFAULT_SEEDS


class AcceptanceTests(unittest.TestCase):
    def test_seed_pairs_cover_both_suites_and_dedupe(self):
        cases = seeded_cases(["manhattan", "harbor", "manhattan"], DEFAULT_SEEDS + [13, 42], "full")
        expected = {(m, s, suite) for m in ["manhattan", "harbor"]
                    for s in [0, *range(1, 14), 17, 42, 99, 1337, 2026]
                    for suite in ["autoplay", "reliability"]}
        self.assertEqual(set(cases), expected)
        self.assertEqual(len(cases), len(expected))

    def test_focused_suite_consumes_requested_seed(self):
        self.assertEqual(seeded_cases(["manhattan"], [42, 42], "reliability"),
                         [("manhattan", 42, "reliability")])

    def test_wrong_identity_cannot_pass(self):
        self.assertFalse(assess(0, "map=manhattan seed=1337\nRELIABILITY PASSED",
                               ["map=manhattan seed=42", "RELIABILITY PASSED"])[0])

    def test_tick_limit_exit_zero_is_not_success(self):
        self.assertFalse(assess(0, "headless: 9000 ticks", ["AUTOPLAY PASSED", "GARAGE PASSED"])[0])

    def test_partial_completion_is_not_success(self):
        self.assertFalse(assess(0, "AUTOPLAY PASSED", ["AUTOPLAY PASSED", "GARAGE PASSED"])[0])

    def test_lua_error_after_markers_is_not_success(self):
        self.assertFalse(assess(0, "AUTOPLAY PASSED\nGARAGE PASSED\n[lua:tick] invalid key to 'next'",
                                ["AUTOPLAY PASSED", "GARAGE PASSED"])[0])

    def test_nonzero_exit_is_not_success(self):
        self.assertFalse(assess(1, "GARAGE PASSED", ["GARAGE PASSED"])[0])

    def test_complete_clean_exit_is_success(self):
        self.assertEqual(assess(0, "AUTOPLAY PASSED\nGARAGE PASSED", ["AUTOPLAY PASSED", "GARAGE PASSED"]),
                         (True, [], []))


if __name__ == "__main__":
    unittest.main()
