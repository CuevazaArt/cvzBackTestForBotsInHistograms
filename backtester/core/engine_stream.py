"""StreamingEngine — backtest engine that emits events as it runs.

Used by `/ws` to push candles, trades, equity points and progress to the
Flutter shell / browser so the user can watch the bot "draw" on the chart
in real time.

Multi-bot: each bot gets an isolated Portfolio slice (capital / n_bots).
Events include `bot_id` so the frontend can color-code by strategy.
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
    build_per_bot_breakdown,
    compute_max_drawdown_pct,
)
from backtester.core.orders import update_trailing_anchor

_LOG = logging.getLogger("backtester.engine.stream")

# Event emitter signature: (event_type, payload) -> None
EmitFn = Callable[[str, dict], None]


class StreamingEngine(BacktestEngine):
    """Same logic as BacktestEngine but emits live events while running.

    Events emitted:
        start    — metadata before first candle
        candle   — per processed candle (throttled by `candle_every`)
        trade    — when a trade is closed (includes bot_id)
        equity   — equity curve point (global + per-bot, throttled)
        progress — % completion
        result   — final summary with per_bot breakdown
        error    — on exceptions
    """

    def __init__(
        self,
        config: BacktestConfig | None = None,
        on_event: Optional[EmitFn] = None,
        total: int = 0,
        candle_every: int = 1,
        equity_every: int = 25,
        progress_every: int = 50,
        cache=None,
    ) -> None:
        super().__init__(config)
        self._emit: EmitFn = on_event or (lambda t, d: None)
        self._total = max(total, 0)
        self._candle_every = max(candle_every, 1)
        self._equity_every = max(equity_every, 1)
        self._progress_every = max(progress_every, 1)
        self._cache = cache  # IndicatorCache | None

    # ── helpers ───────────────────────────────────────────────────

    def _emit_candle(self, candle: Candle, indicators: dict | None = None) -> None:
        payload = {
            "time":   candle.timestamp_ms // 1000,
            "open":   float(candle.open),
            "high":   float(candle.high),
            "low":    float(candle.low),
            "close":  float(candle.close),
            "volume": float(candle.volume),
        }
        if indicators:
            payload["indicators"] = indicators
        self._emit("candle", payload)

    def _emit_trade(self, t: Trade) -> None:
        self._emit("trade", {
            "entry_time":     t.entry_time // 1000,
            "exit_time":      t.exit_time // 1000,
            "entry_price":    float(t.entry_price),
            "exit_price":     float(t.exit_price),
            "qty":            float(t.qty),
            "pnl":            float(t.pnl),
            "pnl_pct":        float(t.pnl_pct),
            "fee_usdt":       float(t.fee_usdt),
            "reason":         t.reason,
            "bot_id":         t.bot_id,
            "mfe_pct":        float(t.mfe_pct),       # ← Max Favorable Excursion
            "mae_pct":        float(t.mae_pct),       # ← Max Adverse Excursion
            "duration_bars":  t.duration_bars,
        })

    def _emit_equity(self, ts_ms: int, value: Decimal, bot_id: str = "total") -> None:
        self._emit("equity", {
            "time":   ts_ms // 1000,
            "value":  float(value),
            "bot_id": bot_id,                 # ← "total" | "BotName_0" | ...
        })

    def _emit_progress(self, idx: int) -> None:
        pct = (idx / self._total * 100.0) if self._total else 0.0
        self._emit("progress", {
            "candles_done":  idx,
            "candles_total": self._total,
            "percent":       pct,
        })

    # ── main loop (multi-bot, with hooks) ─────────────────────────

    def run(
        self,
        bots,
        candles: list[Candle],
        symbol: str = "SYMBOL",
        timeframe: str = "1h",
        indicator_specs: list[dict] | None = None,
        bot_names: list[str] | None = None,
    ) -> BacktestResult:
        if not isinstance(bots, list):
            bots = [bots]

        n = len(bots)
        capital_per_bot = self.config.initial_cash / Decimal(n)

        # Assign stable names (used as series IDs in the frontend)
        names: list[str] = list(bot_names or [])
        for i in range(len(names), n):
            names.append(f"{bots[i].__class__.__name__}_{i}")

        portfolios = [Portfolio(cash=capital_per_bot) for _ in range(n)]
        prev_closed = [0] * n   # track new trades per bot

        # Calculate indicators (pre-run, full series) — cached when available
        from backtester.core.indicators import is_oscillator
        from backtester.core.cache import add_indicators_cached
        ind_data = add_indicators_cached(
            candles,
            indicator_specs or [],
            cache=self._cache,
            symbol=symbol,
            timeframe=timeframe,
        )

        result = BacktestResult(
            symbol=symbol, timeframe=timeframe, candles_processed=len(candles),
        )

        overlay_keys    = [k for k in ind_data if not is_oscillator(k)]
        oscillator_keys = [k for k in ind_data if is_oscillator(k)]

        # ── start event includes bot metadata for the frontend ────
        self._emit("start", {
            "symbol":          symbol,
            "timeframe":       timeframe,
            "candles_total":   len(candles),
            "initial_cash":    float(self.config.initial_cash),
            "indicators_keys": overlay_keys,
            "oscillator_keys": oscillator_keys,
            "bot_ids":         names,         # ← new: frontend creates one equity series per bot
        })

        try:
            for idx, candle in enumerate(candles):

                # ── 1. Each bot decides on its own portfolio ──────
                # Compute circuit-breaker flag once per candle.
                new_entries_halted = self._circuit_breaker_tripped(portfolios, candle, result)

                for bi, (bot, portfolio, bot_id) in enumerate(
                    zip(bots, portfolios, names)
                ):
                    # 1a. Update MFE/MAE BEFORE the bot runs so positions that
                    #     close on this candle capture its full high/low range.
                    for pos in portfolio.positions:
                        pos.update_excursion(candle.high, candle.low)

                    # 1b. Check pending orders FIRST (LIMIT / STOP / TRAILING)
                    #     so SL/TP/trail fire intra-bar with the pre-ratchet
                    #     trailing level. Then ratchet for the NEXT bar.
                    self._process_pending_orders(candle, portfolio, result, bot_id=bot_id)
                    for po in portfolio.pending_orders:
                        update_trailing_anchor(po, candle.high, candle.low)

                    # 1c. Let the bot decide.
                    try:
                        orders = bot.on_candle(candle, portfolio)
                    except Exception as exc:  # noqa: BLE001
                        _LOG.exception("[%s] on_candle crashed; skipping candle", bot_id)
                        self._emit("error", {
                            "message": f"[{bot_id}] {type(exc).__name__}: {exc}",
                            "fatal": False,
                        })
                        orders = []
                    for raw in orders:
                        self._submit_order(
                            raw, candle, portfolio, result,
                            bot_id=bot_id, new_entries_halted=new_entries_halted,
                        )

                    # Emit newly closed trades for this bot
                    new_trades = portfolio.closed_trades[prev_closed[bi]:]
                    for t in new_trades:
                        self._emit_trade(t)
                    prev_closed[bi] = len(portfolio.closed_trades)

                # ── 2. Global equity = sum of all portfolios ──────
                total_equity = sum(p.total_equity(candle.close) for p in portfolios)
                result.equity_curve.append(total_equity)

                # ── 3. Throttled events ───────────────────────────
                if idx % self._candle_every == 0:
                    inds = {k: v[idx] for k, v in ind_data.items() if v[idx] is not None}
                    self._emit_candle(candle, indicators=inds if inds else None)

                if idx % self._equity_every == 0:
                    # Global curve
                    self._emit_equity(candle.timestamp_ms, total_equity, bot_id="total")
                    # Per-bot curves (sampled same cadence)
                    for portfolio, bot_id in zip(portfolios, names):
                        bot_eq = portfolio.total_equity(candle.close)
                        self._emit_equity(candle.timestamp_ms, bot_eq, bot_id=bot_id)

                if idx % self._progress_every == 0:
                    self._emit_progress(idx)

            # ── finalize ─────────────────────────────────────────
            result.trades = [t for p in portfolios for t in p.closed_trades]
            result.final_equity = sum(
                p.total_equity(candles[-1].close) for p in portfolios
            ) if candles else Decimal("0")
            result.peak_equity = (
                max(result.equity_curve) if result.equity_curve else Decimal("0")
            )

            # True peak-to-trough max drawdown on global equity
            result.max_drawdown_pct = compute_max_drawdown_pct(result.equity_curve)

            # Per-bot breakdown
            last_close = candles[-1].close if candles else Decimal("0")
            result.per_bot = build_per_bot_breakdown(names, portfolios, capital_per_bot, last_close)

            # Force one last progress + final equity point
            self._emit_progress(len(candles))
            if candles:
                self._emit_equity(candles[-1].timestamp_ms, result.final_equity, bot_id="total")
                for portfolio, bot_id in zip(portfolios, names):
                    self._emit_equity(
                        candles[-1].timestamp_ms,
                        portfolio.total_equity(candles[-1].close),
                        bot_id=bot_id,
                    )

            self._emit("result", {
                "symbol":           symbol,
                "timeframe":        timeframe,
                "summary":          result.summary(),
                "trades":           len(result.trades),
                "final_equity":     float(result.final_equity),
                "peak_equity":      float(result.peak_equity),
                "max_drawdown_pct": float(result.max_drawdown_pct),
                "per_bot":          result.per_bot,          # ← new
            })

        except Exception as exc:
            _LOG.exception("StreamingEngine crashed")
            self._emit("error", {"message": f"{type(exc).__name__}: {exc}"})
            raise

        return result
