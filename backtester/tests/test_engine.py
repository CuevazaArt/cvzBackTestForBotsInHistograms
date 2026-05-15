"""Engine correctness suite — covers fills, fees, MDD, FIFO, edge cases.

Every test below asserts a mathematical property we *want* to hold for any
production backtester. Numbers were derived by hand so that a regression is
obvious if the engine drifts.
"""

from __future__ import annotations

import math
from typing import Any

import pytest

from backtester.core.engine import (
    BacktestConfig,
    BacktestEngine,
    BacktestResult,
    Candle,
    Portfolio,
)
from backtester.tests.conftest import linear_candles, make_candle


# ─── helpers ───────────────────────────────────────────────────────────────


class ScriptedBot:
    """Bot that issues a pre-recorded list of orders at given candle indices.

    Example: ScriptedBot({0: [{"side": "BUY", "qty": 1.0}], 3: [{"side": "SELL", "qty": 1.0}]})
    """

    def __init__(self, orders_by_idx: dict[int, list[dict[str, Any]]]) -> None:
        self._orders = orders_by_idx
        self._idx = 0

    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict[str, Any]]:
        out = self._orders.get(self._idx, [])
        self._idx += 1
        return out


def cfg(**kwargs: Any) -> BacktestConfig:
    """BacktestConfig with zero fees & slippage by default for easy math."""
    defaults = dict(
        initial_cash=10_000.0,
        taker_fee_pct=0.0,
        slippage_pct=0.0,
        fill_model="close",   # tests pin the fill model explicitly
    )
    defaults.update(kwargs)
    return BacktestConfig(**defaults)


# ─── basic plumbing ────────────────────────────────────────────────────────


def test_empty_candles_returns_zero_result():
    res = BacktestEngine(cfg()).run(ScriptedBot({}), [], "SYM", "1h")
    assert res.candles_processed == 0
    assert res.trades == []
    assert res.equity_curve == []
    s = res.summary()
    assert s["trades"] == 0
    assert s["profit_factor"] == 0.0


def test_no_orders_keeps_initial_cash():
    candles = linear_candles([100.0, 110.0, 120.0])
    res = BacktestEngine(cfg()).run(ScriptedBot({}), candles, "SYM", "1h")
    assert res.final_equity == pytest.approx(10_000.0)
    assert res.max_drawdown_pct == 0.0
    assert res.trades == []


def test_equity_curve_length_matches_candles():
    candles = linear_candles([100, 110, 120, 130])
    res = BacktestEngine(cfg()).run(ScriptedBot({}), candles, "SYM", "1h")
    assert len(res.equity_curve) == 4


# ─── fills + fees + slippage ───────────────────────────────────────────────


def test_zero_cost_round_trip_at_same_price_pnl_zero():
    """BUY 1@100, SELL 1@100 with zero fees & slippage → pnl exactly 0."""
    candles = linear_candles([100, 100, 100, 100])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 1}],
                       2: [{"side": "SELL", "qty": 1}]})
    res = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h")
    assert len(res.trades) == 1
    assert res.trades[0].pnl == pytest.approx(0.0)
    assert res.final_equity == pytest.approx(10_000.0)


def test_winning_trade_pnl_net_of_fees():
    """BUY 1@100, SELL 1@110, fee=0.1%, slip=0% → pnl = 10 − fees."""
    candles = linear_candles([100, 110])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 1}],
                       1: [{"side": "SELL", "qty": 1}]})
    res = BacktestEngine(cfg(taker_fee_pct=0.1)).run(bot, candles, "SYM", "1h")
    t = res.trades[0]
    entry_fee = 100 * 1 * 0.001        # 0.1
    exit_fee = 110 * 1 * 0.001         # 0.11
    expected_pnl = 10 - (entry_fee + exit_fee)
    assert t.pnl == pytest.approx(expected_pnl)
    assert t.fee_usdt == pytest.approx(entry_fee + exit_fee)
    # cash must reflect: 10000 - (100 + 0.1) + (110 - 0.11) = 10009.79
    # final_equity == cash since position closed
    assert res.final_equity == pytest.approx(10_000 + expected_pnl)


def test_slippage_adverse_both_sides():
    """BUY at price*(1+slip), SELL at price*(1-slip)."""
    candles = linear_candles([100, 100])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 1}],
                       1: [{"side": "SELL", "qty": 1}]})
    res = BacktestEngine(cfg(slippage_pct=1.0)).run(bot, candles, "SYM", "1h")  # 1%
    t = res.trades[0]
    # entry=101, exit=99 → gross pnl = -2, fees = 0
    assert t.entry_price == pytest.approx(101.0)
    assert t.exit_price == pytest.approx(99.0)
    assert t.pnl == pytest.approx(-2.0)


def test_buy_rejected_when_cash_insufficient_no_partial():
    """Order for 100 BTC at $200 each needs $20k; we only have $10k → reject."""
    candles = linear_candles([200, 200])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 100}]})
    res = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h")
    assert res.rejected_orders == 1
    assert res.trades == []
    assert res.final_equity == pytest.approx(10_000.0)


def test_buy_partial_fill_when_allowed():
    """With allow_partial_buys, engine scales qty to fit cash exactly."""
    candles = linear_candles([200, 200])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 100}]})
    res = BacktestEngine(cfg(allow_partial_buys=True)).run(bot, candles, "SYM", "1h")
    assert res.rejected_orders == 0
    # cash 10000 / 200 = 50 BTC (zero fees)
    p = next(iter([1]))
    final_cash_consumed = 10_000.0
    # at end, position value at close=200 → equity stays ~10000
    assert res.final_equity == pytest.approx(10_000.0)


def test_sell_more_than_held_caps_to_open_qty():
    candles = linear_candles([100, 100])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 1}],
                       1: [{"side": "SELL", "qty": 99}]})
    res = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h")
    assert len(res.trades) == 1
    assert res.trades[0].qty == pytest.approx(1.0)


# ─── FIFO with proportional fees ───────────────────────────────────────────


def test_fifo_closes_oldest_first_with_proportional_fees():
    """Three BUYs at 100, 105, 110; one SELL of 3 units at 120.
    Each closed Trade should get its own proportional share of fees.
    """
    candles = linear_candles([100, 105, 110, 120])
    bot = ScriptedBot({
        0: [{"side": "BUY", "qty": 1}],
        1: [{"side": "BUY", "qty": 1}],
        2: [{"side": "BUY", "qty": 1}],
        3: [{"side": "SELL", "qty": 3}],
    })
    res = BacktestEngine(cfg(taker_fee_pct=0.1)).run(bot, candles, "SYM", "1h")
    assert len(res.trades) == 3
    entries = [t.entry_price for t in res.trades]
    assert entries == [100.0, 105.0, 110.0]   # FIFO order preserved

    # Total exit fee: 3*120*0.001 = 0.36 → 0.12 per sub-trade
    # Each entry fee: price*0.001 (qty=1 each)
    expected_fees = [
        100 * 0.001 + 0.12,   # 0.1 + 0.12 = 0.22
        105 * 0.001 + 0.12,   # 0.225
        110 * 0.001 + 0.12,   # 0.23
    ]
    for t, exp in zip(res.trades, expected_fees):
        assert t.fee_usdt == pytest.approx(exp), (t.entry_price, t.fee_usdt, exp)

    # Sum of trade pnls must equal final_equity - initial_equity
    total_pnl = sum(t.pnl for t in res.trades)
    assert res.final_equity - res.initial_equity == pytest.approx(total_pnl)


def test_partial_close_keeps_remaining_position():
    candles = linear_candles([100, 100, 110])
    bot = ScriptedBot({
        0: [{"side": "BUY", "qty": 2}],
        2: [{"side": "SELL", "qty": 1}],   # close half
    })
    res = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h")
    assert len(res.trades) == 1
    assert res.trades[0].qty == pytest.approx(1.0)
    # 1 BTC still open at average entry 100
    # equity = cash + 1*110 close


# ─── max drawdown (running) ────────────────────────────────────────────────


def test_max_drawdown_is_peak_to_trough_not_peak_to_final():
    """Build a curve that peaks early, crashes hard, then recovers ~halfway.
    Final equity might look fine, but MDD must reflect the worst valley."""
    # We need a *position open* during the crash so equity actually drops.
    # Buy at 100, hold; prices go 100→150 (peak)→50 (trough)→120 (final).
    candles = linear_candles([100, 150, 50, 120])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 1}]})
    res = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h")

    # Equity samples (mark-to-market at close):
    # t=0: cash 9900 + 1*100 = 10000 (cash net of buy at 100)
    # t=1: 9900 + 150 = 10050  ← peak
    # t=2: 9900 + 50  = 9950   ← trough
    # t=3: 9900 + 120 = 10020
    assert res.equity_curve[1] == pytest.approx(10_050.0)
    assert res.equity_curve[2] == pytest.approx(9_950.0)
    assert res.final_equity == pytest.approx(10_020.0)

    # MDD = (10050 - 9950) / 10050 * 100 = ~0.9950%
    expected_mdd = (10_050 - 9_950) / 10_050 * 100
    assert res.max_drawdown_pct == pytest.approx(expected_mdd, rel=1e-9)

    # And in particular it is NOT (peak - final)/peak * 100 = ~0.2985%
    naive_wrong = (10_050 - 10_020) / 10_050 * 100
    assert not math.isclose(res.max_drawdown_pct, naive_wrong, rel_tol=1e-3)


def test_max_drawdown_zero_when_curve_only_rises():
    candles = linear_candles([100, 110, 120, 130])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 1}]})
    res = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h")
    assert res.max_drawdown_pct == 0.0


# ─── summary metrics ───────────────────────────────────────────────────────


def test_profit_factor_uses_sum_not_average():
    """Two winners +10, +5, one loser -3 → PF = 15/3 = 5.0 (sum-based),
    NOT (7.5 / 3) = 2.5 (avg-based, the old bug).
    """
    # Three independent round-trips with controlled pnl using zero fees/slip.
    # Round trips: (100→110), (100→105), (100→97)
    candles = linear_candles([100, 110, 100, 105, 100, 97])
    orders = {
        0: [{"side": "BUY", "qty": 1}],
        1: [{"side": "SELL", "qty": 1}],   # +10
        2: [{"side": "BUY", "qty": 1}],
        3: [{"side": "SELL", "qty": 1}],   # +5
        4: [{"side": "BUY", "qty": 1}],
        5: [{"side": "SELL", "qty": 1}],   # -3
    }
    res = BacktestEngine(cfg()).run(ScriptedBot(orders), candles, "SYM", "1h")
    assert len(res.trades) == 3
    s = res.summary()
    assert s["winners"] == 2 and s["losers"] == 1
    assert s["profit_factor"] == pytest.approx(15.0 / 3.0)
    assert s["avg_win_usdt"] == pytest.approx(7.5)
    assert s["avg_loss_usdt"] == pytest.approx(-3.0)


def test_profit_factor_inf_when_no_losers():
    candles = linear_candles([100, 110])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 1}],
                       1: [{"side": "SELL", "qty": 1}]})
    s = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h").summary()
    assert s["profit_factor"] == float("inf")


def test_win_rate_and_counts():
    candles = linear_candles([100, 110, 100, 90])
    orders = {
        0: [{"side": "BUY", "qty": 1}],
        1: [{"side": "SELL", "qty": 1}],
        2: [{"side": "BUY", "qty": 1}],
        3: [{"side": "SELL", "qty": 1}],
    }
    s = BacktestEngine(cfg()).run(ScriptedBot(orders), candles, "SYM", "1h").summary()
    assert s["trades"] == 2
    assert s["win_rate_pct"] == pytest.approx(50.0)


def test_sum_of_trade_pnl_matches_total_return():
    """Invariant: total_return ≈ sum(trade.pnl) when all positions are closed."""
    candles = linear_candles([100, 110, 105, 115, 110, 120])
    orders = {
        0: [{"side": "BUY", "qty": 1}],
        1: [{"side": "SELL", "qty": 1}],
        2: [{"side": "BUY", "qty": 2}],
        5: [{"side": "SELL", "qty": 2}],
    }
    res = BacktestEngine(cfg(taker_fee_pct=0.1, slippage_pct=0.05)).run(
        ScriptedBot(orders), candles, "SYM", "1h",
    )
    total_pnl = sum(t.pnl for t in res.trades)
    assert res.final_equity - res.initial_equity == pytest.approx(total_pnl)


# ─── next_open fill model (recommended, no lookahead) ──────────────────────


def test_next_open_fill_uses_next_candle_open_not_current_close():
    """Order on candle i fills at candle (i+1).open with adverse slippage."""
    # Candle 0: close=100; Candle 1: open=105, close=110.
    # BUY emitted on candle 0 → fills at 105 (+slip).
    candles = [
        Candle(timestamp_ms=1_700_000_000_000, open=100, high=101, low=99,  close=100, volume=1),
        Candle(timestamp_ms=1_700_003_600_000, open=105, high=112, low=104, close=110, volume=1),
        Candle(timestamp_ms=1_700_007_200_000, open=110, high=115, low=109, close=112, volume=1),
    ]
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 1}]})
    res = BacktestEngine(BacktestConfig(initial_cash=10_000.0, taker_fee_pct=0.0,
                                         slippage_pct=0.0, fill_model="next_open")
                        ).run(bot, candles, "SYM", "1h")
    # Position opened at 105 (candle 1 open)
    assert len(res.trades) == 0   # not closed yet
    # Equity at the end: cash=10000-105=9895 + 1*112 close = 10007
    assert res.final_equity == pytest.approx(10_007.0)


def test_next_open_pending_order_after_last_candle_is_dropped():
    """If a BUY is emitted on the very last candle and fill_model=next_open,
    there is no 'next' candle to fill it on — that order must be silently
    dropped (not crash, not magically fill)."""
    candles = linear_candles([100, 100])
    bot = ScriptedBot({1: [{"side": "BUY", "qty": 1}]})
    res = BacktestEngine(BacktestConfig(initial_cash=10_000.0, taker_fee_pct=0.0,
                                         slippage_pct=0.0, fill_model="next_open")
                        ).run(bot, candles, "SYM", "1h")
    assert res.trades == []
    assert res.final_equity == pytest.approx(10_000.0)


# ─── invalid input handling ────────────────────────────────────────────────


def test_unknown_side_is_rejected_not_raised():
    candles = linear_candles([100, 100])
    bot = ScriptedBot({0: [{"side": "HODL", "qty": 1}]})
    res = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h")
    assert res.rejected_orders == 1
    assert res.trades == []


def test_zero_or_negative_qty_rejected():
    candles = linear_candles([100, 100])
    bot = ScriptedBot({0: [{"side": "BUY", "qty": 0},
                           {"side": "SELL", "qty": -1}]})
    res = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h")
    assert res.rejected_orders == 2


def test_sell_with_no_position_rejected():
    candles = linear_candles([100, 100])
    bot = ScriptedBot({0: [{"side": "SELL", "qty": 1}]})
    res = BacktestEngine(cfg()).run(bot, candles, "SYM", "1h")
    assert res.rejected_orders == 1
    assert res.trades == []


# ─── Portfolio API used by bots ───────────────────────────────────────────


def test_portfolio_is_long_and_avg_entry():
    p = Portfolio()
    assert not p.is_long()
    assert p.open_qty() == 0.0
    assert p.avg_entry_price() == 0.0

    # Open two positions manually
    from backtester.core.engine import Position
    p.positions.append(Position(entry_price=100.0, qty=1.0, entry_idx=0, entry_time=0))
    p.positions.append(Position(entry_price=120.0, qty=2.0, entry_idx=1, entry_time=1))
    assert p.is_long()
    assert p.open_qty() == pytest.approx(3.0)
    # VWAP: (100*1 + 120*2) / 3 = 113.333…
    assert p.avg_entry_price() == pytest.approx((100 + 240) / 3.0)


def test_total_equity_marks_open_positions_to_market():
    from backtester.core.engine import Position
    p = Portfolio(cash=1_000.0)
    p.positions.append(Position(entry_price=50.0, qty=2.0, entry_idx=0, entry_time=0))
    assert p.total_equity(60.0) == pytest.approx(1_000.0 + 2.0 * 60.0)
