"""OHLCV data-quality validator.

Runs a battery of cheap, stdlib-only checks on a candle stream:

- Monotonic / strictly increasing timestamps.
- Duplicate timestamps.
- Gaps relative to the expected timeframe step (count of missing candles).
- Completeness percentage (observed / expected).
- OHLC consistency violations (``high >= low`` and ``open``/``close`` inside
  the ``[low, high]`` band).
- IQR-based outliers on per-bar simple returns (``r > 3 * IQR`` away from the
  median return).

The validator is intentionally cheap (O(N)) so it can run interactively from
the Flutter UI right after a download.
"""

from __future__ import annotations

import statistics
from dataclasses import asdict, dataclass, field
from decimal import Decimal
from typing import Any, Optional, Sequence

from backtester.core.engine import Candle


@dataclass
class DataQualityReport:
    """Summary of all data-quality checks for a candle stream."""

    total_candles: int = 0
    expected_candles: int = 0
    completeness_pct: float = 0.0
    gaps: list[dict[str, int]] = field(default_factory=list)
    duplicates: list[int] = field(default_factory=list)
    monotonic_ok: bool = True
    ohlc_consistency_violations: list[int] = field(default_factory=list)
    outliers_iqr: list[int] = field(default_factory=list)
    summary_ok: bool = True
    timeframe_seconds: Optional[int] = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _to_float(x: Any) -> float:
    """Coerce ``Decimal``/``str``/``float`` to plain ``float``."""
    if isinstance(x, Decimal):
        return float(x)
    return float(x)


def _infer_timeframe_seconds(timestamps_ms: Sequence[int]) -> Optional[int]:
    """Infer the candle step (seconds) from the median positive delta."""
    if len(timestamps_ms) < 2:
        return None
    diffs = [
        timestamps_ms[i + 1] - timestamps_ms[i]
        for i in range(len(timestamps_ms) - 1)
        if timestamps_ms[i + 1] - timestamps_ms[i] > 0
    ]
    if not diffs:
        return None
    median_ms = statistics.median(diffs)
    if median_ms <= 0:
        return None
    return max(int(round(median_ms / 1000)), 1)


def _compute_gaps(unique_sorted_ts: list[int], step_ms: int) -> list[dict[str, int]]:
    gaps: list[dict[str, int]] = []
    for i in range(len(unique_sorted_ts) - 1):
        delta = unique_sorted_ts[i + 1] - unique_sorted_ts[i]
        if delta > step_ms:
            missing = max(int(delta // step_ms) - 1, 0)
            if missing > 0:
                gaps.append(
                    {
                        "from_ts": int(unique_sorted_ts[i]),
                        "to_ts": int(unique_sorted_ts[i + 1]),
                        "missing_count": missing,
                    }
                )
    return gaps


def _compute_iqr_outliers(closes: list[float]) -> list[int]:
    """Return candle indices (1..N-1) whose simple return is > 3*IQR from median.

    When the IQR collapses to zero (degenerate, near-constant return series),
    falls back to a 3*sigma rule on the same returns so a single spike is
    still flagged. If both spread metrics are zero the series is treated as
    perfectly flat (no outliers).
    """
    if len(closes) < 5:
        return []

    returns: list[float] = []
    for i in range(1, len(closes)):
        prev = closes[i - 1]
        returns.append(0.0 if prev == 0 else (closes[i] / prev) - 1.0)
    if not returns:
        return []

    try:
        q1, _q2, q3 = statistics.quantiles(returns, n=4, method="inclusive")
    except statistics.StatisticsError:
        return []

    iqr = q3 - q1
    median = statistics.median(returns)

    if iqr > 0:
        lower = median - 3.0 * iqr
        upper = median + 3.0 * iqr
    else:
        try:
            sigma = statistics.pstdev(returns)
        except statistics.StatisticsError:
            return []
        if sigma <= 0:
            return []
        lower = median - 3.0 * sigma
        upper = median + 3.0 * sigma

    outliers: list[int] = []
    for j, r in enumerate(returns):
        if r < lower or r > upper:
            outliers.append(j + 1)
    return outliers


def validate_ohlcv(
    candles: Sequence[Candle],
    timeframe_seconds: Optional[int] = None,
) -> DataQualityReport:
    """Run all data-quality checks over ``candles``.

    If ``timeframe_seconds`` is ``None`` the function infers the step from the
    median positive delta between consecutive timestamps.
    """
    report = DataQualityReport(total_candles=len(candles))

    if not candles:
        report.monotonic_ok = True
        report.summary_ok = True
        return report

    timestamps = [int(c.timestamp_ms) for c in candles]

    if timeframe_seconds is None:
        timeframe_seconds = _infer_timeframe_seconds(timestamps)
    report.timeframe_seconds = timeframe_seconds

    seen: dict[int, int] = {}
    for ts in timestamps:
        seen[ts] = seen.get(ts, 0) + 1
    report.duplicates = sorted(ts for ts, n in seen.items() if n > 1)

    report.monotonic_ok = all(
        timestamps[i + 1] > timestamps[i] for i in range(len(timestamps) - 1)
    )

    unique_sorted_ts = sorted(seen.keys())
    if timeframe_seconds and timeframe_seconds > 0:
        step_ms = timeframe_seconds * 1000
        report.gaps = _compute_gaps(unique_sorted_ts, step_ms)
        span_ms = unique_sorted_ts[-1] - unique_sorted_ts[0]
        report.expected_candles = int(span_ms // step_ms) + 1
        report.completeness_pct = (
            (len(unique_sorted_ts) / report.expected_candles) * 100.0
            if report.expected_candles > 0
            else 0.0
        )
    else:
        report.expected_candles = len(candles)
        report.completeness_pct = 100.0 if candles else 0.0

    violations: list[int] = []
    closes: list[float] = []
    for i, c in enumerate(candles):
        o = _to_float(c.open)
        h = _to_float(c.high)
        lo = _to_float(c.low)
        cl = _to_float(c.close)
        if h < lo or cl < lo or cl > h or o < lo or o > h:
            violations.append(i)
        closes.append(cl)
    report.ohlc_consistency_violations = violations

    report.outliers_iqr = _compute_iqr_outliers(closes)

    report.summary_ok = (
        not report.gaps
        and not report.duplicates
        and report.monotonic_ok
        and not report.ohlc_consistency_violations
        and not report.outliers_iqr
        and report.completeness_pct >= 99.999
    )

    return report


__all__ = ["DataQualityReport", "validate_ohlcv"]
