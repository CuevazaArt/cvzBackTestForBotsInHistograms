"""Tests for ResultStore (A3)."""

from __future__ import annotations

from pathlib import Path

import pytest

from backtester.core.result_store import ResultStore


@pytest.fixture()
def store(tmp_path: Path) -> ResultStore:
    return ResultStore(tmp_path / "results.sqlite")


_CONFIG = {"symbol": "BTCUSDT", "timeframe": "1h", "bots": []}
_RESULT = {"final_equity": 12345.0, "trades": 42}


def test_save_and_get(store: ResultStore) -> None:
    store.save("run-1", "BTCUSDT", "1h", _CONFIG, _RESULT)
    rec = store.get("run-1")
    assert rec is not None
    assert rec["run_id"] == "run-1"
    assert rec["symbol"] == "BTCUSDT"
    assert rec["result"]["final_equity"] == 12345.0


def test_get_missing_returns_none(store: ResultStore) -> None:
    assert store.get("does-not-exist") is None


def test_upsert_overwrites(store: ResultStore) -> None:
    store.save("run-1", "BTCUSDT", "1h", _CONFIG, _RESULT)
    store.save("run-1", "BTCUSDT", "1h", _CONFIG, {"final_equity": 99.0})
    rec = store.get("run-1")
    assert rec is not None
    assert rec["result"]["final_equity"] == 99.0


def test_list_recent_order(store: ResultStore) -> None:
    # Insert with small sleeps to ensure strictly increasing created_at,
    # preventing the sub-millisecond collision that causes flakiness on fast CI.
    import time

    for i in range(5):
        store.save(f"run-{i}", "BTCUSDT", "1h", _CONFIG, {"final_equity": float(i)})
        time.sleep(0.005)
    items = store.list_recent(limit=10)
    assert len(items) == 5
    # newest first
    assert items[0]["run_id"] == "run-4"


def test_list_filters_by_symbol(store: ResultStore) -> None:
    store.save("r1", "BTCUSDT", "1h", _CONFIG, _RESULT)
    store.save("r2", "ETHUSDT", "1h", _CONFIG, _RESULT)
    results = store.list_recent(symbol="ETHUSDT")
    assert len(results) == 1
    assert results[0]["symbol"] == "ETHUSDT"


def test_delete_removes_record(store: ResultStore) -> None:
    store.save("run-del", "BTCUSDT", "1h", _CONFIG, _RESULT)
    assert store.delete("run-del") is True
    assert store.get("run-del") is None


def test_delete_missing_returns_false(store: ResultStore) -> None:
    assert store.delete("ghost") is False


def test_cleanup_older_than(store: ResultStore) -> None:
    import time

    store.save("old", "BTCUSDT", "1h", _CONFIG, _RESULT)
    time.sleep(0.05)
    cutoff = 0.01  # 10ms — everything older than 10ms should be deleted
    deleted = store.cleanup_older_than(cutoff)
    assert deleted >= 1
    assert store.get("old") is None
