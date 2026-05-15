"""DSLBot — runnable :class:`BotBase` driven by a parsed DSL spec.

The bot pre-computes every indicator series in :meth:`prepare` (called lazily
on the first ``on_candle``) so per-bar evaluation stays O(rules) instead of
recomputing pandas series each tick. Risk parameters from the DSL (``stop_loss_pct``,
``take_profit_pct``, ``size_pct``) are translated into native bracket-order
fields on the entry order, so the engine's pending-order machinery handles
SL/TP intra-bar exactly as it does for hand-written bots.
"""

from __future__ import annotations

from typing import Any

from backtester.bots.bot_base import BotBase
from backtester.bots.dsl.evaluator import evaluate
from backtester.bots.dsl.parser import StrategySpec, parse_dsl
from backtester.core.engine import Candle, Portfolio
from backtester.core.indicators import add_indicators


class DSLBot(BotBase):
    """Generic bot whose behavior is defined by a YAML DSL document.

    Parameters
    ----------
    dsl_text:
        Raw YAML text (preferred for API / Flutter usage).
    dsl_dict:
        Pre-decoded mapping; useful for tests and programmatic use.

    One of ``dsl_text`` or ``dsl_dict`` must be provided.
    """

    def __init__(
        self,
        dsl_text: str | None = None,
        dsl_dict: dict[str, Any] | None = None,
    ) -> None:
        if dsl_text is None and dsl_dict is None:
            raise ValueError("DSLBot requires either dsl_text or dsl_dict")
        self.spec: StrategySpec = parse_dsl(
            dsl_text if dsl_text is not None else dsl_dict
        )
        # Use the DSL-provided sizing for the BotBase ``calc_qty`` helper too,
        # even though we route entries through bracket orders (the field is
        # still consulted by the validator + UI).
        self.risk_per_trade_pct = self.spec.size_pct

        # Lazily-populated indicator series, keyed by alias.
        self._series: dict[str, list[float | None]] | None = None
        self._idx: int = -1
        # Track whether we've sent a BUY whose fill hasn't yet been confirmed
        # in the portfolio — DSL exits should only fire once we actually hold.
        self._pending_entry: bool = False

    @classmethod
    def from_text(cls, text: str) -> "DSLBot":
        return cls(dsl_text=text)

    @classmethod
    def param_spec(cls) -> dict[str, dict[str, Any]]:
        """The DSLBot is configured by a YAML document, not numeric params.

        We expose a single ``dsl_text`` string field so the API/Flutter can
        render a multiline editor next to the other bots.
        """
        return {
            "dsl_text": {
                "type": "str",
                "default": "",
            }
        }

    def prepare_indicators(self, candles_window: list[Candle]) -> None:
        """Engine hook: pre-compute every indicator series once per backtest.

        :class:`~backtester.core.engine.BacktestEngine` calls this (when
        defined) before iterating the candle list, so we can pre-materialize
        all indicator series and look them up by index later. Standard bots
        don't define this method and are unaffected.

        ``add_indicators`` already aligns each output series to the candle
        list, so we can index it directly by candle position later.
        """
        specs: list[dict[str, Any]] = []
        for b in self.spec.bindings:
            spec: dict[str, Any] = {"name": b.func, "column": b.column}
            if b.func in {"ema", "sma"}:
                spec["period"] = int(b.args[0])
            elif b.func == "rsi":
                spec["period"] = int(b.args[0])
            elif b.func == "macd":
                fast, slow, sig = (b.args + (12, 26, 9))[:3]
                spec.update({"fast": int(fast), "slow": int(slow), "signal": int(sig)})
            elif b.func == "bb":
                spec["period"] = int(b.args[0]) if b.args else 20
            # vwap has no extra args.
            specs.append(spec)
        raw = add_indicators(candles_window, specs)
        # Map series key → alias for fast lookup at evaluation time.
        self._series = {}
        for binding in self.spec.bindings:
            key = binding.series_key()
            if key in raw:
                self._series[binding.alias] = raw[key]
            else:
                # Indicator failed to materialize (warm-up too short, bad
                # args). Fill with None so the evaluator short-circuits.
                self._series[binding.alias] = [None] * len(candles_window)

    def _build_context(self, idx: int) -> dict[str, float | None]:
        if self._series is None:
            return {alias: None for alias in self.spec.indicators_used()}
        ctx: dict[str, float | None] = {}
        for alias in self.spec.indicators_used():
            series = self._series.get(alias) or []
            ctx[alias] = series[idx] if idx < len(series) else None
        return ctx

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        """Decide using the indicator values at the current bar.

        Per-bar logic:

        1. Advance the bar index.
        2. Build the alias→value context from the precomputed series.
        3. If no position is open and ``entry.long`` is True → BUY with
           bracket SL/TP from the DSL ``risk`` block.
        4. Otherwise, if a position is open and ``exit.long`` is True →
           MARKET SELL (the bracket children attached at entry will be
           cancelled automatically by the engine on close).
        """
        self._idx += 1
        orders: list[dict[str, Any]] = []
        ctx = self._build_context(self._idx)

        has_position = bool(portfolio.positions)
        # If we just placed a BUY last bar that hasn't filled yet, do not
        # double up — wait until the position shows up.
        if self._pending_entry and not has_position:
            return orders
        if has_position:
            self._pending_entry = False

        if not has_position:
            if evaluate(self.spec.entry_long, ctx):
                qty = self.calc_qty(candle.close, portfolio, self.spec.size_pct)
                if qty > 0:
                    order: dict[str, Any] = {
                        "side": "BUY",
                        "qty": float(qty),
                        "reason": "DSL_ENTRY",
                    }
                    if self.spec.stop_loss_pct is not None:
                        order["stop_loss_pct"] = float(self.spec.stop_loss_pct) * 100.0
                    if self.spec.take_profit_pct is not None:
                        order["take_profit_pct"] = (
                            float(self.spec.take_profit_pct) * 100.0
                        )
                    orders.append(order)
                    self._pending_entry = True
            return orders

        if evaluate(self.spec.exit_long, ctx):
            qty = self.max_sell_qty(portfolio)
            if qty > 0:
                orders.append(
                    {
                        "side": "SELL",
                        "qty": float(qty),
                        "reason": "DSL_EXIT",
                    }
                )
        return orders
