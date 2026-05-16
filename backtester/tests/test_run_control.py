"""Unit tests for RunController (no engine needed).

Covers: pause/resume, step, cancel, speed, wait_if_paused responsiveness.
"""

from __future__ import annotations

import threading
import time

import pytest

from backtester.core.run_control import RunController


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _run_wait_in_thread(
    ctrl: RunController,
) -> tuple[threading.Thread, list[tuple[bool, float]]]:
    """Call wait_if_paused() in a background thread.

    Returns the started thread and a list that will receive ``(cancelled, elapsed)``
    once ``wait_if_paused`` returns. Tests join the thread and inspect the list.
    """
    result: list[tuple[bool, float]] = []

    def _worker() -> None:
        t0 = time.monotonic()
        cancelled = ctrl.wait_if_paused()
        result.append((cancelled, time.monotonic() - t0))

    t = threading.Thread(target=_worker, daemon=True)
    t.start()
    return t, result


# ---------------------------------------------------------------------------
# Initial state
# ---------------------------------------------------------------------------


def test_initial_state():
    ctrl = RunController()
    assert not ctrl.is_paused
    assert not ctrl.is_cancelled
    assert ctrl.speed_ms == RunController.DEFAULT_SPEED_MS


# ---------------------------------------------------------------------------
# Pause / resume
# ---------------------------------------------------------------------------


def test_pause_sets_paused():
    ctrl = RunController()
    ctrl.pause()
    assert ctrl.is_paused


def test_resume_clears_paused():
    ctrl = RunController()
    ctrl.pause()
    ctrl.resume()
    assert not ctrl.is_paused


def test_wait_if_paused_returns_immediately_when_not_paused():
    ctrl = RunController()
    t0 = time.monotonic()
    result = ctrl.wait_if_paused()
    elapsed = time.monotonic() - t0
    assert result is False
    assert elapsed < 0.05  # should be near-instant


def test_wait_if_paused_blocks_until_resumed():
    ctrl = RunController()
    ctrl.pause()

    t, result = _run_wait_in_thread(ctrl)
    time.sleep(0.05)  # let the thread enter the wait loop
    assert len(result) == 0, "thread should still be blocked"

    ctrl.resume()
    t.join(timeout=1.0)
    assert len(result) == 1
    cancelled, elapsed = result[0]
    assert not cancelled
    assert elapsed < 1.0


# ---------------------------------------------------------------------------
# Step
# ---------------------------------------------------------------------------


def test_step_unblocks_once_then_re_pauses():
    ctrl = RunController()
    ctrl.pause()

    released = []

    def _engine_loop():
        for _ in range(3):
            should_stop = ctrl.wait_if_paused()
            if should_stop:
                break
            released.append(1)

    t = threading.Thread(target=_engine_loop, daemon=True)
    t.start()

    time.sleep(0.05)  # let thread block
    assert len(released) == 0

    ctrl.step()  # allow exactly 1 candle
    time.sleep(0.15)
    assert len(released) == 1  # only one candle passed

    ctrl.step()  # allow one more
    time.sleep(0.15)
    assert len(released) == 2

    ctrl.resume()  # let the rest through
    t.join(timeout=1.0)
    assert len(released) == 3


# ---------------------------------------------------------------------------
# Cancel
# ---------------------------------------------------------------------------


def test_cancel_sets_cancelled():
    ctrl = RunController()
    ctrl.cancel()
    assert ctrl.is_cancelled


def test_cancel_unblocks_wait_if_paused():
    ctrl = RunController()
    ctrl.pause()

    t, result = _run_wait_in_thread(ctrl)
    time.sleep(0.05)
    assert len(result) == 0

    ctrl.cancel()
    t.join(timeout=1.0)
    assert len(result) == 1
    cancelled, _ = result[0]
    assert cancelled is True


def test_cancel_while_running_detected_immediately():
    ctrl = RunController()
    ctrl.cancel()
    # wait_if_paused returns True immediately even without pause
    assert ctrl.wait_if_paused() is True


# ---------------------------------------------------------------------------
# Speed
# ---------------------------------------------------------------------------


def test_set_speed_valid():
    ctrl = RunController()
    ctrl.set_speed(200)
    assert ctrl.speed_ms == 200
    ctrl.set_speed(0)
    assert ctrl.speed_ms == 0


def test_set_speed_negative_raises():
    ctrl = RunController()
    with pytest.raises(ValueError):
        ctrl.set_speed(-1)


# ---------------------------------------------------------------------------
# Resume drains leftover step permits
# ---------------------------------------------------------------------------


def test_resume_drains_step_permits():
    """Extra step() calls before resume() must not leak through as free candles."""
    ctrl = RunController()
    ctrl.pause()
    ctrl.step()
    ctrl.step()
    ctrl.step()

    ctrl.resume()  # must drain all 3 permits
    assert not ctrl.is_paused

    # If we pause again, wait_if_paused should block (no leftover permits).
    ctrl.pause()
    t, result = _run_wait_in_thread(ctrl)
    time.sleep(0.05)
    assert len(result) == 0, "permits leaked through after resume()"

    ctrl.resume()
    t.join(timeout=1.0)
