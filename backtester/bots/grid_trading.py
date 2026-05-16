"""Grid trading bot: equispaced buy/sell ladder between ``lower`` and ``upper``.

The bot precomputes ``num_levels`` equispaced prices between ``lower`` and
``upper``. Each level is either "empty" (no slice held from it) or "filled"
(we own one ``qty_per_level`` slice bought at that level). On every candle:

- For each EMPTY level the candle's low touched or crossed → submit BUY of
  ``qty_per_level`` and mark the level filled.
- For each FILLED level whose NEXT level up was touched or crossed by the
  candle's high → submit SELL of ``qty_per_level`` and mark the level empty.

If ``lower == upper == 0``, the range is auto-set on the very first candle
to ``[close * (1 - p), close * (1 + p)]`` where ``p = auto_range_pct / 100``.
A zero / unusable range disables the bot (no orders).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


@dataclass
class GridLevel:
    """One rung in the grid ladder."""

    price: float
    filled: bool = False


class GridTrading(BotBase):
    """Range-bound mean-reversion grid bot.

    Works best on sideways markets. Each filled level becomes a pending
    "sell at the next rung up" obligation; each empty level is a standing
    "buy if the price dips here" bid. The strategy is profitable when the
    price oscillates inside the configured band — every up-cross of one
    grid step pockets ``qty_per_level * grid_step`` of P&L.
    """

    def __init__(
        self,
        lower: float = 0.0,
        upper: float = 0.0,
        num_levels: int = 10,
        qty_per_level: float = 0.01,
        auto_range_pct: float = 0.0,
    ) -> None:
        self.lower = float(lower)
        self.upper = float(upper)
        self.num_levels = int(num_levels)
        self.qty_per_level = float(qty_per_level)
        self.auto_range_pct = float(auto_range_pct)

        self._levels: list[GridLevel] = []
        self._initialised: bool = False

        if self.lower > 0 and self.upper > self.lower and self.num_levels >= 2:
            self._init_levels(self.lower, self.upper)

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "lower": {
                "type": "float",
                "default": 0.0,
                "min": 0.0,
                "max": 1_000_000.0,
                "step": 0.01,
            },
            "upper": {
                "type": "float",
                "default": 0.0,
                "min": 0.0,
                "max": 1_000_000.0,
                "step": 0.01,
            },
            "num_levels": {
                "type": "int",
                "default": 10,
                "min": 2,
                "max": 100,
                "step": 1,
            },
            "qty_per_level": {
                "type": "float",
                "default": 0.01,
                "min": 0.0001,
                "max": 1000.0,
                "step": 0.001,
            },
            "auto_range_pct": {
                "type": "float",
                "default": 0.0,
                "min": 0.0,
                "max": 50.0,
                "step": 0.1,
            },
        }

    # ── Internal helpers ────────────────────────────────────────────

    def _init_levels(self, lower: float, upper: float) -> None:
        """Build the equispaced ladder. Called once."""
        if self.num_levels < 2 or upper <= lower:
            self._levels = []
            self._initialised = True
            return
        step = (upper - lower) / (self.num_levels - 1)
        # Round each rung to 8 decimals so a 10 % autorange around 100 doesn't
        # land at 110.00000000000001 due to binary-float drift.
        self._levels = [
            GridLevel(price=round(lower + i * step, 8)) for i in range(self.num_levels)
        ]
        self.lower = round(lower, 8)
        self.upper = round(upper, 8)
        self._initialised = True

    def _maybe_auto_range(self, first_close: float) -> None:
        """Configure ``[close*(1-p), close*(1+p)]`` if user left bounds at 0."""
        if self._initialised:
            return
        if self.lower == 0.0 and self.upper == 0.0 and self.auto_range_pct > 0.0:
            p = self.auto_range_pct / 100.0
            lo = round(first_close * (1.0 - p), 8)
            hi = round(first_close * (1.0 + p), 8)
            self._init_levels(lo, hi)
        else:
            self._initialised = True

    # ── Main loop ───────────────────────────────────────────────────

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        orders: list[dict[str, Any]] = []

        if not self._initialised:
            self._maybe_auto_range(float(candle.close))

        if not self._levels:
            return orders

        high = float(candle.high)
        low = float(candle.low)

        # Pre-check cash so we don't submit doomed BUYs (and would otherwise
        # have to also flip ``filled`` on/off to track engine rejections).
        # We approximate worst-case fill cost with the level price; the
        # engine still applies its own slippage/fee check on top.
        cash = float(portfolio.cash)

        for idx, level in enumerate(self._levels):
            # SELL: filled level whose NEXT rung up was touched.
            if level.filled and idx + 1 < len(self._levels):
                next_up = self._levels[idx + 1].price
                if high >= next_up:
                    orders.append(
                        {
                            "side": "SELL",
                            "qty": float(self.qty_per_level),
                            "reason": "GRID_SELL",
                        }
                    )
                    level.filled = False
                    continue

            # BUY: empty level the candle range straddled (low <= L <= high).
            # The high-side check ensures the candle actually *crossed* L
            # from above instead of starting (and staying) entirely below it
            # — that would mean L is no longer a "next dip" the price visits.
            if not level.filled and low <= level.price <= high:
                est_cost = self.qty_per_level * level.price
                if est_cost <= 0 or cash < est_cost:
                    continue
                orders.append(
                    {
                        "side": "BUY",
                        "qty": float(self.qty_per_level),
                        "reason": "GRID_BUY",
                    }
                )
                level.filled = True
                cash -= est_cost

        return orders
