"""StreamingEngine — extension of BacktestEngine that pushes live events.

Used by the WebSocket `/ws` endpoint so the Flutter shell / browser can
watch the bot "draw" on the chart as the simulation progresses.

Emits:
    start     — once, at the beginning
    candle    — per candle (throttled by `candle_every`)
    trade     — every time a position is closed
    equity    — equity samples (throttled by `equity_every`)
    progress  — % completion (throttled by `progress_every`)
    result    — once, at the end (success or after `error`)
    error     — on exception (the run still attempts to finalize)
"""

from __future__ import annotations

import logging
from typing import Any, Callable, Optional

from backtester.core.engine import (
    BacktestConfig,
    BacktestEngine,
    BacktestResult,
    Candle,
    Portfolio,
    Trade,
)

_LOG = logging.getLogger("backtester.engine.stream")

EmitFn = Callable[[str, dict], None]


class StreamingEngine(BacktestEngine):
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

    # -- emitters ----------------------------------------------------------

    def _emit_candle(self, c: Candle) -> None:
        self._emit("candle", {
            "time": c.timestamp_ms // 1000,
            "open": c.open, "high": c.high, "low": c.low,
            "close": c.close, "volume": c.volume,
        })

    def _emit_trade(self, t: Trade) -> None:
        self._emit("trade", {
            "entry_time": t.entry_time // 1000,
            "exit_time": t.exit_time // 1000,
            "entry_price": t.entry_price,
            "exit_price": t.exit_price,
            "qty": t.qty,
            "pnl": t.pnl,
            "pnl_pct": t.pnl_pct,
            "fee_usdt": t.fee_usdt,
            "reason": t.reason,
        })

    def _emit_equity(self, ts_ms: int, value: float) -> None:
        self._emit("equity", {"time": ts_ms // 1000, "value": value})

    def _emit_progress(self, idx: int) -> None:
        pct = (idx / self._total * 100.0) if self._total else 0.0
        self._emit("progress", {
            "candles_done": idx,
            "candles_total": self._total,
            "percent": pct,
        })

    # -- run loop ----------------------------------------------------------

    def run(
        self,
        bot,
        candles: list[Candle],
        symbol: str = "SYMBOL",
        timeframe: str = "1h",
    ) -> BacktestResult:
        self._emit("start", {
            "symbol": symbol,
            "timeframe": timeframe,
            "candles_total": len(candles),
            "initial_cash": self.config.initial_cash,
            "fill_model": self.config.fill_model,
            "taker_fee_pct": self.config.taker_fee_pct,
            "slippage_pct": self.config.slippage_pct,
        })

        if not candles:
            empty = BacktestResult(symbol=symbol, timeframe=timeframe, candles_processed=0)
            self._emit("result", {"symbol": symbol, "timeframe": timeframe,
                                  "summary": empty.summary()})
            return empty

        portfolio = Portfolio(cash=self.config.initial_cash)
        result = BacktestResult(
            symbol=symbol, timeframe=timeframe,
            candles_processed=len(candles),
            initial_equity=self.config.initial_cash,
        )
        pending: list[dict[str, Any]] = []
        running_peak = self.config.initial_cash
        running_mdd_pct = 0.0
        prev_closed = 0

        try:
            for idx, candle in enumerate(candles):
                # 1. Fill queued orders at this candle's open (next_open model)
                if pending and self.config.fill_model == "next_open":
                    for order in pending:
                        self._execute(order, candle.open, idx, candle.timestamp_ms,
                                      portfolio, result)
                    pending = []

                # 2. Ask the bot
                orders = bot.on_candle(candle, portfolio)

                # 3. Route orders
                for order in orders:
                    if self.config.fill_model == "close":
                        self._execute(order, candle.close, idx, candle.timestamp_ms,
                                      portfolio, result)
                    else:
                        pending.append(order)

                # 4. Mark-to-market
                equity = portfolio.total_equity(candle.close)
                portfolio.equity_curve.append(equity)
                result.equity_curve.append(equity)
                if equity > running_peak:
                    running_peak = equity
                if running_peak > 0.0:
                    dd = (running_peak - equity) / running_peak * 100.0
                    if dd > running_mdd_pct:
                        running_mdd_pct = dd

                # 5. Stream events
                if idx % self._candle_every == 0:
                    self._emit_candle(candle)
                if len(portfolio.closed_trades) > prev_closed:
                    for t in portfolio.closed_trades[prev_closed:]:
                        self._emit_trade(t)
                    prev_closed = len(portfolio.closed_trades)
                if idx % self._equity_every == 0:
                    self._emit_equity(candle.timestamp_ms, equity)
                if idx % self._progress_every == 0:
                    self._emit_progress(idx)

            # Finalize
            result.trades = portfolio.closed_trades
            result.final_equity = result.equity_curve[-1]
            result.peak_equity = running_peak
            result.max_drawdown_pct = running_mdd_pct

            # Force one last set of events so the UI ends consistent
            self._emit_progress(len(candles))
            self._emit_equity(candles[-1].timestamp_ms, result.final_equity)

            # Final result — includes full equity curve and trades so the
            # browser/Flutter can populate all charts without a separate HTTP call.
            equity_curve = [
                {"time": candles[i].timestamp_ms // 1000, "value": result.equity_curve[i]}
                for i in range(min(len(result.equity_curve), len(candles)))
            ]
            trades_out = [
                {
                    "entry_time":  t.entry_time // 1000,
                    "exit_time":   t.exit_time // 1000 if t.exit_time else None,
                    "entry_price": t.entry_price,
                    "exit_price":  t.exit_price,
                    "qty":         t.qty,
                    "pnl":         t.pnl,
                    "pnl_pct":     t.pnl_pct,
                    "fee_usdt":    t.fee_usdt,
                    "reason":      t.reason or None,
                }
                for t in result.trades
            ]
            candles_out = [
                {
                    "time":   c.timestamp_ms // 1000,
                    "open":   c.open, "high": c.high,
                    "low":    c.low,  "close": c.close,
                    "volume": c.volume,
                }
                for c in candles
            ]
            self._emit("result", {
                "symbol":       symbol,
                "timeframe":    timeframe,
                "summary":      result.summary(),
                "candles":      candles_out,
                "trades":       trades_out,
                "equity_curve": equity_curve,
            })

        except Exception as exc:
            _LOG.exception("StreamingEngine crashed")
            self._emit("error", {"message": f"{type(exc).__name__}: {exc}"})
            raise

        return result
