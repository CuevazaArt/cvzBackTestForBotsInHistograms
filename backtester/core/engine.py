"""Realistic backtest engine with fees and slippage simulation."""

from __future__ import annotations

import itertools
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Any, Optional

from backtester.core.orders import (
    OrderSide,
    OrderType,
    PendingOrder,
    TriggerReason,
    limit_triggers,
    parse_order_dict,
    stop_triggers,
    update_trailing_anchor,
)

_LOG = logging.getLogger("backtester.engine")

# Monotonic id generator for Position objects so bracket children can
# reference their parent without object-identity coupling.
_POSITION_ID = itertools.count(1)


@dataclass
class Candle:
    """Single OHLCV candle."""

    timestamp_ms: int
    open: Decimal
    high: Decimal
    low: Decimal
    close: Decimal
    volume: Decimal

    @classmethod
    def from_dict(cls, d: dict) -> "Candle":
        """Create from database row or API response."""
        return cls(
            timestamp_ms=int(d["timestamp_ms"]),
            open=Decimal(str(d["open"])),
            high=Decimal(str(d["high"])),
            low=Decimal(str(d["low"])),
            close=Decimal(str(d["close"])),
            volume=Decimal(str(d["volume"])),
        )


@dataclass
class Position:
    """Open trading position.

    Tracks Maximum Favorable Excursion (MFE) and Maximum Adverse Excursion (MAE)
    so closed trades can report how far in-favor / against the trade went before
    being closed. Useful for stop placement and trade quality analysis.
    """

    entry_price: Decimal
    qty: Decimal
    entry_idx: int
    entry_time: int
    bot_id: str = ""
    # Running excursion trackers (updated each candle while position is open)
    max_favorable_price: Decimal = Decimal("0")  # Highest price seen → MFE
    max_adverse_price: Decimal = Decimal("0")  # Lowest price seen  → MAE
    # Monotonic id so PendingOrder.parent_position_id can reference us.
    position_id: int = field(default_factory=lambda: next(_POSITION_ID))

    def update_excursion(self, high: Decimal, low: Decimal) -> None:
        """Update MFE/MAE trackers given the current candle's high/low.

        Initializes from entry_price on first call; subsequent calls expand
        the favorable/adverse extremes.
        """
        if self.max_favorable_price == 0:
            self.max_favorable_price = self.entry_price
            self.max_adverse_price = self.entry_price
        if high > self.max_favorable_price:
            self.max_favorable_price = high
        if low < self.max_adverse_price or self.max_adverse_price == 0:
            self.max_adverse_price = low


@dataclass
class Trade:
    """Closed trade record.

    Includes Maximum Favorable Excursion (MFE) and Maximum Adverse Excursion
    (MAE) — the highest unrealized profit and lowest unrealized loss reached
    while the position was open. Reported in absolute Decimal and as percent
    of entry price for easy comparison across symbols.

    `reason` captures the trigger that closed the position (STOP_LOSS,
    TAKE_PROFIT, TRAILING_STOP, LIMIT, MANUAL...). Useful for filtering
    "how many trades exited at stop vs. profit target" in analytics.
    """

    entry_price: Decimal
    exit_price: Decimal
    qty: Decimal
    entry_idx: int
    exit_idx: int
    entry_time: int
    exit_time: int
    pnl: Decimal
    pnl_pct: Decimal
    fee_usdt: Decimal
    reason: str
    bot_id: str = ""
    # Excursion stats (snapshot from Position at close time)
    mfe_pct: Decimal = Decimal("0")  # Max favorable excursion %
    mae_pct: Decimal = Decimal("0")  # Max adverse excursion % (negative)
    duration_bars: int = 0  # Number of bars position was held


@dataclass
class Portfolio:
    """Portfolio state.

    `pending_orders` holds LIMIT / STOP / STOP_LIMIT / TRAILING_STOP orders
    that are waiting for price triggers. They are scanned at the start of
    each bar BEFORE the bot's on_candle runs.
    """

    cash: Decimal = Decimal("10000")
    positions: list[Position] = field(default_factory=list)
    closed_trades: list[Trade] = field(default_factory=list)
    equity_curve: list[Decimal] = field(default_factory=list)
    pending_orders: list[PendingOrder] = field(default_factory=list)

    def total_equity(self, current_price: Decimal) -> Decimal:
        """Current portfolio value."""
        position_value = sum(p.qty * current_price for p in self.positions)
        return self.cash + position_value

    def open_position_cost(self) -> Decimal:
        """Total cost of open positions at current price."""
        return sum(p.qty * p.entry_price for p in self.positions)

    def cancel_orders_for_position(self, position_id: int) -> None:
        """Remove any pending child orders attached to a closed position.

        Called by the engine after a position closes so the lingering SL/TP
        orders from a bracket entry don't fire against unrelated future
        positions.
        """
        self.pending_orders = [
            po for po in self.pending_orders if po.parent_position_id != position_id
        ]


class BacktestBot(ABC):
    """Base class for backtest bots.

    Order dict shape (all keys optional except side, qty):
        {
            "side": "BUY" | "SELL",
            "qty": Decimal | float,
            "type": "MARKET" | "LIMIT" | "STOP" | "STOP_LIMIT" | "TRAILING_STOP",
            "limit_price": Decimal,   # LIMIT, STOP_LIMIT
            "stop_price": Decimal,    # STOP, STOP_LIMIT
            "trail_pct": Decimal,     # TRAILING_STOP (1.5 = 1.5%)
            # Bracket order shortcuts — only valid on entry orders:
            "stop_loss_price": Decimal,    # protective SELL at this price
            "stop_loss_pct": Decimal,      # protective SELL at entry*(1-pct/100)
            "take_profit_price": Decimal,  # protective SELL at this price
            "take_profit_pct": Decimal,    # protective SELL at entry*(1+pct/100)
            "trailing_stop_pct": Decimal,  # auto-attached TRAILING_STOP child
            "reason": str,
        }

    Legacy {"side": ..., "qty": ...} dicts work unchanged (treated as MARKET).
    """

    @abstractmethod
    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        """
        Called on each candle. See class docstring for the order dict shape.
        """

    @staticmethod
    def size_by_risk(
        portfolio: Portfolio,
        current_price: Decimal | float,
        stop_pct: Decimal | float,
        risk_pct: Decimal | float = Decimal("1.0"),
    ) -> Decimal:
        """Compute position size such that hitting the stop loses risk_pct of equity.

        Standard professional sizing: if equity = $10k, risk_pct = 1%, and
        stop_pct = 2% (you'd cut at 2% loss), then position notional = $5k
        (because a 2% move on $5k = $100 = 1% of equity).

        Returns Decimal(0) if any input is non-positive (caller can skip).
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


@dataclass
class BacktestConfig:
    """Backtest parameters.

    `max_drawdown_pct_halt`: if set and the global equity drawdown exceeds
    this %, the engine stops accepting new BUY orders (open positions can
    still close via stops/take-profits). Acts as a circuit breaker for
    "stop trading if losing X% of capital". None disables.
    """

    initial_cash: Decimal = Decimal("10000")
    taker_fee_pct: Decimal = Decimal("0.1")  # Binance default
    slippage_pct: Decimal = Decimal("0.05")  # Spread + impact
    max_position_qty: Optional[Decimal] = None  # None = unlimited
    max_drawdown_pct_halt: Optional[Decimal] = None  # circuit breaker


@dataclass
class BacktestResult:
    """Results of a backtest run."""

    symbol: str
    timeframe: str
    candles_processed: int
    trades: list[Trade] = field(default_factory=list)
    equity_curve: list[Decimal] = field(default_factory=list)
    final_equity: Decimal = Decimal("0")
    peak_equity: Decimal = Decimal("0")
    max_drawdown_pct: Decimal = Decimal("0")
    # Per-bot breakdown: {bot_id: {metric: value, ...}}
    per_bot: dict[str, dict[str, Any]] = field(default_factory=dict)

    def summary(self) -> dict[str, Any]:
        """Compute performance metrics."""
        initial = self.equity_curve[0] if self.equity_curve else Decimal("0")
        total_return = (
            ((self.final_equity - initial) / initial * 100) if initial > 0 else 0
        )

        closed = [t for t in self.trades if t.exit_idx is not None]
        winners = [t for t in closed if t.pnl > 0]
        losers = [t for t in closed if t.pnl < 0]

        win_rate = len(winners) / len(closed) * 100 if closed else 0
        avg_win = (
            sum(t.pnl for t in winners) / len(winners) if winners else Decimal("0")
        )
        avg_loss = sum(t.pnl for t in losers) / len(losers) if losers else Decimal("0")

        profit_factor = float(avg_win / abs(avg_loss)) if avg_loss != 0 else 0

        total_fees = sum(t.fee_usdt for t in closed)

        return {
            "total_return_pct": float(total_return),
            "trades": len(closed),
            "win_rate_pct": float(win_rate),
            "profit_factor": profit_factor,
            "max_drawdown_pct": float(self.max_drawdown_pct),
            "total_fees_usdt": float(total_fees),
            "final_equity": float(self.final_equity),
        }


def compute_max_drawdown_pct(equity_curve: list[Decimal]) -> Decimal:
    """Peak-to-trough max drawdown as a percentage."""
    if not equity_curve:
        return Decimal("0")
    max_dd = Decimal("0")
    running_peak = Decimal("0")
    for eq in equity_curve:
        if eq > running_peak:
            running_peak = eq
        if running_peak > 0:
            dd = (running_peak - eq) / running_peak
            if dd > max_dd:
                max_dd = dd
    return max_dd * 100


def build_per_bot_breakdown(
    names: list[str],
    portfolios: list["Portfolio"],
    capital_per_bot: Decimal,
    last_close: Decimal,
) -> dict[str, dict[str, Any]]:
    """Aggregate per-bot performance metrics for the BacktestResult."""
    breakdown: dict[str, dict[str, Any]] = {}
    for bot_id, portfolio in zip(names, portfolios):
        bot_trades = portfolio.closed_trades
        wins = [t for t in bot_trades if t.pnl > 0]
        gross_profit = sum(t.pnl for t in wins)
        gross_loss = abs(sum(t.pnl for t in bot_trades if t.pnl < 0))
        final_eq = float(portfolio.total_equity(last_close))
        breakdown[bot_id] = {
            "bot_id": bot_id,
            "trades": len(bot_trades),
            "wins": len(wins),
            "win_rate_pct": float(len(wins) / len(bot_trades) * 100)
            if bot_trades
            else 0.0,
            "total_return_pct": float(
                (final_eq - float(capital_per_bot)) / float(capital_per_bot) * 100
            ),
            "total_pnl": float(sum(t.pnl for t in bot_trades)),
            "total_fees_usdt": float(sum(t.fee_usdt for t in bot_trades)),
            "profit_factor": float(gross_profit / gross_loss)
            if gross_loss > 0
            else 0.0,
            "final_equity": final_eq,
            "initial_cash": float(capital_per_bot),
        }
    return breakdown


class BacktestEngine:
    """Backtest engine."""

    def __init__(self, config: BacktestConfig | None = None) -> None:
        self.config = config or BacktestConfig()

    def run(
        self,
        bots: "BacktestBot | list[BacktestBot]",
        candles: list[Candle],
        symbol: str = "",
        timeframe: str = "",
        indicator_specs: list[dict[str, Any]] | None = None,
        bot_names: list[str] | None = None,
    ) -> BacktestResult:
        """Run backtest.

        Each bot receives its own isolated Portfolio slice so individual
        performance can be measured independently.
        """
        if not isinstance(bots, list):
            bots = [bots]

        n = len(bots)
        if n == 0:
            return BacktestResult(
                symbol=symbol, timeframe=timeframe, candles_processed=0
            )

        capital_per_bot = self.config.initial_cash / Decimal(n)

        # Assign names
        names = list(bot_names or [])
        for i in range(len(names), n):
            names.append(f"{bots[i].__class__.__name__}_{i}")

        # One Portfolio per bot
        portfolios = [Portfolio(cash=capital_per_bot) for _ in range(n)]

        result = BacktestResult(
            symbol=symbol,
            timeframe=timeframe,
            candles_processed=len(candles),
        )

        for candle in candles:
            # Global circuit breaker: compute equity once per bar against the
            # candle's open and disable new entries if drawdown > threshold.
            new_entries_halted = self._circuit_breaker_tripped(
                portfolios, candle, result
            )

            for bot, portfolio, bot_id in zip(bots, portfolios, names):
                # 1. Update MFE/MAE BEFORE anything else so positions closed
                #    on this bar capture its full high/low range.
                for pos in portfolio.positions:
                    pos.update_excursion(candle.high, candle.low)

                # 2. Check pending orders FIRST (with the PREVIOUS bar's
                #    trailing-stop level). Industry-standard "favorable to
                #    trader" convention: trailing stops only ratchet at the
                #    END of a bar, so a same-bar ratchet-and-fire is avoided.
                self._process_pending_orders(candle, portfolio, result, bot_id=bot_id)

                # 3. NOW ratchet any surviving trailing stops for the NEXT bar.
                for po in portfolio.pending_orders:
                    update_trailing_anchor(po, candle.high, candle.low)

                # 4. Let the bot decide.
                try:
                    orders = bot.on_candle(candle, portfolio)
                except Exception:  # noqa: BLE001
                    _LOG.exception("[%s] on_candle crashed; skipping candle", bot_id)
                    orders = []
                for raw in orders:
                    self._submit_order(
                        raw,
                        candle,
                        portfolio,
                        result,
                        bot_id=bot_id,
                        new_entries_halted=new_entries_halted,
                    )

            # Global equity = sum of all bot portfolios
            total_equity = sum(p.total_equity(candle.close) for p in portfolios)
            result.equity_curve.append(total_equity)

        # Merge all trades into global result
        result.trades = [t for p in portfolios for t in p.closed_trades]
        result.final_equity = (
            sum(p.total_equity(candles[-1].close) for p in portfolios)
            if candles
            else Decimal("0")
        )
        result.peak_equity = (
            max(result.equity_curve) if result.equity_curve else Decimal("0")
        )

        # True peak-to-trough max drawdown on global equity
        result.max_drawdown_pct = compute_max_drawdown_pct(result.equity_curve)

        # Per-bot breakdown
        last_close = candles[-1].close if candles else Decimal("0")
        result.per_bot = build_per_bot_breakdown(
            names, portfolios, capital_per_bot, last_close
        )

        return result

    # ── circuit breaker ───────────────────────────────────────────

    def _circuit_breaker_tripped(
        self,
        portfolios: list[Portfolio],
        candle: Candle,
        result: BacktestResult,
    ) -> bool:
        """Return True when the global drawdown exceeds the configured halt %.

        Open positions are still allowed to close (via pending stops/TPs),
        but no new BUY orders are accepted until equity recovers.
        """
        if self.config.max_drawdown_pct_halt is None:
            return False
        # Use the in-flight curve plus current candle equity for a real-time check
        cur_equity = sum(p.total_equity(candle.close) for p in portfolios)
        peak = (
            max(result.equity_curve + [cur_equity])
            if result.equity_curve
            else cur_equity
        )
        if peak <= 0:
            return False
        dd = (peak - cur_equity) / peak * Decimal(100)
        return dd > self.config.max_drawdown_pct_halt

    # ── order routing ─────────────────────────────────────────────

    def _submit_order(
        self,
        raw: dict[str, Any],
        candle: Candle,
        portfolio: Portfolio,
        result: BacktestResult,
        bot_id: str,
        new_entries_halted: bool = False,
    ) -> None:
        """Route a bot-emitted order dict to fill or pending-orders queue."""
        try:
            o = parse_order_dict(raw)
        except Exception as exc:  # noqa: BLE001
            _LOG.warning("[%s] Bad order dict %r: %s", bot_id, raw, exc)
            return

        side, qty, otype = o["side"], o["qty"], o["type"]
        if qty <= 0:
            return

        # Block new BUY entries when circuit breaker tripped (exits ok).
        if new_entries_halted and side == OrderSide.BUY:
            _LOG.info("[%s] BUY blocked: max DD halt active", bot_id)
            return

        if otype == OrderType.MARKET:
            if side == OrderSide.BUY:
                self._process_buy(
                    candle,
                    portfolio,
                    qty,
                    result,
                    bot_id=bot_id,
                    reason=o["reason"],
                    bracket=o,
                )
            else:
                self._process_sell(
                    candle,
                    portfolio,
                    qty,
                    result,
                    bot_id=bot_id,
                    reason=o["reason"],
                )
            return

        # LIMIT / STOP / STOP_LIMIT / TRAILING_STOP → enqueue
        fill_reason = (
            TriggerReason.LIMIT_FILL
            if otype == OrderType.LIMIT
            else (
                TriggerReason.STOP_LOSS
                if otype
                in (OrderType.STOP, OrderType.STOP_LIMIT, OrderType.TRAILING_STOP)
                else TriggerReason.MARKET_ENTRY
            )
        )
        po = PendingOrder(
            side=side,
            qty=qty,
            type=otype,
            stop_price=o["stop_price"],
            limit_price=o["limit_price"],
            trail_pct=o["trail_pct"],
            reason=fill_reason,
            fill_reason=fill_reason,
            bot_id=bot_id,
        )
        portfolio.pending_orders.append(po)

    # ── pending order processing (per bar, before bot sees the bar) ──

    def _process_pending_orders(
        self,
        candle: Candle,
        portfolio: Portfolio,
        result: BacktestResult,
        bot_id: str,
    ) -> None:
        """Fire any pending orders triggered by this bar's high/low.

        Iterates a snapshot so newly created bracket children don't fire on
        the same bar that created them (they fire next bar earliest).
        """
        if not portfolio.pending_orders:
            return
        survivors: list[PendingOrder] = []
        for po in list(portfolio.pending_orders):
            if po.bot_id and po.bot_id != bot_id:
                # Order belongs to another bot's portfolio — leave it.
                survivors.append(po)
                continue

            fired = False
            if po.type == OrderType.LIMIT:
                if limit_triggers(po, candle.high, candle.low):
                    # Conservative fill: at the limit price (better than market)
                    fill_price = po.limit_price
                    self._fill_pending(
                        po, fill_price, candle, portfolio, result, bot_id
                    )
                    fired = True
            elif po.type in (
                OrderType.STOP,
                OrderType.STOP_LIMIT,
                OrderType.TRAILING_STOP,
            ):
                if stop_triggers(po, candle.high, candle.low):
                    if po.type == OrderType.STOP_LIMIT and po.limit_price is not None:
                        # Stop fired; downgrade to LIMIT and re-enqueue at limit_price
                        # for next bars. (Conservative: limit may not fill.)
                        po.type = OrderType.LIMIT
                        po.stop_price = None
                        survivors.append(po)
                        continue
                    # STOP / TRAILING_STOP → fill at stop_price (with slippage)
                    self._fill_pending(
                        po, po.stop_price, candle, portfolio, result, bot_id
                    )
                    fired = True
            if not fired:
                survivors.append(po)
        portfolio.pending_orders = survivors

    def _fill_pending(
        self,
        po: PendingOrder,
        ref_price: Decimal,
        candle: Candle,
        portfolio: Portfolio,
        result: BacktestResult,
        bot_id: str,
    ) -> None:
        """Execute a triggered pending order at ref_price (with slippage)."""
        reason = (
            po.fill_reason.value
            if hasattr(po.fill_reason, "value")
            else str(po.fill_reason)
        )
        if po.side == OrderSide.BUY:
            # Synthesize a candle with ref_price as close so slippage applies
            self._process_buy_at(
                ref_price,
                candle,
                portfolio,
                po.qty,
                result,
                bot_id=bot_id,
                reason=reason,
            )
        else:
            self._process_sell_at(
                ref_price,
                candle,
                portfolio,
                po.qty,
                result,
                bot_id=bot_id,
                reason=reason,
                parent_position_id=po.parent_position_id,
            )

    # ── MARKET buy/sell ───────────────────────────────────────────

    def _process_buy(
        self,
        candle: Candle,
        portfolio: Portfolio,
        qty: Decimal,
        result: BacktestResult,
        bot_id: str = "",
        reason: str = "BUY",
        bracket: dict[str, Any] | None = None,
    ) -> None:
        """Execute MARKET buy order at candle.close (plus slippage).

        If `bracket` carries stop_loss_* / take_profit_* / trailing_stop_pct
        fields, automatically register protective pending orders against the
        new position.
        """
        self._process_buy_at(
            candle.close,
            candle,
            portfolio,
            qty,
            result,
            bot_id=bot_id,
            reason=reason,
            bracket=bracket,
        )

    def _process_buy_at(
        self,
        ref_price: Decimal,
        candle: Candle,
        portfolio: Portfolio,
        qty: Decimal,
        result: BacktestResult,
        bot_id: str = "",
        reason: str = "BUY",
        bracket: dict[str, Any] | None = None,
    ) -> None:
        if qty <= 0:
            return

        # Apply slippage (buy fills at a slightly higher price than ref)
        fill_price = ref_price * (1 + self.config.slippage_pct / 100)
        cost = qty * fill_price
        fee = cost * self.config.taker_fee_pct / 100

        if portfolio.cash < cost + fee:
            _LOG.warning(
                f"[{bot_id}] Insufficient cash: need {cost + fee:.2f}, have {portfolio.cash:.2f}"
            )
            return

        # Enforce per-portfolio position cap when configured.
        if self.config.max_position_qty is not None:
            held = sum(p.qty for p in portfolio.positions if p.bot_id == bot_id)
            remaining_cap = self.config.max_position_qty - held
            if remaining_cap <= 0:
                _LOG.debug("[%s] max_position_qty cap reached, buy skipped", bot_id)
                return
            qty = min(qty, remaining_cap)

        portfolio.cash -= cost + fee
        pos = Position(
            entry_price=fill_price,
            qty=qty,
            entry_idx=len(result.equity_curve),
            entry_time=candle.timestamp_ms,
            bot_id=bot_id,
        )
        # Seed MFE/MAE with the entry candle's range so a same-candle exit
        # still reports the full intra-bar excursion.
        pos.update_excursion(candle.high, candle.low)
        portfolio.positions.append(pos)

        # Attach bracket protective orders if requested.
        if bracket:
            self._attach_bracket_orders(pos, bracket, bot_id, portfolio)

    def _attach_bracket_orders(
        self,
        pos: Position,
        bracket: dict[str, Any],
        bot_id: str,
        portfolio: Portfolio,
    ) -> None:
        """Create protective SL / TP / trailing-stop orders against a new position."""
        # Stop loss
        sl_price = bracket.get("stop_loss_price")
        sl_pct = bracket.get("stop_loss_pct")
        if sl_price is None and sl_pct is not None:
            sl_price = pos.entry_price * (Decimal(1) - sl_pct / Decimal(100))
        if sl_price is not None:
            portfolio.pending_orders.append(
                PendingOrder(
                    side=OrderSide.SELL,
                    qty=pos.qty,
                    type=OrderType.STOP,
                    stop_price=sl_price,
                    reason=TriggerReason.STOP_LOSS,
                    fill_reason=TriggerReason.STOP_LOSS,
                    bot_id=bot_id,
                    parent_position_id=pos.position_id,
                )
            )

        # Take profit
        tp_price = bracket.get("take_profit_price")
        tp_pct = bracket.get("take_profit_pct")
        if tp_price is None and tp_pct is not None:
            tp_price = pos.entry_price * (Decimal(1) + tp_pct / Decimal(100))
        if tp_price is not None:
            portfolio.pending_orders.append(
                PendingOrder(
                    side=OrderSide.SELL,
                    qty=pos.qty,
                    type=OrderType.LIMIT,
                    limit_price=tp_price,
                    reason=TriggerReason.TAKE_PROFIT,
                    fill_reason=TriggerReason.TAKE_PROFIT,
                    bot_id=bot_id,
                    parent_position_id=pos.position_id,
                )
            )

        # Trailing stop
        trail = bracket.get("trailing_stop_pct")
        if trail is not None and trail > 0:
            anchor = pos.entry_price
            stop = anchor * (Decimal(1) - trail / Decimal(100))
            portfolio.pending_orders.append(
                PendingOrder(
                    side=OrderSide.SELL,
                    qty=pos.qty,
                    type=OrderType.TRAILING_STOP,
                    stop_price=stop,
                    trail_pct=trail,
                    trail_anchor_price=anchor,
                    reason=TriggerReason.TRAILING_STOP,
                    fill_reason=TriggerReason.TRAILING_STOP,
                    bot_id=bot_id,
                    parent_position_id=pos.position_id,
                )
            )

    def _process_sell(
        self,
        candle: Candle,
        portfolio: Portfolio,
        qty: Decimal,
        result: BacktestResult,
        bot_id: str = "",
        reason: str = "SELL",
    ) -> None:
        """Execute MARKET sell order at candle.close (minus slippage)."""
        self._process_sell_at(
            candle.close, candle, portfolio, qty, result, bot_id=bot_id, reason=reason
        )

    def _process_sell_at(
        self,
        ref_price: Decimal,
        candle: Candle,
        portfolio: Portfolio,
        qty: Decimal,
        result: BacktestResult,
        bot_id: str = "",
        reason: str = "SELL",
        parent_position_id: Optional[int] = None,
    ) -> None:
        """Execute sell at ref_price (minus slippage), closing FIFO positions.

        If parent_position_id is set, close only that position (used for
        bracket SL/TP exits so an SL doesn't accidentally close a sibling
        position the bot opened in parallel).
        """
        if qty <= 0 or not portfolio.positions:
            return

        # Apply slippage (sell at lower price)
        fill_price = ref_price * (1 - self.config.slippage_pct / 100)
        total_revenue = qty * fill_price
        total_fee = total_revenue * self.config.taker_fee_pct / 100

        # If a bracket child fires, close ONLY its parent position. Otherwise
        # close FIFO (oldest position first) — Binance convention.
        if parent_position_id is not None:
            targets = [
                p for p in portfolio.positions if p.position_id == parent_position_id
            ]
        else:
            targets = list(portfolio.positions)

        qty_remaining = qty
        closed_position_ids: list[int] = []
        for pos in targets:
            if qty_remaining <= 0:
                break

            qty_to_close = min(qty_remaining, pos.qty)
            prorated_fee = total_fee * (qty_to_close / qty) if qty > 0 else Decimal("0")
            revenue_this = qty_to_close * fill_price

            pnl = qty_to_close * (fill_price - pos.entry_price) - prorated_fee
            pnl_pct = (
                ((fill_price - pos.entry_price) / pos.entry_price * 100)
                if pos.entry_price > 0
                else Decimal("0")
            )

            portfolio.cash += revenue_this - prorated_fee

            # Compute MFE/MAE %: position is long-only, so MFE uses the highest
            # high seen, MAE uses the lowest low. Falls back gracefully if the
            # position closed on the same candle it opened (no excursion data).
            if pos.entry_price > 0 and pos.max_favorable_price > 0:
                mfe_pct = (
                    (pos.max_favorable_price - pos.entry_price) / pos.entry_price * 100
                )
                mae_pct = (
                    (pos.max_adverse_price - pos.entry_price) / pos.entry_price * 100
                )
            else:
                mfe_pct = Decimal("0")
                mae_pct = Decimal("0")
            duration_bars = max(0, len(result.equity_curve) - pos.entry_idx)

            trade = Trade(
                entry_price=pos.entry_price,
                exit_price=fill_price,
                qty=qty_to_close,
                entry_idx=pos.entry_idx,
                exit_idx=len(result.equity_curve),
                entry_time=pos.entry_time,
                exit_time=candle.timestamp_ms,
                pnl=pnl,
                pnl_pct=pnl_pct,
                fee_usdt=prorated_fee,
                reason=reason,
                bot_id=bot_id,
                mfe_pct=mfe_pct,
                mae_pct=mae_pct,
                duration_bars=duration_bars,
            )
            portfolio.closed_trades.append(trade)

            pos.qty -= qty_to_close
            qty_remaining -= qty_to_close
            if pos.qty <= 0:
                closed_position_ids.append(pos.position_id)

        # Cancel pending bracket children of any fully-closed position so
        # their sibling SL doesn't fire after a TP already closed it.
        for pid in closed_position_ids:
            portfolio.cancel_orders_for_position(pid)

        # Remove empty positions
        portfolio.positions = [p for p in portfolio.positions if p.qty > 0]
