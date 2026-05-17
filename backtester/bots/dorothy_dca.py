"""DorothyDCA — ladder/DCA strategy adapted from Pecunator Dorothy v7.

Strategy:
  - On first candle with no position: BUY a slot.
  - After a buy, set a virtual SELL target at buy_price * (1 + profit_factor).
  - SELL (take profit) when price >= sell_target.
  - Re-BUY when price drops from last_buy_price by (profit_factor + margin_drop_factor),
    up to max_positions open simultaneously.
  - Stop-loss: if price drops below avg_cost * (1 - stop_loss_pct), liquidate all.
"""

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class DorothyDCA(BotBase):
    """DCA ladder strategy inspired by Pecunator Dorothy.

    Buys on dips from the last buy anchor and sells each rung at a
    fixed profit target. Multiple concurrent positions are allowed up
    to max_positions.
    """

    def __init__(
        self,
        profit_factor: float = 0.05,
        margin_drop_factor: float = 0.004,
        max_positions: int = 3,
        stop_loss_pct: float = 0.15,
        quote_order_qty: float = 7.0,
    ) -> None:
        self.profit_factor = profit_factor
        self.margin_drop_factor = margin_drop_factor
        self.max_positions = max_positions
        self.stop_loss_pct = stop_loss_pct
        self.quote_order_qty = quote_order_qty

        self._last_buy_price: float | None = None
        self._sell_target: float | None = None
        self._warmup_done: bool = False

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "profit_factor": {
                "type": "float",
                "default": 0.05,
                "min": 0.005,
                "max": 0.5,
                "step": 0.005,
            },
            "margin_drop_factor": {
                "type": "float",
                "default": 0.004,
                "min": 0.001,
                "max": 0.2,
                "step": 0.001,
            },
            "max_positions": {
                "type": "int",
                "default": 3,
                "min": 1,
                "max": 10,
                "step": 1,
            },
            "stop_loss_pct": {
                "type": "float",
                "default": 0.15,
                "min": 0.0,
                "max": 0.5,
                "step": 0.01,
            },
            "quote_order_qty": {
                "type": "float",
                "default": 7.0,
                "min": 1.0,
                "max": 1000.0,
                "step": 1.0,
            },
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        price = float(candle.close)
        orders: list[dict[str, Any]] = []
        n_open = len(portfolio.positions)

        # ── Stop-loss: liquidate all if price too far below avg cost ──
        # stop_loss_pct <= 0 disables the protection entirely.
        if n_open > 0 and self.stop_loss_pct > 0:
            avg_cost = float(
                sum(p.entry_price * p.qty for p in portfolio.positions)
                / sum(p.qty for p in portfolio.positions)
            )
            if price < avg_cost * (1 - self.stop_loss_pct):
                qty = self.max_sell_qty(portfolio)
                if qty > 0:
                    orders.append(
                        {"side": "SELL", "qty": float(qty), "reason": "STOP_LOSS"}
                    )
                self._last_buy_price = None
                self._sell_target = None
                return orders

        # ── Take profit: sell all when price reaches target ───────────
        if n_open > 0 and self._sell_target is not None:
            if price >= self._sell_target:
                qty = self.max_sell_qty(portfolio)
                if qty > 0:
                    orders.append(
                        {"side": "SELL", "qty": float(qty), "reason": "TAKE_PROFIT"}
                    )
                self._last_buy_price = None
                self._sell_target = None
                return orders

        # ── Entry: first buy or DCA dip ───────────────────────────────
        if n_open < self.max_positions:
            should_buy = False

            if self._last_buy_price is None:
                # No position yet — buy on first opportunity
                should_buy = True
            else:
                # DCA: buy when price drops enough from last anchor
                drop_threshold = self._last_buy_price * (
                    1 - (self.profit_factor + self.margin_drop_factor)
                )
                if price <= drop_threshold:
                    should_buy = True

            if should_buy:
                actual_usdt = min(float(portfolio.cash), self.quote_order_qty)
                qty = actual_usdt / price if price > 0 else 0.0
                if qty > 0:
                    orders.append(
                        {"side": "BUY", "qty": float(qty), "reason": "DCA_BUY"}
                    )
                    self._last_buy_price = price
                    # Sell target is always relative to latest buy price
                    self._sell_target = price * (1 + self.profit_factor)

        return orders
