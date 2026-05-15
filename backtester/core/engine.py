"""Production-grade backtest engine — float64, realistic fills, correct fees & MDD.

Design contract
---------------
- Prices, sizes and equity are `float` (IEEE-754 double). For backtest sims
  this gives ~15 significant digits, plenty for crypto. If you need exact
  Decimal precision for *live* trading, do that conversion at the broker
  connector boundary, not here.

- Fees: BUY pays a maker/taker fee proportional to notional; SELL pays one
  on the proceeds. Each `Trade` reports the fee actually attributable to
  that trade (proportional in case of partial FIFO closes).

- Slippage: adverse percentage applied to the fill price. The default fill
  model is `next_open` (orders generated on candle i fill at the open of
  candle i+1) — that's the only way to be lookahead-free. `close` is kept
  for backwards compatibility, but you should know it can produce
  optimistic results.

- Equity is sampled at every candle close (mark-to-market). The equity
  curve has the same length as `candles`.

- Max drawdown is computed running (peak-to-trough), not from final equity,
  and exposed in percent of the peak.

- The bot does *not* track its own position state. Always query
  `portfolio` (it is the source of truth). Use `portfolio.is_long()` /
  `portfolio.open_qty()`.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Literal, Optional

_LOG = logging.getLogger("backtester.engine")

FillModel = Literal["close", "next_open"]


# ───────────────────────── data ─────────────────────────


@dataclass
class Candle:
    """Single OHLCV candle. Times in epoch milliseconds."""
    timestamp_ms: int
    open: float
    high: float
    low: float
    close: float
    volume: float

    @classmethod
    def from_dict(cls, d: dict) -> "Candle":
        return cls(
            timestamp_ms=int(d["timestamp_ms"]),
            open=float(d["open"]),
            high=float(d["high"]),
            low=float(d["low"]),
            close=float(d["close"]),
            volume=float(d["volume"]),
        )


@dataclass
class Position:
    """Open long position. Multi-position is supported (DCA / pyramiding)."""
    entry_price: float          # already includes BUY slippage
    qty: float
    entry_idx: int
    entry_time: int             # epoch ms
    entry_fee: float = 0.0      # fee paid on entry (absolute, USDT-equivalent)


@dataclass
class Trade:
    """Closed trade record. `pnl` is NET of both entry and exit fees."""
    entry_price: float
    exit_price: float
    qty: float
    entry_idx: int
    exit_idx: int
    entry_time: int
    exit_time: int
    pnl: float                  # net of fees
    pnl_pct: float              # net of fees, vs entry notional
    fee_usdt: float             # entry fee + exit fee, attributable to this trade only
    reason: str


@dataclass
class Portfolio:
    """Account state during a backtest run.

    The portfolio is the *single source of truth* for bot logic. Never keep
    private position flags inside a bot — derive from here.
    """
    cash: float = 10_000.0
    positions: list[Position] = field(default_factory=list)
    closed_trades: list[Trade] = field(default_factory=list)
    equity_curve: list[float] = field(default_factory=list)

    # -- read helpers for bots ---------------------------------------------

    def open_qty(self) -> float:
        """Total open long quantity across all positions."""
        return sum(p.qty for p in self.positions)

    def is_long(self) -> bool:
        return self.open_qty() > 0.0

    def avg_entry_price(self) -> float:
        """Volume-weighted average entry price across open positions."""
        total_qty = self.open_qty()
        if total_qty <= 0.0:
            return 0.0
        return sum(p.entry_price * p.qty for p in self.positions) / total_qty

    def total_equity(self, mark_price: float) -> float:
        """Mark-to-market portfolio value at `mark_price`."""
        return self.cash + self.open_qty() * mark_price


# ───────────────────────── bot ABC ─────────────────────────


class BacktestBot(ABC):
    """Base class for trading bots.

    `on_candle` is called once per closed candle. Return a list of orders:
        [{"side": "BUY",  "qty": 0.1, "reason": "RSI_OVERSOLD"},
         {"side": "SELL", "qty": 0.1, "reason": "TP_HIT"}]

    Allowed sides: ``"BUY"``, ``"SELL"``. Orders without a valid side or
    with non-positive qty are silently skipped.

    Orders are filled by the engine at the price prescribed by
    `BacktestConfig.fill_model`:
        - ``"next_open"`` (default, recommended): open of the *next* candle
        - ``"close"`` (legacy): close of the same candle (allows lookahead!)
    """

    @abstractmethod
    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]: ...


# ───────────────────────── config ─────────────────────────


@dataclass
class BacktestConfig:
    """Engine parameters."""
    initial_cash: float = 10_000.0
    taker_fee_pct: float = 0.10              # 0.10% Binance taker default
    slippage_pct: float = 0.05               # 0.05% adverse
    fill_model: FillModel = "next_open"
    allow_partial_buys: bool = False         # if cash short, scale down qty


# ───────────────────────── result ─────────────────────────


@dataclass
class BacktestResult:
    """Output of one backtest run."""
    symbol: str
    timeframe: str
    candles_processed: int
    trades: list[Trade] = field(default_factory=list)
    equity_curve: list[float] = field(default_factory=list)
    initial_equity: float = 0.0
    final_equity: float = 0.0
    peak_equity: float = 0.0
    max_drawdown_pct: float = 0.0            # 0..100, running peak-to-trough
    rejected_orders: int = 0

    def summary(self) -> dict[str, Any]:
        """Industry-standard performance metrics."""
        if self.initial_equity > 0.0:
            total_return = (self.final_equity - self.initial_equity) / self.initial_equity * 100.0
        else:
            total_return = 0.0

        winners = [t for t in self.trades if t.pnl > 0.0]
        losers = [t for t in self.trades if t.pnl < 0.0]
        n_closed = len(self.trades)

        win_rate = (len(winners) / n_closed * 100.0) if n_closed else 0.0

        sum_wins = sum(t.pnl for t in winners)
        sum_losses_abs = sum(-t.pnl for t in losers)
        if sum_losses_abs > 0.0:
            profit_factor = sum_wins / sum_losses_abs
        elif sum_wins > 0.0:
            profit_factor = float("inf")
        else:
            profit_factor = 0.0

        total_fees = sum(t.fee_usdt for t in self.trades)
        avg_win = (sum_wins / len(winners)) if winners else 0.0
        avg_loss = (-sum_losses_abs / len(losers)) if losers else 0.0

        return {
            "total_return_pct": total_return,
            "trades": n_closed,
            "winners": len(winners),
            "losers": len(losers),
            "win_rate_pct": win_rate,
            "profit_factor": profit_factor,
            "avg_win_usdt": avg_win,
            "avg_loss_usdt": avg_loss,
            "max_drawdown_pct": self.max_drawdown_pct,
            "total_fees_usdt": total_fees,
            "initial_equity": self.initial_equity,
            "final_equity": self.final_equity,
            "peak_equity": self.peak_equity,
            "rejected_orders": self.rejected_orders,
        }


# ───────────────────────── engine ─────────────────────────


class BacktestEngine:
    """Single-asset spot backtest with realistic fees, slippage and fill model."""

    def __init__(self, config: BacktestConfig | None = None) -> None:
        self.config: BacktestConfig = config or BacktestConfig()
        # Cache derived constants (avoid recomputing per candle)
        self._fee_rate: float = self.config.taker_fee_pct / 100.0
        self._slip_rate: float = self.config.slippage_pct / 100.0

    # -- public entry point ------------------------------------------------

    def run(
        self,
        bot: BacktestBot,
        candles: list[Candle],
        symbol: str = "SYMBOL",
        timeframe: str = "1h",
    ) -> BacktestResult:
        if not candles:
            return BacktestResult(symbol=symbol, timeframe=timeframe, candles_processed=0)

        portfolio = Portfolio(cash=self.config.initial_cash)
        result = BacktestResult(
            symbol=symbol,
            timeframe=timeframe,
            candles_processed=len(candles),
            initial_equity=self.config.initial_cash,
        )

        # Pending orders to fill at the *next* candle's open
        pending: list[dict[str, Any]] = []

        # Running peak / drawdown tracking
        running_peak = self.config.initial_cash
        running_mdd_pct = 0.0

        for idx, candle in enumerate(candles):
            # 1. Fill orders queued from the previous candle (next_open model)
            if pending and self.config.fill_model == "next_open":
                for order in pending:
                    self._execute(order, candle.open, idx, candle.timestamp_ms,
                                  portfolio, result)
                pending = []

            # 2. Ask the bot for new orders
            orders = bot.on_candle(candle, portfolio)

            # 3. Route orders: either fill now (close model) or queue (next_open)
            for order in orders:
                if self.config.fill_model == "close":
                    self._execute(order, candle.close, idx, candle.timestamp_ms,
                                  portfolio, result)
                else:
                    pending.append(order)

            # 4. Mark-to-market equity at close
            equity = portfolio.total_equity(candle.close)
            portfolio.equity_curve.append(equity)
            result.equity_curve.append(equity)

            # 5. Running peak / drawdown
            if equity > running_peak:
                running_peak = equity
            if running_peak > 0.0:
                dd_pct = (running_peak - equity) / running_peak * 100.0
                if dd_pct > running_mdd_pct:
                    running_mdd_pct = dd_pct

        # Finalize
        result.trades = portfolio.closed_trades
        result.final_equity = result.equity_curve[-1]
        result.peak_equity = running_peak
        result.max_drawdown_pct = running_mdd_pct
        return result

    # -- internals ---------------------------------------------------------

    def _execute(
        self,
        order: dict[str, Any],
        ref_price: float,
        idx: int,
        ts_ms: int,
        portfolio: Portfolio,
        result: BacktestResult,
    ) -> None:
        side = str(order.get("side", "")).upper()
        try:
            qty = float(order.get("qty", 0.0))
        except (TypeError, ValueError):
            result.rejected_orders += 1
            return
        if qty <= 0.0 or not (ref_price > 0.0):
            result.rejected_orders += 1
            return
        reason = str(order.get("reason", side))

        if side == "BUY":
            self._fill_buy(qty, ref_price, idx, ts_ms, portfolio, result, reason)
        elif side == "SELL":
            self._fill_sell(qty, ref_price, idx, ts_ms, portfolio, result, reason)
        else:
            result.rejected_orders += 1

    def _fill_buy(
        self,
        qty: float,
        ref_price: float,
        idx: int,
        ts_ms: int,
        portfolio: Portfolio,
        result: BacktestResult,
        reason: str,
    ) -> None:
        # Adverse slippage: pay more than the reference price
        fill_price = ref_price * (1.0 + self._slip_rate)
        notional = qty * fill_price
        fee = notional * self._fee_rate
        total_cost = notional + fee

        if portfolio.cash < total_cost:
            if not self.config.allow_partial_buys:
                _LOG.debug("BUY rejected: need %.4f USDT, have %.4f", total_cost, portfolio.cash)
                result.rejected_orders += 1
                return
            # Partial: scale qty so that notional + fee ≤ cash
            # qty * fill * (1 + fee_rate) = cash → qty = cash / (fill * (1+fee_rate))
            scale_denom = fill_price * (1.0 + self._fee_rate)
            if scale_denom <= 0.0:
                result.rejected_orders += 1
                return
            qty = portfolio.cash / scale_denom
            notional = qty * fill_price
            fee = notional * self._fee_rate
            total_cost = notional + fee
            if qty <= 0.0:
                result.rejected_orders += 1
                return

        portfolio.cash -= total_cost
        portfolio.positions.append(Position(
            entry_price=fill_price,
            qty=qty,
            entry_idx=idx,
            entry_time=ts_ms,
            entry_fee=fee,
        ))

    def _fill_sell(
        self,
        qty: float,
        ref_price: float,
        idx: int,
        ts_ms: int,
        portfolio: Portfolio,
        result: BacktestResult,
        reason: str,
    ) -> None:
        if not portfolio.positions:
            result.rejected_orders += 1
            return

        fill_price = ref_price * (1.0 - self._slip_rate)
        # Sell at most what we hold
        available = portfolio.open_qty()
        sell_qty = min(qty, available)
        if sell_qty <= 0.0:
            result.rejected_orders += 1
            return

        # Exit fee is on the total proceeds; we attribute it proportionally
        # to each FIFO sub-trade below.
        total_proceeds = sell_qty * fill_price
        total_exit_fee = total_proceeds * self._fee_rate
        portfolio.cash += total_proceeds - total_exit_fee

        qty_left = sell_qty
        for pos in portfolio.positions:
            if qty_left <= 0.0:
                break
            close_qty = min(qty_left, pos.qty)
            if close_qty <= 0.0:
                continue

            # Proportional fees
            entry_fee_part = (pos.entry_fee * close_qty / pos.qty) if pos.qty > 0.0 else 0.0
            exit_fee_part = total_exit_fee * close_qty / sell_qty
            trade_fee = entry_fee_part + exit_fee_part

            gross_pnl = close_qty * (fill_price - pos.entry_price)
            net_pnl = gross_pnl - trade_fee
            entry_notional = close_qty * pos.entry_price
            net_pnl_pct = (net_pnl / entry_notional * 100.0) if entry_notional > 0.0 else 0.0

            portfolio.closed_trades.append(Trade(
                entry_price=pos.entry_price,
                exit_price=fill_price,
                qty=close_qty,
                entry_idx=pos.entry_idx,
                exit_idx=idx,
                entry_time=pos.entry_time,
                exit_time=ts_ms,
                pnl=net_pnl,
                pnl_pct=net_pnl_pct,
                fee_usdt=trade_fee,
                reason=reason,
            ))

            # Reduce the position (and its remaining entry_fee proportionally)
            pos.entry_fee -= entry_fee_part
            pos.qty -= close_qty
            qty_left -= close_qty

        # Drop emptied positions
        portfolio.positions = [p for p in portfolio.positions if p.qty > 1e-12]
