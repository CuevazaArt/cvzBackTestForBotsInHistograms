"""Backtest metrics computation."""

from decimal import Decimal
from typing import Any

from backtester.core.engine import BacktestResult


def compute_metrics(result: BacktestResult) -> dict[str, Any]:
    """Compute comprehensive performance metrics."""
    return {
        **result.summary(),
        "peak_equity": float(result.peak_equity),
        "final_equity": float(result.final_equity),
        "max_drawdown_pct": float(result.max_drawdown_pct),
    }
