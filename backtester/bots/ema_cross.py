"""EMA Crossover trading bot.

Position state is derived from `portfolio` (never tracked locally).
Indicators are incremental — O(1) per candle, not O(n).
"""

from __future__ import annotations

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class _EMA:
    """Stateful exponential moving average. O(1) per update."""

    def __init__(self, period: int) -> None:
        if period < 1:
            raise ValueError("EMA period must be >= 1")
        self.period = period
        self.alpha = 2.0 / (period + 1.0)
        self._value: float | None = None
        self._seed: list[float] = []

    @property
    def ready(self) -> bool:
        return self._value is not None

    @property
    def value(self) -> float:
        return self._value if self._value is not None else 0.0

    def update(self, x: float) -> float | None:
        """Push one new sample, return the EMA value or None if not yet seeded."""
        if self._value is None:
            self._seed.append(x)
            if len(self._seed) >= self.period:
                self._value = sum(self._seed) / float(self.period)
            return self._value
        self._value = self.alpha * x + (1.0 - self.alpha) * self._value
        return self._value


class EMACross(BotBase):
    """BUY on fast↑slow (golden cross), SELL on fast↓slow (death cross).

    A take-profit and a stop-loss are checked first; either closes the
    entire position. Crossovers are evaluated against the previous bar
    so we never trade in the candle where the cross became visible —
    fills happen at the *next* candle's open (engine-side).
    """

    def __init__(
        self,
        fast_ema: int = 12,
        slow_ema: int = 26,
        profit_factor: float = 0.02,
        stop_loss_pct: float = 0.05,
        order_qty: float = 1.0,
    ) -> None:
        if fast_ema >= slow_ema:
            raise ValueError("fast_ema must be < slow_ema")
        if order_qty <= 0:
            raise ValueError("order_qty must be > 0")
        self.fast_ema = fast_ema
        self.slow_ema = slow_ema
        self.profit_factor = float(profit_factor)
        self.stop_loss_pct = float(stop_loss_pct)
        self.order_qty = float(order_qty)

        self._fast = _EMA(fast_ema)
        self._slow = _EMA(slow_ema)
        self._prev_fast: float | None = None
        self._prev_slow: float | None = None

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "fast_ema":      {"type": "int",   "default": 12,    "min": 2,     "max": 50,    "step": 1},
            "slow_ema":      {"type": "int",   "default": 26,    "min": 5,     "max": 200,   "step": 1},
            "profit_factor": {"type": "float", "default": 0.02,  "min": 0.001, "max": 0.10,  "step": 0.001},
            "stop_loss_pct": {"type": "float", "default": 0.05,  "min": 0.01,  "max": 0.50,  "step": 0.01},
            "order_qty":     {"type": "float", "default": 1.0,   "min": 0.001, "max": 1000.0, "step": 0.001},
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        # Step indicators
        new_fast = self._fast.update(candle.close)
        new_slow = self._slow.update(candle.close)

        orders: list[dict[str, Any]] = []
        price = candle.close

        # TP / SL based on portfolio state, not a private flag
        if portfolio.is_long():
            avg_entry = portfolio.avg_entry_price()
            if avg_entry > 0.0:
                tp = avg_entry * (1.0 + self.profit_factor)
                sl = avg_entry * (1.0 - self.stop_loss_pct)
                qty = portfolio.open_qty()
                if price >= tp:
                    orders.append({"side": "SELL", "qty": qty, "reason": "TAKE_PROFIT"})
                    self._prev_fast, self._prev_slow = new_fast, new_slow
                    return orders
                if price <= sl:
                    orders.append({"side": "SELL", "qty": qty, "reason": "STOP_LOSS"})
                    self._prev_fast, self._prev_slow = new_fast, new_slow
                    return orders

        # Crossover only valid once we have both prev and current
        if (self._prev_fast is not None and self._prev_slow is not None
                and new_fast is not None and new_slow is not None):
            golden = self._prev_fast <= self._prev_slow and new_fast > new_slow
            death = self._prev_fast >= self._prev_slow and new_fast < new_slow
            if golden and not portfolio.is_long():
                orders.append({"side": "BUY", "qty": self.order_qty, "reason": "GOLDEN_CROSS"})
            elif death and portfolio.is_long():
                orders.append({"side": "SELL", "qty": portfolio.open_qty(), "reason": "DEATH_CROSS"})

        self._prev_fast, self._prev_slow = new_fast, new_slow
        return orders
