"""LRU-bounded cache for indicator calculations.

When the experiment / optimization runner sweeps a parameter grid on the same
(symbol, timeframe, candle range), most indicators with non-swept params are
recomputed identically every run. This module memoises those results.

Process-local (in-memory). For multi-process workers, instantiate one cache
per worker — the speedup matters most inside a single Optuna study, which is
single-process today.
"""

from __future__ import annotations

import hashlib
import json
import sys
import threading
from collections import OrderedDict
from typing import Callable, Iterable

IndicatorSpec = dict
IndicatorResult = dict[str, list[float | None]]


def _spec_hash(spec: IndicatorSpec) -> str:
    """Stable hash for an indicator spec dict."""
    canonical = json.dumps(spec, sort_keys=True, separators=(",", ":"))
    return hashlib.sha1(canonical.encode("utf-8")).hexdigest()[:16]


def _candles_fingerprint(candles: Iterable) -> str:
    """Cheap fingerprint of a candle series — uses first/last ts + length.

    Backtester data is append-only and immutable for a given (symbol, tf),
    so length + edge timestamps uniquely identifies a slice.
    """
    candles_list = list(candles)
    n = len(candles_list)
    if n == 0:
        return "empty"
    first_ts = getattr(candles_list[0], "timestamp_ms", None)
    last_ts = getattr(candles_list[-1], "timestamp_ms", None)
    return f"{n}:{first_ts}:{last_ts}"


class IndicatorCache:
    """Thread-safe LRU cache for per-spec indicator results.

    Eviction is purely by entry count (max_entries). Memory ceilings are
    coarse — series are typically O(n_candles) floats, so 256 entries with
    1000-candle backtests sits well under 50 MB.
    """

    def __init__(self, max_entries: int = 256) -> None:
        self.max_entries = max_entries
        self._lock = threading.Lock()
        self._data: OrderedDict[str, IndicatorResult] = OrderedDict()
        self._hits = 0
        self._misses = 0

    def get_or_compute(
        self,
        symbol: str,
        timeframe: str,
        candles_fingerprint: str,
        spec: IndicatorSpec,
        compute: Callable[[IndicatorSpec], IndicatorResult],
    ) -> IndicatorResult:
        key = self._key(symbol, timeframe, candles_fingerprint, spec)
        with self._lock:
            hit = self._data.get(key)
            if hit is not None:
                self._data.move_to_end(key)
                self._hits += 1
                return hit
            self._misses += 1
        # Compute outside the lock to avoid serialising heavy work.
        result = compute(spec)
        with self._lock:
            self._data[key] = result
            self._data.move_to_end(key)
            while len(self._data) > self.max_entries:
                self._data.popitem(last=False)
        return result

    def clear(self) -> None:
        with self._lock:
            self._data.clear()
            self._hits = 0
            self._misses = 0

    def stats(self) -> dict:
        with self._lock:
            total = self._hits + self._misses
            hit_rate = (self._hits / total) if total else 0.0
            return {
                "entries": len(self._data),
                "max_entries": self.max_entries,
                "hits": self._hits,
                "misses": self._misses,
                "hit_rate": hit_rate,
                "approx_bytes": sys.getsizeof(self._data),
            }

    @staticmethod
    def _key(symbol: str, timeframe: str, fp: str, spec: IndicatorSpec) -> str:
        return f"{symbol}|{timeframe}|{fp}|{_spec_hash(spec)}"


def add_indicators_cached(
    candles,
    specs: list[IndicatorSpec],
    *,
    cache: IndicatorCache | None,
    symbol: str = "",
    timeframe: str = "",
) -> IndicatorResult:
    """Drop-in replacement for `indicators.add_indicators` that consults a cache.

    Falls back to direct computation when `cache` is None — keeps the hot
    path zero-overhead for single backtests.
    """
    from backtester.core.indicators import add_indicators

    if not specs or not candles:
        return {}

    if cache is None:
        return add_indicators(candles, specs)

    fp = _candles_fingerprint(candles)
    merged: IndicatorResult = {}
    for spec in specs:
        single = cache.get_or_compute(
            symbol=symbol,
            timeframe=timeframe,
            candles_fingerprint=fp,
            spec=spec,
            compute=lambda s: add_indicators(candles, [s]),
        )
        merged.update(single)
    return merged
