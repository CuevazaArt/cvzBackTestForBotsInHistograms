"""Parallel experiment runner."""

import json
import logging
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable, Optional

from backtester.core import BinanceDownloader, BacktestEngine, BacktestConfig, compute_metrics
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


class ExperimentRunner:
    """Run experiments in parallel."""

    def __init__(
        self,
        downloader: BinanceDownloader,
        bot_registry: dict[str, Callable],
        engine_config: Optional[BacktestConfig] = None,
    ) -> None:
        self.downloader = downloader
        self.bot_registry = bot_registry
        self.engine_config = engine_config or BacktestConfig()

    def run_batch(
        self,
        experiments: list[Experiment],
        workers: int = 4,
        progress_callback: Optional[Callable[[int, int], None]] = None,
    ) -> list[ExperimentResult]:
        """Run experiments in parallel."""
        results = []
        completed = 0

        with ProcessPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(self._run_single, exp): exp
                for exp in experiments
            }

            for future in as_completed(futures):
                try:
                    result = future.result()
                    results.append(result)
                except Exception as e:
                    exp = futures[future]
                    _LOG.error(f"Experiment failed: {exp}: {e}")
                    results.append(ExperimentResult(
                        experiment=exp,
                        success=False,
                        error=str(e),
                    ))

                completed += 1
                if progress_callback:
                    progress_callback(completed, len(experiments))

        return results

    def _run_single(self, exp: Experiment) -> ExperimentResult:
        """Run a single experiment."""
        try:
            # Load candles
            candles_data = self.downloader.load_candles(exp.symbol, exp.timeframe)
            if not candles_data:
                raise ValueError(f"No candles found for {exp.symbol} {exp.timeframe}")

            candles = [Candle.from_dict(c) for c in candles_data]

            # Instantiate bot
            bot_class = self.bot_registry.get(exp.bot_class)
            if not bot_class:
                raise ValueError(f"Unknown bot: {exp.bot_class}")

            bot = bot_class(**exp.bot_params)

            # Run backtest
            engine = BacktestEngine(self.engine_config)
            result = engine.run(bot, candles, symbol=exp.symbol, timeframe=exp.timeframe)

            # Compute metrics
            metrics = compute_metrics(result)

            return ExperimentResult(
                experiment=exp,
                success=True,
                metrics=metrics,
            )

        except Exception as e:
            return ExperimentResult(
                experiment=exp,
                success=False,
                error=str(e),
            )

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
        _LOG.info(f"Results saved to {output_path}")
