"""WebSocket transport tests for the Playback Transport feature.

Covers the two contract bugs uncovered during code review:

* **Bug 1** — The concurrent-run guard at the top of the ``backtest`` action
  must reject a second backtest as long as the previous engine task is still
  in flight, even if the previous controller was cancelled (its
  ``is_cancelled`` flag flips instantly while the engine thread keeps running
  until its next ``wait_if_paused`` checkpoint).

* **Bug 2** — The Flutter client embeds ``speed_ms`` inside the ``config``
  payload, while programmatic clients pass it at the top level of the
  message. The server must accept either form so the client's speed
  preference is not silently dropped.
"""

from __future__ import annotations

import math
import tempfile
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# Fixture — minimal app with synthetic candles
# ---------------------------------------------------------------------------


def _synthetic_klines(n: int = 30) -> list[list]:
    """Generate the smallest synthetic kline set that still triggers EMA crosses."""
    klines: list[list] = []
    for i in range(n):
        offset = 30 * math.sin(i / 4.0) + i * 0.5
        close = 100.0 + offset
        o = 100.0 + 30 * math.sin((i - 1) / 4.0) + (i - 1) * 0.5 if i > 0 else close
        h = max(o, close) + 0.3
        low_p = min(o, close) - 0.3
        ts_ms = i * 3_600_000  # 1h candles starting at epoch.
        klines.append([ts_ms, o, h, low_p, close, 100.0, ts_ms + 3_599_999, 10000.0])
    return klines


@pytest.fixture
def ws_app():
    """FastAPI app with a tiny pre-loaded DuckDB so /ws can run real backtests."""
    from backtester.api.deps import AppContext, BOT_REGISTRY
    from backtester.api.jobs import JobRegistry
    from backtester.api.server import create_app
    from backtester.core import BinanceDownloader, CredentialManager
    from backtester.core.cache import IndicatorCache
    from backtester.core.preset_store import PresetStore
    from backtester.core.result_store import ResultStore

    tmpdir = tempfile.mkdtemp(prefix="ws_transport_test_")
    root = Path(tmpdir)
    (root / "data").mkdir(parents=True, exist_ok=True)
    (root / ".vault").mkdir(parents=True, exist_ok=True)

    downloader = BinanceDownloader(root / "data" / "candles.duckdb")
    downloader._save_batch("TESTUSDT", "1h", _synthetic_klines(30))

    app = create_app(is_test=True)
    app.state.ctx = AppContext(
        base_dir=root,
        downloader=downloader,
        credentials=CredentialManager(root / ".vault"),
        bot_registry=dict(BOT_REGISTRY),
        jobs=JobRegistry(root / "data" / "jobs.sqlite"),
        presets=PresetStore(root / "data" / "presets.sqlite"),
        indicator_cache=IndicatorCache(max_entries=64),
        result_store=ResultStore(root / "data" / "results.sqlite"),
    )
    return app


def _backtest_config(speed_ms: int | None = None) -> dict:
    """Build a small backtest config; optionally embed speed_ms inside it."""
    cfg: dict = {
        "symbol": "TESTUSDT",
        "timeframe": "1h",
        "bots": [
            {
                "name": "EMACross",
                "params": {"fast_ema": 3, "slow_ema": 7},
            }
        ],
        "initial_cash": 10000.0,
        "indicators": [],
        # Bound the run so timing-based assertions stay reliable.
        "start_ms": 0,
        "end_ms": 9 * 3_600_000,  # 10 candles
    }
    if speed_ms is not None:
        cfg["speed_ms"] = speed_ms
    return cfg


def _drain_until(ws, predicate, timeout_s: float = 5.0) -> list[dict]:
    """Read events until *predicate(event)* is True or we time out."""
    out: list[dict] = []
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        try:
            ev = ws.receive_json()
        except Exception:
            break
        out.append(ev)
        if predicate(ev):
            return out
    raise AssertionError(
        f"Timeout waiting for predicate; got events: {[e.get('type') for e in out]}"
    )


# ---------------------------------------------------------------------------
# Bug 1 — race between cancel and a follow-up backtest
# ---------------------------------------------------------------------------


def test_concurrent_backtest_rejected_while_previous_run_in_flight(ws_app):
    """A second ``backtest`` while the engine thread is still alive must be
    rejected, even if ``cancel`` has already flipped ``is_cancelled``.
    """
    client = TestClient(ws_app)
    with client.websocket_connect("/ws") as ws:
        # Drain the initial "ready" event.
        _drain_until(ws, lambda e: e.get("type") == "ready")

        # Start a slow run so the engine thread is comfortably alive.
        ws.send_json(
            {
                "action": "backtest",
                "config": _backtest_config(speed_ms=200),
            }
        )
        # Wait for the "start" event so we know the engine entered its loop.
        _drain_until(ws, lambda e: e.get("type") == "start")

        # Cancel the first run — engine thread keeps running until next
        # wait_if_paused checkpoint, so its task is still not done().
        ws.send_json({"action": "cancel"})

        # Immediately try a second backtest. With the bug, this would be
        # accepted (ctrl1.is_cancelled == True). With the fix, the
        # _run_task.done() check rejects it.
        ws.send_json({"action": "backtest", "config": _backtest_config(speed_ms=0)})

        # The next non-engine event must be the "already running" error.
        events = _drain_until(
            ws,
            lambda e: e.get("type") == "error"
            and "already running" in (e.get("data") or {}).get("message", ""),
        )
        # Sanity: we must NOT have received a second "start" event before
        # the rejection (which would mean the new run actually launched).
        starts_before_error = sum(1 for e in events[:-1] if e.get("type") == "start")
        assert starts_before_error == 0, (
            f"Second backtest started despite previous run being in flight; "
            f"got events: {[e.get('type') for e in events]}"
        )


# ---------------------------------------------------------------------------
# Bug 2 — speed_ms must be honoured whether sent at top level OR in config
# ---------------------------------------------------------------------------


def _measure_run_duration(ws_app, *, speed_ms: int, location: str) -> float:
    """Run a fixed-size backtest and return wall-clock time until ``result``.

    location: ``"top"`` to send speed_ms at the top of the message,
              ``"config"`` to embed it inside the BacktestRequest payload.
    """
    client = TestClient(ws_app)
    cfg = _backtest_config(speed_ms=speed_ms if location == "config" else None)
    msg: dict = {"action": "backtest", "config": cfg}
    if location == "top":
        msg["speed_ms"] = speed_ms

    with client.websocket_connect("/ws") as ws:
        _drain_until(ws, lambda e: e.get("type") == "ready")
        t0 = time.monotonic()
        ws.send_json(msg)
        _drain_until(
            ws,
            lambda e: e.get("type") in {"result", "error"},
            timeout_s=15.0,
        )
        return time.monotonic() - t0


def test_speed_ms_inside_config_is_respected(ws_app):
    """speed_ms embedded in config (Flutter contract) must pace the engine."""
    elapsed = _measure_run_duration(ws_app, speed_ms=200, location="config")
    # 10 candles × 200 ms ≈ 2.0 s. With the bug it would default to 100 ms
    # (≈ 1.0 s). Threshold: 1.4 s leaves comfortable margin both sides.
    assert elapsed >= 1.4, (
        f"speed_ms in config was ignored — run took {elapsed:.2f}s "
        f"(expected ≥ 1.4s for 10 × 200 ms)."
    )


def test_speed_ms_at_top_level_is_respected(ws_app):
    """speed_ms at the top level (programmatic contract) must pace the engine."""
    elapsed = _measure_run_duration(ws_app, speed_ms=200, location="top")
    assert elapsed >= 1.4, (
        f"speed_ms at top level was ignored — run took {elapsed:.2f}s "
        f"(expected ≥ 1.4s for 10 × 200 ms)."
    )


def test_speed_ms_zero_runs_at_max_speed(ws_app):
    """speed_ms=0 (Max preset) should skip pacing entirely."""
    elapsed = _measure_run_duration(ws_app, speed_ms=0, location="config")
    # 10 candles at Max should comfortably finish in well under 1s.
    assert (
        elapsed < 1.0
    ), f"speed_ms=0 did not run at Max — took {elapsed:.2f}s (expected <1.0s)."
