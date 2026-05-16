"""HTTP routers (each module owns a slice of `/api/*`)."""

from backtester.api.routes import (
    analysis,
    backtest,
    bots,
    candles,
    credentials,
    data,
    experiments,
    optimize,
    results,
)

__all__ = [
    "analysis",
    "backtest",
    "bots",
    "candles",
    "credentials",
    "data",
    "experiments",
    "optimize",
    "results",
]
