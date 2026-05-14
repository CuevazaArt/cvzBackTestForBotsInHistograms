"""RSI Reversion trading bot."""

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class RSIReversion(BotBase):
    """RSI-based mean reversion: BUY at oversold, SELL at overbought."""

    def __init__(
        self,
        rsi_period: int = 14,
        oversold_level: float = 30.0,
        overbought_level: float = 70.0,
        profit_factor: float = 0.02,
    ) -> None:
        self.rsi_period = rsi_period
        self.oversold_level = oversold_level
        self.overbought_level = overbought_level
        self.profit_factor = profit_factor
        self._prices = []
        self._rsi_value = None
        self._entry_price = None
        self._in_position = False

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "rsi_period": {"type": "int", "default": 14, "min": 2, "max": 50, "step": 1},
            "oversold_level": {"type": "float", "default": 30.0, "min": 10.0, "max": 50.0, "step": 1.0},
            "overbought_level": {"type": "float", "default": 70.0, "min": 50.0, "max": 90.0, "step": 1.0},
            "profit_factor": {"type": "float", "default": 0.02, "min": 0.001, "max": 0.1, "step": 0.001},
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        """RSI reversion logic."""
        self._prices.append(float(candle.close))
        if len(self._prices) < self.rsi_period + 1:
            return []

        self._rsi_value = self._rsi(self._prices, self.rsi_period)
        orders = []

        # Check take profit
        if self._in_position and self._entry_price:
            tp_price = float(self._entry_price) * (1 + self.profit_factor)
            if float(candle.close) >= tp_price:
                orders.append({"side": "SELL", "qty": 1.0, "reason": "TAKE_PROFIT"})
                self._in_position = False
                self._entry_price = None

        # BUY at oversold
        if not self._in_position and self._rsi_value < self.oversold_level:
            orders.append({"side": "BUY", "qty": 1.0, "reason": "OVERSOLD"})
            self._in_position = True
            self._entry_price = float(candle.close)

        # SELL at overbought
        if self._in_position and self._rsi_value > self.overbought_level:
            orders.append({"side": "SELL", "qty": 1.0, "reason": "OVERBOUGHT"})
            self._in_position = False
            self._entry_price = None

        return orders

    def _rsi(self, prices: list[float], period: int) -> float:
        """Calculate RSI."""
        if len(prices) < period + 1:
            return 50.0

        deltas = [prices[i] - prices[i - 1] for i in range(1, len(prices))]
        ups = [d for d in deltas[-period:] if d > 0]
        downs = [-d for d in deltas[-period:] if d < 0]

        avg_up = sum(ups) / period if ups else 0
        avg_down = sum(downs) / period if downs else 0

        rs = avg_up / avg_down if avg_down > 0 else 0
        rsi = 100 - (100 / (1 + rs)) if rs > 0 else 50

        return rsi
