"""Walk-Forward Analysis (WFA) — out-of-sample strategy validation.

Walk-forward analysis is the industry standard for detecting parameter
overfitting. It works in rolling windows:

    [────── in-sample (train) ──────][── out-of-sample (test) ──]
                  ↑                              ↑
            optimize params              validate with frozen params

The window slides forward (anchored or rolling) and we report performance on
each out-of-sample (OOS) period. A strategy is robust when:
  - Average OOS return is positive
  - The OOS / IS efficiency ratio is high (>0.5 typical threshold)
  - Performance is consistent across windows (low CV of returns)

This module is engine-agnostic: callers supply a `train_fn` that returns the
best params for a given candle slice, and a `test_fn` that backtests with
those params on another slice. We orchestrate the splits and aggregation.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

_LOG = logging.getLogger("backtester.analysis.walk_forward")


@dataclass
class WalkForwardWindow:
    """One in-sample / out-of-sample pair."""
    window_idx: int
    is_start: int          # candle index (inclusive)
    is_end: int            # candle index (exclusive)
    oos_start: int
    oos_end: int
    best_params: dict[str, Any] = field(default_factory=dict)
    is_metrics: dict[str, Any] = field(default_factory=dict)
    oos_metrics: dict[str, Any] = field(default_factory=dict)
    efficiency: float = 0.0   # OOS_return / IS_return (clamped)


@dataclass
class WalkForwardConfig:
    """Walk-forward analysis configuration.

    Sizes are in number of candles. Choose them based on timeframe — e.g.
    on 1h, 720 candles ≈ 30 days, 168 ≈ 1 week.
    """
    train_size: int                   # in-sample window length (candles)
    test_size: int                    # out-of-sample window length
    step_size: Optional[int] = None   # how much to slide forward (default = test_size)
    anchored: bool = False            # if True, train window grows; else rolls
    objective_metric: str = "total_return_pct"  # what to optimize on IS

    def __post_init__(self) -> None:
        if self.train_size <= 0 or self.test_size <= 0:
            raise ValueError("train_size and test_size must be positive")
        if self.step_size is None:
            self.step_size = self.test_size
        if self.step_size <= 0:
            raise ValueError("step_size must be positive")


@dataclass
class WalkForwardResult:
    """Aggregated walk-forward result across all windows."""
    config: WalkForwardConfig
    windows: list[WalkForwardWindow]
    avg_oos_return_pct: float
    avg_is_return_pct: float
    efficiency_ratio: float           # mean(OOS) / mean(IS), clamped to [-2, 2]
    consistency: float                # 1 - CV (coefficient of variation) of OOS returns
    profitable_windows: int           # how many OOS windows had positive return
    total_windows: int
    verdict: str                      # one of: robust, weak, overfit, inconclusive

    def to_dict(self) -> dict[str, Any]:
        return {
            "config": {
                "train_size": self.config.train_size,
                "test_size": self.config.test_size,
                "step_size": self.config.step_size,
                "anchored": self.config.anchored,
                "objective_metric": self.config.objective_metric,
            },
            "windows": [
                {
                    "window_idx": w.window_idx,
                    "is_range": [w.is_start, w.is_end],
                    "oos_range": [w.oos_start, w.oos_end],
                    "best_params": w.best_params,
                    "is_metrics": w.is_metrics,
                    "oos_metrics": w.oos_metrics,
                    "efficiency": w.efficiency,
                }
                for w in self.windows
            ],
            "summary": {
                "avg_oos_return_pct": self.avg_oos_return_pct,
                "avg_is_return_pct": self.avg_is_return_pct,
                "efficiency_ratio": self.efficiency_ratio,
                "consistency": self.consistency,
                "profitable_windows": self.profitable_windows,
                "total_windows": self.total_windows,
                "verdict": self.verdict,
            },
        }


def _generate_windows(
    n_candles: int,
    cfg: WalkForwardConfig,
) -> list[tuple[int, int, int, int]]:
    """Generate (is_start, is_end, oos_start, oos_end) tuples."""
    windows = []
    is_start = 0
    test_start = cfg.train_size
    while test_start + cfg.test_size <= n_candles:
        is_end = test_start
        oos_start = test_start
        oos_end = test_start + cfg.test_size
        # Anchored = expand training from 0; rolling = slide both ends
        actual_is_start = 0 if cfg.anchored else is_start
        windows.append((actual_is_start, is_end, oos_start, oos_end))
        # advance
        test_start += cfg.step_size
        is_start += cfg.step_size
    return windows


def _safe_mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _std_dev(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    m = _safe_mean(values)
    var = sum((v - m) ** 2 for v in values) / len(values)
    return math.sqrt(var)


def _verdict(eff: float, oos_avg: float, consistency: float, prof_ratio: float) -> str:
    """Heuristic verdict based on aggregate stats.

    - robust       : OOS positive AND efficiency >0.5 AND >60% windows profitable
    - weak         : OOS positive but efficiency low or inconsistent
    - overfit      : IS strongly positive, OOS negative/flat
    - inconclusive : not enough data or mixed signals
    """
    if oos_avg > 0 and eff > 0.5 and prof_ratio > 0.6 and consistency > 0.3:
        return "robust"
    if oos_avg > 0 and (eff > 0.2 or prof_ratio > 0.5):
        return "weak"
    if oos_avg <= 0 and eff < 0.2:
        return "overfit"
    return "inconclusive"


def run_walk_forward(
    n_candles: int,
    config: WalkForwardConfig,
    train_fn: Callable[[int, int, int], tuple[dict[str, Any], dict[str, Any]]],
    test_fn: Callable[[dict[str, Any], int, int, int], dict[str, Any]],
    on_window: Optional[Callable[[WalkForwardWindow], None]] = None,
) -> WalkForwardResult:
    """Orchestrate a walk-forward analysis.

    Args:
        n_candles: total number of candles available
        config: WalkForwardConfig with window sizes
        train_fn: (is_start, is_end, window_idx) -> (best_params, is_metrics)
            Called for each in-sample window. Should return the params that
            scored highest on the chosen objective and the IS metrics dict.
        test_fn: (params, oos_start, oos_end, window_idx) -> oos_metrics
            Called with the frozen best params from train_fn to evaluate on
            the out-of-sample window.
        on_window: optional callback called after each window completes.
            Useful for streaming progress to a WebSocket.

    Returns:
        WalkForwardResult with per-window detail and aggregate verdict.
    """
    splits = _generate_windows(n_candles, config)
    if not splits:
        return WalkForwardResult(
            config=config,
            windows=[],
            avg_oos_return_pct=0.0,
            avg_is_return_pct=0.0,
            efficiency_ratio=0.0,
            consistency=0.0,
            profitable_windows=0,
            total_windows=0,
            verdict="inconclusive",
        )

    windows: list[WalkForwardWindow] = []
    for idx, (is_s, is_e, oos_s, oos_e) in enumerate(splits):
        try:
            best_params, is_metrics = train_fn(is_s, is_e, idx)
            oos_metrics = test_fn(best_params, oos_s, oos_e, idx)
        except Exception as exc:  # noqa: BLE001
            _LOG.exception("WF window %d failed: %s", idx, exc)
            continue

        is_ret = float(is_metrics.get("total_return_pct", 0.0))
        oos_ret = float(oos_metrics.get("total_return_pct", 0.0))
        # Efficiency: capped ratio of OOS to IS return (avoid div-by-zero / extreme outliers)
        if abs(is_ret) > 0.01:
            eff = max(-2.0, min(2.0, oos_ret / is_ret))
        else:
            eff = 0.0 if oos_ret == 0 else math.copysign(1.0, oos_ret)

        w = WalkForwardWindow(
            window_idx=idx,
            is_start=is_s,
            is_end=is_e,
            oos_start=oos_s,
            oos_end=oos_e,
            best_params=best_params,
            is_metrics=is_metrics,
            oos_metrics=oos_metrics,
            efficiency=round(eff, 4),
        )
        windows.append(w)
        if on_window is not None:
            try:
                on_window(w)
            except Exception:  # noqa: BLE001
                _LOG.exception("on_window callback failed for window %d", idx)

    if not windows:
        return WalkForwardResult(
            config=config,
            windows=[],
            avg_oos_return_pct=0.0,
            avg_is_return_pct=0.0,
            efficiency_ratio=0.0,
            consistency=0.0,
            profitable_windows=0,
            total_windows=0,
            verdict="inconclusive",
        )

    oos_returns = [float(w.oos_metrics.get("total_return_pct", 0.0)) for w in windows]
    is_returns = [float(w.is_metrics.get("total_return_pct", 0.0)) for w in windows]

    oos_avg = _safe_mean(oos_returns)
    is_avg = _safe_mean(is_returns)
    # Aggregate efficiency uses means to avoid noise from per-window outliers.
    if abs(is_avg) > 0.01:
        agg_eff = max(-2.0, min(2.0, oos_avg / is_avg))
    else:
        agg_eff = 0.0

    # Consistency: 1 - CV (coefficient of variation) of OOS returns.
    std = _std_dev(oos_returns)
    if abs(oos_avg) > 0.01:
        consistency = max(0.0, 1.0 - (std / abs(oos_avg)))
    else:
        consistency = 0.0

    profitable = sum(1 for r in oos_returns if r > 0)
    prof_ratio = profitable / len(oos_returns)

    verdict = _verdict(agg_eff, oos_avg, consistency, prof_ratio)

    return WalkForwardResult(
        config=config,
        windows=windows,
        avg_oos_return_pct=round(oos_avg, 4),
        avg_is_return_pct=round(is_avg, 4),
        efficiency_ratio=round(agg_eff, 4),
        consistency=round(consistency, 4),
        profitable_windows=profitable,
        total_windows=len(windows),
        verdict=verdict,
    )
