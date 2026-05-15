"""Parallel experiment runner.

The worker function is module-level (not a bound method) and takes only
picklable args. This is critical: DuckDB connections cannot be pickled, so
we pass a `db_path` and bot class name instead and rebuild a downloader
inside each worker process.
"""

import json
import logging
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Optional

from backtester.core import (
    BacktestConfig,
    BacktestEngine,
    BinanceDownloader,
    compute_metrics,
)
from backtester.core.engine import Candle

_LOG = logging.getLogger("backtester.experiments")


@dataclass
class Experiment:
    """Single experiment configuration."""

    symbol: str
    timeframe: str
    bot_class: str
    bot_params: dict[str, Any]
    config_id: Optional[str] = None


@dataclass
class ExperimentResult:
    """Result of an experiment."""

    experiment: Experiment
    success: bool
    metrics: dict[str, Any] = None
    error: Optional[str] = None
    cache_stats: Optional[dict[str, Any]] = None


# ── Worker (module-level so it can be pickled) ─────────────────


def _run_experiment(
    db_path_str: str,
    bot_module: str,
    bot_attr: str,
    bot_params: dict[str, Any],
    symbol: str,
    timeframe: str,
    engine_cfg: BacktestConfig,
    exp: Experiment,
) -> ExperimentResult:
    """Worker: build a fresh downloader and run a single experiment.

    Lives at module scope so multiprocessing.Pool can pickle it. Receives
    only picklable args (strings, dataclass, dict) — the DuckDB connection
    is created inside this process.
    """
    try:
        import importlib

        downloader = BinanceDownloader(Path(db_path_str))
        candles_data = downloader.load_candles(symbol, timeframe)
        if not candles_data:
            raise ValueError(f"No candles found for {symbol} {timeframe}")
        candles = [Candle.from_dict(c) for c in candles_data]

        mod = importlib.import_module(bot_module)
        bot_class = getattr(mod, bot_attr)
        bot = bot_class(**bot_params)

        engine = BacktestEngine(engine_cfg)
        result = engine.run(bot, candles, symbol=symbol, timeframe=timeframe)
        metrics = compute_metrics(result)
        return ExperimentResult(experiment=exp, success=True, metrics=metrics)
    except Exception as e:  # noqa: BLE001
        return ExperimentResult(experiment=exp, success=False, error=str(e))


class ExperimentRunner:
    """Run experiments in parallel.

    Production-safe across multiprocessing: the worker function is
    module-level and only receives picklable arguments (no DuckDB conns).
    """

    def __init__(
        self,
        downloader: BinanceDownloader,
        bot_registry: dict[str, Callable],
        engine_config: Optional[BacktestConfig] = None,
        cache=None,
    ) -> None:
        self.downloader = downloader
        self.bot_registry = bot_registry
        self.engine_config = engine_config or BacktestConfig()
        self._cache = cache  # IndicatorCache | None

    def run_batch(
        self,
        experiments: list[Experiment],
        workers: int = 4,
        progress_callback: Optional[Callable[[int, int], None]] = None,
    ) -> list[ExperimentResult]:
        """Run experiments in parallel.

        With `workers=1` runs sequentially in the current process (useful for
        tests and for embedded environments where multiprocessing is undesirable).
        """
        results: list[ExperimentResult] = []
        completed = 0
        total = len(experiments)
        db_path_str = str(self.downloader.db_path)
        engine_cfg = self.engine_config

        def _build_args(exp: Experiment):
            bot_class = self.bot_registry.get(exp.bot_class)
            if bot_class is None:
                return None
            return (
                db_path_str,
                bot_class.__module__,
                bot_class.__name__,
                exp.bot_params,
                exp.symbol,
                exp.timeframe,
                engine_cfg,
                exp,
            )

        # Sequential fast-path: skip multiprocessing entirely.
        if workers <= 1:
            for exp in experiments:
                args = _build_args(exp)
                if args is None:
                    results.append(
                        ExperimentResult(
                            experiment=exp,
                            success=False,
                            error=f"Unknown bot: {exp.bot_class}",
                        )
                    )
                else:
                    results.append(_run_experiment(*args))
                completed += 1
                if progress_callback:
                    progress_callback(completed, total)
            # Attach cache stats snapshot to every result
            if self._cache is not None:
                stats = self._cache.stats()
                for r in results:
                    r.cache_stats = stats
            return results

        with ProcessPoolExecutor(max_workers=workers) as executor:
            futures = {}
            for exp in experiments:
                args = _build_args(exp)
                if args is None:
                    results.append(
                        ExperimentResult(
                            experiment=exp,
                            success=False,
                            error=f"Unknown bot: {exp.bot_class}",
                        )
                    )
                    completed += 1
                    if progress_callback:
                        progress_callback(completed, total)
                    continue
                futures[executor.submit(_run_experiment, *args)] = exp

            for future in as_completed(futures):
                exp = futures[future]
                try:
                    results.append(future.result())
                except Exception as e:  # noqa: BLE001
                    _LOG.error("Experiment failed: %s: %s", exp, e)
                    results.append(
                        ExperimentResult(
                            experiment=exp,
                            success=False,
                            error=str(e),
                        )
                    )
                completed += 1
                if progress_callback:
                    progress_callback(completed, total)

        # Cache is process-local; attach stats if available (only meaningful in
        # sequential mode — multiprocess workers have isolated caches).
        if self._cache is not None:
            stats = self._cache.stats()
            for r in results:
                r.cache_stats = stats
        return results

    @staticmethod
    def save_results(results: list[ExperimentResult], output_path: Path) -> None:
        """Save results to JSON."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        data = []
        for r in results:
            row = {
                "symbol": r.experiment.symbol,
                "timeframe": r.experiment.timeframe,
                "bot": r.experiment.bot_class,
                "params": r.experiment.bot_params,
                "success": r.success,
            }
            if r.success:
                row.update(r.metrics)
            else:
                row["error"] = r.error
            data.append(row)

        output_path.write_text(json.dumps(data, indent=2))
        _LOG.info("Results saved to %s", output_path)
