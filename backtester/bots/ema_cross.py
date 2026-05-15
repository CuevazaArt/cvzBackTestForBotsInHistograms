"""EMA Crossover trading bot — production-quality version.

Fixes vs previous version:
- Uses ``calc_qty()`` from BotBase (position sizing based on % of cash).
- EMA computed incrementally: O(1) per candle, not O(n).
- Sells the *full* held position (not a hardcoded qty=1.0).
- ``risk_per_trade_pct`` exposed as a configurable param.
"""

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class EMACross(BotBase):
    """EMA crossover strategy.

    BUY when fast EMA crosses above slow EMA (golden cross).
    SELL (full position) when fast EMA crosses below slow EMA (death cross),
    stop-loss, or take-profit triggers.
    """

    def __init__(
        self,
        fast_ema: int = 12,
        slow_ema: int = 26,
        profit_factor: float = 0.02,
        stop_loss_pct: float = 0.05,
        risk_per_trade_pct: float = 2.0,
    ) -> None:
        self.fast_ema = fast_ema
        self.slow_ema = slow_ema
        self.profit_factor = profit_factor
        self.stop_loss_pct = stop_loss_pct
        self.risk_per_trade_pct = risk_per_trade_pct

        # Incremental EMA state (O(1) per candle)
        self._fast_ema: float | None = None
        self._slow_ema: float | None = None
        self._prev_fast: float | None = None
        self._prev_slow: float | None = None
        self._k_fast: float = 2.0 / (fast_ema + 1)
        self._k_slow: float = 2.0 / (slow_ema + 1)
        self._warmup_prices: list[float] = []
        self._warmed_up: bool = False

        self._entry_price: float | None = None
        self._in_position: bool = False

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "fast_ema": {"type": "int", "default": 12, "min": 2, "max": 50, "step": 1},
            "slow_ema": {"type": "int", "default": 26, "min": 5, "max": 200, "step": 1},
            "profit_factor": {"type": "float", "default": 0.02, "min": 0.001, "max": 0.5, "step": 0.001},
            "stop_loss_pct": {"type": "float", "default": 0.05, "min": 0.005, "max": 0.5, "step": 0.005},
            "risk_per_trade_pct": {"type": "float", "default": 2.0, "min": 0.5, "max": 20.0, "step": 0.5},
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        price = float(candle.close)
        orders: list[dict[str, Any]] = []

        # ── Warm-up phase: collect enough prices for SMA seed ────
        if not self._warmed_up:
            self._warmup_prices.append(price)
            if len(self._warmup_prices) >= self.slow_ema:
                # Seed both EMAs with their respective SMA
                fast_prices = self._warmup_prices[-self.fast_ema:]
                self._fast_ema = sum(fast_prices) / len(fast_prices)
                self._slow_ema = sum(self._warmup_prices) / len(self._warmup_prices)
                self._prev_fast = self._fast_ema
                self._prev_slow = self._slow_ema
                self._warmed_up = True
            return orders

        # ── Incremental EMA update (O(1)) ────────────────────────
        self._prev_fast = self._fast_ema
        self._prev_slow = self._slow_ema
        self._fast_ema = price * self._k_fast + self._fast_ema * (1 - self._k_fast)
        self._slow_ema = price * self._k_slow + self._slow_ema * (1 - self._k_slow)

        # ── Stop-loss ────────────────────────────────────────────
        if self._in_position and self._entry_price is not None:
            stop_price = self._entry_price * (1 - self.stop_loss_pct)
            if price < stop_price:
                qty = self.max_sell_qty(portfolio)
                if qty > 0:
                    orders.append({"side": "SELL", "qty": float(qty), "reason": "STOP_LOSS"})
                self._in_position = False
                self._entry_price = None
                return orders  # No more signals this candle

        # ── Take-profit ──────────────────────────────────────────
        if self._in_position and self._entry_price is not None:
            tp_price = self._entry_price * (1 + self.profit_factor)
            if price >= tp_price:
                qty = self.max_sell_qty(portfolio)
                if qty > 0:
                    orders.append({"side": "SELL", "qty": float(qty), "reason": "TAKE_PROFIT"})
                self._in_position = False
                self._entry_price = None
                return orders

        # ── Crossover signals ────────────────────────────────────
        if self._prev_fast is None or self._prev_slow is None:
            return orders

        golden = self._prev_fast <= self._prev_slow and self._fast_ema > self._slow_ema
        death  = self._prev_fast >= self._prev_slow and self._fast_ema < self._slow_ema

        if golden and not self._in_position:
            qty = self.calc_qty(candle.close, portfolio, self.risk_per_trade_pct)
            if qty > 0:
                orders.append({"side": "BUY", "qty": float(qty), "reason": "GOLDEN_CROSS"})
                self._in_position = True
                self._entry_price = price

        elif death and self._in_position:
            qty = self.max_sell_qty(portfolio)
            if qty > 0:
                orders.append({"side": "SELL", "qty": float(qty), "reason": "DEATH_CROSS"})
            self._in_position = False
            self._entry_price = None

        return orders
