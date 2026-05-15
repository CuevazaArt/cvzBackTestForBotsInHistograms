"""Backtest metrics computation.

Provides both basic summary stats (return, win-rate, profit factor) and
advanced risk-adjusted performance metrics (Sharpe, Sortino, Calmar).
"""

import math
from decimal import Decimal
from typing import Any

from backtester.core.engine import BacktestResult


# ── Helpers ──────────────────────────────────────────────────────

def _equity_returns(curve: list[Decimal]) -> list[float]:
    """Compute per-bar fractional returns from equity curve."""
    if len(curve) < 2:
        return []
    returns = []
    for i in range(1, len(curve)):
        prev = float(curve[i - 1])
        if prev > 0:
            returns.append((float(curve[i]) - prev) / prev)
        else:
            returns.append(0.0)
    return returns


def _annualization_factor(timeframe: str) -> float:
    """Approximate bars-per-year for common timeframes."""
    mapping = {
        "1m": 525_600,
        "5m": 105_120,
        "15m": 35_040,
        "1h": 8_760,
        "4h": 2_190,
        "1d": 365,
        "1w": 52,
    }
    return mapping.get(timeframe, 8_760)  # default 1h


# ── Core ─────────────────────────────────────────────────────────

def compute_metrics(result: BacktestResult) -> dict[str, Any]:
    """Compute comprehensive performance metrics.

    Includes basic stats from result.summary() plus:
    - sharpe_ratio  : annualized Sharpe (risk-free = 0)
    - sortino_ratio : annualized Sortino (downside deviation)
    - calmar_ratio  : annualized return / max drawdown
    - avg_trade_duration_hrs : mean holding period in hours
    - avg_win_pnl   : average profit on winning trades
    - avg_loss_pnl  : average loss on losing trades
    - expectancy    : (win_rate × avg_win) - (loss_rate × |avg_loss|)
    """
    base = result.summary()
    base["peak_equity"] = float(result.peak_equity)

    # Returns series
    returns = _equity_returns(result.equity_curve)
    ann = _annualization_factor(result.timeframe)

    # ── Sharpe Ratio ─────────────────────────────────────────────
    if returns:
        mean_r = sum(returns) / len(returns)
        var = sum((r - mean_r) ** 2 for r in returns) / len(returns)
        std_r = math.sqrt(var) if var > 0 else 0.0
        base["sharpe_ratio"] = round(
            (mean_r / std_r * math.sqrt(ann)) if std_r > 0 else 0.0, 4
        )
    else:
        base["sharpe_ratio"] = 0.0

    # ── Sortino Ratio ────────────────────────────────────────────
    if returns:
        mean_r = sum(returns) / len(returns)
        downside = [min(r, 0.0) ** 2 for r in returns]
        down_dev = math.sqrt(sum(downside) / len(downside)) if downside else 0.0
        base["sortino_ratio"] = round(
            (mean_r / down_dev * math.sqrt(ann)) if down_dev > 0 else 0.0, 4
        )
    else:
        base["sortino_ratio"] = 0.0

    # ── Calmar Ratio ─────────────────────────────────────────────
    max_dd_frac = float(result.max_drawdown_pct) / 100.0  # e.g. 0.12
    total_return_frac = base["total_return_pct"] / 100.0
    n_bars = len(result.equity_curve)
    if n_bars > 0 and max_dd_frac > 0:
        # annualize return
        ann_return = total_return_frac * (ann / n_bars)
        base["calmar_ratio"] = round(ann_return / max_dd_frac, 4)
    else:
        base["calmar_ratio"] = 0.0

    # ── Trade-level stats ────────────────────────────────────────
    closed = [t for t in result.trades if t.exit_idx is not None]
    winners = [t for t in closed if t.pnl > 0]
    losers = [t for t in closed if t.pnl < 0]

    avg_win = float(sum(t.pnl for t in winners) / len(winners)) if winners else 0.0
    avg_loss = float(sum(t.pnl for t in losers) / len(losers)) if losers else 0.0
    base["avg_win_pnl"] = round(avg_win, 4)
    base["avg_loss_pnl"] = round(avg_loss, 4)

    # Expectancy: (WR × avg_win) - (LR × |avg_loss|)
    wr = len(winners) / len(closed) if closed else 0
    lr = len(losers) / len(closed) if closed else 0
    base["expectancy"] = round(wr * avg_win - lr * abs(avg_loss), 4)

    # Average holding duration
    durations_ms = [
        t.exit_time - t.entry_time
        for t in closed
        if t.exit_time is not None and t.entry_time is not None
    ]
    if durations_ms:
        avg_ms = sum(durations_ms) / len(durations_ms)
        base["avg_trade_duration_hrs"] = round(avg_ms / 3_600_000, 2)
    else:
        base["avg_trade_duration_hrs"] = 0.0

    return base
