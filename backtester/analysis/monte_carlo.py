"""Monte Carlo simulation — robustness testing via trade re-sampling.

Standard backtest results report a SINGLE realization of the strategy. But
the order of wins/losses dramatically affects the worst-case drawdown. Two
strategies with identical trade-distribution can have very different paths.

Monte Carlo answers: "If the same trades had occurred in a different order,
what range of outcomes could I have seen?"

Methods supported:
- shuffle  : randomize the order of historical trades (preserves stats, tests path)
- bootstrap: resample WITH replacement (tests "if I'd had a different sample
             of trades from this distribution")

Both reconstruct synthetic equity curves and compute percentile statistics
(P5, P25, P50, P75, P95) for:
- Total return %
- Max drawdown %
- Worst losing streak

Use these to set risk budgets: "P5 of max DD is the worst-case loss I should
plan for to be 95% confident."
"""

from __future__ import annotations

import logging
import random
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

_LOG = logging.getLogger("backtester.analysis.monte_carlo")


@dataclass
class MonteCarloConfig:
    """Monte Carlo simulation configuration."""
    trials: int = 1000                # number of simulated equity curves
    method: str = "shuffle"           # "shuffle" or "bootstrap"
    seed: Optional[int] = None        # for reproducibility
    initial_equity: float = 10_000.0

    def __post_init__(self) -> None:
        if self.trials < 10:
            raise ValueError("trials must be at least 10 (10_000 recommended)")
        if self.method not in ("shuffle", "bootstrap"):
            raise ValueError("method must be 'shuffle' or 'bootstrap'")


@dataclass
class MonteCarloPercentiles:
    """Percentile stats for a single metric across simulations."""
    p5: float
    p25: float
    p50: float
    p75: float
    p95: float
    mean: float
    std: float

    def to_dict(self) -> dict[str, float]:
        return {
            "p5": self.p5, "p25": self.p25, "p50": self.p50,
            "p75": self.p75, "p95": self.p95,
            "mean": self.mean, "std": self.std,
        }


@dataclass
class MonteCarloResult:
    """Aggregated Monte Carlo simulation results."""
    config: MonteCarloConfig
    n_trials: int
    n_trades: int                                # trades in source data
    return_pct: MonteCarloPercentiles
    max_drawdown_pct: MonteCarloPercentiles
    worst_losing_streak: MonteCarloPercentiles
    prob_profit: float                           # P(final return > 0)
    prob_ruin: float                             # P(max DD > 50% of initial)
    var_95_pct: float                            # Value-at-Risk: -P5 of returns
    cvar_95_pct: float                           # Conditional VaR: mean of returns below P5
    # Sample of equity curves for plotting (max 20)
    sample_curves: list[list[float]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "config": {
                "trials": self.config.trials,
                "method": self.config.method,
                "seed": self.config.seed,
                "initial_equity": self.config.initial_equity,
            },
            "n_trials": self.n_trials,
            "n_trades": self.n_trades,
            "return_pct": self.return_pct.to_dict(),
            "max_drawdown_pct": self.max_drawdown_pct.to_dict(),
            "worst_losing_streak": self.worst_losing_streak.to_dict(),
            "prob_profit": self.prob_profit,
            "prob_ruin": self.prob_ruin,
            "var_95_pct": self.var_95_pct,
            "cvar_95_pct": self.cvar_95_pct,
            "sample_curves": self.sample_curves,
        }


def _percentile(sorted_values: list[float], pct: float) -> float:
    """Linear-interpolated percentile from a sorted list."""
    if not sorted_values:
        return 0.0
    if len(sorted_values) == 1:
        return sorted_values[0]
    k = (len(sorted_values) - 1) * (pct / 100.0)
    floor = int(k)
    ceil_idx = min(floor + 1, len(sorted_values) - 1)
    frac = k - floor
    return sorted_values[floor] + (sorted_values[ceil_idx] - sorted_values[floor]) * frac


def _percentiles(values: list[float]) -> MonteCarloPercentiles:
    if not values:
        return MonteCarloPercentiles(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    s = sorted(values)
    mean = sum(values) / len(values)
    var = sum((v - mean) ** 2 for v in values) / len(values)
    std = var ** 0.5
    return MonteCarloPercentiles(
        p5=round(_percentile(s, 5), 4),
        p25=round(_percentile(s, 25), 4),
        p50=round(_percentile(s, 50), 4),
        p75=round(_percentile(s, 75), 4),
        p95=round(_percentile(s, 95), 4),
        mean=round(mean, 4),
        std=round(std, 4),
    )


def _simulate_curve(
    trade_pnls: list[float],
    initial_equity: float,
) -> tuple[float, float, int, list[float]]:
    """Replay trades in the given order and return (return_pct, max_dd_pct,
    worst_losing_streak, equity_curve).
    """
    equity = initial_equity
    peak = initial_equity
    max_dd = 0.0
    curve = [initial_equity]
    cur_loss_streak = 0
    worst_streak = 0
    for pnl in trade_pnls:
        equity += pnl
        if equity > peak:
            peak = equity
        if peak > 0:
            dd = (peak - equity) / peak * 100.0
            if dd > max_dd:
                max_dd = dd
        if pnl < 0:
            cur_loss_streak += 1
            if cur_loss_streak > worst_streak:
                worst_streak = cur_loss_streak
        elif pnl > 0:
            cur_loss_streak = 0
        curve.append(equity)
    ret_pct = (equity - initial_equity) / initial_equity * 100.0 if initial_equity > 0 else 0.0
    return ret_pct, max_dd, worst_streak, curve


def run_monte_carlo(
    trade_pnls: list[float],
    config: MonteCarloConfig,
    on_trial: Optional[Callable[[int, int], None]] = None,
) -> MonteCarloResult:
    """Run a Monte Carlo simulation on a sequence of trade PnLs.

    Args:
        trade_pnls: realized PnL of each historical trade, in USDT
        config: MonteCarloConfig (trials, method, seed)
        on_trial: optional callback (trial_idx, total) for progress streaming

    Returns:
        MonteCarloResult with percentile distributions and risk metrics.
    """
    if not trade_pnls:
        empty = MonteCarloPercentiles(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        return MonteCarloResult(
            config=config, n_trials=0, n_trades=0,
            return_pct=empty, max_drawdown_pct=empty, worst_losing_streak=empty,
            prob_profit=0.0, prob_ruin=0.0, var_95_pct=0.0, cvar_95_pct=0.0,
            sample_curves=[],
        )

    rng = random.Random(config.seed)
    returns: list[float] = []
    drawdowns: list[float] = []
    streaks: list[float] = []
    sample_curves: list[list[float]] = []
    sample_every = max(1, config.trials // 20)  # keep at most ~20 curves

    base = list(trade_pnls)
    for trial in range(config.trials):
        if config.method == "shuffle":
            seq = base[:]
            rng.shuffle(seq)
        else:  # bootstrap
            seq = [rng.choice(base) for _ in range(len(base))]
        ret, dd, streak, curve = _simulate_curve(seq, config.initial_equity)
        returns.append(ret)
        drawdowns.append(dd)
        streaks.append(float(streak))
        if trial % sample_every == 0:
            sample_curves.append([round(v, 2) for v in curve])
        if on_trial is not None and trial % max(1, config.trials // 100) == 0:
            try:
                on_trial(trial, config.trials)
            except Exception:  # noqa: BLE001
                _LOG.exception("on_trial callback failed")

    ret_perc = _percentiles(returns)
    dd_perc = _percentiles(drawdowns)
    streak_perc = _percentiles(streaks)

    prob_profit = sum(1 for r in returns if r > 0) / len(returns)
    prob_ruin = sum(1 for d in drawdowns if d > 50.0) / len(drawdowns)
    # 95% VaR: the worst loss we'd expect with 95% confidence
    var_95 = round(-ret_perc.p5, 4)
    # Conditional VaR (Expected Shortfall): mean return in the worst 5%
    sorted_returns = sorted(returns)
    cutoff = max(1, len(sorted_returns) // 20)  # 5%
    cvar = sum(sorted_returns[:cutoff]) / cutoff if cutoff > 0 else 0.0

    return MonteCarloResult(
        config=config,
        n_trials=config.trials,
        n_trades=len(trade_pnls),
        return_pct=ret_perc,
        max_drawdown_pct=dd_perc,
        worst_losing_streak=streak_perc,
        prob_profit=round(prob_profit, 4),
        prob_ruin=round(prob_ruin, 4),
        var_95_pct=var_95,
        cvar_95_pct=round(-cvar, 4),
        sample_curves=sample_curves,
    )
