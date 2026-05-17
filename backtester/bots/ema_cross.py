"""EMA Crossover trading bot — bracket-order edition (Phase 4).

What changed in Phase 4:
- Uses BRACKET orders at entry: SL + TP + (optional) trailing stop are
  attached to the BUY at the moment of entry, and fire INTRA-BAR via the
  engine's pending-order machinery. This is more realistic than checking
  stop / take-profit at each candle close (which under-reports drawdowns
  for fast moves).
- Optionally sizes by risk: with `use_risk_sizing=True`, the qty is chosen
  so that hitting the stop-loss costs `risk_per_trade_pct` of equity. Pro
  traders' default.
- Death-cross still triggers a MARKET sell (signal-based exit).
"""

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.core.engine import BacktestBot, Candle, Portfolio


class EMACross(BotBase):
    """EMA crossover strategy with bracket-order risk management.

    BUY on golden cross with attached stop-loss + take-profit (and optional
    trailing stop). SELL on death cross (market). The engine handles the
    intra-bar SL/TP triggering.
    """

    def __init__(
        self,
        fast_ema: int = 12,
        slow_ema: int = 26,
        profit_factor: float = 0.02,  # take_profit % above entry
        stop_loss_pct: float = 0.05,  # stop-loss % below entry
        risk_per_trade_pct: float = 2.0,  # used by calc_qty / size_by_risk
        trailing_stop_pct: float = 0.0,  # 0 = disabled. e.g. 3.0 = 3% trail.
        use_risk_sizing: bool = False,  # use size_by_risk instead of calc_qty
    ) -> None:
        self.fast_ema = fast_ema
        self.slow_ema = slow_ema
        self.profit_factor = profit_factor
        self.stop_loss_pct = stop_loss_pct
        self.risk_per_trade_pct = risk_per_trade_pct
        self.trailing_stop_pct = trailing_stop_pct
        self.use_risk_sizing = use_risk_sizing

        # Incremental EMA state (O(1) per candle)
        self._fast_ema: float | None = None
        self._slow_ema: float | None = None
        self._prev_fast: float | None = None
        self._prev_slow: float | None = None
        self._k_fast: float = 2.0 / (fast_ema + 1)
        self._k_slow: float = 2.0 / (slow_ema + 1)
        self._warmup_prices: list[float] = []
        self._warmed_up: bool = False

        self._in_position: bool = False

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        return {
            "fast_ema": {"type": "int", "default": 12, "min": 2, "max": 50, "step": 1},
            "slow_ema": {"type": "int", "default": 26, "min": 5, "max": 200, "step": 1},
            "profit_factor": {
                "type": "float",
                "default": 0.02,
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
            "trailing_stop_pct": {
                "type": "float",
                "default": 0.0,
                "min": 0.0,
                "max": 20.0,
                "step": 0.5,
            },
            "use_risk_sizing": {"type": "bool", "default": False},
        }

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        price = float(candle.close)
        orders: list[dict[str, Any]] = []

        # ── Warm-up phase: collect enough prices for SMA seed ────
        if not self._warmed_up:
            self._warmup_prices.append(price)
            if len(self._warmup_prices) >= self.slow_ema:
                # Seed both EMAs with their respective SMA
                fast_prices = self._warmup_prices[-self.fast_ema :]
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

        # ── Sync state with portfolio (in case a bracket SL/TP closed us) ──
        # Engine handles intra-bar SL/TP. If we thought we were in position
        # but the engine closed us, sync back so we can re-enter on the next
        # golden cross.
        if self._in_position and not portfolio.positions:
            self._in_position = False

        # ── Crossover signals ────────────────────────────────────
        if self._prev_fast is None or self._prev_slow is None:
            return orders

        golden = self._prev_fast <= self._prev_slow and self._fast_ema > self._slow_ema
        death = self._prev_fast >= self._prev_slow and self._fast_ema < self._slow_ema

        if golden and not self._in_position:
            # Pick sizing method
            if self.use_risk_sizing:
                qty = BacktestBot.size_by_risk(
                    portfolio,
                    current_price=candle.close,
                    stop_pct=self.stop_loss_pct * 100,  # convert to %
                    risk_pct=self.risk_per_trade_pct,
                )
            else:
                qty = self.calc_qty(candle.close, portfolio, self.risk_per_trade_pct)
            if qty > 0:
                # BRACKET order: BUY with attached SL + TP + optional trail
                order: dict[str, Any] = {
                    "side": "BUY",
                    "qty": float(qty),
                    "reason": "GOLDEN_CROSS",
                    "stop_loss_pct": self.stop_loss_pct * 100,
                    "take_profit_pct": self.profit_factor * 100,
                }
                if self.trailing_stop_pct > 0:
                    order["trailing_stop_pct"] = self.trailing_stop_pct
                orders.append(order)
                self._in_position = True

        elif death and self._in_position:
            qty = self.max_sell_qty(portfolio)
            if qty > 0:
                orders.append(
                    {"side": "SELL", "qty": float(qty), "reason": "DEATH_CROSS"}
                )
            self._in_position = False

        return orders
