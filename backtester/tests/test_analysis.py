"""Tests for Phase 3 decision-support analysis modules.

Covers:
- MAE/MFE tracking on engine Trade records
- Advanced metrics (Ulcer Index, recovery factor, streaks, excursions)
- Walk-Forward Analysis (window generation, verdict logic)
- Monte Carlo simulation (shuffle, bootstrap, percentile stability)
- Robustness Score (normalization, weighting, ranking)
"""

from __future__ import annotations

import math
from decimal import Decimal


from backtester.analysis import (
    MonteCarloConfig,
    WalkForwardConfig,
    run_monte_carlo,
    run_walk_forward,
    score_runs,
)
from backtester.analysis.walk_forward import _generate_windows
from backtester.core.engine import BacktestConfig, BacktestEngine, Candle


# ── Helpers ──────────────────────────────────────────────────────────


def _candles(n: int = 200, *, trend: float = 0.0) -> list[Candle]:
    """Synthetic 1h candles with optional drift."""
    out = []
    for i in range(n):
        base = Decimal(str(100.0 + 30 * math.sin(i / 20.0) + trend * i))
        out.append(
            Candle(
                timestamp_ms=i * 3_600_000,
                open=base,
                high=base + Decimal("1.5"),
                low=base - Decimal("1.5"),
                close=base + Decimal("0.2"),
                volume=Decimal("10"),
            )
        )
    return out


class _AlwaysBuyAndSell:
    """Toy bot: buys on even bars, sells on odd bars. Used to generate trades."""

    def on_candle(self, candle, portfolio):
        bar = candle.timestamp_ms // 3_600_000
        if bar % 4 == 0 and portfolio.cash > candle.close * Decimal("0.1"):
            return [{"side": "BUY", "qty": Decimal("0.1")}]
        if bar % 4 == 2 and portfolio.positions:
            return [{"side": "SELL", "qty": Decimal("0.1")}]
        return []


# ── MAE/MFE ──────────────────────────────────────────────────────────


def test_engine_records_mfe_mae_on_closed_trades():
    """Closed trades should carry mfe_pct and mae_pct snapshot from Position."""
    engine = BacktestEngine(
        BacktestConfig(initial_cash=Decimal("10000"), fill_on_next_open=False)
    )
    result = engine.run([_AlwaysBuyAndSell()], _candles(100))
    assert len(result.trades) > 0
    for t in result.trades:
        assert hasattr(t, "mfe_pct"), "Trade must expose mfe_pct"
        assert hasattr(t, "mae_pct"), "Trade must expose mae_pct"
        assert hasattr(t, "duration_bars")
        # MFE should be >= 0 (price went up at some point above entry, or 0 if never)
        # MAE should be <= 0 (price went below entry, or 0 if never)
        assert t.mfe_pct >= 0, f"MFE must be non-negative, got {t.mfe_pct}"
        assert t.mae_pct <= 0, f"MAE must be non-positive, got {t.mae_pct}"
        assert t.duration_bars >= 0


def test_mfe_mae_includes_exit_candle_range():
    """Regression: MFE/MAE must capture the high/low of the exit candle itself.

    Build 3 candles where the exit candle has a clearly wider range than the
    entry candle; the trade's MFE/MAE should reflect that wider range.
    """

    class _BuyHoldSell:
        """Buy on first candle, hold through middle, sell on the third."""

        def __init__(self):
            self.n = 0

        def on_candle(self, candle, portfolio):
            self.n += 1
            if self.n == 1:
                return [{"side": "BUY", "qty": Decimal("1")}]
            if self.n == 3 and portfolio.positions:
                return [{"side": "SELL", "qty": Decimal("1")}]
            return []

    # Entry candle: tight range around 100. Mid candle: wide rally to 120,
    # dip to 80. Exit candle: even wider — top 130, bottom 70. The trade's
    # MFE must reflect 130, MAE must reflect 70.
    candles = [
        Candle(
            timestamp_ms=0,
            open=Decimal("100"),
            high=Decimal("101"),
            low=Decimal("99"),
            close=Decimal("100"),
            volume=Decimal("1"),
        ),
        Candle(
            timestamp_ms=3_600_000,
            open=Decimal("100"),
            high=Decimal("120"),
            low=Decimal("80"),
            close=Decimal("100"),
            volume=Decimal("1"),
        ),
        Candle(
            timestamp_ms=7_200_000,
            open=Decimal("100"),
            high=Decimal("130"),
            low=Decimal("70"),
            close=Decimal("100"),
            volume=Decimal("1"),
        ),
    ]
    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=Decimal("10000"),
            taker_fee_pct=Decimal("0"),
            slippage_pct=Decimal("0"),
            fill_on_next_open=False,
        )
    )
    result = engine.run([_BuyHoldSell()], candles)
    assert len(result.trades) == 1
    t = result.trades[0]
    # Entry was at candle[0].close = 100. MFE should reach at least the third
    # candle's high (130) → +30%. MAE should reach the third candle's low
    # (70) → -30%. Allow small tolerance for slippage rounding.
    assert float(t.mfe_pct) >= 29.0, (
        f"MFE must include exit candle high, got {t.mfe_pct}"
    )
    assert float(t.mae_pct) <= -29.0, (
        f"MAE must include exit candle low, got {t.mae_pct}"
    )


def test_metrics_include_advanced_fields():
    """compute_metrics should expose Phase 3 advanced metrics."""
    from backtester.core.metrics import compute_metrics

    engine = BacktestEngine()
    result = engine.run([_AlwaysBuyAndSell()], _candles(200))
    m = compute_metrics(result)
    for key in (
        "ulcer_index",
        "recovery_factor",
        "max_consecutive_wins",
        "max_consecutive_losses",
        "avg_mfe_pct",
        "avg_mae_pct",
        "max_mfe_pct",
        "max_mae_pct",
        "mfe_to_pnl_ratio",
        "median_trade_duration_hrs",
    ):
        assert key in m, f"Missing metric: {key}"


# ── Walk-Forward ─────────────────────────────────────────────────────


def test_walk_forward_window_generation_rolling():
    splits = _generate_windows(
        n_candles=1000,
        cfg=WalkForwardConfig(train_size=400, test_size=100, step_size=100),
    )
    # First window: train [0,400), test [400,500)
    assert splits[0] == (0, 400, 400, 500)
    # Walks until last test ends at n=1000
    assert splits[-1][3] <= 1000
    # Non-anchored: train start slides forward each step
    assert splits[1][0] == 100


def test_walk_forward_window_generation_anchored():
    splits = _generate_windows(
        n_candles=600,
        cfg=WalkForwardConfig(train_size=200, test_size=100, anchored=True),
    )
    # Anchored: every train window starts at 0
    for s in splits:
        assert s[0] == 0


def test_walk_forward_orchestration_with_stub_callbacks():
    """Orchestrator should call train/test fns per window and produce verdict."""
    calls = {"train": 0, "test": 0}

    def train_fn(is_s, is_e, idx):
        calls["train"] += 1
        return {"fast": 5 + idx}, {"total_return_pct": 10.0 + idx}

    def test_fn(params, oos_s, oos_e, idx):
        calls["test"] += 1
        # Simulate OOS being roughly half of IS (typical decay)
        return {"total_return_pct": (5.0 + idx) * 0.6}

    cfg = WalkForwardConfig(train_size=200, test_size=50, step_size=50)
    result = run_walk_forward(
        n_candles=500, config=cfg, train_fn=train_fn, test_fn=test_fn
    )

    assert calls["train"] >= 3
    assert calls["test"] == calls["train"]
    assert result.total_windows == len(result.windows)
    assert result.efficiency_ratio != 0.0
    assert result.verdict in ("robust", "weak", "overfit", "inconclusive")


def test_walk_forward_overfit_verdict():
    """Strongly positive IS, negative OOS → overfit verdict."""

    def train_fn(is_s, is_e, idx):
        return {"x": 1}, {"total_return_pct": 30.0}

    def test_fn(params, oos_s, oos_e, idx):
        return {"total_return_pct": -5.0}

    cfg = WalkForwardConfig(train_size=200, test_size=50)
    result = run_walk_forward(
        n_candles=600, config=cfg, train_fn=train_fn, test_fn=test_fn
    )
    assert result.verdict == "overfit"
    assert result.avg_oos_return_pct < 0


def test_walk_forward_robust_verdict():
    """Consistent positive OOS with good IS→OOS efficiency → robust."""

    def train_fn(is_s, is_e, idx):
        return {"x": 1}, {"total_return_pct": 10.0}

    def test_fn(params, oos_s, oos_e, idx):
        # Stable, positive, ~80% of IS
        return {"total_return_pct": 8.0 + (idx % 2) * 0.5}

    cfg = WalkForwardConfig(train_size=200, test_size=50)
    result = run_walk_forward(
        n_candles=800, config=cfg, train_fn=train_fn, test_fn=test_fn
    )
    assert result.verdict in ("robust", "weak")
    assert result.profitable_windows == result.total_windows


# ── Monte Carlo ──────────────────────────────────────────────────────


def test_monte_carlo_shuffle_preserves_mean_return():
    """Shuffling preserves total PnL — mean return across trials ≈ deterministic return."""
    pnls = [10.0, -5.0, 15.0, -3.0, 8.0, -2.0, 12.0, -4.0, 7.0, -1.0]
    expected_total = sum(pnls)
    result = run_monte_carlo(
        pnls,
        MonteCarloConfig(trials=500, method="shuffle", seed=42, initial_equity=10_000),
    )
    expected_return_pct = expected_total / 10_000 * 100
    # Mean of shuffled trials should equal the deterministic return (within numerical noise)
    assert abs(result.return_pct.mean - expected_return_pct) < 0.01


def test_monte_carlo_bootstrap_varies_returns():
    """Bootstrap (with replacement) should produce a wider return distribution than shuffle."""
    pnls = [10.0, -5.0, 15.0, -3.0, 8.0, -2.0, 12.0, -4.0, 7.0, -1.0]
    bs = run_monte_carlo(pnls, MonteCarloConfig(trials=500, method="bootstrap", seed=1))
    sh = run_monte_carlo(pnls, MonteCarloConfig(trials=500, method="shuffle", seed=1))
    # Bootstrap should have higher std (resampling adds variance vs. fixed-set permutation)
    assert bs.return_pct.std >= sh.return_pct.std


def test_monte_carlo_percentiles_ordered():
    """Percentiles must satisfy p5 <= p25 <= p50 <= p75 <= p95."""
    pnls = [1.0, -1.0, 2.0, -1.5, 0.5, -0.5, 3.0, -2.0]
    result = run_monte_carlo(pnls, MonteCarloConfig(trials=200, seed=7))
    p = result.return_pct
    assert p.p5 <= p.p25 <= p.p50 <= p.p75 <= p.p95


def test_monte_carlo_prob_profit_ranges_0_to_1():
    pnls = [10.0, 5.0, 3.0, 2.0, 1.0]  # all winners
    result = run_monte_carlo(pnls, MonteCarloConfig(trials=100, seed=0))
    # All winners → prob_profit should be 1.0 (or very close)
    assert result.prob_profit > 0.99


def test_monte_carlo_empty_trades_returns_zeros():
    result = run_monte_carlo([], MonteCarloConfig(trials=100))
    assert result.n_trials == 0
    assert result.return_pct.mean == 0.0


def test_monte_carlo_configurable_ruin_threshold():
    """ruin_drawdown_pct controls what counts as 'ruin' for prob_ruin."""
    # Trades that produce a ~25% drawdown
    pnls = [-2500.0] + [50.0] * 50
    aggressive = run_monte_carlo(
        pnls,
        MonteCarloConfig(trials=200, seed=0, ruin_drawdown_pct=75.0),
    )
    conservative = run_monte_carlo(
        pnls,
        MonteCarloConfig(trials=200, seed=0, ruin_drawdown_pct=20.0),
    )
    # The same drawdown is "ruin" by the conservative threshold but not the
    # aggressive one → conservative.prob_ruin >= aggressive.prob_ruin
    assert conservative.prob_ruin >= aggressive.prob_ruin


def test_monte_carlo_rejects_invalid_ruin_threshold():
    import pytest as _pytest

    with _pytest.raises(ValueError):
        MonteCarloConfig(trials=100, ruin_drawdown_pct=0.0)
    with _pytest.raises(ValueError):
        MonteCarloConfig(trials=100, ruin_drawdown_pct=150.0)


# ── Robustness Score ─────────────────────────────────────────────────


def test_robustness_score_orders_by_composite():
    """Candidate with best metrics overall should rank #1."""
    candidates = [
        {
            "params": {"fast": 5},
            "metrics": {
                "sharpe_ratio": 1.5,
                "profit_factor": 2.0,
                "recovery_factor": 3.0,
                "win_rate_pct": 55.0,
                "trades": 100,
                "max_drawdown_pct": 8.0,
            },
        },
        {
            "params": {"fast": 12},
            "metrics": {
                "sharpe_ratio": 0.5,
                "profit_factor": 1.1,
                "recovery_factor": 1.2,
                "win_rate_pct": 45.0,
                "trades": 50,
                "max_drawdown_pct": 25.0,
            },
        },
        {
            "params": {"fast": 20},
            "metrics": {
                "sharpe_ratio": 1.0,
                "profit_factor": 1.5,
                "recovery_factor": 2.0,
                "win_rate_pct": 50.0,
                "trades": 80,
                "max_drawdown_pct": 15.0,
            },
        },
    ]

    def _label(c):
        items = ", ".join(f"{k}={v}" for k, v in c["params"].items())
        return items or "default"

    ranked = score_runs(candidates, label_fn=_label)
    assert len(ranked) == 3
    assert ranked[0].rank == 1
    # The strongest candidate (fast=5) should top the list
    assert ranked[0].label == "fast=5"
    assert 0.0 <= ranked[0].score <= 1.0


def test_robustness_score_handles_identical_candidates():
    """All-equal candidates → all components ≈ 0.5 (mid-range)."""
    same = {
        "params": {"x": 1},
        "metrics": {
            "sharpe_ratio": 1.0,
            "profit_factor": 1.5,
            "recovery_factor": 2.0,
            "win_rate_pct": 50.0,
            "trades": 100,
        },
    }
    ranked = score_runs([same, dict(same), dict(same)])
    for s in ranked:
        # All normalized components should be 0.5 (handled by _normalize_min_max when hi==lo)
        for k, v in s.components.items():
            if k == "trade_count":
                continue  # trade_count saturates at 1.0
            assert v == 0.5


def test_robustness_score_low_trade_count_penalized():
    """Candidate with <30 trades should be penalized in trade_count component."""
    cands = [
        {"params": {}, "metrics": {"sharpe_ratio": 1.0, "trades": 10}},
        {"params": {}, "metrics": {"sharpe_ratio": 1.0, "trades": 100}},
    ]
    ranked = score_runs(cands)
    # The one with 100 trades should outrank the one with 10
    high_trades = next(s for s in ranked if s.metrics["trades"] == 100)
    low_trades = next(s for s in ranked if s.metrics["trades"] == 10)
    assert high_trades.rank < low_trades.rank
    assert high_trades.components["trade_count"] > low_trades.components["trade_count"]
