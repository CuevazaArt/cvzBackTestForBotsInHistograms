"""Robustness Score — multi-metric ranking for choosing the best bot setup.

Picking the bot config with the highest backtest return is naive: it usually
overfits. A more robust approach combines several risk-adjusted metrics into
a single score, and lets the user weight what they care about.

The default weighting reflects a typical "trade money I can lose" profile:
    35% Sharpe ratio       — risk-adjusted return
    20% Profit factor      — gross win / gross loss
    20% Recovery factor    — return / max DD (capital efficiency)
    15% Win rate           — psychological consistency
    10% Trade count        — statistical significance penalty if too few

All inputs are normalized to [0, 1] using percentile rank within the candidate
set, then weighted-summed. Result is always in [0, 1] where 1 is best.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


# Default weights — sum to 1.0
DEFAULT_WEIGHTS = {
    "sharpe_ratio": 0.35,
    "profit_factor": 0.20,
    "recovery_factor": 0.20,
    "win_rate_pct": 0.15,
    "trade_count": 0.10,
}

# Metrics where LOWER is better → invert before ranking
LOWER_IS_BETTER = {"max_drawdown_pct", "ulcer_index"}


@dataclass
class RobustnessScore:
    """Single candidate's robustness score and component breakdown."""

    label: str  # human-friendly identifier (e.g. params dict)
    score: float  # final aggregate score [0, 1]
    rank: int  # 1 = best
    components: dict[str, float] = field(
        default_factory=dict
    )  # raw metric → normalized [0,1]
    metrics: dict[str, Any] = field(default_factory=dict)  # raw metrics for display

    def to_dict(self) -> dict[str, Any]:
        return {
            "label": self.label,
            "score": self.score,
            "rank": self.rank,
            "components": self.components,
            "metrics": self.metrics,
        }


def _normalize_min_max(values: list[float], invert: bool = False) -> list[float]:
    """Min-max scale to [0, 1]. If invert=True, lower raw → higher normalized."""
    if not values:
        return []
    lo, hi = min(values), max(values)
    if hi == lo:
        return [0.5] * len(values)
    scaled = [(v - lo) / (hi - lo) for v in values]
    return [1.0 - s for s in scaled] if invert else scaled


def _penalize_low_trade_count(n_trades: int, threshold: int = 30) -> float:
    """Statistical significance penalty.

    A strategy with <30 trades has unreliable stats. Returns 1.0 at threshold,
    linear ramp-down to 0 at 0 trades, saturates at 1.0 above threshold.
    """
    if n_trades >= threshold:
        return 1.0
    if n_trades <= 0:
        return 0.0
    return n_trades / threshold


def score_runs(
    candidates: list[dict[str, Any]],
    weights: dict[str, float] | None = None,
    label_fn=None,
) -> list[RobustnessScore]:
    """Score and rank a list of backtest result candidates.

    Args:
        candidates: list of {"params": dict, "metrics": dict} entries.
            Each metrics dict should contain the keys defined in DEFAULT_WEIGHTS
            (sharpe_ratio, profit_factor, recovery_factor, win_rate_pct, trades).
        weights: optional override of metric weights. Must sum to 1.0.
        label_fn: optional callable(candidate) → str to build a display label.

    Returns:
        List of RobustnessScore sorted by rank (best first).
    """
    if not candidates:
        return []
    w = dict(weights) if weights is not None else dict(DEFAULT_WEIGHTS)
    total = sum(w.values())
    if total <= 0:
        raise ValueError("weights must sum to a positive number")
    # Normalize weights to sum to 1
    w = {k: v / total for k, v in w.items()}

    # Extract raw values per metric across all candidates
    def _get(metric: str, c: dict) -> float:
        # Special case: trade_count comes from metrics["trades"]
        if metric == "trade_count":
            n = c.get("metrics", {}).get("trades", 0)
            return float(_penalize_low_trade_count(int(n)))
        return float(c.get("metrics", {}).get(metric, 0.0))

    columns: dict[str, list[float]] = {}
    for metric in w:
        columns[metric] = [_get(metric, c) for c in candidates]

    # Normalize each column (invert if "lower is better")
    norm: dict[str, list[float]] = {}
    for metric, vals in columns.items():
        invert = metric in LOWER_IS_BETTER
        # trade_count is already in [0, 1] from penalty function — no normalization
        if metric == "trade_count":
            norm[metric] = vals
        else:
            norm[metric] = _normalize_min_max(vals, invert=invert)

    # Compute weighted score per candidate
    scores: list[RobustnessScore] = []
    for i, c in enumerate(candidates):
        components = {m: round(norm[m][i], 4) for m in w}
        agg = sum(w[m] * norm[m][i] for m in w)
        label = label_fn(c) if label_fn else f"candidate_{i}"
        scores.append(
            RobustnessScore(
                label=label,
                score=round(agg, 4),
                rank=0,  # filled below
                components=components,
                metrics={
                    k: c.get("metrics", {}).get(k)
                    for k in (
                        "total_return_pct",
                        "sharpe_ratio",
                        "sortino_ratio",
                        "calmar_ratio",
                        "profit_factor",
                        "recovery_factor",
                        "win_rate_pct",
                        "max_drawdown_pct",
                        "ulcer_index",
                        "trades",
                    )
                },
            )
        )

    # Sort descending and assign ranks
    scores.sort(key=lambda s: s.score, reverse=True)
    for rank, s in enumerate(scores, start=1):
        s.rank = rank
    return scores
