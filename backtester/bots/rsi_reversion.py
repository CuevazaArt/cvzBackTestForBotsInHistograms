"""RSI mean-reversion bot.

Wilder's RSI computed incrementally (O(1) per candle). Position state is
read from `portfolio`, never tracked locally.
"""

from __future__ import annotations

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class _WilderRSI:
    """Wilder's RSI: SMA seed of length `period`, then EMA-style smoothing."""

    def __init__(self, period: int) -> None:
        if period < 2:
            raise ValueError("RSI period must be >= 2")
        self.period = period
        self._prev_close: float | None = None
        self._gains_seed: list[float] = []
        self._losses_seed: list[float] = []
        self._avg_gain: float | None = None
        self._avg_loss: float | None = None
        self._value: float | None = None

    @property
    def ready(self) -> bool:
        return self._value is not None

    @property
    def value(self) -> float:
        return self._value if self._value is not None else 50.0

    def update(self, close: float) -> float | None:
        if self._prev_close is None:
            self._prev_close = close
            return None

        change = close - self._prev_close
        gain = change if change > 0.0 else 0.0
        loss = -change if change < 0.0 else 0.0
        self._prev_close = close

        if self._avg_gain is None:
            self._gains_seed.append(gain)
            self._losses_seed.append(loss)
            if len(self._gains_seed) >= self.period:
                self._avg_gain = sum(self._gains_seed) / self.period
                self._avg_loss = sum(self._losses_seed) / self.period
                self._gains_seed = self._losses_seed = []
        else:
            # Wilder smoothing
            self._avg_gain = (self._avg_gain * (self.period - 1) + gain) / self.period
            self._avg_loss = (self._avg_loss * (self.period - 1) + loss) / self.period

        if self._avg_gain is None or self._avg_loss is None:
            return None

        if self._avg_loss == 0.0:
            self._value = 100.0
        else:
            rs = self._avg_gain / self._avg_loss
            self._value = 100.0 - (100.0 / (1.0 + rs))
        return self._value


class RSIReversion(BotBase):
    """BUY when RSI crosses up out of oversold; SELL at overbought or TP."""

    def __init__(
        self,
        rsi_period: int = 14,
        oversold_level: float = 30.0,
        overbought_level: float = 70.0,
        profit_factor: float = 0.02,
        order_qty: float = 1.0,
    ) -> None:
        if not 0 < oversold_level < overbought_level < 100:
            raise ValueError("Need 0 < oversold < overbought < 100")
        if order_qty <= 0:
            raise ValueError("order_qty must be > 0")
        self.rsi_period = rsi_period
        self.oversold_level = float(oversold_level)
        self.overbought_level = float(overbought_level)
        self.profit_factor = float(profit_factor)
        self.order_qty = float(order_qty)
        self._rsi = _WilderRSI(rsi_period)

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "rsi_period":        {"type": "int",   "default": 14,   "min": 2,    "max": 50,   "step": 1},
            "oversold_level":    {"type": "float", "default": 30.0, "min": 10.0, "max": 50.0, "step": 1.0},
            "overbought_level":  {"type": "float", "default": 70.0, "min": 50.0, "max": 90.0, "step": 1.0},
            "profit_factor":     {"type": "float", "default": 0.02, "min": 0.001,"max": 0.10, "step": 0.001},
            "order_qty":         {"type": "float", "default": 1.0,  "min": 0.001,"max": 1000.0,"step": 0.001},
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        rsi = self._rsi.update(candle.close)
        if rsi is None:
            return []

        orders: list[dict[str, Any]] = []
        price = candle.close

        # TP from average entry
        if portfolio.is_long():
            avg_entry = portfolio.avg_entry_price()
            if avg_entry > 0.0 and price >= avg_entry * (1.0 + self.profit_factor):
                orders.append({"side": "SELL", "qty": portfolio.open_qty(),
                               "reason": "TAKE_PROFIT"})
                return orders

        # Mean reversion entries / exits
        if not portfolio.is_long() and rsi < self.oversold_level:
            orders.append({"side": "BUY", "qty": self.order_qty, "reason": "OVERSOLD"})
        elif portfolio.is_long() and rsi > self.overbought_level:
            orders.append({"side": "SELL", "qty": portfolio.open_qty(),
                           "reason": "OVERBOUGHT"})

        return orders
