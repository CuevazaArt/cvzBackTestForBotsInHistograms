"""Engine throughput benchmarks.

Opt-in performance regression suite for the core backtest loop. All
tests in this module carry the ``benchmark`` marker (registered in
:mod:`backtester.tests.conftest`) and are skipped by default; CI only
runs them on a weekly schedule (see ``.github/CI_QUALITY_PROPOSAL.md``).
Locally:

.. code-block:: bash

    # run the benchmarks (and only the benchmarks)
    pytest backtester/tests/test_benchmark.py -m benchmark --benchmark-only

    # turn the soft assertion into a hard one
    STRICT_BENCH=1 pytest backtester/tests/test_benchmark.py -m benchmark

The ``STRICT_BENCH`` env var promotes the throughput target into a real
``assert``; without it the test always succeeds and only **prints** the
achieved candles/sec rate. This keeps the CI signal honest (a slow
runner won't fail PRs) while still surfacing perf regressions in the
weekly job log.

Skips cleanly with :func:`pytest.importorskip` if ``pytest_benchmark``
isn't installed, so this module never breaks the baseline test suite.
"""

from __future__ import annotations

import math
import os
from decimal import Decimal

import pytest

pytest.importorskip("pytest_benchmark")

from backtester.bots import EMACross  # noqa: E402
from backtester.core.engine import (  # noqa: E402
    BacktestConfig,
    BacktestEngine,
    Candle,
)

pytestmark = pytest.mark.benchmark

# Throughput target on a baseline developer laptop. Soft-asserted unless
# STRICT_BENCH=1 is set in the environment. Pytest-benchmark's overhead
# is small relative to engine wall-clock at this candle count.
_MIN_CANDLES_PER_SEC = 100_000

# 100k candles balances "enough work to be a real benchmark" with "fast
# enough to fit comfortably under 60s on a laptop". Lower this if you
# port the suite to constrained CI runners.
_N_CANDLES = 100_000


def _build_synthetic_candles(n: int) -> list[Candle]:
    """Sine wave around price 100 with deterministic noise.

    Uses the index modulo a small prime as pseudo-noise so the series
    is reproducible run-to-run (no RNG seed plumbing needed). The
    amplitude (5) and period (200 bars) are large enough relative to
    the EMA windows (12 / 26) that ``EMACross`` actually fires multiple
    crosses inside the series — a benchmark that produced zero trades
    would only measure the ``on_candle`` no-op path.
    """
    candles: list[Candle] = []
    for i in range(n):
        base = 100 + 5 * math.sin(i / 200 * math.pi)
        noise = ((i * 37) % 11 - 5) * 0.05
        mid = base + noise
        spread = 0.5
        candles.append(
            Candle(
                timestamp_ms=1_700_000_000_000 + i * 60_000,
                open=Decimal(f"{mid:.4f}"),
                high=Decimal(f"{mid + spread:.4f}"),
                low=Decimal(f"{max(0.01, mid - spread):.4f}"),
                close=Decimal(f"{mid:.4f}"),
                volume=Decimal("1"),
            )
        )
    return candles


def _run_once(candles: list[Candle]) -> int:
    """Single engine run, returns candle count actually processed."""
    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=Decimal("10000"),
            taker_fee_pct=Decimal("0.1"),
            slippage_pct=Decimal("0.05"),
        )
    )
    bot = EMACross()
    result = engine.run(bot, candles, symbol="BENCH", timeframe="1m")  # type: ignore[arg-type]
    return result.candles_processed


def test_engine_throughput_100k_candles(benchmark) -> None:
    """Benchmark the full engine loop on 100k candles with EMACross.

    pytest-benchmark runs the call repeatedly and reports min / mean /
    median / stddev. We compute candles/sec from the **mean** wall
    time (less noise than min on Windows where the clock resolution is
    coarse). The achieved rate is always printed and is also exposed
    on the ``benchmark`` fixture's ``extra_info`` so the JSON dump
    contains it for trend tracking.
    """
    candles = _build_synthetic_candles(_N_CANDLES)

    # ``pedantic`` mode lets us pin rounds + iterations so the run
    # completes in a predictable wall time even if pytest-benchmark
    # heuristics decide otherwise.
    benchmark.pedantic(_run_once, args=(candles,), rounds=3, iterations=1)

    mean_seconds = benchmark.stats.stats.mean
    rate = _N_CANDLES / mean_seconds if mean_seconds > 0 else float("inf")
    benchmark.extra_info["candles_per_second"] = rate
    benchmark.extra_info["n_candles"] = _N_CANDLES

    print(
        f"\n[benchmark] engine throughput: "
        f"{rate:,.0f} candles/sec "
        f"({_N_CANDLES:,} candles in {mean_seconds:.3f}s mean)"
    )

    if os.environ.get("STRICT_BENCH"):
        assert rate >= _MIN_CANDLES_PER_SEC, (
            f"Throughput regression: {rate:,.0f} < target "
            f"{_MIN_CANDLES_PER_SEC:,} candles/sec"
        )
