"""Tests for the thread-safe Binance weight tracker.

The ``WeightTracker`` wraps the previously global ``BINANCE_USED_WEIGHT_1M``
counter so concurrent download threads and the FastAPI ``/health`` reader
can no longer race.
"""

from __future__ import annotations

import threading

from backtester.core.downloader import (
    BINANCE_WEIGHT_TRACKER,
    WeightTracker,
    get_binance_used_weight_1m,
    set_binance_used_weight_1m,
)


def test_weight_tracker_concurrent_increments_are_lossless() -> None:
    """Many threads racing ``increment`` should yield exactly N total."""
    tracker = WeightTracker(0)
    n_threads = 16
    increments_per_thread = 250

    def _worker() -> None:
        for _ in range(increments_per_thread):
            tracker.increment(1)

    threads = [threading.Thread(target=_worker) for _ in range(n_threads)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert tracker.get() == n_threads * increments_per_thread


def test_weight_tracker_set_and_get_roundtrip() -> None:
    tracker = WeightTracker(0)
    tracker.set(123)
    assert tracker.get() == 123
    tracker.reset()
    assert tracker.get() == 0


def test_module_level_accessors_read_global_tracker() -> None:
    """``get_binance_used_weight_1m``/``set_…`` operate on the shared tracker."""
    original = get_binance_used_weight_1m()
    try:
        set_binance_used_weight_1m(99)
        assert get_binance_used_weight_1m() == 99
        assert BINANCE_WEIGHT_TRACKER.get() == 99
    finally:
        set_binance_used_weight_1m(original)


def test_legacy_module_attribute_reads_live_value() -> None:
    """``from … import BINANCE_USED_WEIGHT_1M`` must always reflect the tracker."""
    from backtester.core import downloader

    original = get_binance_used_weight_1m()
    try:
        set_binance_used_weight_1m(77)
        assert downloader.BINANCE_USED_WEIGHT_1M == 77
        set_binance_used_weight_1m(11)
        assert downloader.BINANCE_USED_WEIGHT_1M == 11
    finally:
        set_binance_used_weight_1m(original)
