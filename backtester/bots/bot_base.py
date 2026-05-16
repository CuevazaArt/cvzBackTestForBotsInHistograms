"""Base class for trading bots with position sizing support."""

from abc import ABC, abstractmethod
from decimal import Decimal
from typing import Any

from backtester.core.engine import Candle, Portfolio


class BotBase(ABC):
    """Base class for trading bots.

    Subclasses implement `on_candle()` and optionally `param_spec()`.
    Position sizing helpers are provided here so bots don't need to
    hard-code qty=1.0.
    """

    # Default: risk 2% of available cash per trade.
    risk_per_trade_pct: float = 2.0

    @abstractmethod
    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        """Called on each new candle.

        Args:
            candle:    Current OHLCV candle.
            portfolio: Current portfolio state (cash, positions, …).

        Returns:
            List of order dicts, e.g.:
            [{"side": "BUY",  "qty": 0.05},
             {"side": "SELL", "qty": 0.05}]
        """

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        """Return parameter specification for the UI editor.

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

    # ── Sizing helpers ────────────────────────────────────────────

    def calc_qty(
        self,
        price: Decimal | float,
        portfolio: Portfolio,
        risk_pct: float | None = None,
    ) -> Decimal:
        """Calculate a safe BUY quantity based on available cash and risk %.

        Args:
            price:     Current price per unit (e.g. candle.close).
            portfolio: Portfolio containing available ``cash``.
            risk_pct:  Fraction of cash to risk, 0-100.
                       Falls back to ``self.risk_per_trade_pct``.

        Returns:
            Quantity (Decimal) that can be purchased, or Decimal("0") if
            cash is insufficient.
        """
        pct = Decimal(
            str(risk_pct if risk_pct is not None else self.risk_per_trade_pct)
        )
        price_d = Decimal(str(price))
        if price_d <= 0:
            return Decimal("0")
        capital_to_use = portfolio.cash * pct / Decimal("100")
        qty = capital_to_use / price_d
        # Round to 6 decimal places (standard precision for crypto)
        return qty.quantize(Decimal("0.000001"))

    def max_sell_qty(self, portfolio: Portfolio) -> Decimal:
        """Total quantity held across all open positions."""
        return sum((p.qty for p in portfolio.positions), start=Decimal("0"))

    @staticmethod
    def size_by_risk(
        portfolio: Portfolio,
        current_price: Decimal | float,
        stop_pct: Decimal | float,
        risk_pct: Decimal | float = Decimal("1.0"),
    ) -> Decimal:
        """Compute position size such that hitting the stop loses ``risk_pct`` of equity.

        Mirrors :meth:`backtester.core.engine.BacktestBot.size_by_risk` so that
        bots extending :class:`BotBase` (which is the public bot SDK base) can
        size positions by risk without having to import ``BacktestBot`` directly.

        Returns ``Decimal(0)`` if any input is non-positive.
        """
        eq = portfolio.total_equity(Decimal(str(current_price)))
        price = Decimal(str(current_price))
        sp = Decimal(str(stop_pct))
        rp = Decimal(str(risk_pct))
        if eq <= 0 or price <= 0 or sp <= 0 or rp <= 0:
            return Decimal(0)
        risk_amount = eq * rp / Decimal(100)
        loss_per_unit = price * sp / Decimal(100)
        if loss_per_unit <= 0:
            return Decimal(0)
        return (risk_amount / loss_per_unit).quantize(Decimal("0.00000001"))
