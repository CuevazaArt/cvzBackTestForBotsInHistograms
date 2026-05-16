"""Integration tests for StreamingEngine with RunController.

Tests run entirely in-process (no real data, no WS) using a tiny synthetic
candle set and a no-op bot.  A background thread manipulates the controller
while the engine runs, asserting events and lifecycle.
"""

from __future__ import annotations

import threading
import time
from decimal import Decimal

from backtester.core.engine import BacktestConfig, Candle, Portfolio
from backtester.core.engine_stream import StreamingEngine
from backtester.core.run_control import RunController


# ---------------------------------------------------------------------------
# Helpers / fixtures
# ---------------------------------------------------------------------------


def _make_candles(n: int = 20) -> list[Candle]:
    candles = []
    for i in range(n):
        price = Decimal(str(100 + i))
        candles.append(
            Candle(
                timestamp_ms=1_700_000_000_000 + i * 60_000,
                open=price,
                high=price + Decimal("1"),
                low=price - Decimal("1"),
                close=price,
                volume=Decimal("10"),
            )
        )
    return candles


class _NoOpBot:
    """Bot that never places orders."""

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list:
        return []


def _make_engine(controller: RunController, events: list) -> StreamingEngine:
    def _emit(event_type: str, data: dict | None = None) -> None:
        events.append(event_type)

    cfg = BacktestConfig(
        initial_cash=Decimal("10000"),
        taker_fee_pct=Decimal("0"),
        slippage_pct=Decimal("0"),
    )
    return StreamingEngine(
        config=cfg,
        on_event=_emit,
        total=20,
        candle_every=1,
        equity_every=1,
        progress_every=1,
        controller=controller,
    )


def _run_engine(engine: StreamingEngine, candles: list[Candle]) -> None:
    engine.run(bots=[_NoOpBot()], candles=candles, symbol="TEST", timeframe="1m")


# ---------------------------------------------------------------------------
# Test: no controller — engine runs to completion
# ---------------------------------------------------------------------------


def test_engine_without_controller_completes():
    events: list[str] = []
    candles = _make_candles(5)
    cfg = BacktestConfig(initial_cash=Decimal("10000"))
    engine = StreamingEngine(config=cfg, on_event=lambda t, d: events.append(t), total=5)
    engine.run(bots=[_NoOpBot()], candles=candles, symbol="TEST", timeframe="1m")

    assert "start" in events
    assert "result" in events
    assert "cancelled" not in events


# ---------------------------------------------------------------------------
# Test: cancel before loop starts
# ---------------------------------------------------------------------------


def test_cancel_before_run_stops_at_first_candle():
    ctrl = RunController()
    ctrl.cancel()

    events: list[str] = []
    engine = _make_engine(ctrl, events)
    candles = _make_candles(20)
    _run_engine(engine, candles)

    assert "cancelled" in events
    assert "result" not in events
    # At most a tiny number of candle events (cancel checked first)
    candle_count = events.count("candle")
    assert candle_count <= 1


# ---------------------------------------------------------------------------
# Test: cancel mid-run from a background thread
# ---------------------------------------------------------------------------


def test_cancel_mid_run():
    ctrl = RunController()
    ctrl.set_speed(0)  # Max speed
    ctrl.pause()  # Start paused so engine cannot race ahead at 0 ms/candle

    events: list[str] = []
    engine = _make_engine(ctrl, events)
    candles = _make_candles(50)

    run_thread = threading.Thread(
        target=_run_engine, args=(engine, candles), daemon=True
    )
    run_thread.start()

    # Give engine time to emit "start" and enter wait_if_paused.
    time.sleep(0.1)
    ctrl.cancel()
    run_thread.join(timeout=2.0)

    assert "cancelled" in events
    assert "result" not in events


# ---------------------------------------------------------------------------
# Test: pause → resume → completion
# ---------------------------------------------------------------------------


def test_pause_then_resume_completes():
    ctrl = RunController()
    ctrl.set_speed(0)  # Max speed

    events: list[str] = []
    engine = _make_engine(ctrl, events)
    candles = _make_candles(20)

    def _pause_then_resume():
        time.sleep(0.01)
        ctrl.pause()
        time.sleep(0.1)
        ctrl.resume()

    t = threading.Thread(target=_pause_then_resume, daemon=True)
    t.start()

    _run_engine(engine, candles)
    t.join(timeout=2.0)

    assert "result" in events
    assert "cancelled" not in events


# ---------------------------------------------------------------------------
# Test: step advances exactly N candles while paused
# ---------------------------------------------------------------------------


def test_step_advances_one_candle_at_a_time():
    ctrl = RunController()
    ctrl.set_speed(0)
    ctrl.pause()  # start paused

    events: list[str] = []
    engine = _make_engine(ctrl, events)
    candles = _make_candles(10)

    run_thread = threading.Thread(
        target=_run_engine, args=(engine, candles), daemon=True
    )
    run_thread.start()

    # Let the engine thread enter wait_if_paused
    time.sleep(0.05)
    candle_before = events.count("candle")

    ctrl.step()
    time.sleep(0.15)
    candle_after_1 = events.count("candle")
    assert candle_after_1 == candle_before + 1

    ctrl.step()
    time.sleep(0.15)
    candle_after_2 = events.count("candle")
    assert candle_after_2 == candle_before + 2

    # Resume to let the engine finish
    ctrl.resume()
    run_thread.join(timeout=2.0)
    assert "result" in events


# ---------------------------------------------------------------------------
# Test: speed_ms pacing
# ---------------------------------------------------------------------------


def test_speed_pacing_delays_run():
    ctrl = RunController()
    ctrl.set_speed(20)  # 20 ms per candle

    events: list[str] = []
    engine = _make_engine(ctrl, events)
    candles = _make_candles(5)

    t0 = time.monotonic()
    _run_engine(engine, candles)
    elapsed = time.monotonic() - t0

    # 5 candles × 20 ms = ≥ 100 ms
    assert elapsed >= 0.08, f"Expected ≥ 0.08s, got {elapsed:.3f}s"


def test_speed_zero_runs_at_max():
    ctrl = RunController()
    ctrl.set_speed(0)

    events: list[str] = []
    engine = _make_engine(ctrl, events)
    candles = _make_candles(5)

    t0 = time.monotonic()
    _run_engine(engine, candles)
    elapsed = time.monotonic() - t0

    # Should run very fast (< 200 ms even on slow CI)
    assert elapsed < 0.5, f"Expected < 0.5s, got {elapsed:.3f}s"
    assert "result" in events


# ---------------------------------------------------------------------------
# Test: cancel is responsive while paused (≤ 200 ms)
# ---------------------------------------------------------------------------


def test_cancel_responsive_while_paused():
    ctrl = RunController()
    ctrl.set_speed(0)
    ctrl.pause()

    events: list[str] = []
    engine = _make_engine(ctrl, events)
    candles = _make_candles(20)

    run_thread = threading.Thread(
        target=_run_engine, args=(engine, candles), daemon=True
    )
    run_thread.start()

    time.sleep(0.05)  # let it block in wait_if_paused

    t0 = time.monotonic()
    ctrl.cancel()
    run_thread.join(timeout=1.0)
    elapsed = time.monotonic() - t0

    assert not run_thread.is_alive(), "Engine did not stop after cancel"
    assert "cancelled" in events
    assert elapsed < 0.2, f"Cancel took too long: {elapsed:.3f}s"
