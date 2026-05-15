"""Tests for IndicatorCache (Sprint 4)."""

from __future__ import annotations

from backtester.core.cache import IndicatorCache, add_indicators_cached


class _Candle:
    """Minimal OHLCV stand-in usable by both the fingerprint and add_indicators."""
    __slots__ = ("timestamp_ms", "open", "high", "low", "close", "volume")
    def __init__(self, ts: int, price: float = 100.0) -> None:
        self.timestamp_ms = ts
        self.open = price
        self.high = price + 1
        self.low = price - 1
        self.close = price + 0.5
        self.volume = 10.0


def test_cache_hit_returns_memoised_result():
    cache = IndicatorCache(max_entries=4)
    calls = {"n": 0}

    def compute(spec):
        calls["n"] += 1
        return {"ema_9": [1.0, 2.0, 3.0]}

    spec = {"name": "ema", "period": 9}
    cache.get_or_compute("BTC", "1h", "fp1", spec, compute)
    cache.get_or_compute("BTC", "1h", "fp1", spec, compute)
    cache.get_or_compute("BTC", "1h", "fp1", spec, compute)

    assert calls["n"] == 1
    s = cache.stats()
    assert s["hits"] == 2 and s["misses"] == 1 and s["hit_rate"] > 0.66


def test_cache_miss_on_different_fingerprint():
    cache = IndicatorCache()
    calls = {"n": 0}

    def compute(_spec):
        calls["n"] += 1
        return {"ema_9": [1.0]}

    spec = {"name": "ema", "period": 9}
    cache.get_or_compute("BTC", "1h", "fp1", spec, compute)
    cache.get_or_compute("BTC", "1h", "fp2", spec, compute)  # diff candles
    assert calls["n"] == 2


def test_cache_lru_eviction():
    cache = IndicatorCache(max_entries=2)
    counter = {"n": 0}

    def compute(_spec):
        counter["n"] += 1
        return {"x": [counter["n"]]}

    a = {"name": "ema", "period": 9}
    b = {"name": "ema", "period": 21}
    c = {"name": "ema", "period": 50}

    cache.get_or_compute("BTC", "1h", "fp", a, compute)
    cache.get_or_compute("BTC", "1h", "fp", b, compute)
    cache.get_or_compute("BTC", "1h", "fp", c, compute)  # evicts a (oldest)
    cache.get_or_compute("BTC", "1h", "fp", a, compute)  # miss again

    assert counter["n"] == 4
    assert cache.stats()["entries"] == 2


def test_add_indicators_cached_falls_through_without_cache():
    candles = [_Candle(1_000 * i, price=100.0 + i * 0.1) for i in range(50)]
    out = add_indicators_cached(
        candles, [{"name": "ema", "period": 5}], cache=None,
        symbol="BTC", timeframe="1h",
    )
    assert "ema_5" in out
    assert len(out["ema_5"]) == 50


def test_add_indicators_cached_memoises_across_calls():
    candles = [_Candle(1_000 * i) for i in range(80)]
    cache = IndicatorCache(max_entries=8)

    out1 = add_indicators_cached(
        candles, [{"name": "ema", "period": 5}, {"name": "ema", "period": 20}],
        cache=cache, symbol="BTC", timeframe="1h",
    )
    out2 = add_indicators_cached(
        candles, [{"name": "ema", "period": 5}, {"name": "ema", "period": 20}],
        cache=cache, symbol="BTC", timeframe="1h",
    )
    assert out1 == out2
    s = cache.stats()
    assert s["hits"] == 2 and s["misses"] == 2  # 2 specs, each cached then hit


def test_cache_clear_resets_stats():
    cache = IndicatorCache()
    cache.get_or_compute("BTC", "1h", "fp", {"name": "ema"}, lambda _: {"x": [1.0]})
    cache.clear()
    s = cache.stats()
    assert s["entries"] == 0 and s["hits"] == 0 and s["misses"] == 0
