#!/usr/bin/env python3
"""Backtester CLI entry point."""

import argparse
from pathlib import Path

from backtester.ui import BacktesterCLI


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Mini MetaTrader: Backtester for trading bots",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Setup credentials (one-time)
  python main.py --setup-credentials

  # Download historical candles
  python main.py --download-candles BTCUSDT 1h 2024-01-01 2024-12-31

  # Interactive backtest editor
  python main.py --backtest

  # Run experiments in parallel
  python main.py --experiments experiments.json --workers 4

  # Optimize parameters (requires optional deps:
  #   pip install -r backtester/requirements-optimize.txt)
  python main.py --optimize optimize.json --backend optuna --trials 100
  python main.py --optimize optimize.json --backend nevergrad --trials 200 --sampler CMA
        """,
    )

    parser.add_argument(
        "--setup-credentials", action="store_true", help="Setup Binance API credentials"
    )
    parser.add_argument(
        "--download-candles",
        nargs=4,
        metavar=("SYMBOL", "TIMEFRAME", "FROM", "TO"),
        help="Download candles",
    )
    parser.add_argument(
        "--backtest", action="store_true", help="Interactive backtest editor"
    )
    parser.add_argument(
        "--experiments", type=Path, help="Run experiments from JSON config"
    )
    parser.add_argument(
        "--workers", type=int, default=4, help="Number of parallel workers"
    )
    parser.add_argument(
        "--optimize", type=Path, help="Optimize parameters from JSON config"
    )
    parser.add_argument(
        "--backend",
        choices=["optuna", "nevergrad"],
        default="optuna",
        help="Optimization backend",
    )
    parser.add_argument(
        "--trials", type=int, default=100, help="Number of optimization trials"
    )
    parser.add_argument(
        "--sampler",
        type=str,
        default="tpe",
        help="Sampler/optimizer (Optuna: tpe/cma/random/nsga2; Nevergrad: NGOpt/CMA/DE/OnePlusOne)",
    )
    parser.add_argument(
        "--seed", type=int, default=None, help="Random seed for reproducibility"
    )
    parser.add_argument(
        "--base-dir",
        type=Path,
        default=Path(__file__).parent,
        help="Base directory for data/results",
    )

    args = parser.parse_args()

    cli = BacktesterCLI(args.base_dir)

    if args.setup_credentials:
        cli.setup_credentials()
    elif args.download_candles:
        symbol, timeframe, date_from, date_to = args.download_candles
        cli.download_candles(symbol, timeframe, date_from, date_to)
    elif args.backtest:
        cli.interactive_backtest()
    elif args.experiments:
        cli.run_experiments(args.experiments, workers=args.workers)
    elif args.optimize:
        cli.optimize(
            args.optimize,
            backend=args.backend,
            trials=args.trials,
            sampler=args.sampler,
            seed=args.seed,
        )
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
