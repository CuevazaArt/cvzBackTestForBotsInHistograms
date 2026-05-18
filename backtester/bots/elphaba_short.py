"""ElphabaShort — ladder/DCA short strategy adapted from Pecunator.

Strategy:
  - On first candle with no position: SELL (short) a slot.
  - After a short, set a virtual BUY target at sell_price * (1 - profit_factor).
  - BUY (take profit) when price <= buy_target.
  - Re-SELL when price rises from last_sell_price by (profit_factor + margin_drop_factor),
    up to max_positions open simultaneously.
  - Stop-loss: if price rises above avg_cost * (1 + stop_loss_pct), liquidate all.
"""

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class ElphabaShort(BotBase):
    """Short DCA ladder strategy (mirror of Dorothy).

    Shorts on rallies from the last sell anchor and covers each rung at a
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

        self._last_sell_price: float | None = None
        self._buy_target: float | None = None
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
        # Filter only short positions
        n_open = sum(1 for p in portfolio.positions if p.side == "short")

        # ── Stop-loss: liquidate all if price too far above avg cost ──
        # stop_loss_pct <= 0 disables the protection entirely.
        if n_open > 0 and self.stop_loss_pct > 0:
            avg_cost = float(
                sum(
                    p.entry_price * p.qty
                    for p in portfolio.positions
                    if p.side == "short"
                )
                / sum(p.qty for p in portfolio.positions if p.side == "short")
            )
            if price > avg_cost * (1 + self.stop_loss_pct):
                qty = sum(p.qty for p in portfolio.positions if p.side == "short")
                if qty > 0:
                    orders.append(
                        {
                            "side": "BUY",
                            "action": "close_short",
                            "qty": float(qty),
                            "reason": "STOP_LOSS",
                        }
                    )
                self._last_sell_price = None
                self._buy_target = None
                return orders

        # ── Take profit: cover all when price drops to target ─────────
        if n_open > 0 and self._buy_target is not None:
            if price <= self._buy_target:
                qty = sum(p.qty for p in portfolio.positions if p.side == "short")
                if qty > 0:
                    orders.append(
                        {
                            "side": "BUY",
                            "action": "close_short",
                            "qty": float(qty),
                            "reason": "TAKE_PROFIT",
                        }
                    )
                self._last_sell_price = None
                self._buy_target = None
                return orders

        # ── Entry: first sell or DCA rally ────────────────────────────
        if n_open < self.max_positions:
            should_sell = False

            if self._last_sell_price is None:
                # No position yet — sell on first opportunity
                should_sell = True
            else:
                # DCA: sell when price rises enough from last anchor
                rally_threshold = self._last_sell_price * (
                    1 + (self.profit_factor + self.margin_drop_factor)
                )
                if price >= rally_threshold:
                    should_sell = True

            if should_sell:
                actual_usdt = min(float(portfolio.cash), self.quote_order_qty)
                sell_qty = actual_usdt / price if price > 0 else 0.0
                if sell_qty > 0:
                    orders.append(
                        {
                            "side": "SELL",
                            "action": "open_short",
                            "qty": sell_qty,
                            "reason": "DCA_SHORT",
                        }
                    )
                    self._last_sell_price = price
                    # Buy target is always relative to latest sell price
                    self._buy_target = price * (1 - self.profit_factor)

        return orders
