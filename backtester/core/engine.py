"""Realistic backtest engine with fees and slippage simulation."""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Any, Optional

_LOG = logging.getLogger("backtester.engine")


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
    """Open trading position."""
    entry_price: Decimal
    qty: Decimal
    entry_idx: int
    entry_time: int


@dataclass
class Trade:
    """Closed trade record."""
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


@dataclass
class Portfolio:
    """Portfolio state."""
    cash: Decimal = Decimal("10000")
    positions: list[Position] = field(default_factory=list)
    closed_trades: list[Trade] = field(default_factory=list)
    equity_curve: list[Decimal] = field(default_factory=list)

    def total_equity(self, current_price: Decimal) -> Decimal:
        """Current portfolio value."""
        position_value = sum(p.qty * current_price for p in self.positions)
        return self.cash + position_value

    def open_position_cost(self) -> Decimal:
        """Total cost of open positions at current price."""
        return sum(p.qty * p.entry_price for p in self.positions)


class BacktestBot(ABC):
    """Base class for backtest bots."""

    @abstractmethod
    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        """
        Called on each candle.

        Returns list of orders:
            [{"side": "BUY", "qty": 1.0}, {"side": "SELL", "qty": 1.0}]
        """


@dataclass
class BacktestConfig:
    """Backtest parameters."""
    initial_cash: Decimal = Decimal("10000")
    taker_fee_pct: Decimal = Decimal("0.1")  # Binance default
    slippage_pct: Decimal = Decimal("0.05")  # Spread + impact
    max_position_qty: Optional[Decimal] = None  # None = unlimited


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

    def summary(self) -> dict[str, Any]:
        """Compute performance metrics."""
        initial = self.equity_curve[0] if self.equity_curve else Decimal("0")
        total_return = ((self.final_equity - initial) / initial * 100) if initial > 0 else 0

        closed = [t for t in self.trades if t.exit_idx is not None]
        winners = [t for t in closed if t.pnl > 0]
        losers = [t for t in closed if t.pnl < 0]

        win_rate = len(winners) / len(closed) * 100 if closed else 0
        avg_win = sum(t.pnl for t in winners) / len(winners) if winners else Decimal("0")
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


class BacktestEngine:
    """Backtest engine."""

    def __init__(self, config: BacktestConfig | None = None) -> None:
        self.config = config or BacktestConfig()

    def run(
        self,
        bots: BacktestBot | list[BacktestBot],
        candles: list[Candle],
        symbol: str = "SYMBOL",
        timeframe: str = "1h",
    ) -> BacktestResult:
        """Run backtest on candles."""
        if not isinstance(bots, list):
            bots = [bots]
            
        portfolio = Portfolio(cash=self.config.initial_cash)
        result = BacktestResult(
            symbol=symbol,
            timeframe=timeframe,
            candles_processed=len(candles),
        )

        for idx, candle in enumerate(candles):
            # Get orders from bots
            for bot in bots:
                orders = bot.on_candle(candle, portfolio)

                # Process orders
                for order in orders:
                    side = order.get("side", "").upper()
                    qty = Decimal(str(order.get("qty", 0)))

                    if side == "BUY":
                        self._process_buy(candle, portfolio, qty, result)
                    elif side == "SELL":
                        self._process_sell(candle, portfolio, qty, result)

            # Update equity curve
            current_equity = portfolio.total_equity(candle.close)
            portfolio.equity_curve.append(current_equity)
            result.equity_curve.append(current_equity)

        # Compute final stats
        result.trades = portfolio.closed_trades
        result.final_equity = portfolio.total_equity(candles[-1].close) if candles else Decimal("0")
        result.peak_equity = max(result.equity_curve) if result.equity_curve else Decimal("0")

        # Max drawdown: true peak-to-trough over the entire equity curve
        max_dd = Decimal("0")
        running_peak = Decimal("0")
        for eq in result.equity_curve:
            if eq > running_peak:
                running_peak = eq
            if running_peak > 0:
                dd = (running_peak - eq) / running_peak
                if dd > max_dd:
                    max_dd = dd
        result.max_drawdown_pct = max_dd * 100

        return result

    def _process_buy(
        self,
        candle: Candle,
        portfolio: Portfolio,
        qty: Decimal,
        result: BacktestResult,
    ) -> None:
        """Execute buy order."""
        if qty <= 0:
            return

        # Apply slippage
        fill_price = candle.close * (1 + self.config.slippage_pct / 100)
        cost = qty * fill_price
        fee = cost * self.config.taker_fee_pct / 100

        if portfolio.cash < cost + fee:
            _LOG.warning(f"Insufficient cash for buy: need {cost + fee}, have {portfolio.cash}")
            return

        portfolio.cash -= cost + fee
        portfolio.positions.append(Position(
            entry_price=fill_price,
            qty=qty,
            entry_idx=len(result.equity_curve),
            entry_time=candle.timestamp_ms,
        ))

    def _process_sell(
        self,
        candle: Candle,
        portfolio: Portfolio,
        qty: Decimal,
        result: BacktestResult,
    ) -> None:
        """Execute sell order."""
        if qty <= 0 or not portfolio.positions:
            return

        # Apply slippage (sell at lower price)
        fill_price = candle.close * (1 - self.config.slippage_pct / 100)
        total_revenue = qty * fill_price
        total_fee = total_revenue * self.config.taker_fee_pct / 100

        # Close positions FIFO
        qty_remaining = qty
        for pos in list(portfolio.positions):
            if qty_remaining <= 0:
                break

            qty_to_close = min(qty_remaining, pos.qty)
            # Prorate fee by fraction of total qty being closed at this position
            prorated_fee = total_fee * (qty_to_close / qty) if qty > 0 else Decimal("0")
            revenue_this = qty_to_close * fill_price

            pnl = qty_to_close * (fill_price - pos.entry_price) - prorated_fee
            pnl_pct = (
                (fill_price - pos.entry_price) / pos.entry_price * 100
            ) if pos.entry_price > 0 else Decimal("0")

            portfolio.cash += revenue_this - prorated_fee

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
                reason=f"SELL@{fill_price}",
            )
            portfolio.closed_trades.append(trade)

            pos.qty -= qty_to_close
            qty_remaining -= qty_to_close

        # Remove empty positions
        portfolio.positions = [p for p in portfolio.positions if p.qty > 0]
