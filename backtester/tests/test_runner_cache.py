"""A1 — IndicatorCache wired into StreamingEngine + ExperimentRunner.

Verifies:
- StreamingEngine uses the cache: second identical run yields cache hits.
- ExperimentRunner attaches cache_stats to results (sequential mode).
- Cache is actually reducing redundant add_indicators calls (hit_rate > 0).
"""
from __future__ import annotations

import math
from decimal import Decimal
from pathlib import Path

from backtester.core.cache import IndicatorCache
from backtester.core.engine import BacktestConfig, Candle


# ── Helpers ──────────────────────────────────────────────────────────────────


def _make_candles(n: int = 200) -> list[Candle]:
    candles = []
    for i in range(n):
        price = Decimal(str(100.0 + 30 * math.sin(i / 20.0)))
        candles.append(Candle(
            timestamp_ms=i * 3_600_000,
            open=price,
            high=price + Decimal("0.5"),
            low=price - Decimal("0.5"),
            close=price + Decimal("0.1"),
            volume=Decimal("10"),
        ))
    return candles


_INDICATOR_SPECS = [
    {"name": "ema", "period": 9},
    {"name": "ema", "period": 21},
    {"name": "rsi", "period": 14},
]


# ── StreamingEngine cache tests ───────────────────────────────────────────────


def test_streaming_engine_populates_cache_on_first_run():
    from backtester.core.engine_stream import StreamingEngine
    from backtester.bots.ema_cross import EMACross

    cache = IndicatorCache(max_entries=64)
    cfg = BacktestConfig()
    engine = StreamingEngine(cfg, total=200, cache=cache)
    candles = _make_candles(200)

    engine.run(EMACross(), candles, symbol="BTC", timeframe="1h",
               indicator_specs=_INDICATOR_SPECS)

    stats = cache.stats()
    # First run: all misses, entries now populated
    assert stats["misses"] == len(_INDICATOR_SPECS)
    assert stats["hits"] == 0
    assert stats["entries"] == len(_INDICATOR_SPECS)


def test_streaming_engine_hits_cache_on_second_run():
    from backtester.core.engine_stream import StreamingEngine
    from backtester.bots.ema_cross import EMACross

    cache = IndicatorCache(max_entries=64)
    cfg = BacktestConfig()
    candles = _make_candles(200)

    # Run 1: warm the cache
    engine1 = StreamingEngine(cfg, total=200, cache=cache)
    engine1.run(EMACross(), candles, symbol="BTC", timeframe="1h",
                indicator_specs=_INDICATOR_SPECS)

    stats_after_run1 = cache.stats()
    assert stats_after_run1["misses"] == len(_INDICATOR_SPECS)

    # Run 2: same candles + specs → all hits
    engine2 = StreamingEngine(cfg, total=200, cache=cache)
    engine2.run(EMACross(fast_ema=5, slow_ema=15), candles, symbol="BTC",
                timeframe="1h", indicator_specs=_INDICATOR_SPECS)

    stats_after_run2 = cache.stats()
    assert stats_after_run2["hits"] == len(_INDICATOR_SPECS)
    assert stats_after_run2["hit_rate"] >= 0.5


def test_streaming_engine_no_cache_still_works():
    """cache=None must not break the engine."""
    from backtester.core.engine_stream import StreamingEngine
    from backtester.bots.ema_cross import EMACross

    engine = StreamingEngine(BacktestConfig(), total=100)  # cache defaults to None
    result = engine.run(
        EMACross(), _make_candles(100),
        symbol="ETH", timeframe="4h",
        indicator_specs=[{"name": "ema", "period": 9}],
    )
    assert result.candles_processed == 100


# ── ExperimentRunner cache_stats tests ───────────────────────────────────────


def _make_downloader(tmp_path: Path) -> "BinanceDownloader":  # type: ignore[name-defined]
    """Create a downloader pre-seeded with synthetic candles."""
    import math
    from backtester.core import BinanceDownloader

    dl = BinanceDownloader(tmp_path / "candles.duckdb")
    klines = []
    for i in range(200):
        p = 100.0 + 30 * math.sin(i / 20.0)
        ts = i * 3_600_000
        klines.append([ts, p - 0.2, p + 0.5, p - 0.5, p + 0.1, 100.0,
                        ts + 3_599_999, 10000.0])
    dl._save_batch("BTCUSDT", "1h", klines)
    return dl


def test_experiment_runner_attaches_cache_stats(tmp_path: Path):
    from backtester.bots.ema_cross import EMACross
    from backtester.experiments.runner import Experiment, ExperimentRunner

    dl = _make_downloader(tmp_path)
    cache = IndicatorCache(max_entries=32)
    runner = ExperimentRunner(
        downloader=dl,
        bot_registry={"EMACross": EMACross},
        cache=cache,
    )

    experiments = [
        Experiment("BTCUSDT", "1h", "EMACross", {"fast_ema": f, "slow_ema": f + 10})
        for f in range(5, 21, 5)  # 4 configs
    ]

    results = runner.run_batch(experiments, workers=1)

    assert len(results) == 4
    for r in results:
        assert r.cache_stats is not None, "cache_stats must be populated"
    # Runner itself doesn't call add_indicators, but cache_stats is attached
    last = results[-1].cache_stats
    assert "hits" in last and "misses" in last and "hit_rate" in last
