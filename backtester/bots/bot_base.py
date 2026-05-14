"""Base class for trading bots."""

from abc import ABC, abstractmethod
from typing import Any

from backtester.core.engine import Candle, Portfolio


class BotBase(ABC):
    """Base class for trading bots."""

    @abstractmethod
    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        """
        Called on each new candle.

        Args:
            candle: Current candle
            portfolio: Current portfolio state

        Returns:
            List of orders, e.g.:
            [
                {"side": "BUY", "qty": 1.0},
                {"side": "SELL", "qty": 0.5}
            ]
        """

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        """Return parameter specification for UI editor.

        Returns:
            {
                "param_name": {
                    "type": "int" | "float" | "str",
                    "default": 10,
                    "min": 1,
                    "max": 100,
                    "step": 1
                }
            }
        """
        return {}
