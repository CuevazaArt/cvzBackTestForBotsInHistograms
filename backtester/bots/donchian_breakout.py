"""Donchian channel breakout bot with ATR-based trailing stop.

Classic trend-following recipe popularised by the Turtles:
- BUY when the close pushes above the PRIOR N-bar high (breakout).
- Exit when price falls below ``entry - atr_mult * ATR`` (volatility-scaled
  trailing stop measured from the entry).

The channel high/low is computed from the previous ``channel_len`` bars
(not including the current one) so the signal is not look-ahead biased.
ATR uses Wilder's true-range definition and a simple rolling mean over
``atr_len`` bars (cheap O(1) updates via a deque).
"""

from __future__ import annotations

from collections import deque
from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import Candle, Portfolio


class DonchianBreakout(BotBase):
    """Donchian breakout strategy with ATR trailing stop.

    State carried across candles:
        - rolling ``channel_len`` window of (high, low) for the channel
        - rolling ``atr_len`` window of true-range values for ATR
        - previous close (needed by the TR formula)
        - last computed ATR
        - entry price + ATR at entry (the trailing stop is fixed off the
          entry per the spec; volatility is locked in at fill time)
    """

    def __init__(
        self,
        channel_len: int = 20,
        atr_len: int = 14,
        atr_mult: float = 2.0,
        risk_per_trade_pct: float = 1.0,
    ) -> None:
        self.channel_len = int(channel_len)
        self.atr_len = int(atr_len)
        self.atr_mult = float(atr_mult)
        self.risk_per_trade_pct = float(risk_per_trade_pct)

        self._channel: deque[tuple[float, float]] = deque(maxlen=self.channel_len)
        self._tr_window: deque[float] = deque(maxlen=self.atr_len)
        self._prev_close: float | None = None
        self._atr: float | None = None

        self._in_position: bool = False
        self._entry_price: float | None = None
        self._atr_at_entry: float | None = None

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "channel_len": {
                "type": "int",
                "default": 20,
                "min": 5,
                "max": 200,
                "step": 1,
            },
            "atr_len": {
                "type": "int",
                "default": 14,
                "min": 5,
                "max": 100,
                "step": 1,
            },
            "atr_mult": {
                "type": "float",
                "default": 2.0,
                "min": 0.5,
                "max": 10.0,
                "step": 0.1,
            },
            "risk_per_trade_pct": {
                "type": "float",
                "default": 1.0,
                "min": 0.1,
                "max": 20.0,
                "step": 0.1,
            },
        }

    def _channel_high(self) -> float | None:
        """High of the rolling window BEFORE the current candle is added."""
        if not self._channel:
            return None
        return max(h for h, _ in self._channel)

    def _channel_low(self) -> float | None:
        if not self._channel:
            return None
        return min(low for _, low in self._channel)

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        high = float(candle.high)
        low = float(candle.low)
        close = float(candle.close)
        orders: list[dict[str, Any]] = []

        # ── ATR (Wilder true range, simple rolling mean) ─────────
        if self._prev_close is None:
            tr = high - low
        else:
            tr = max(
                high - low, abs(high - self._prev_close), abs(low - self._prev_close)
            )
        self._tr_window.append(tr)
        if len(self._tr_window) >= self.atr_len:
            self._atr = sum(self._tr_window) / len(self._tr_window)

        # Sync in-memory flag with the actual portfolio in case an external
        # exit (e.g. circuit breaker) closed the position behind our back.
        if self._in_position and not portfolio.positions:
            self._in_position = False
            self._entry_price = None
            self._atr_at_entry = None

        # ── Trailing-stop exit ───────────────────────────────────
        if (
            self._in_position
            and self._entry_price is not None
            and self._atr_at_entry is not None
        ):
            stop = self._entry_price - self.atr_mult * self._atr_at_entry
            if close < stop:
                qty = self.max_sell_qty(portfolio)
                if qty > 0:
                    orders.append(
                        {
                            "side": "SELL",
                            "qty": float(qty),
                            "reason": "ATR_TRAIL_STOP",
                        }
                    )
                self._in_position = False
                self._entry_price = None
                self._atr_at_entry = None

        # ── Breakout entry (uses PRIOR N-bar high — no look-ahead) ──
        prior_high = (
            self._channel_high() if len(self._channel) >= self.channel_len else None
        )

        if (
            not self._in_position
            and prior_high is not None
            and self._atr is not None
            and close > prior_high
        ):
            qty = self.calc_qty(candle.close, portfolio, self.risk_per_trade_pct)
            if qty > 0:
                orders.append(
                    {
                        "side": "BUY",
                        "qty": float(qty),
                        "reason": "DONCHIAN_BREAKOUT",
                    }
                )
                self._in_position = True
                self._entry_price = close
                self._atr_at_entry = self._atr

        # ── Update channel window AFTER the signal so today's bar
        #    doesn't influence its own breakout reference. ──────
        self._channel.append((high, low))
        self._prev_close = close

        return orders
