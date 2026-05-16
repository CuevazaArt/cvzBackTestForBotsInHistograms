"""Minimalist CLI with Rich."""

import json
import logging
from pathlib import Path
from typing import Any, Optional

from rich.console import Console
from rich.prompt import Prompt, Confirm
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn

from backtester.bots import BOT_REGISTRY
from backtester.core import (
    BinanceDownloader,
    BacktestEngine,
    CredentialManager,
    Candle,
    compute_metrics,
)
from backtester.experiments import ExperimentRunner, Experiment, ExperimentResult
from backtester.optimize import OptimizationConfig, Objective, OptimizationResult

console = Console()
logging.basicConfig(level=logging.INFO)
_LOG = logging.getLogger("backtester.cli")


class BacktesterCLI:
    """Minimalist backtester CLI."""

    def __init__(self, base_dir: Path) -> None:
        self.base_dir = Path(base_dir)
        self.data_dir = self.base_dir / "data"
        self.results_dir = self.base_dir / "results"
        self.vault_dir = self.base_dir / ".vault"

        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.results_dir.mkdir(parents=True, exist_ok=True)
        self.vault_dir.mkdir(parents=True, exist_ok=True)

        self.credentials = CredentialManager(self.vault_dir)
        self.downloader = BinanceDownloader(self.data_dir / "candles.db")

    def setup_credentials(self) -> None:
        """Interactive credential setup."""
        console.print("\n[bold cyan]Binance API Credentials Setup[/bold cyan]")

        if self.credentials.exists():
            if not Confirm.ask("Credentials already exist. Overwrite?"):
                return

        api_key = Prompt.ask("[yellow]Binance API Key[/yellow]")
        api_secret = Prompt.ask("[yellow]Binance API Secret[/yellow]", password=True)

        if api_key and api_secret:
            self.credentials.save(api_key, api_secret)
            console.print("[green][OK] Credentials saved (encrypted)[/green]\n")
        else:
            console.print("[red][FAIL] Invalid credentials[/red]\n")

    def download_candles(
        self, symbol: str, timeframe: str, date_from: str, date_to: str
    ) -> None:
        """Download candles from Binance."""
        api_key, _ = self.credentials.load() or (None, None)

        console.print(f"\n[bold]Downloading {symbol} {timeframe}[/bold]")
        console.print(f"Range: {date_from} to {date_to}")

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            transient=True,
        ) as progress:
            progress.add_task("Downloading...", total=None)
            count = self.downloader.download(symbol, timeframe, date_from, date_to)

        console.print(f"[green][OK] Downloaded {count} candles[/green]\n")

    def interactive_backtest(self) -> None:
        """Interactive backtest editor."""
        console.print("\n[bold cyan]Interactive Backtest[/bold cyan]\n")

        # Select symbol
        symbol = Prompt.ask("Symbol", default="BTCUSDT").upper()
        timeframe = Prompt.ask("Timeframe", default="1h")

        # Check candles exist
        candles_data = self.downloader.load_candles(symbol, timeframe)
        if not candles_data:
            console.print(f"[red][FAIL] No candles for {symbol} {timeframe}[/red]")
            console.print(
                f"Download first: python main.py --download {symbol} {timeframe} 2024-01-01 2024-12-31\n"
            )
            return

        # Select bot
        console.print("\nAvailable bots:")
        for i, bot_name in enumerate(BOT_REGISTRY.keys(), 1):
            console.print(f"  {i}. {bot_name}")

        bot_idx = Prompt.ask("Choose bot", default="1")
        bot_name = list(BOT_REGISTRY.keys())[int(bot_idx) - 1]
        bot_class = BOT_REGISTRY[bot_name]

        # Edit parameters
        params = self._edit_bot_params(bot_class)

        # Run backtest
        self._run_single_backtest(
            symbol, timeframe, bot_name, bot_class, params, candles_data
        )

    def _edit_bot_params(self, bot_class: type) -> dict[str, Any]:
        """Interactive parameter editor."""
        spec = bot_class.param_spec()
        params = {}

        console.print("\n[bold]Configure parameters:[/bold]")

        for param_name, param_info in spec.items():
            default = param_info.get("default")
            min_val = param_info.get("min")
            max_val = param_info.get("max")

            prompt_text = f"{param_name}"
            if min_val is not None and max_val is not None:
                prompt_text += f" [{min_val}-{max_val}]"

            value = Prompt.ask(prompt_text, default=str(default))

            param_type = param_info.get("type", "float")
            if param_type == "int":
                params[param_name] = int(value)
            elif param_type == "float":
                params[param_name] = float(value)
            else:
                params[param_name] = value

        return params

    def _run_single_backtest(
        self,
        symbol: str,
        timeframe: str,
        bot_name: str,
        bot_class: type,
        params: dict[str, Any],
        candles_data: list[dict],
    ) -> None:
        """Run single backtest."""
        candles = [Candle.from_dict(c) for c in candles_data]

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            transient=True,
        ) as progress:
            progress.add_task("Running backtest...", total=None)
            bot = bot_class(**params)
            engine = BacktestEngine()
            result = engine.run(bot, candles, symbol=symbol, timeframe=timeframe)

        metrics = compute_metrics(result)

        # Display results
        self._print_backtest_results(bot_name, params, result, metrics)

    def run_experiments(self, config_path: Path, workers: int = 4) -> None:
        """Run multiple experiments in parallel."""
        console.print("\n[bold cyan]Parallel Experiment Runner[/bold cyan]\n")

        # Load config
        config = json.loads(config_path.read_text())
        symbol = config["symbol"]
        timeframe = config["timeframe"]

        experiments = []
        for bot_cfg in config.get("bots", []):
            bot_name = bot_cfg["name"]
            for bot_params in bot_cfg.get("configs", []):
                experiments.append(
                    Experiment(
                        symbol=symbol,
                        timeframe=timeframe,
                        bot_class=bot_name,
                        bot_params=bot_params,
                    )
                )

        console.print(
            f"Running {len(experiments)} experiments with {workers} workers...\n"
        )

        runner = ExperimentRunner(self.downloader, BOT_REGISTRY)

        def progress_cb(done, total):
            console.print(f"Progress: {done}/{total}", end="\r")

        results = runner.run_batch(
            experiments, workers=workers, progress_callback=progress_cb
        )

        # Save results
        output_file = self.results_dir / f"experiments_{symbol}_{timeframe}.json"
        runner.save_results(results, output_file)

        # Display summary
        self._print_experiment_summary(results)

    def optimize(
        self,
        config_path: Path,
        backend: str = "optuna",
        trials: int = 100,
        sampler: str = "tpe",
        seed: Optional[int] = None,
    ) -> None:
        """Run hyperparameter optimization with Optuna or Nevergrad."""
        console.print(
            f"\n[bold cyan]Hyperparameter Optimization ({backend})[/bold cyan]\n"
        )

        cfg = OptimizationConfig.from_dict(json.loads(config_path.read_text()))
        objective = Objective(cfg, self.downloader, BOT_REGISTRY)

        console.print(f"Bot:       [yellow]{cfg.bot_class}[/yellow]")
        console.print(f"Symbol:    [yellow]{cfg.symbol} {cfg.timeframe}[/yellow]")
        console.print(
            f"Objective: [yellow]{cfg.objective}[/yellow] ({objective.direction})"
        )
        console.print(f"Trials:    [yellow]{trials}[/yellow]\n")

        best_so_far = {"score": None}

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TextColumn("{task.completed}/{task.total}"),
        ) as progress:
            task = progress.add_task("Optimizing...", total=trials)

            def on_trial(i: int, result: OptimizationResult) -> None:
                cur = result.score
                bs = best_so_far["score"]
                better = bs is None or (
                    (objective.direction == "max" and cur > bs)
                    or (objective.direction == "min" and cur < bs)
                )
                if better:
                    best_so_far["score"] = cur
                progress.update(
                    task,
                    advance=1,
                    description=f"trial {i + 1} | best {best_so_far['score']:.3f}",
                )

            if backend == "optuna":
                from backtester.optimize.optuna_runner import run_optuna

                results = run_optuna(
                    objective,
                    trials=trials,
                    sampler=sampler,
                    seed=seed,
                    on_trial=on_trial,
                )
            elif backend == "nevergrad":
                from backtester.optimize.nevergrad_runner import run_nevergrad

                results = run_nevergrad(
                    objective,
                    budget=trials,
                    optimizer=sampler,
                    seed=seed,
                    on_trial=on_trial,
                )
            else:
                console.print(
                    f"[red]Unknown backend '{backend}'. Use 'optuna' or 'nevergrad'.[/red]"
                )
                return

        # Save and display
        output_file = (
            self.results_dir
            / f"optimize_{cfg.bot_class}_{cfg.symbol}_{cfg.timeframe}_{backend}.json"
        )
        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.write_text(
            json.dumps(
                [
                    {"params": r.params, "score": r.score, "metrics": r.metrics}
                    for r in results
                ],
                indent=2,
                default=str,
            )
        )

        self._print_optimization_summary(results, cfg, output_file)

    def _print_optimization_summary(
        self,
        results: list[OptimizationResult],
        cfg: OptimizationConfig,
        output_file: Path,
    ) -> None:
        """Pretty-print top trials."""
        console.print("\n[bold green]═══ Top 10 Trials ═══[/bold green]\n")

        table = Table(title=f"Best {cfg.objective}")
        table.add_column("#", style="dim")
        table.add_column(cfg.objective, justify="right", style="magenta")
        table.add_column("Trades", justify="right")
        table.add_column("Win%", justify="right")
        table.add_column("Max DD%", justify="right")
        table.add_column("Params", style="cyan")

        for i, r in enumerate(results[:10], 1):
            m = r.metrics
            params_str = ", ".join(
                f"{k}={v:.3f}" if isinstance(v, float) else f"{k}={v}"
                for k, v in r.params.items()
                if k in cfg.search_space
            )
            table.add_row(
                str(i),
                f"{r.score:.3f}",
                str(m.get("trades", 0)),
                f"{m.get('win_rate_pct', 0):.1f}",
                f"{m.get('max_drawdown_pct', 0):.2f}",
                params_str,
            )

        console.print(table)
        console.print(
            f"\n[green][OK] Saved {len(results)} trials to {output_file}[/green]\n"
        )

    def _print_backtest_results(
        self,
        bot_name: str,
        params: dict[str, Any],
        result: Any,
        metrics: dict[str, Any],
    ) -> None:
        """Pretty-print backtest results."""
        console.print("\n[bold green]═══ Results ═══[/bold green]\n")

        # Bot config
        console.print(f"[bold]Bot:[/bold] {bot_name}")
        for k, v in params.items():
            console.print(f"  {k}: {v}")

        console.print()

        # Metrics table
        table = Table(title="Performance Metrics")
        table.add_column("Metric", style="cyan")
        table.add_column("Value", style="magenta", justify="right")

        metrics_display = [
            ("Total Return %", f"{metrics.get('total_return_pct', 0):.2f}%"),
            ("Final Equity", f"${metrics.get('final_equity', 0):,.2f}"),
            ("Trades", str(metrics.get("trades", 0))),
            ("Win Rate %", f"{metrics.get('win_rate_pct', 0):.1f}%"),
            ("Profit Factor", f"{metrics.get('profit_factor', 0):.2f}"),
            ("Max Drawdown %", f"{metrics.get('max_drawdown_pct', 0):.2f}%"),
            ("Total Fees", f"${metrics.get('total_fees_usdt', 0):.2f}"),
        ]

        for metric, value in metrics_display:
            table.add_row(metric, value)

        console.print(table)
        console.print()

    def _print_experiment_summary(self, results: list[ExperimentResult]) -> None:
        """Print experiment summary table."""
        console.print("\n[bold green]═══ Experiment Results ═══[/bold green]\n")

        table = Table(title="Top 10 Experiments")
        table.add_column("Bot", style="cyan")
        table.add_column("Return %", justify="right")
        table.add_column("Win Rate %", justify="right")
        table.add_column("Max DD %", justify="right")
        table.add_column("Profit Factor", justify="right")

        # Sort by return
        sorted_results = sorted(
            [r for r in results if r.success],
            key=lambda r: r.metrics.get("total_return_pct", 0),
            reverse=True,
        )[:10]

        for r in sorted_results:
            m = r.metrics
            table.add_row(
                r.experiment.bot_class,
                f"{m.get('total_return_pct', 0):.2f}%",
                f"{m.get('win_rate_pct', 0):.1f}%",
                f"{m.get('max_drawdown_pct', 0):.2f}%",
                f"{m.get('profit_factor', 0):.2f}",
            )

        console.print(table)
        console.print()
