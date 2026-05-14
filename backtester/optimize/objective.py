"""Common objective function for hyperparameter optimization."""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path
from typing import Any, Callable, Optional

from backtester.core import BinanceDownloader, BacktestEngine, BacktestConfig, compute_metrics
from backtester.core.engine import Candle

# Supported objective metrics (what to maximize/minimize)
SUPPORTED_METRICS = {
    "total_return_pct": "max",
    "win_rate_pct": "max",
    "profit_factor": "max",
    "max_drawdown_pct": "min",  # We want this LOW
    "trades": "max",  # More trades = more data
}


@dataclass
class OptimizationConfig:
    """Optimization run config (read from JSON)."""
    symbol: str
    timeframe: str
    bot_class: str                         # "EMACross", etc.
    search_space: dict[str, dict[str, Any]]  # param_name → {type, low, high, step, choices}
    objective: str = "total_return_pct"    # which metric to optimize
    fixed_params: dict[str, Any] = field(default_factory=dict)  # frozen params
    initial_cash: float = 10000.0
    taker_fee_pct: float = 0.1
    slippage_pct: float = 0.05

    @classmethod
    def from_dict(cls, d: dict) -> "OptimizationConfig":
        return cls(**d)


@dataclass
class OptimizationResult:
    """One trial result."""
    params: dict[str, Any]
    score: float
    metrics: dict[str, Any]


class Objective:
    """Wraps backtester core into a single-call objective: params → score."""

    def __init__(
        self,
        cfg: OptimizationConfig,
        downloader: BinanceDownloader,
        bot_registry: dict[str, Callable],
    ) -> None:
        self.cfg = cfg
        self.downloader = downloader
        self.bot_registry = bot_registry
        self._candles: Optional[list[Candle]] = None
        self._direction = SUPPORTED_METRICS.get(cfg.objective, "max")

        if cfg.objective not in SUPPORTED_METRICS:
            raise ValueError(
                f"Unsupported objective '{cfg.objective}'. "
                f"Choose from: {list(SUPPORTED_METRICS)}"
            )

    @property
    def direction(self) -> str:
        """`max` if higher = better, `min` otherwise."""
        return self._direction

    def _load_candles(self) -> list[Candle]:
        """Lazy-load candles once and cache them."""
        if self._candles is None:
            rows = self.downloader.load_candles(self.cfg.symbol, self.cfg.timeframe)
            if not rows:
                raise ValueError(
                    f"No candles for {self.cfg.symbol} {self.cfg.timeframe}. "
                    f"Download first with --download-candles."
                )
            self._candles = [Candle.from_dict(r) for r in rows]
        return self._candles

    def evaluate(self, params: dict[str, Any]) -> OptimizationResult:
        """Run one backtest with `params` and return score + metrics."""
        bot_cls = self.bot_registry.get(self.cfg.bot_class)
        if bot_cls is None:
            raise ValueError(f"Bot '{self.cfg.bot_class}' not in registry.")

        full_params = {**self.cfg.fixed_params, **params}

        bot = bot_cls(**full_params)
        engine = BacktestEngine(BacktestConfig(
            initial_cash=Decimal(str(self.cfg.initial_cash)),
            taker_fee_pct=Decimal(str(self.cfg.taker_fee_pct)),
            slippage_pct=Decimal(str(self.cfg.slippage_pct)),
        ))
        result = engine.run(bot, self._load_candles(), self.cfg.symbol, self.cfg.timeframe)
        metrics = compute_metrics(result)

        score = float(metrics.get(self.cfg.objective, 0))
        # For Optuna/Nevergrad: both maximize by default, so negate "min" objectives
        # when needed (each backend handles direction in its own way; we expose raw).
        return OptimizationResult(params=full_params, score=score, metrics=metrics)

    def get_signed_score(self, result: OptimizationResult) -> float:
        """Return score with sign convention: higher = better, always."""
        return result.score if self._direction == "max" else -result.score
