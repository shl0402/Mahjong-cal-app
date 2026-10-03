"""Attempt-level selective recognition metrics with explicit denominators."""

import math
from statistics import NormalDist


def _counts(successes, total):
    if type(successes) is not int or type(total) is not int or not 0 <= successes <= total:
        raise ValueError("counts must be integers satisfying 0 <= successes <= total")


def wilson_interval(successes, total, confidence=.95):
    """Two-sided Wilson score interval; None when no trials were observed.

    Assumes independent Bernoulli trials. Correlated video frames are not trials.
    """
    _counts(successes, total)
    if type(confidence) not in (int, float) or not 0 < confidence < 1:
        raise ValueError("confidence must lie strictly between zero and one")
    if total == 0:
        return None
    z = -NormalDist().inv_cdf((1 - confidence) / 2)
    p = successes / total
    denominator = 1 + z * z / total
    center = (p + z * z / (2 * total)) / denominator
    half = z * math.sqrt(p * (1 - p) / total + z * z / (4 * total * total)) / denominator
    return max(0., center - half), min(1., center + half)


def zero_failure_upper_bound(total, confidence=.95):
    """Exact one-sided binomial upper bound when zero failures are observed."""
    _counts(0, total)
    if type(confidence) not in (int, float) or not 0 < confidence < 1:
        raise ValueError("confidence must lie strictly between zero and one")
    if total == 0:
        return None
    return -math.expm1(math.log1p(-confidence) / total)


def rate(successes, total):
    _counts(successes, total)
    return {"numerator": successes, "denominator": total,
            "estimate": successes / total if total else None,
            "wilson_95": wilson_interval(successes, total)}


def selective_metrics(*, attempts, accepted, wrong_accepted, in_scope_attempts,
                      correct_in_scope_accepted):
    """Counts are distinct capture attempts, with at most one first lock each.

    Unsupported/negative attempts can only abstain or be wrongly accepted.
    False-acceptance risk is undefined when every attempt abstains.
    """
    _counts(accepted, attempts)
    _counts(wrong_accepted, accepted)
    _counts(in_scope_attempts, attempts)
    _counts(correct_in_scope_accepted, in_scope_attempts)
    if correct_in_scope_accepted != accepted - wrong_accepted:
        raise ValueError("accepted must partition into correct in-scope and wrong accepts")
    return {
        "coverage": rate(accepted, attempts),
        "wrong_among_accepted": rate(wrong_accepted, accepted),
        "wrong_accepts_per_attempt": rate(wrong_accepted, attempts),
        "correct_lock_yield": rate(correct_in_scope_accepted, in_scope_attempts),
        "zero_wrong_accepts_upper_95": zero_failure_upper_bound(accepted)
        if wrong_accepted == 0 else None,
        "uncertainty_warning": "Intervals assume independent attempts; also report session/tile-set clusters.",
    }
