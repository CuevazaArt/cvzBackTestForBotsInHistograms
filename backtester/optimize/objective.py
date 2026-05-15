"""Common objective function for hyperparameter optimization."""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
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
    validation_split_pct: float = 0.2
    min_trades: int = 0
    max_drawdown_pct_limit: float | None = None

    @classmethod
    def from_dict(cls, d: dict) -> "OptimizationConfig":
        return cls(**d)


@dataclass
class OptimizationResult:
    """One trial result."""
    params: dict[str, Any]
    score: float
    metrics: dict[str, Any]
    cache_stats: dict[str, Any] | None = None


class Objective:
    """Wraps backtester core into a single-call objective: params → score."""

    def __init__(
        self,
        cfg: OptimizationConfig,
        downloader: BinanceDownloader,
        bot_registry: dict[str, Callable],
        cache=None,
    ) -> None:
        self.cfg = cfg
        self.downloader = downloader
        self.bot_registry = bot_registry
        self._candles: Optional[list[Candle]] = None
        self._direction = SUPPORTED_METRICS.get(cfg.objective, "max")
        self._cache = cache  # IndicatorCache | None

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
        candles = self._load_candles()
        split = int(len(candles) * (1.0 - self.cfg.validation_split_pct))
        if split <= 0 or split >= len(candles):
            split = len(candles)
        train_candles = candles[:split]
        val_candles = candles[split:] if split < len(candles) else []

        train_result = engine.run(bot, train_candles, self.cfg.symbol, self.cfg.timeframe)
        train_metrics = compute_metrics(train_result)

        val_metrics = None
        if val_candles:
            bot_val = bot_cls(**full_params)
            val_result = engine.run(bot_val, val_candles, self.cfg.symbol, self.cfg.timeframe)
            val_metrics = compute_metrics(val_result)

        metrics = dict(train_metrics)
        if val_metrics:
            metrics.update({
                "validation_total_return_pct": val_metrics.get("total_return_pct", 0.0),
                "validation_win_rate_pct": val_metrics.get("win_rate_pct", 0.0),
                "validation_profit_factor": val_metrics.get("profit_factor", 0.0),
                "validation_max_drawdown_pct": val_metrics.get("max_drawdown_pct", 0.0),
                "validation_trades": val_metrics.get("trades", 0),
            })
            train_score_raw = float(train_metrics.get(self.cfg.objective, 0))
            val_score_raw = float(val_metrics.get(self.cfg.objective, 0))
            # Favor robust params that work in both train and validation windows.
            score = (train_score_raw * 0.4) + (val_score_raw * 0.6)
        else:
            score = float(train_metrics.get(self.cfg.objective, 0))

        # Constraints are evaluated against training-window metrics.
        # This is intentional: validation data should test generalization,
        # not be filtered by constraints that could bias the search.
        penalties: list[str] = []

        trades = int(metrics.get("trades", 0))
        if trades < self.cfg.min_trades:
            penalties.append(f"min_trades<{self.cfg.min_trades}")

        if self.cfg.max_drawdown_pct_limit is not None:
            dd = float(metrics.get("max_drawdown_pct", 0))
            if dd > self.cfg.max_drawdown_pct_limit:
                penalties.append(f"max_drawdown_pct>{self.cfg.max_drawdown_pct_limit}")

        if penalties:
            score = -1e9 if self._direction == "max" else 1e9
            metrics["constraint_penalty"] = "; ".join(penalties)

        # For Optuna/Nevergrad: both maximize by default, so negate "min" objectives
        # when needed (each backend handles direction in its own way; we expose raw).
        return OptimizationResult(params=full_params, score=score, metrics=metrics)

    def get_signed_score(self, result: OptimizationResult) -> float:
        """Return score with sign convention: higher = better, always."""
        return result.score if self._direction == "max" else -result.score
