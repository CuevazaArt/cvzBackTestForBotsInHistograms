"""EMA Crossover trading bot."""

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class EMACross(BotBase):
    """EMA crossover strategy: BUY when fast EMA > slow EMA, SELL when cross below."""

    def __init__(
        self,
        fast_ema: int = 12,
        slow_ema: int = 26,
        profit_factor: float = 0.02,
        stop_loss_pct: float = 0.05,
    ) -> None:
        self.fast_ema = fast_ema
        self.slow_ema = slow_ema
        self.profit_factor = profit_factor
        self.stop_loss_pct = stop_loss_pct
        self._prices = []
        self._fast_ema_value = None
        self._slow_ema_value = None
        self._entry_price = None
        self._in_position = False

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "fast_ema": {"type": "int", "default": 12, "min": 2, "max": 50, "step": 1},
            "slow_ema": {"type": "int", "default": 26, "min": 5, "max": 200, "step": 1},
            "profit_factor": {"type": "float", "default": 0.02, "min": 0.001, "max": 0.1, "step": 0.001},
            "stop_loss_pct": {"type": "float", "default": 0.05, "min": 0.01, "max": 0.5, "step": 0.01},
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        """EMA crossover logic."""
        self._prices.append(float(candle.close))
        if len(self._prices) < self.slow_ema:
            return []

        # Compute EMAs
        self._fast_ema_value = self._ema(self._prices, self.fast_ema)
        self._slow_ema_value = self._ema(self._prices, self.slow_ema)

        orders = []

        # Check stop loss
        if self._in_position and self._entry_price:
            stop_price = float(self._entry_price) * (1 - self.stop_loss_pct)
            if float(candle.close) < stop_price:
                orders.append({"side": "SELL", "qty": 1.0, "reason": "STOP_LOSS"})
                self._in_position = False
                self._entry_price = None

        # Check take profit
        if self._in_position and self._entry_price:
            tp_price = float(self._entry_price) * (1 + self.profit_factor)
            if float(candle.close) >= tp_price:
                orders.append({"side": "SELL", "qty": 1.0, "reason": "TAKE_PROFIT"})
                self._in_position = False
                self._entry_price = None

        # Check crossover
        if len(self._prices) >= self.slow_ema + 1:
            prev_fast = self._ema(self._prices[:-1], self.fast_ema)
            prev_slow = self._ema(self._prices[:-1], self.slow_ema)

            # Golden cross: fast crosses above slow
            if prev_fast <= prev_slow and self._fast_ema_value > self._slow_ema_value:
                if not self._in_position:
                    orders.append({"side": "BUY", "qty": 1.0, "reason": "GOLDEN_CROSS"})
                    self._in_position = True
                    self._entry_price = float(candle.close)

            # Death cross: fast crosses below slow
            elif prev_fast >= prev_slow and self._fast_ema_value < self._slow_ema_value:
                if self._in_position:
                    orders.append({"side": "SELL", "qty": 1.0, "reason": "DEATH_CROSS"})
                    self._in_position = False
                    self._entry_price = None

        return orders

    def _ema(self, prices: list[float], period: int) -> float:
        """Calculate EMA."""
        if len(prices) < period:
            return sum(prices) / len(prices)

        k = 2 / (period + 1)
        ema = sum(prices[:period]) / period
        for p in prices[period:]:
            ema = p * k + ema * (1 - k)
        return ema
