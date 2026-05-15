#!/usr/bin/env python3
"""
Example: Using backtester programmatically (not via CLI).

This shows how to:
1. Load candles
2. Create a bot
3. Run backtest
4. Display results
5. Run experiments
"""

from pathlib import Path

from backtester.bots import EMACross
from backtester.core import (
    BinanceDownloader,
    BacktestEngine,
    BacktestConfig,
    Candle,
    compute_metrics,
)
from backtester.experiments import ExperimentRunner, Experiment

# Setup paths
BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(exist_ok=True)

downloader = BinanceDownloader(DATA_DIR / "candles.db")


def example_1_simple_backtest():
    """Simple single backtest."""
    print("\n=== Example 1: Simple Backtest ===\n")

    # Load candles (assumes already downloaded)
    candles_data = downloader.load_candles("BTCUSDT", "1h")
    if not candles_data:
        print("No candles for BTCUSDT 1h. Download first:")
        print("  python backtester/main.py --download-candles BTCUSDT 1h 2024-01-01 2024-12-31")
        return

    # Convert to Candle objects
    candles = [Candle.from_dict(c) for c in candles_data]

    # Create bot with parameters
    bot = EMACross(fast_ema=12, slow_ema=26, profit_factor=0.02, stop_loss_pct=0.05)

    # Run backtest
    engine = BacktestEngine(BacktestConfig(initial_cash=10000))
    result = engine.run(bot, candles, symbol="BTCUSDT", timeframe="1h")

    # Display results
    metrics = compute_metrics(result)
    print(f"Total Return: {metrics['total_return_pct']:.2f}%")
    print(f"Final Equity: ${metrics['final_equity']:.2f}")
    print(f"Trades: {metrics['trades']}")
    print(f"Win Rate: {metrics['win_rate_pct']:.1f}%")
    print(f"Max Drawdown: {metrics['max_drawdown_pct']:.2f}%")
    print()


def example_2_multiple_params():
    """Test multiple parameter sets."""
    print("\n=== Example 2: Parameter Sweep ===\n")

    candles_data = downloader.load_candles("BTCUSDT", "1h")
    if not candles_data:
        print("No candles. Download first with --download-candles")
        return

    candles = [Candle.from_dict(c) for c in candles_data]
    engine = BacktestEngine(BacktestConfig(initial_cash=10000))

    # Test different EMA configurations
    configs = [
        {"fast_ema": 10, "slow_ema": 20, "profit_factor": 0.02},
        {"fast_ema": 12, "slow_ema": 26, "profit_factor": 0.02},
        {"fast_ema": 15, "slow_ema": 30, "profit_factor": 0.03},
    ]

    results = []
    for config in configs:
        bot = EMACross(**config)
        result = engine.run(bot, candles, symbol="BTCUSDT", timeframe="1h")
        metrics = compute_metrics(result)
        results.append((config, metrics))

    # Sort by return
    results.sort(key=lambda x: x[1]["total_return_pct"], reverse=True)

    print("Top configurations:")
    for i, (config, metrics) in enumerate(results, 1):
        print(f"\n{i}. {config}")
        print(f"   Return: {metrics['total_return_pct']:.2f}%")
        print(f"   Win Rate: {metrics['win_rate_pct']:.1f}%")
        print(f"   Max DD: {metrics['max_drawdown_pct']:.2f}%")
    print()


def example_3_parallel_experiments():
    """Run multiple experiments in parallel."""
    print("\n=== Example 3: Parallel Experiments ===\n")

    # Create experiments
    experiments = []

    # EMACross with 3 configs
    for fast, slow in [(10, 20), (12, 26), (15, 30)]:
        experiments.append(Experiment(
            symbol="BTCUSDT",
            timeframe="1h",
            bot_class="EMACross",
            bot_params={"fast_ema": fast, "slow_ema": slow, "profit_factor": 0.02},
        ))

    # RSIReversion with 2 configs
    for period in [14, 21]:
        experiments.append(Experiment(
            symbol="BTCUSDT",
            timeframe="1h",
            bot_class="RSIReversion",
            bot_params={"rsi_period": period, "oversold_level": 30, "overbought_level": 70},
        ))

    # Run in parallel
    bot_registry = {
        "EMACross": EMACross,
    }

    runner = ExperimentRunner(downloader, bot_registry)

    # Progress callback
    def on_progress(done, total):
        print(f"Progress: {done}/{total}", end="\r")

    results = runner.run_batch(experiments, workers=2, progress_callback=on_progress)

    print("\nResults:")
    for r in results:
        if r.success:
            print(f"\n{r.experiment.bot_class} {r.experiment.bot_params}")
            print(f"  Return: {r.metrics['total_return_pct']:.2f}%")
        else:
            print(f"\n{r.experiment.bot_class} {r.experiment.bot_params}")
            print(f"  Error: {r.error}")

    # Save results
    output = BASE_DIR / "results" / "experiments_example.json"
    output.parent.mkdir(exist_ok=True)
    runner.save_results(results, output)
    print(f"\nResults saved to {output}")
    print()


def example_4_analyze_trades():
    """Analyze individual trades from backtest."""
    print("\n=== Example 4: Trade Analysis ===\n")

    candles_data = downloader.load_candles("BTCUSDT", "1h")
    if not candles_data:
        return

    candles = [Candle.from_dict(c) for c in candles_data]

    bot = EMACross(fast_ema=12, slow_ema=26, profit_factor=0.02)
    engine = BacktestEngine()
    result = engine.run(bot, candles, symbol="BTCUSDT", timeframe="1h")

    # Analyze trades
    print(f"Total trades: {len(result.trades)}\n")

    if result.trades:
        print("Top 5 winners:")
        winners = sorted(
            [t for t in result.trades if t.pnl > 0],
            key=lambda t: t.pnl,
            reverse=True,
        )[:5]
        for t in winners:
            print(f"  +${t.pnl:.2f} ({t.pnl_pct:.2f}%) - Entry: ${t.entry_price:.2f}")

        print("\nTop 5 losers:")
        losers = sorted(
            [t for t in result.trades if t.pnl < 0],
            key=lambda t: t.pnl,
        )[:5]
        for t in losers:
            print(f"  -${abs(t.pnl):.2f} ({t.pnl_pct:.2f}%) - Entry: ${t.entry_price:.2f}")

    print()


if __name__ == "__main__":
    print("Backtester Examples")
    print("=" * 50)

    try:
        example_1_simple_backtest()
        example_2_multiple_params()
        example_3_parallel_experiments()
        example_4_analyze_trades()
    except Exception as e:
        print(f"Error: {e}")
        print("\nTip: Make sure you've downloaded candles first:")
        print("  python backtester/main.py --download-candles BTCUSDT 1h 2024-01-01 2024-12-31")
