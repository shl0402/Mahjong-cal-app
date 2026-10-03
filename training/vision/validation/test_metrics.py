import unittest

from vision.validation.metrics import selective_metrics, wilson_interval, zero_failure_upper_bound


class MetricsTests(unittest.TestCase):
    def test_two_of_seven_has_large_uncertainty(self):
        low, high = wilson_interval(2, 7)
        self.assertAlmostEqual(low, .082218924004, places=10)
        self.assertAlmostEqual(high, .641065548167, places=10)

    def test_zero_or_all_success_boundaries_are_not_false_certainty(self):
        low, high = wilson_interval(0, 10)
        self.assertAlmostEqual(low, 0)
        self.assertAlmostEqual(high, .2775327998628892)
        all_low, all_high = wilson_interval(10, 10)
        self.assertAlmostEqual(all_low, 1 - high)
        self.assertAlmostEqual(all_high, 1)
        self.assertIsNone(wilson_interval(0, 0))

    def test_zero_false_acceptance_bound_requires_many_independent_accepted_attempts(self):
        self.assertIsNone(zero_failure_upper_bound(0))
        self.assertAlmostEqual(zero_failure_upper_bound(1), .95)
        self.assertGreater(zero_failure_upper_bound(298), .01)
        self.assertLess(zero_failure_upper_bound(299), .01)
        self.assertGreater(zero_failure_upper_bound(2994), .001)
        self.assertLess(zero_failure_upper_bound(2995), .001)

    def test_never_accepting_is_not_perfect_precision(self):
        result = selective_metrics(attempts=20, accepted=0, wrong_accepted=0,
                                   in_scope_attempts=15, correct_in_scope_accepted=0)
        self.assertIsNone(result["wrong_among_accepted"]["estimate"])
        self.assertIsNone(result["zero_wrong_accepts_upper_95"])
        self.assertEqual(result["coverage"]["estimate"], 0)
        self.assertEqual(result["correct_lock_yield"]["estimate"], 0)

    def test_selective_risk_coverage_yield_and_attempt_risk_have_distinct_denominators(self):
        result = selective_metrics(attempts=100, accepted=20, wrong_accepted=2,
                                   in_scope_attempts=80, correct_in_scope_accepted=18)
        self.assertEqual(result["coverage"]["estimate"], .2)
        self.assertEqual(result["wrong_among_accepted"]["estimate"], .1)
        self.assertEqual(result["wrong_accepts_per_attempt"]["estimate"], .02)
        self.assertEqual(result["correct_lock_yield"]["estimate"], .225)
        self.assertIsNone(result["zero_wrong_accepts_upper_95"])

    def test_invalid_counts_probabilities_and_inconsistent_partitions_rejected(self):
        for counts in [(-1, 1), (2, 1), (0, -1), (True, 2), (1.0, 2)]:
            with self.assertRaises(ValueError):
                wilson_interval(*counts)
        for confidence in [0, 1, float("nan"), float("inf"), True, "95"]:
            with self.assertRaises(ValueError):
                wilson_interval(0, 1, confidence)
            with self.assertRaises(ValueError):
                zero_failure_upper_bound(1, confidence)
        with self.assertRaises(ValueError):
            selective_metrics(attempts=10, accepted=8, wrong_accepted=2,
                              in_scope_attempts=10, correct_in_scope_accepted=5)

    def test_all_small_count_pairs_stay_bounded_symmetric_and_contain_estimate(self):
        for total in range(1, 101):
            for successes in range(total + 1):
                low, high = wilson_interval(successes, total)
                reverse_low, reverse_high = wilson_interval(total - successes, total)
                self.assertLessEqual(low, successes / total + 1e-15)
                self.assertGreaterEqual(high + 1e-15, successes / total)
                self.assertTrue(0 <= low <= high <= 1)
                self.assertAlmostEqual(low, 1 - reverse_high)
                self.assertAlmostEqual(high, 1 - reverse_low)


if __name__ == "__main__":
    unittest.main()
