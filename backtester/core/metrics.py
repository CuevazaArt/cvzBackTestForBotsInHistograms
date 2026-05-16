"""Backtest metrics computation.

Provides both basic summary stats (return, win-rate, profit factor) and
advanced risk-adjusted performance metrics (Sharpe, Sortino, Calmar).
"""

import math
from decimal import Decimal
from statistics import NormalDist
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


def _compute_returns_moments(returns: list[float]) -> tuple[float, float]:
    """Return (skewness, kurtosis) of returns.

    Kurtosis returned here is the *non-excess* kurtosis (normal == 3).
    """
    n = len(returns)
    if n < 3:
        return 0.0, 3.0
    mean_r = sum(returns) / n
    var = sum((r - mean_r) ** 2 for r in returns) / n
    if var <= 0:
        return 0.0, 3.0
    std = math.sqrt(var)
    m3 = sum(((r - mean_r) / std) ** 3 for r in returns) / n
    m4 = sum(((r - mean_r) / std) ** 4 for r in returns) / n
    return m3, m4


def probabilistic_sharpe_ratio(
    sr_hat: float,
    sr_benchmark: float,
    n: int,
    skew: float = 0.0,
    kurt: float = 3.0,
) -> float:
    """Probability that estimated SR is greater than a benchmark SR."""
    if n <= 1:
        return 0.0
    denom = math.sqrt(
        max(1e-12, 1.0 - skew * sr_hat + ((kurt - 1.0) / 4.0) * (sr_hat**2))
    )
    z = ((sr_hat - sr_benchmark) * math.sqrt(n - 1)) / denom
    return float(NormalDist().cdf(z))


def deflated_sharpe_ratio(
    sr_hat: float,
    sr_benchmarks: list[float],
    n: int,
    skew: float = 0.0,
    kurt: float = 3.0,
) -> float:
    """Deflated Sharpe ratio (DSR) using a multiple-testing benchmark."""
    if not sr_benchmarks:
        return probabilistic_sharpe_ratio(sr_hat, 0.0, n, skew, kurt)
    mean_b = sum(sr_benchmarks) / len(sr_benchmarks)
    var_b = sum((x - mean_b) ** 2 for x in sr_benchmarks) / len(sr_benchmarks)
    std_b = math.sqrt(max(var_b, 0.0))
    trials = max(2, len(sr_benchmarks))
    quantile = 1.0 - (1.0 / trials)
    z_max = NormalDist().inv_cdf(min(0.999999, max(0.500001, quantile)))
    sr_star = mean_b + std_b * z_max
    return probabilistic_sharpe_ratio(sr_hat, sr_star, n, skew, kurt)


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
        base["median_trade_duration_hrs"] = round(
            sorted(durations_ms)[len(durations_ms) // 2] / 3_600_000,
            2,
        )
    else:
        base["avg_trade_duration_hrs"] = 0.0
        base["median_trade_duration_hrs"] = 0.0

    # ── Advanced metrics (Phase 3) ───────────────────────────────
    base["ulcer_index"] = _ulcer_index(result.equity_curve)
    base["recovery_factor"] = _recovery_factor(result, base["total_return_pct"])
    base.update(_streak_analysis(closed))
    base.update(_excursion_stats(closed))

    # ── Probabilistic / deflated Sharpe (selection-bias aware) ──
    skew, kurt = _compute_returns_moments(returns)
    sr_hat = float(base.get("sharpe_ratio", 0.0))
    n_ret = len(returns)
    base["psr"] = round(
        probabilistic_sharpe_ratio(sr_hat, 0.0, n_ret, skew=skew, kurt=kurt), 6
    )
    # For single-run summaries we only have one observed SR; callers that have
    # many trial SRs can call `deflated_sharpe_ratio(...)` directly.
    base["dsr"] = round(
        deflated_sharpe_ratio(sr_hat, [sr_hat], n_ret, skew=skew, kurt=kurt), 6
    )

    return base


# ── Advanced metric helpers ──────────────────────────────────────


def _ulcer_index(equity_curve: list[Decimal]) -> float:
    """Ulcer Index — RMS of percentage drawdowns at every bar.

    Penalizes deep AND prolonged drawdowns more harshly than max-DD alone.
    Lower is better. Used for risk-aware ranking (Martin ratio = return / UI).
    """
    if not equity_curve:
        return 0.0
    peak = Decimal("0")
    squared = []
    for eq in equity_curve:
        if eq > peak:
            peak = eq
        if peak > 0:
            dd = float((peak - eq) / peak * 100)  # %
            squared.append(dd * dd)
    if not squared:
        return 0.0
    return round(math.sqrt(sum(squared) / len(squared)), 4)


def _recovery_factor(result: BacktestResult, total_return_pct: float) -> float:
    """Recovery Factor — total net return divided by max drawdown.

    Measures how efficiently the strategy recovers from its worst dip.
    Values >2 are typically considered strong; <1 is concerning.
    """
    dd = float(result.max_drawdown_pct)
    if dd <= 0:
        return 0.0
    return round(abs(total_return_pct) / dd, 4)


def _streak_analysis(closed_trades: list) -> dict[str, Any]:
    """Compute consecutive win/loss streaks and stability metrics.

    Returns:
        max_consecutive_wins  : longest winning streak count
        max_consecutive_losses: longest losing streak count
        avg_consecutive_wins  : mean length of winning runs
        avg_consecutive_losses: mean length of losing runs
    """
    if not closed_trades:
        return {
            "max_consecutive_wins": 0,
            "max_consecutive_losses": 0,
            "avg_consecutive_wins": 0.0,
            "avg_consecutive_losses": 0.0,
        }
    win_runs: list[int] = []
    loss_runs: list[int] = []
    cur_win, cur_loss = 0, 0
    for t in closed_trades:
        if t.pnl > 0:
            cur_win += 1
            if cur_loss > 0:
                loss_runs.append(cur_loss)
                cur_loss = 0
        elif t.pnl < 0:
            cur_loss += 1
            if cur_win > 0:
                win_runs.append(cur_win)
                cur_win = 0
        # break-even (pnl == 0) does not extend either streak
    if cur_win > 0:
        win_runs.append(cur_win)
    if cur_loss > 0:
        loss_runs.append(cur_loss)
    return {
        "max_consecutive_wins": max(win_runs) if win_runs else 0,
        "max_consecutive_losses": max(loss_runs) if loss_runs else 0,
        "avg_consecutive_wins": round(sum(win_runs) / len(win_runs), 2)
        if win_runs
        else 0.0,
        "avg_consecutive_losses": round(sum(loss_runs) / len(loss_runs), 2)
        if loss_runs
        else 0.0,
    }


def _excursion_stats(closed_trades: list) -> dict[str, Any]:
    """Aggregate MFE/MAE statistics over all closed trades.

    Helps decide stop-loss / take-profit placement:
    - High avg_mfe with low avg_pnl → exits too early (leaving money)
    - High avg_mae with positive avg_pnl → stops too tight (good risk)
    """
    if not closed_trades:
        return {
            "avg_mfe_pct": 0.0,
            "avg_mae_pct": 0.0,
            "max_mfe_pct": 0.0,
            "max_mae_pct": 0.0,
            "mfe_to_pnl_ratio": 0.0,
        }
    mfes = [float(t.mfe_pct) for t in closed_trades]
    maes = [float(t.mae_pct) for t in closed_trades]
    pnl_pcts = [float(t.pnl_pct) for t in closed_trades]
    avg_mfe = sum(mfes) / len(mfes)
    avg_pnl_pct = sum(pnl_pcts) / len(pnl_pcts)
    return {
        "avg_mfe_pct": round(avg_mfe, 4),
        "avg_mae_pct": round(sum(maes) / len(maes), 4),
        "max_mfe_pct": round(max(mfes), 4),
        "max_mae_pct": round(min(maes), 4),
        # mfe_to_pnl > 2 suggests exits leave a lot of profit on the table
        "mfe_to_pnl_ratio": round(avg_mfe / abs(avg_pnl_pct), 4)
        if avg_pnl_pct != 0
        else 0.0,
    }
