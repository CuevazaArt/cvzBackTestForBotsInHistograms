"""Tests for resumable downloads (A2)."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest

from backtester.core.downloader import BinanceDownloader


def _make_kline(ts_ms: int, price: float = 100.0) -> list:
    """Minimal kline row matching Binance API format."""
    return [
        ts_ms,          # open time
        str(price),     # open
        str(price + 1), # high
        str(price - 1), # low
        str(price),     # close
        "10.0",         # volume
        ts_ms + 59999,  # close time
        str(price * 10),# quote asset volume
    ]


def _make_batch(start_ms: int, count: int, interval_ms: int = 60_000) -> list[list]:
    return [_make_kline(start_ms + i * interval_ms) for i in range(count)]


@pytest.fixture()
def dl(tmp_path: Path) -> BinanceDownloader:
    return BinanceDownloader(db_path=tmp_path / "test.duckdb")


def test_download_calls_fetch_from_start(dl: BinanceDownloader) -> None:
    """Without start_from_ms, fetch begins at date_from."""
    start_ms = dl._parse_date("2024-01-01")
    batch = _make_batch(start_ms, 3)

    fetch_calls: list[int] = []

    def fake_fetch(symbol, timeframe, start_time, limit=1000):
        fetch_calls.append(start_time)
        if start_time == start_ms:
            return batch
        return []

    with patch.object(dl, "_fetch_batch", side_effect=fake_fetch), \
         patch("backtester.core.downloader.time.sleep"):
        dl.download("BTCUSDT", "1m", "2024-01-01", "2024-01-01")

    assert fetch_calls[0] == start_ms


def test_start_from_ms_skips_earlier_batches(dl: BinanceDownloader) -> None:
    """start_from_ms causes fetch to begin mid-range, skipping earlier candles."""
    start_ms = dl._parse_date("2024-01-01")
    resume_ms = start_ms + 60_000 * 5  # 5 candles in
    batch = _make_batch(resume_ms, 3)

    fetch_calls: list[int] = []

    def fake_fetch(symbol, timeframe, start_time, limit=1000):
        fetch_calls.append(start_time)
        if start_time == resume_ms:
            return batch
        return []

    with patch.object(dl, "_fetch_batch", side_effect=fake_fetch), \
         patch("backtester.core.downloader.time.sleep"):
        count = dl.download(
            "BTCUSDT", "1m", "2024-01-01", "2024-01-02",
            start_from_ms=resume_ms,
        )

    assert fetch_calls[0] == resume_ms, "must not fetch anything before resume_ms"
    assert count == 3


def test_on_progress_called_after_each_batch(dl: BinanceDownloader) -> None:
    """on_progress receives cumulative candle count and next timestamp."""
    start_ms = dl._parse_date("2024-01-01")
    batch1 = _make_batch(start_ms, 5)
    batch2 = _make_batch(start_ms + 60_000 * 5, 3)

    call_log: list[tuple[int, int]] = []

    def fake_fetch(symbol, timeframe, start_time, limit=1000):
        if start_time == start_ms:
            return batch1
        if start_time == start_ms + 60_000 * 5:
            return batch2
        return []

    def on_progress(candles_added: int, last_ts: int) -> None:
        call_log.append((candles_added, last_ts))

    with patch.object(dl, "_fetch_batch", side_effect=fake_fetch), \
         patch("backtester.core.downloader.time.sleep"):
        dl.download(
            "BTCUSDT", "1m", "2024-01-01", "2024-01-01",
            on_progress=on_progress,
        )

    assert len(call_log) >= 1
    candles_seen = [c for c, _ in call_log]
    # cumulative counts must be non-decreasing
    assert candles_seen == sorted(candles_seen)


def test_resume_produces_no_duplicates(dl: BinanceDownloader) -> None:
    """Overlapping candles on resume are silently ignored (ON CONFLICT DO NOTHING)."""
    start_ms = dl._parse_date("2024-01-01")
    interval = 60_000  # 1m
    all_candles = _make_batch(start_ms, 10, interval)
    second_half = all_candles[5:]  # overlap from index 5

    call_count = {"n": 0}

    def fake_fetch_first(symbol, timeframe, start_time, limit=1000):
        call_count["n"] += 1
        if start_time == start_ms:
            return all_candles
        return []

    with patch.object(dl, "_fetch_batch", side_effect=fake_fetch_first), \
         patch("backtester.core.downloader.time.sleep"):
        dl.download("BTCUSDT", "1m", "2024-01-01", "2024-01-01")

    # Now "resume" starting from candle 5 (overlaps with already-stored candles)
    resume_ms = start_ms + 5 * interval

    def fake_fetch_resume(symbol, timeframe, start_time, limit=1000):
        if start_time == resume_ms:
            return second_half
        return []

    with patch.object(dl, "_fetch_batch", side_effect=fake_fetch_resume), \
         patch("backtester.core.downloader.time.sleep"):
        dl.download(
            "BTCUSDT", "1m", "2024-01-01", "2024-01-01",
            start_from_ms=resume_ms,
        )

    rows = dl.conn.execute(
        "SELECT COUNT(*) FROM candles WHERE symbol='BTCUSDT' AND timeframe='1m'"
    ).fetchone()
    assert rows is not None
    assert rows[0] == 10, f"expected 10 unique candles, got {rows[0]}"
