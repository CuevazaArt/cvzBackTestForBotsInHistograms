from __future__ import annotations

from decimal import Decimal

from backtester.core.engine import BacktestResult
from backtester.core.metrics import (
    _compute_returns_moments,
    compute_metrics,
    deflated_sharpe_ratio,
    probabilistic_sharpe_ratio,
)


def test_probabilistic_sharpe_ratio_monotonic_on_sr_hat():
    low = probabilistic_sharpe_ratio(0.2, 0.0, 200, skew=0.0, kurt=3.0)
    high = probabilistic_sharpe_ratio(1.2, 0.0, 200, skew=0.0, kurt=3.0)
    assert high > low
    assert 0.0 <= low <= 1.0
    assert 0.0 <= high <= 1.0


def test_probabilistic_sharpe_ratio_zero_when_not_enough_samples():
    assert probabilistic_sharpe_ratio(1.0, 0.0, 1) == 0.0


def test_deflated_sharpe_ratio_below_psr_with_many_trials():
    sr_hat = 1.0
    trials = [0.2, 0.4, 0.6, 0.8, 0.9, 1.1]
    psr = probabilistic_sharpe_ratio(sr_hat, 0.0, 250)
    dsr = deflated_sharpe_ratio(sr_hat, trials, 250)
    assert dsr <= psr


def test_compute_returns_moments_defaults_for_short_series():
    skew, kurt = _compute_returns_moments([0.1, -0.1])
    assert skew == 0.0
    assert kurt == 3.0


def test_compute_metrics_summary_contains_psr_dsr():
    res = BacktestResult(
        symbol="X",
        timeframe="1h",
        candles_processed=4,
        equity_curve=[
            Decimal("100"),
            Decimal("101"),
            Decimal("100.5"),
            Decimal("102"),
        ],
        final_equity=Decimal("102"),
        peak_equity=Decimal("102"),
    )
    summary = compute_metrics(res)
    assert "total_return_pct" in summary
    assert "psr" in summary
    assert "dsr" in summary
