"""Optional hyperparameter optimization (Optuna + Nevergrad).

Install with:
    pip install -r backtester/requirements-optimize.txt

Then use via CLI:
    python backtester/main.py --optimize optimize.json --backend optuna --trials 100
    python backtester/main.py --optimize optimize.json --backend nevergrad --budget 200
"""

from backtester.optimize.objective import (
    Objective,
    OptimizationConfig,
    OptimizationResult,
)

__all__ = ["Objective", "OptimizationConfig", "OptimizationResult"]
