"""Property-based invariant tests for :mod:`backtester.core.engine`.

Uses `hypothesis <https://hypothesis.readthedocs.io>`_ to generate small
random candle series and a deterministic toggle-bot, then verifies three
invariants every backtest must satisfy regardless of the input data:

Invariant 1 - **Equity conservation per bar**
    On every candle the engine sees,
    ``portfolio.cash + sum(pos.qty * candle.close for pos in portfolio.positions)``
    must equal ``portfolio.total_equity(candle.close)`` exactly. This is the
    contract the rest of the analytics stack relies on; if the equation
    drifts we silently corrupt drawdown / Sharpe / PSR downstream.

Invariant 2 - **Fees are non-negative**
    ``sum(t.fee_usdt for t in result.trades) >= 0`` for any run, regardless
    of the trading pattern. A negative aggregate fee would mean we're
    paying the trader to trade, which would silently inflate every
    strategy's measured edge.

Invariant 3 - **P&L conservation after a force close-all**
    With ``taker_fee_pct = slippage_pct = 0`` (so no value leaks into
    fees / spread), after running until the last candle and then
    force-closing every remaining open position at the last close,
    ``final_equity - initial_capital == sum(t.pnl) - sum(t.fee_usdt)``
    within Decimal tolerance. This is the "no money is created or
    destroyed" check on the engine's cash-flow accounting.

If ``hypothesis`` is not installed (e.g. on the slim CI image) the whole
module is skipped via :func:`pytest.importorskip` so the rest of the
suite still runs.
"""

from __future__ import annotations

import pytest

pytest.importorskip("hypothesis")

from decimal import Decimal  # noqa: E402

from hypothesis import HealthCheck, given, settings  # noqa: E402
from hypothesis import strategies as st  # noqa: E402

from backtester.core.engine import (  # noqa: E402
    BacktestBot,
    BacktestConfig,
    BacktestEngine,
    Candle,
    Portfolio,
    Trade,
)

pytestmark = pytest.mark.property

# Decimal tolerance used for cash-flow conservation. The engine uses
# Decimal end-to-end so the difference should be exactly zero, but we
# leave a generous tolerance to absorb any future rounding (e.g. a
# `quantize` introduced inside the engine for display).
_TOL = Decimal("0.0001")


# ── Hypothesis strategies ────────────────────────────────────────────


def _decimal(min_value: str, max_value: str, places: int = 2) -> st.SearchStrategy:
    """Wrapper around ``st.decimals`` that always disables NaN / Infinity.

    Hypothesis ships with sensible defaults but the engine assumes finite
    positive Decimals throughout, so an unconstrained NaN slips through
    silently and corrupts every downstream comparison.
    """
    return st.decimals(
        min_value=Decimal(min_value),
        max_value=Decimal(max_value),
        allow_nan=False,
        allow_infinity=False,
        places=places,
    )


@st.composite
def candle_series(draw: st.DrawFn, min_n: int = 3, max_n: int = 50) -> list[Candle]:
    """Generate a short OHLCV series with valid OHLC ordering.

    The series is a random walk seeded around a positive base price; for
    each step we sample a small symmetric delta and a non-negative
    intra-bar spread, then synthesize ``high = mid + spread`` and
    ``low = max(epsilon, mid - spread)`` so OHLC consistency holds by
    construction. Volume is fixed at 1 — none of the invariants under
    test depend on it.
    """
    n = draw(st.integers(min_value=min_n, max_value=max_n))
    base = draw(_decimal("1.00", "1000.00"))
    candles: list[Candle] = []
    for i in range(n):
        delta = draw(_decimal("-3.00", "3.00"))
        base = max(Decimal("0.50"), base + delta)
        spread = draw(_decimal("0.10", "2.00"))
        mid = base
        high = mid + spread
        low = max(Decimal("0.10"), mid - spread)
        # ``open`` and ``close`` set to mid keeps the bar self-consistent
        # while still letting the engine see varied closes through the
        # random walk on ``base``.
        candles.append(
            Candle(
                timestamp_ms=1_700_000_000_000 + i * 60_000,
                open=mid,
                high=high,
                low=low,
                close=mid,
                volume=Decimal("1"),
            )
        )
    return candles


# ── Deterministic test bots ──────────────────────────────────────────


class _ToggleBot(BacktestBot):
    """Buys on even-numbered bars (when flat), sells on odd ones.

    Sized so each entry only spends ~10% of available cash, which keeps
    the bot from running out of money even on adversarial price walks
    Hypothesis explores. Records the live ``Portfolio`` reference on
    first call so the test can inspect mutated state after the run.

    Invariant 1 is checked inside ``on_candle`` (which fires once per
    bar), and any failure is collected into ``invariant_failures`` so a
    single bad bar produces a useful error message instead of an
    AssertionError storm across 50 candles.
    """

    def __init__(self) -> None:
        self._bar = -1
        self.invariant_failures: list[str] = []
        self.portfolio_ref: Portfolio | None = None

    def on_candle(self, candle, portfolio):  # type: ignore[override]
        self._bar += 1
        if self.portfolio_ref is None:
            self.portfolio_ref = portfolio

        # Invariant 1: total_equity must equal cash + open-position value.
        manual = portfolio.cash + sum(
            (p.qty * candle.close for p in portfolio.positions),
            start=Decimal("0"),
        )
        engine_eq = portfolio.total_equity(candle.close)
        if manual != engine_eq:
            self.invariant_failures.append(
                f"bar={self._bar} cash={portfolio.cash} "
                f"manual={manual} engine={engine_eq}"
            )

        if self._bar % 2 == 0 and not portfolio.positions:
            spend = portfolio.cash * Decimal("0.10")
            if spend < Decimal("1") or candle.close <= 0:
                return []
            qty = (spend / candle.close).quantize(Decimal("0.000001"))
            if qty <= 0:
                return []
            return [{"side": "BUY", "qty": qty, "reason": "TOGGLE_BUY"}]

        if self._bar % 2 == 1 and portfolio.positions:
            qty = sum((p.qty for p in portfolio.positions), start=Decimal("0"))
            if qty <= 0:
                return []
            return [{"side": "SELL", "qty": qty, "reason": "TOGGLE_SELL"}]

        return []


class _NoopBot(BacktestBot):
    """Records the portfolio reference but never trades.

    Useful for invariants that don't depend on the bot doing anything —
    e.g. checking that an idle portfolio's equity equals its initial
    cash on every bar.
    """

    def __init__(self) -> None:
        self.portfolio_ref: Portfolio | None = None

    def on_candle(self, candle, portfolio):  # type: ignore[override]
        if self.portfolio_ref is None:
            self.portfolio_ref = portfolio
        return []


# ── Helpers ──────────────────────────────────────────────────────────


def _force_close_all(
    portfolio: Portfolio,
    last_candle: Candle,
    fee_pct: Decimal = Decimal("0"),
    slippage_pct: Decimal = Decimal("0"),
) -> None:
    """Close every remaining open position at ``last_candle.close``.

    Mirrors the engine's ``_process_sell_at`` accounting (slippage,
    pro-rated fee, P&L = qty * (fill - entry) - fee, append a Trade,
    bump cash) without going through the ``BacktestEngine`` API — the
    engine doesn't expose a public force-close hook.

    Defaults to zero fees / slippage so callers can use the result for
    exact P&L conservation checks (Invariant 3); pass non-zero values
    if you want to model realistic close-out costs.
    """
    for pos in list(portfolio.positions):
        fill_price = last_candle.close * (Decimal(1) - slippage_pct / Decimal(100))
        revenue = pos.qty * fill_price
        fee = revenue * fee_pct / Decimal(100)
        pnl = pos.qty * (fill_price - pos.entry_price) - fee
        pnl_pct = (
            (fill_price - pos.entry_price) / pos.entry_price * Decimal(100)
            if pos.entry_price > 0
            else Decimal("0")
        )
        portfolio.cash += revenue - fee
        portfolio.closed_trades.append(
            Trade(
                entry_price=pos.entry_price,
                exit_price=fill_price,
                qty=pos.qty,
                entry_idx=pos.entry_idx,
                exit_idx=len(portfolio.equity_curve),
                entry_time=pos.entry_time,
                exit_time=last_candle.timestamp_ms,
                pnl=pnl,
                pnl_pct=pnl_pct,
                fee_usdt=fee,
                reason="FORCE_CLOSE",
                bot_id=pos.bot_id,
            )
        )
    portfolio.positions = []


def _approx_equal(a: Decimal, b: Decimal, tol: Decimal = _TOL) -> bool:
    """Decimal near-equality used by all invariant assertions."""
    return abs(a - b) <= tol


# ── Property tests ───────────────────────────────────────────────────

# Hypothesis defaults are tuned for fast unit tests; we cap at 25
# examples (the user-requested budget) and disable the deadline because
# the engine touches Decimal arithmetic and a single example can take
# tens of milliseconds. ``suppress_health_check`` quiets the
# data-generation-too-slow warning when shrinking on Windows.
_HYPOTHESIS = settings(
    max_examples=25,
    deadline=None,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)


@_HYPOTHESIS
@given(candles=candle_series())
def test_invariant_equity_conservation_per_bar(candles: list[Candle]) -> None:
    """Invariant 1: cash + sum(qty * close) == total_equity on every bar."""
    bot = _ToggleBot()
    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=Decimal("10000"),
            taker_fee_pct=Decimal("0.1"),
            slippage_pct=Decimal("0.05"),
        )
    )
    engine.run(bot, candles, symbol="HYPO", timeframe="1m")

    assert not bot.invariant_failures, (
        "Equity invariant violated on at least one bar:\n"
        + "\n".join(bot.invariant_failures[:5])
    )


@_HYPOTHESIS
@given(candles=candle_series())
def test_invariant_fees_non_negative(candles: list[Candle]) -> None:
    """Invariant 2: sum of trade fees is never negative."""
    bot = _ToggleBot()
    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=Decimal("10000"),
            taker_fee_pct=Decimal("0.1"),
            slippage_pct=Decimal("0.05"),
        )
    )
    result = engine.run(bot, candles, symbol="HYPO", timeframe="1m")

    total_fees = sum((t.fee_usdt for t in result.trades), start=Decimal("0"))
    assert total_fees >= Decimal(
        "0"
    ), f"Aggregate fees went negative: {total_fees} across {len(result.trades)} trades"
    # And per-trade fees should also be non-negative individually — a
    # negative trade fee would average out in the sum but indicates an
    # accounting bug just the same.
    bad = [t for t in result.trades if t.fee_usdt < 0]
    assert not bad, f"{len(bad)} trades have negative fees, e.g. {bad[0]}"


@_HYPOTHESIS
@given(candles=candle_series())
def test_invariant_pnl_conservation_after_close_all(
    candles: list[Candle],
) -> None:
    """Invariant 3: with zero fees+slippage, equity delta == net P&L."""
    bot = _ToggleBot()
    initial_cash = Decimal("10000")
    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=initial_cash,
            # Zero out fees + slippage so the cash-flow identity holds
            # exactly: trade.pnl is then qty*(sell-buy), no buy_fee leak,
            # and final_equity == initial + sum(trade.pnl).
            taker_fee_pct=Decimal("0"),
            slippage_pct=Decimal("0"),
        )
    )
    engine.run(bot, candles, symbol="HYPO", timeframe="1m")
    assert bot.portfolio_ref is not None

    last_close = candles[-1].close
    _force_close_all(bot.portfolio_ref, candles[-1])

    final_equity = bot.portfolio_ref.total_equity(last_close)
    net_pnl = sum((t.pnl for t in bot.portfolio_ref.closed_trades), start=Decimal("0"))
    total_fees = sum(
        (t.fee_usdt for t in bot.portfolio_ref.closed_trades), start=Decimal("0")
    )

    lhs = final_equity - initial_cash
    rhs = net_pnl - total_fees
    assert _approx_equal(lhs, rhs), (
        f"P&L conservation broken: lhs={lhs} (final {final_equity} - "
        f"init {initial_cash}) vs rhs={rhs} (pnl {net_pnl} - fees {total_fees})"
    )
    # And after a true close-all, no positions should remain.
    assert bot.portfolio_ref.positions == []


# ── Sanity / edge-case tests ─────────────────────────────────────────


def test_invariant_holds_for_idle_bot_known_series() -> None:
    """A bot that never trades preserves cash exactly across every bar.

    Acts as a fast smoke test independent of Hypothesis: if this
    regresses the issue is in the engine's bookkeeping, not in the
    randomized inputs.
    """
    bot = _NoopBot()
    candles = [
        Candle(
            timestamp_ms=1_700_000_000_000 + i * 60_000,
            open=Decimal("100"),
            high=Decimal("101"),
            low=Decimal("99"),
            close=Decimal("100"),
            volume=Decimal("1"),
        )
        for i in range(5)
    ]
    engine = BacktestEngine(BacktestConfig(initial_cash=Decimal("10000")))
    result = engine.run(bot, candles, symbol="IDLE", timeframe="1m")

    assert bot.portfolio_ref is not None
    assert bot.portfolio_ref.cash == Decimal("10000")
    assert bot.portfolio_ref.positions == []
    assert all(eq == Decimal("10000") for eq in result.equity_curve)
    assert result.final_equity == Decimal("10000")
