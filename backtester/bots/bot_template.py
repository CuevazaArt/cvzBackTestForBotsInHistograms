"""Copy this file to ``my_strategy.py`` and register the class in ``registry.py``.

This module is NOT imported by the backtester. It is documentation-as-code.

Integration checklist:
  1. Subclass ``BotBase`` and put all logic in ``on_candle``.
  2. Expose tunables via ``param_spec()`` (UI only — enforce limits in your code).
  3. Add ``from backtester.bots.my_strategy import MyStrategy`` to ``registry.py``
     and append ``MyStrategy`` to ``_BOT_CLASSES``.
  4. Add tests under ``backtester/tests/`` (see ``test_bot_registry.py``).
  5. Do not put ``stop_loss_pct`` / ``take_profit_pct`` on BUY orders unless you
     want the engine's bracket machinery (use explicit SELL logic instead).
"""

from __future__ import annotations

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class ExampleTemplateBot(BotBase):
    """Minimal mean-reversion sketch — replace with your own rules."""

    def __init__(self, lookback: int = 20, entry_z: float = -2.0, exit_z: float = 2.0):
        if lookback < 2:
            raise ValueError("lookback must be >= 2")
        self.lookback = lookback
        self.entry_z = entry_z
        self.exit_z = exit_z
        self._closes: list[float] = []
        self._in_position = False

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "lookback": {"type": "int", "default": 20, "min": 2, "max": 500, "step": 1},
            "entry_z": {
                "type": "float",
                "default": -2.0,
                "min": -10.0,
                "max": 0.0,
                "step": 0.1,
            },
            "exit_z": {
                "type": "float",
                "default": 2.0,
                "min": 0.0,
                "max": 10.0,
                "step": 0.1,
            },
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        price = float(candle.close)
        self._closes.append(price)
        if len(self._closes) > self.lookback:
            self._closes.pop(0)
        if len(self._closes) < self.lookback:
            return []

        mean = sum(self._closes) / len(self._closes)
        var = sum((x - mean) ** 2 for x in self._closes) / len(self._closes)
        std = var**0.5 or 1e-9
        z = (price - mean) / std

        orders: list[dict[str, Any]] = []

        if not self._in_position and z <= self.entry_z:
            qty = self.calc_qty(candle.close, portfolio)
            if qty > 0:
                orders.append({"side": "BUY", "qty": float(qty), "reason": "ENTRY"})
                self._in_position = True
        elif self._in_position and z >= self.exit_z:
            qty = self.max_sell_qty(portfolio)
            if qty > 0:
                orders.append({"side": "SELL", "qty": float(qty), "reason": "EXIT"})
                self._in_position = False

        return orders
