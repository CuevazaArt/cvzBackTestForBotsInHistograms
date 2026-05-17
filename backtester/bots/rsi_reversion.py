"""RSI Mean-Reversion trading bot — production-quality version.

Fixes vs previous version:
- Uses ``calc_qty()`` from BotBase (position sizing based on % of cash).
- RSI computed with Wilder's smoothing (proper SMMA), not simple average.
- Sells the *full* held position instead of hardcoded qty=1.0.
- ``risk_per_trade_pct`` exposed as a configurable param.
"""

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class RSIReversion(BotBase):
    """RSI-based mean reversion strategy.

    BUY when RSI drops below ``oversold_level``.
    SELL (full position) when RSI rises above ``overbought_level`` or
    take-profit triggers.
    """

    def __init__(
        self,
        rsi_period: int = 14,
        oversold_level: float = 30.0,
        overbought_level: float = 70.0,
        profit_factor: float = 0.03,
        stop_loss_pct: float = 0.05,
        risk_per_trade_pct: float = 2.0,
    ) -> None:
        self.rsi_period = rsi_period
        self.oversold_level = oversold_level
        self.overbought_level = overbought_level
        self.profit_factor = profit_factor
        self.stop_loss_pct = stop_loss_pct
        self.risk_per_trade_pct = risk_per_trade_pct

        # Wilder's SMMA state
        self._avg_gain: float | None = None
        self._avg_loss: float | None = None
        self._prev_price: float | None = None
        self._warmup_changes: list[tuple[float, float]] = []
        self._warmed_up: bool = False
        self._rsi_value: float | None = None

        self._entry_price: float | None = None
        self._in_position: bool = False

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "rsi_period": {
                "type": "int",
                "default": 14,
                "min": 2,
                "max": 50,
                "step": 1,
            },
            "oversold_level": {
                "type": "float",
                "default": 30.0,
                "min": 10.0,
                "max": 50.0,
                "step": 1.0,
            },
            "overbought_level": {
                "type": "float",
                "default": 70.0,
                "min": 50.0,
                "max": 90.0,
                "step": 1.0,
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
                "min": 0.0,
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

        # ── RSI calculation (Wilder's SMMA) ──────────────────────
        if self._prev_price is not None:
            change = price - self._prev_price
            gain = max(change, 0.0)
            loss = max(-change, 0.0)

            if not self._warmed_up:
                self._warmup_changes.append((gain, loss))
                if len(self._warmup_changes) >= self.rsi_period:
                    # Seed with simple averages
                    self._avg_gain = (
                        sum(g for g, _ in self._warmup_changes) / self.rsi_period
                    )
                    self._avg_loss = (
                        sum(loss_val for _, loss_val in self._warmup_changes)
                        / self.rsi_period
                    )
                    self._warmed_up = True
            else:
                # Wilder's smoothing
                self._avg_gain = (
                    self._avg_gain * (self.rsi_period - 1) + gain
                ) / self.rsi_period
                self._avg_loss = (
                    self._avg_loss * (self.rsi_period - 1) + loss
                ) / self.rsi_period

            if self._warmed_up and self._avg_loss and self._avg_loss > 0:
                rs = self._avg_gain / self._avg_loss
                self._rsi_value = 100.0 - (100.0 / (1.0 + rs))
            elif self._warmed_up:
                self._rsi_value = 100.0  # No losses = overbought

        self._prev_price = price

        if self._rsi_value is None:
            return orders

        # ── Stop-loss (skipped when stop_loss_pct <= 0) ─────────
        if (
            self._in_position
            and self._entry_price is not None
            and self.stop_loss_pct > 0
        ):
            stop_price = self._entry_price * (1 - self.stop_loss_pct)
            if price < stop_price:
                qty = self.max_sell_qty(portfolio)
                if qty > 0:
                    orders.append(
                        {"side": "SELL", "qty": float(qty), "reason": "STOP_LOSS"}
                    )
                self._in_position = False
                self._entry_price = None
                return orders

        # ── Take-profit ──────────────────────────────────────────
        if self._in_position and self._entry_price is not None:
            tp_price = self._entry_price * (1 + self.profit_factor)
            if price >= tp_price:
                qty = self.max_sell_qty(portfolio)
                if qty > 0:
                    orders.append(
                        {"side": "SELL", "qty": float(qty), "reason": "TAKE_PROFIT"}
                    )
                self._in_position = False
                self._entry_price = None
                return orders

        # ── RSI signals ──────────────────────────────────────────
        if not self._in_position and self._rsi_value < self.oversold_level:
            qty = self.calc_qty(candle.close, portfolio, self.risk_per_trade_pct)
            if qty > 0:
                orders.append({"side": "BUY", "qty": float(qty), "reason": "OVERSOLD"})
                self._in_position = True
                self._entry_price = price

        elif self._in_position and self._rsi_value > self.overbought_level:
            qty = self.max_sell_qty(portfolio)
            if qty > 0:
                orders.append(
                    {"side": "SELL", "qty": float(qty), "reason": "OVERBOUGHT"}
                )
            self._in_position = False
            self._entry_price = None

        return orders
