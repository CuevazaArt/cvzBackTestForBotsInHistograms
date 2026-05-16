"""Unit tests for :mod:`backtester.core.data_quality`.

Covers 8 scenarios:
    1. Perfect data — every check passes.
    2. Single gap — one missing candle is reported.
    3. Multiple gaps — each is reported independently.
    4. Duplicate timestamps — collisions are surfaced.
    5. OHLC violation — high < low is flagged.
    6. Outlier detection — a large return spike lands in ``outliers_iqr``.
    7. Empty list — validator returns a clean default-ok report.
    8. All-identical candles — no outliers (IQR == 0) and not flagged.
"""

from __future__ import annotations

from decimal import Decimal

from backtester.core.data_quality import DataQualityReport, validate_ohlcv
from backtester.core.engine import Candle


_STEP_MS = 60 * 60 * 1000  # 1h candles


def _make_candle(
    ts_ms: int,
    *,
    open_: float = 100.0,
    high: float | None = None,
    low: float | None = None,
    close: float | None = None,
    volume: float = 1.0,
) -> Candle:
    o = open_
    c = close if close is not None else open_
    h = high if high is not None else max(o, c) + 0.5
    lo = low if low is not None else min(o, c) - 0.5
    return Candle(
        timestamp_ms=ts_ms,
        open=Decimal(str(o)),
        high=Decimal(str(h)),
        low=Decimal(str(lo)),
        close=Decimal(str(c)),
        volume=Decimal(str(volume)),
    )


def _perfect_series(n: int = 50) -> list[Candle]:
    return [
        _make_candle(i * _STEP_MS, open_=100.0 + i * 0.1, close=100.0 + i * 0.1)
        for i in range(n)
    ]


def test_perfect_data_passes_every_check() -> None:
    candles = _perfect_series(60)
    report = validate_ohlcv(candles, timeframe_seconds=3600)

    assert isinstance(report, DataQualityReport)
    assert report.total_candles == 60
    assert report.expected_candles == 60
    assert report.completeness_pct == 100.0
    assert report.gaps == []
    assert report.duplicates == []
    assert report.monotonic_ok is True
    assert report.ohlc_consistency_violations == []
    assert report.outliers_iqr == []
    assert report.summary_ok is True


def test_single_gap_is_reported() -> None:
    candles = _perfect_series(20)
    # Drop the candle at index 10 so there's a 2-step jump.
    candles_with_hole = candles[:10] + candles[11:]
    report = validate_ohlcv(candles_with_hole, timeframe_seconds=3600)

    assert len(report.gaps) == 1
    gap = report.gaps[0]
    assert gap["missing_count"] == 1
    assert gap["from_ts"] == 9 * _STEP_MS
    assert gap["to_ts"] == 11 * _STEP_MS
    assert report.completeness_pct < 100.0
    assert report.summary_ok is False


def test_multiple_gaps_are_each_reported() -> None:
    candles = _perfect_series(30)
    # Drop two separate ranges: index 5 and indices 15+16.
    survivors = [c for i, c in enumerate(candles) if i not in {5, 15, 16}]
    report = validate_ohlcv(survivors, timeframe_seconds=3600)

    assert len(report.gaps) == 2
    missing_counts = sorted(g["missing_count"] for g in report.gaps)
    assert missing_counts == [1, 2]
    assert report.summary_ok is False


def test_duplicate_timestamps_are_surfaced() -> None:
    candles = _perfect_series(10)
    # Re-emit candle at idx 4 — same timestamp.
    duplicated = candles + [_make_candle(4 * _STEP_MS, open_=100.0, close=101.0)]
    report = validate_ohlcv(duplicated, timeframe_seconds=3600)

    assert report.duplicates == [4 * _STEP_MS]
    # Same timestamp twice in a row → not strictly monotonic.
    assert report.monotonic_ok is False
    assert report.summary_ok is False


def test_ohlc_violation_high_below_low_is_flagged() -> None:
    candles = _perfect_series(8)
    candles[3] = Candle(
        timestamp_ms=3 * _STEP_MS,
        open=Decimal("100"),
        high=Decimal("99"),
        low=Decimal("101"),
        close=Decimal("100"),
        volume=Decimal("1"),
    )
    report = validate_ohlcv(candles, timeframe_seconds=3600)

    assert 3 in report.ohlc_consistency_violations
    assert report.summary_ok is False


def test_outlier_iqr_detects_return_spike() -> None:
    candles: list[Candle] = []
    price = 100.0
    for i in range(40):
        if i == 25:
            price = price * 2.0
        else:
            price = price * 1.001
        candles.append(_make_candle(i * _STEP_MS, open_=price, close=price))

    report = validate_ohlcv(candles, timeframe_seconds=3600)
    assert 25 in report.outliers_iqr
    assert report.summary_ok is False


def test_empty_candle_list_returns_default_ok_report() -> None:
    report = validate_ohlcv([], timeframe_seconds=3600)

    assert report.total_candles == 0
    assert report.expected_candles == 0
    assert report.completeness_pct == 0.0
    assert report.gaps == []
    assert report.duplicates == []
    assert report.monotonic_ok is True
    assert report.ohlc_consistency_violations == []
    assert report.outliers_iqr == []
    assert report.summary_ok is True


def test_all_identical_candles_have_no_outliers() -> None:
    # 30 candles, all the same price → return = 0, IQR = 0, no outliers.
    candles = [_make_candle(i * _STEP_MS, open_=100.0, close=100.0) for i in range(30)]
    report = validate_ohlcv(candles, timeframe_seconds=3600)

    assert report.outliers_iqr == []
    assert report.ohlc_consistency_violations == []
    assert report.gaps == []
    assert report.duplicates == []
    assert report.monotonic_ok is True
    assert report.summary_ok is True


def test_timeframe_inference_when_not_provided() -> None:
    candles = _perfect_series(15)
    report = validate_ohlcv(candles, timeframe_seconds=None)
    assert report.timeframe_seconds == 3600
