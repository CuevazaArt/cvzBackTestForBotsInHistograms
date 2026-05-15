"""Smoke tests for compute_metrics (delegates to BacktestResult.summary)."""

from __future__ import annotations

import pytest

from backtester.core import compute_metrics
from backtester.core.engine import BacktestConfig, BacktestEngine
from backtester.tests.conftest import linear_candles
from backtester.tests.test_engine import ScriptedBot


def test_compute_metrics_keys_present():
    candles = linear_candles([100, 110])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 1}],
                       1: [{"side": "SELL", "qty": 1}]})
    cfg = BacktestConfig(initial_cash=10_000.0, taker_fee_pct=0.0,
                         slippage_pct=0.0, fill_model="close")
    res = BacktestEngine(cfg).run(bot, candles, "SYM", "1h")
    m = compute_metrics(res)
    required = {
        "total_return_pct", "trades", "winners", "losers", "win_rate_pct",
        "profit_factor", "avg_win_usdt", "avg_loss_usdt", "max_drawdown_pct",
        "total_fees_usdt", "initial_equity", "final_equity", "peak_equity",
        "rejected_orders",
    }
    assert required.issubset(m.keys()), f"Missing keys: {required - m.keys()}"
