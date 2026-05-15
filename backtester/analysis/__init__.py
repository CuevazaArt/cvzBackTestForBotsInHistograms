"""Decision-support analysis modules (Phase 3).

Provides advanced tools for choosing the best bot configurations:
- walk_forward: train/test split validation to detect overfitting
- monte_carlo:  trade-order randomization for confidence intervals
- robustness:   multi-metric ranking combining return, risk, and stability
"""

from backtester.analysis.monte_carlo import MonteCarloConfig, run_monte_carlo
from backtester.analysis.robustness import RobustnessScore, score_runs
from backtester.analysis.walk_forward import WalkForwardConfig, run_walk_forward

__all__ = [
    "WalkForwardConfig",
    "run_walk_forward",
    "MonteCarloConfig",
    "run_monte_carlo",
    "RobustnessScore",
    "score_runs",
]
