"""Bollinger Bands Mean-Reversion trading bot."""

import math
from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class BollingerReversion(BotBase):
    """Bollinger Bands mean-reversion strategy.

    BUY when price drops below the lower band (oversold).
    SELL when price reverts to the mean (SMA) or upper band,
    or via take-profit/stop-loss.
    """

    def __init__(
        self,
        bb_period: int = 20,
        std_dev_multiplier: float = 2.0,
        profit_factor: float = 0.03,
        stop_loss_pct: float = 0.05,
        risk_per_trade_pct: float = 2.0,
    ) -> None:
        self.bb_period = bb_period
        self.std_dev_multiplier = std_dev_multiplier
        self.profit_factor = profit_factor
        self.stop_loss_pct = stop_loss_pct
        self.risk_per_trade_pct = risk_per_trade_pct

        self._history: list[float] = []
        self._entry_price: float | None = None
        self._in_position: bool = False

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "bb_period": {"type": "int", "default": 20, "min": 5, "max": 100, "step": 1},
            "std_dev_multiplier": {"type": "float", "default": 2.0, "min": 1.0, "max": 4.0, "step": 0.1},
            "profit_factor": {"type": "float", "default": 0.03, "min": 0.001, "max": 0.5, "step": 0.001},
            "stop_loss_pct": {"type": "float", "default": 0.05, "min": 0.005, "max": 0.5, "step": 0.005},
            "risk_per_trade_pct": {"type": "float", "default": 2.0, "min": 0.5, "max": 20.0, "step": 0.5},
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> None:
        price = candle.close

        # Update rolling history
        self._history.append(price)
        if len(self._history) > self.bb_period:
            self._history.pop(0)

        if len(self._history) < self.bb_period:
            return  # Not enough data for BB calculation

        # Calculate SMA
        sma = sum(self._history) / self.bb_period

        # Calculate Standard Deviation
        variance = sum((x - sma) ** 2 for x in self._history) / self.bb_period
        std_dev = math.sqrt(variance)

        lower_band = sma - (self.std_dev_multiplier * std_dev)

        if not self._in_position:
            # Entry condition: Price dips below lower band
            if price < lower_band:
                qty = self.calc_qty(price, float(portfolio.cash), self.risk_per_trade_pct)
                if qty > 0:
                    portfolio.buy(self.__class__.__name__, price, qty, candle.timestamp_ms)
                    self._entry_price = price
                    self._in_position = True

        else:
            # Exit conditions
            if self._entry_price is None:
                return

            gain_pct = (price - self._entry_price) / self._entry_price

            # Mean reversion achieved (price hits SMA), or Stop Loss, or Take Profit
            if price >= sma or gain_pct >= self.profit_factor or gain_pct <= -self.stop_loss_pct:
                pos = portfolio.positions.get(self.__class__.__name__)
                if pos and pos > 0:
                    portfolio.sell(self.__class__.__name__, price, pos, candle.timestamp_ms)
                self._in_position = False
                self._entry_price = None

    def get_state(self) -> dict[str, Any]:
        return {
            "bb_period": self.bb_period,
            "std_dev_multiplier": self.std_dev_multiplier,
            "in_position": self._in_position,
            "history_len": len(self._history),
        }
