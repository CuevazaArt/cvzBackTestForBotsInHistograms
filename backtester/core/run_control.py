"""RunController — cooperative pause/step/speed/cancel for StreamingEngine.

One controller is created per WS backtest run and shared between:
  - the engine worker thread (reads state each candle)
  - the WS handler coroutine (writes state in response to client actions)

Thread-safety contract:
  - All public methods are thread-safe (Events and Semaphore are thread-safe).
  - ``speed_ms`` is a plain int; reads/writes on CPython are effectively atomic
    for small ints, but we guard it with a lock for correctness.
"""

from __future__ import annotations

import threading
import time

_POLL_INTERVAL_S: float = 0.05  # 50 ms — cancel check granularity while paused


class RunController:
    """Controls a running backtest engine: pause, resume, step, speed, cancel.

    Typical flow
    ------------
    1. WS handler creates a RunController and passes it to StreamingEngine.run().
    2. StreamingEngine calls ``wait_if_paused()`` at the top of every candle.
    3. WS handler calls ``pause()`` / ``resume()`` / ``step()`` / ``cancel()``
       in response to client actions.

    Speed
    -----
    ``speed_ms > 0`` → sleep that many ms per candle (wall-clock pacing).
    ``speed_ms == 0`` → Max speed, no sleep.
    Default is 100 ms (≈ 1x preset).
    """

    DEFAULT_SPEED_MS: int = 100

    def __init__(self) -> None:
        self._pause_event = threading.Event()  # set = paused
        self._cancel_event = threading.Event()
        # Semaphore used for step: allow exactly N candles to proceed past pause.
        self._step_sem: threading.Semaphore = threading.Semaphore(0)
        self._speed_lock = threading.Lock()
        self._speed_ms: int = self.DEFAULT_SPEED_MS

    # ── read-only properties ──────────────────────────────────────────────────

    @property
    def is_paused(self) -> bool:
        return self._pause_event.is_set()

    @property
    def is_cancelled(self) -> bool:
        return self._cancel_event.is_set()

    @property
    def speed_ms(self) -> int:
        with self._speed_lock:
            return self._speed_ms

    # ── actions (called by WS handler) ───────────────────────────────────────

    def pause(self) -> None:
        """Signal the engine to pause before the next candle."""
        self._pause_event.set()

    def resume(self) -> None:
        """Resume a paused engine."""
        self._pause_event.clear()
        # Drain any leftover step permits so they don't carry over.
        while self._step_sem.acquire(blocking=False):
            pass

    def step(self) -> None:
        """Allow exactly one candle to proceed while paused."""
        # Make sure we are paused so the engine honours the semaphore path.
        self._pause_event.set()
        self._step_sem.release()

    def set_speed(self, speed_ms: int) -> None:
        """Set per-candle sleep duration in milliseconds (0 = Max / no sleep)."""
        if speed_ms < 0:
            raise ValueError(f"speed_ms must be >= 0, got {speed_ms}")
        with self._speed_lock:
            self._speed_ms = speed_ms

    def cancel(self) -> None:
        """Signal the engine to stop and emit a 'cancelled' event."""
        self._cancel_event.set()
        # Unblock wait_if_paused so cancel is responsive.
        self._pause_event.clear()
        self._step_sem.release()

    # ── engine-side API ───────────────────────────────────────────────────────

    def wait_if_paused(self) -> bool:
        """Called by the engine at the top of each candle iteration.

        Blocks while paused, polling ``cancel_event`` every ~50 ms so that
        a cancel() call is always responded to promptly.

        Returns
        -------
        bool
            ``True`` if the engine should stop (cancel was requested).
        """
        if not self._pause_event.is_set():
            return self.is_cancelled

        # We are paused — check whether this is a step request.
        if self._step_sem.acquire(blocking=False):
            # One step granted; engine processes this candle then re-pauses.
            return self.is_cancelled

        # True pause: spin with a 50 ms poll so cancel is responsive.
        while self._pause_event.is_set():
            if self._cancel_event.is_set():
                return True
            # Try to consume a step permit released while we were sleeping.
            if self._step_sem.acquire(blocking=False):
                return self.is_cancelled
            time.sleep(_POLL_INTERVAL_S)

        return self.is_cancelled
