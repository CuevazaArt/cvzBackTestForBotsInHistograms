"""MACDCross — MACD signal-line crossover strategy.

Entry / exit:
  BUY  when MACD line crosses above the Signal line (bullish cross).
  SELL when MACD line crosses below the Signal line (bearish cross),
       or when stop-loss / take-profit is triggered.

All EMAs are computed incrementally (O(1) per candle).
"""

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class MACDCross(BotBase):
    """MACD signal-line crossover strategy.

    Buys on bullish MACD cross and sells on bearish cross or TP/SL.
    """

    def __init__(
        self,
        fast_ema: int = 12,
        slow_ema: int = 26,
        signal_period: int = 9,
        profit_factor: float = 0.04,
        stop_loss_pct: float = 0.05,
        risk_per_trade_pct: float = 2.0,
    ) -> None:
        self.fast_ema = fast_ema
        self.slow_ema = slow_ema
        self.signal_period = signal_period
        self.profit_factor = profit_factor
        self.stop_loss_pct = stop_loss_pct
        self.risk_per_trade_pct = risk_per_trade_pct

        # EMA multipliers
        self._k_fast = 2.0 / (fast_ema + 1)
        self._k_slow = 2.0 / (slow_ema + 1)
        self._k_sig  = 2.0 / (signal_period + 1)

        # Running state
        self._ema_fast: float | None = None
        self._ema_slow: float | None = None
        self._macd: float | None = None
        self._signal: float | None = None
        self._prev_macd: float | None = None
        self._prev_signal: float | None = None

        self._warmup: list[float] = []
        self._warmed_up = False
        self._macd_history: list[float] = []   # for signal warm-up

        self._in_position = False
        self._entry_price: float | None = None

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "fast_ema":          {"type": "int",   "default": 12,  "min": 2,   "max": 50,   "step": 1},
            "slow_ema":          {"type": "int",   "default": 26,  "min": 5,   "max": 200,  "step": 1},
            "signal_period":     {"type": "int",   "default": 9,   "min": 2,   "max": 50,   "step": 1},
            "profit_factor":     {"type": "float", "default": 0.04, "min": 0.005, "max": 0.5, "step": 0.005},
            "stop_loss_pct":     {"type": "float", "default": 0.05, "min": 0.005, "max": 0.5, "step": 0.005},
            "risk_per_trade_pct":{"type": "float", "default": 2.0,  "min": 0.5,  "max": 20.0, "step": 0.5},
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        price = float(candle.close)
        orders: list[dict[str, Any]] = []

        # ── Phase 1: warm up slow EMA ─────────────────────────────────
        if not self._warmed_up:
            self._warmup.append(price)
            if len(self._warmup) == self.slow_ema:
                self._ema_slow = sum(self._warmup) / len(self._warmup)
                self._ema_fast = sum(self._warmup[-self.fast_ema:]) / self.fast_ema
                self._warmed_up = True
            return orders

        # ── Phase 2: update fast/slow EMAs ───────────────────────────
        self._ema_fast = price * self._k_fast + self._ema_fast * (1 - self._k_fast)
        self._ema_slow = price * self._k_slow + self._ema_slow * (1 - self._k_slow)
        macd_val = self._ema_fast - self._ema_slow

        # ── Phase 3: warm up signal EMA with MACD history ─────────────
        if self._signal is None:
            self._macd_history.append(macd_val)
            if len(self._macd_history) >= self.signal_period:
                self._signal = sum(self._macd_history) / len(self._macd_history)
                self._macd = macd_val
            return orders

        # ── Phase 4: update signal ────────────────────────────────────
        self._prev_macd   = self._macd
        self._prev_signal = self._signal
        self._macd   = macd_val
        self._signal = macd_val * self._k_sig + self._signal * (1 - self._k_sig)

        # ── Stop-loss ─────────────────────────────────────────────────
        if self._in_position and self._entry_price is not None:
            if price < self._entry_price * (1 - self.stop_loss_pct):
                qty = self.max_sell_qty(portfolio)
                if qty > 0:
                    orders.append({"side": "SELL", "qty": float(qty), "reason": "STOP_LOSS"})
                self._in_position = False
                self._entry_price = None
                return orders

        # ── Take-profit ───────────────────────────────────────────────
        if self._in_position and self._entry_price is not None:
            if price >= self._entry_price * (1 + self.profit_factor):
                qty = self.max_sell_qty(portfolio)
                if qty > 0:
                    orders.append({"side": "SELL", "qty": float(qty), "reason": "TAKE_PROFIT"})
                self._in_position = False
                self._entry_price = None
                return orders

        # ── Crossover signals ─────────────────────────────────────────
        if self._prev_macd is None or self._prev_signal is None:
            return orders

        bull_cross = self._prev_macd <= self._prev_signal and self._macd > self._signal
        bear_cross = self._prev_macd >= self._prev_signal and self._macd < self._signal

        if bull_cross and not self._in_position:
            qty = self.calc_qty(candle.close, portfolio, self.risk_per_trade_pct)
            if qty > 0:
                orders.append({"side": "BUY", "qty": float(qty), "reason": "BULL_CROSS"})
                self._in_position = True
                self._entry_price = price

        elif bear_cross and self._in_position:
            qty = self.max_sell_qty(portfolio)
            if qty > 0:
                orders.append({"side": "SELL", "qty": float(qty), "reason": "BEAR_CROSS"})
            self._in_position = False
            self._entry_price = None

        return orders
