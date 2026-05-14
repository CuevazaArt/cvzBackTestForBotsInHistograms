"""StreamingEngine — backtest engine that emits events as it runs.

Used by `/ws` to push candles, trades, equity points and progress to the
Flutter shell / browser so the user can watch the bot "draw" on the chart
in real time.
"""

from __future__ import annotations

import logging
from decimal import Decimal
from typing import Callable, Optional

from backtester.core.engine import (
    BacktestConfig,
    BacktestEngine,
    BacktestResult,
    Candle,
    Portfolio,
    Trade,
)

_LOG = logging.getLogger("backtester.engine.stream")

# Event emitter signature: (event_type, payload) -> None
EmitFn = Callable[[str, dict], None]


class StreamingEngine(BacktestEngine):
    """Same logic as BacktestEngine but emits live events while running.

    Events emitted:
        candle    — per processed candle (throttled by `candle_every`)
        trade     — when a trade is closed
        equity    — equity curve point (throttled by `equity_every`)
        progress  — % completion (throttled by `progress_every`)
        result    — final summary at end
        error     — on exceptions
    """

    def __init__(
        self,
        config: BacktestConfig | None = None,
        on_event: Optional[EmitFn] = None,
        total: int = 0,
        candle_every: int = 1,
        equity_every: int = 25,
        progress_every: int = 50,
    ) -> None:
        super().__init__(config)
        self._emit: EmitFn = on_event or (lambda t, d: None)
        self._total = max(total, 0)
        self._candle_every = max(candle_every, 1)
        self._equity_every = max(equity_every, 1)
        self._progress_every = max(progress_every, 1)

    # ---- helpers ----

    def _emit_candle(self, candle: Candle) -> None:
        self._emit("candle", {
            "time": candle.timestamp_ms // 1000,
            "open": float(candle.open),
            "high": float(candle.high),
            "low": float(candle.low),
            "close": float(candle.close),
            "volume": float(candle.volume),
        })

    def _emit_trade(self, t: Trade) -> None:
        self._emit("trade", {
            "entry_time": t.entry_time // 1000,
            "exit_time": t.exit_time // 1000,
            "entry_price": float(t.entry_price),
            "exit_price": float(t.exit_price),
            "qty": float(t.qty),
            "pnl": float(t.pnl),
            "pnl_pct": float(t.pnl_pct),
            "fee_usdt": float(t.fee_usdt),
            "reason": t.reason,
        })

    def _emit_equity(self, ts_ms: int, value: Decimal) -> None:
        self._emit("equity", {"time": ts_ms // 1000, "value": float(value)})

    def _emit_progress(self, idx: int) -> None:
        pct = (idx / self._total * 100.0) if self._total else 0.0
        self._emit("progress", {
            "candles_done": idx,
            "candles_total": self._total,
            "percent": pct,
        })

    # ---- main loop (mirrors BacktestEngine.run with hooks) ----

    def run(
        self,
        bot,
        candles: list[Candle],
        symbol: str = "SYMBOL",
        timeframe: str = "1h",
    ) -> BacktestResult:
        portfolio = Portfolio(cash=self.config.initial_cash)
        result = BacktestResult(
            symbol=symbol, timeframe=timeframe, candles_processed=len(candles),
        )

        # Tell the client we're starting
        self._emit("start", {
            "symbol": symbol,
            "timeframe": timeframe,
            "candles_total": len(candles),
            "initial_cash": float(self.config.initial_cash),
        })

        prev_closed_count = 0

        try:
            for idx, candle in enumerate(candles):
                # 1. Bot makes decision
                orders = bot.on_candle(candle, portfolio)

                # 2. Engine fills (slippage + fees)
                for order in orders:
                    side = order.get("side", "").upper()
                    qty = Decimal(str(order.get("qty", 0)))
                    if side == "BUY":
                        self._process_buy(candle, portfolio, qty, result)
                    elif side == "SELL":
                        self._process_sell(candle, portfolio, qty, result)

                # 3. Equity update
                current_equity = portfolio.total_equity(candle.close)
                portfolio.equity_curve.append(current_equity)
                result.equity_curve.append(current_equity)

                # 4. Emit events (throttled)
                if idx % self._candle_every == 0:
                    self._emit_candle(candle)

                # New trades closed during this candle
                if len(portfolio.closed_trades) > prev_closed_count:
                    for t in portfolio.closed_trades[prev_closed_count:]:
                        self._emit_trade(t)
                    prev_closed_count = len(portfolio.closed_trades)

                if idx % self._equity_every == 0:
                    self._emit_equity(candle.timestamp_ms, current_equity)

                if idx % self._progress_every == 0:
                    self._emit_progress(idx)

            # ---- finalize ----
            result.trades = portfolio.closed_trades
            result.final_equity = (
                portfolio.total_equity(candles[-1].close) if candles else Decimal("0")
            )
            result.peak_equity = (
                max(result.equity_curve) if result.equity_curve else Decimal("0")
            )
            if result.peak_equity > 0:
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
            else:
                result.max_drawdown_pct = Decimal("0")

            # Force one last progress + equity point
            self._emit_progress(len(candles))
            if candles:
                self._emit_equity(candles[-1].timestamp_ms, result.final_equity)

            self._emit("result", {
                "symbol": symbol,
                "timeframe": timeframe,
                "summary": result.summary(),
                "trades": len(result.trades),
                "final_equity": float(result.final_equity),
                "peak_equity": float(result.peak_equity),
                "max_drawdown_pct": float(result.max_drawdown_pct),
            })

        except Exception as exc:
            _LOG.exception("StreamingEngine crashed")
            self._emit("error", {"message": f"{type(exc).__name__}: {exc}"})
            raise

        return result
