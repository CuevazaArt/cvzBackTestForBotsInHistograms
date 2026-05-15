"""Bollinger Bands Mean-Reversion trading bot.

Modernised to the bracket-order API used by the other bots in this package
(legacy implementation called ``portfolio.buy/.sell`` and indexed positions
as a dict — neither exists on :class:`backtester.core.engine.Portfolio`).
"""

import math
from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class BollingerReversion(BotBase):
    """Bollinger Bands mean-reversion strategy.

    BUY when price drops below the lower band (oversold). The protective
    stop-loss / take-profit are attached as bracket children at the same
    moment so the engine fires them intra-bar.
    SELL when price reverts to the SMA (signal-driven exit).
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
        self._in_position: bool = False

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "bb_period": {
                "type": "int",
                "default": 20,
                "min": 5,
                "max": 100,
                "step": 1,
            },
            "std_dev_multiplier": {
                "type": "float",
                "default": 2.0,
                "min": 1.0,
                "max": 4.0,
                "step": 0.1,
            },
            "profit_factor": {
                "type": "float",
                "default": 0.03,
                "min": 0.001,
                "max": 0.5,
                "step": 0.001,
            },
            "stop_loss_pct": {
                "type": "float",
                "default": 0.05,
                "min": 0.005,
                "max": 0.5,
                "step": 0.005,
            },
            "risk_per_trade_pct": {
                "type": "float",
                "default": 2.0,
                "min": 0.5,
                "max": 20.0,
                "step": 0.5,
            },
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        price = float(candle.close)
        orders: list[dict[str, Any]] = []

        # Rolling window of floats so std calculations stay in float math.
        self._history.append(price)
        if len(self._history) > self.bb_period:
            self._history.pop(0)
        if len(self._history) < self.bb_period:
            return orders

        sma = sum(self._history) / self.bb_period
        variance = sum((x - sma) ** 2 for x in self._history) / self.bb_period
        std = math.sqrt(variance)
        lower_band = sma - self.std_dev_multiplier * std

        # Keep in-memory flag in sync with the engine in case a bracket
        # SL/TP closed the position.
        if self._in_position and not portfolio.positions:
            self._in_position = False

        if not self._in_position:
            if price < lower_band:
                qty = self.calc_qty(candle.close, portfolio, self.risk_per_trade_pct)
                if qty > 0:
                    orders.append(
                        {
                            "side": "BUY",
                            "qty": float(qty),
                            "reason": "BB_OVERSOLD",
                            "stop_loss_pct": self.stop_loss_pct * 100,
                            "take_profit_pct": self.profit_factor * 100,
                        }
                    )
                    self._in_position = True
            return orders

        # Mean-reversion exit: price recovers to the SMA.
        if price >= sma:
            qty = self.max_sell_qty(portfolio)
            if qty > 0:
                orders.append(
                    {
                        "side": "SELL",
                        "qty": float(qty),
                        "reason": "BB_MEAN_REVERT",
                    }
                )
                self._in_position = False
        return orders
