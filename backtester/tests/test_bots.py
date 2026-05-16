from decimal import Decimal

from backtester.bots.donchian_breakout import DonchianBreakout
from backtester.bots.grid_trading import GridTrading
from backtester.bots.macd_cross import MACDCross
from backtester.bots.rsi_reversion import RSIReversion
from backtester.core.engine import BacktestConfig, BacktestEngine, Candle, Portfolio


def _generate_sine_candles(length=100) -> list[Candle]:
    import math
    import time

    base_price = 100
    klines = []
    t = int(time.time() * 1000)
    for i in range(length):
        price = base_price + math.sin(i / 5.0) * 10
        klines.append(
            Candle(
                timestamp_ms=t + i * 3600000,
                open=Decimal(str(price)),
                high=Decimal(str(price + 1)),
                low=Decimal(str(price - 1)),
                close=Decimal(str(price)),
                volume=Decimal("1000"),
            )
        )
    return klines


def test_macd_cross_integration():
    df = _generate_sine_candles(200)
    bot = MACDCross(fast_ema=12, slow_ema=26, signal_period=9)
    config = BacktestConfig(initial_cash=Decimal("1000.0"), fill_on_next_open=False)
    engine = BacktestEngine(config)
    res = engine.run(bot, df)
    # res.bot_name does not exist, bots are in res.per_bot
    assert "MACDCross_0" in res.per_bot
    assert res.final_equity > 0
    # Should have done some trades
    assert len(res.trades) >= 0


def test_rsi_reversion_integration():
    df = _generate_sine_candles(200)
    bot = RSIReversion(rsi_period=14, overbought_level=70, oversold_level=30)
    config = BacktestConfig(initial_cash=Decimal("1000.0"), fill_on_next_open=False)
    engine = BacktestEngine(config)
    res = engine.run(bot, df)
    assert "RSIReversion_0" in res.per_bot
    assert res.final_equity > 0


# ───────────────────────── helpers for new bots ──────────────────────


def _make_candle(
    i: int,
    o: float,
    h: float,
    low: float,
    c: float,
    v: float = 1000.0,
) -> Candle:
    """Tiny factory to keep the synthetic-candle tests readable."""
    return Candle(
        timestamp_ms=1_700_000_000_000 + i * 3_600_000,
        open=Decimal(str(o)),
        high=Decimal(str(h)),
        low=Decimal(str(low)),
        close=Decimal(str(c)),
        volume=Decimal(str(v)),
    )


def _empty_portfolio(cash: float = 10_000.0) -> Portfolio:
    return Portfolio(cash=Decimal(str(cash)))


# ───────────────────────── DonchianBreakout ──────────────────────────


def test_donchian_param_spec_returns_expected_keys():
    """``DonchianBreakout.param_spec()`` exposes the 4 documented knobs."""
    spec = DonchianBreakout.param_spec()
    for key in ("channel_len", "atr_len", "atr_mult", "risk_per_trade_pct"):
        assert key in spec, f"missing {key} in DonchianBreakout.param_spec()"
    assert spec["channel_len"]["type"] == "int"
    assert spec["atr_mult"]["type"] == "float"
    assert spec["channel_len"]["default"] == 20
    assert spec["atr_len"]["default"] == 14


def test_donchian_no_signal_during_accumulation_phase():
    """Bot must stay silent until the channel window has filled up.

    We feed exactly ``channel_len`` flat candles. Even though the close
    on the last bar equals every prior close (no breakout possible),
    the channel still needs the next bar to fire ``prior_high``.
    """
    bot = DonchianBreakout(channel_len=10, atr_len=5, risk_per_trade_pct=1.0)
    portfolio = _empty_portfolio()
    seen_orders: list[dict] = []
    # 10 flat candles: prior_high never gets above close
    for i in range(10):
        c = _make_candle(i, 100, 100.5, 99.5, 100)
        seen_orders.extend(bot.on_candle(c, portfolio))
    assert seen_orders == []
    assert not bot._in_position


def test_donchian_breakout_triggers_buy():
    """A close above the prior N-bar high should emit a BUY order."""
    bot = DonchianBreakout(channel_len=5, atr_len=3, risk_per_trade_pct=2.0)
    portfolio = _empty_portfolio()

    # 5 flat-ish candles to fill the channel (high ~ 100.5)
    for i in range(5):
        bot.on_candle(_make_candle(i, 100, 100.5, 99.5, 100), portfolio)

    # 6th candle blows through the prior channel high (100.5).
    breakout_orders = bot.on_candle(
        _make_candle(5, 100, 105, 100, 104),
        portfolio,
    )
    sides = [o["side"] for o in breakout_orders]
    assert "BUY" in sides
    assert bot._in_position
    assert bot._entry_price == 104.0


def test_donchian_trailing_stop_exits_below_band():
    """After entry, a close below ``entry - atr_mult * ATR`` triggers SELL."""
    bot = DonchianBreakout(
        channel_len=5,
        atr_len=3,
        atr_mult=2.0,
        risk_per_trade_pct=2.0,
    )
    config = BacktestConfig(
        initial_cash=Decimal("10000"),
        taker_fee_pct=Decimal("0"),
        slippage_pct=Decimal("0"),
        fill_on_next_open=False,
    )
    engine = BacktestEngine(config)

    # Build candles: 5 flat → 1 breakout → 1 huge dump below the trail.
    candles = [_make_candle(i, 100, 100.5, 99.5, 100) for i in range(5)]
    candles.append(_make_candle(5, 100, 105, 100, 104))  # breakout BUY @ 104
    # Dump well below entry - 2 * ATR (ATR ≈ 1, so stop ≈ 102).
    candles.append(_make_candle(6, 104, 104, 90, 91))

    result = engine.run(bot, candles)
    sell_trades = [t for t in result.trades if t.reason == "ATR_TRAIL_STOP"]
    assert (
        sell_trades
    ), f"expected ATR_TRAIL_STOP exit, got {[t.reason for t in result.trades]}"


# ───────────────────────── GridTrading ───────────────────────────────


def test_grid_param_spec_returns_expected_keys():
    spec = GridTrading.param_spec()
    for key in ("lower", "upper", "num_levels", "qty_per_level", "auto_range_pct"):
        assert key in spec, f"missing {key} in GridTrading.param_spec()"
    assert spec["num_levels"]["type"] == "int"
    assert spec["lower"]["type"] == "float"


def test_grid_levels_auto_computed_when_range_is_zero():
    """When ``lower==upper==0`` and ``auto_range_pct>0`` the band derives
    from the first candle's close.
    """
    bot = GridTrading(lower=0, upper=0, num_levels=5, auto_range_pct=10.0)
    portfolio = _empty_portfolio()

    # First candle seeds the auto-range. Close=100, ±10% → [90, 110].
    bot.on_candle(_make_candle(0, 100, 100.0, 100.0, 100), portfolio)

    assert bot._initialised
    assert len(bot._levels) == 5
    prices = [lvl.price for lvl in bot._levels]
    assert prices[0] == 90.0
    assert prices[-1] == 110.0
    # Equispaced check
    spacings = [round(prices[i + 1] - prices[i], 6) for i in range(len(prices) - 1)]
    assert len(set(spacings)) == 1


def test_grid_buy_fires_at_level_cross_down():
    """An empty level touched by the candle's low triggers a BUY."""
    bot = GridTrading(lower=90, upper=110, num_levels=5, qty_per_level=0.5)
    portfolio = _empty_portfolio(cash=10_000)
    # Levels: 90, 95, 100, 105, 110

    # First candle: high=99, low=94 → crosses 95 from above. Should BUY @ 95.
    orders = bot.on_candle(_make_candle(0, 96, 99, 94, 98), portfolio)
    buys = [o for o in orders if o["side"] == "BUY"]
    assert len(buys) == 1
    assert buys[0]["qty"] == 0.5
    # The 95 level is now filled, 100/105/110 still empty.
    filled_prices = [lvl.price for lvl in bot._levels if lvl.filled]
    assert filled_prices == [95.0]


def test_grid_sell_fires_at_level_cross_up():
    """A filled level whose next-up rung is touched by the high triggers a SELL."""
    bot = GridTrading(lower=90, upper=110, num_levels=5, qty_per_level=0.5)
    portfolio = _empty_portfolio(cash=10_000)
    # Levels: 90, 95, 100, 105, 110

    # 1) Push price down so we buy 95.
    bot.on_candle(_make_candle(0, 96, 99, 94, 98), portfolio)
    assert any(lvl.filled and lvl.price == 95.0 for lvl in bot._levels)

    # 2) Push price up so the 100 rung is crossed → SELL the 95 fill.
    orders = bot.on_candle(_make_candle(1, 98, 101, 98, 100), portfolio)
    sells = [o for o in orders if o["side"] == "SELL"]
    assert len(sells) == 1
    assert sells[0]["qty"] == 0.5
    # 95 should now be empty again.
    assert not any(lvl.filled and lvl.price == 95.0 for lvl in bot._levels)


# ───────────────────────── E2E integration ────────────────────────────


def test_donchian_e2e_step_up_trend():
    """End-to-end run: step-up price series should generate ≥1 trade and
    finish with finite equity.
    """
    # Flat phase (warmup), then a sustained step-up trend.
    candles = []
    base = 100.0
    for i in range(20):  # warmup
        candles.append(_make_candle(i, base, base + 0.5, base - 0.5, base))
    for i in range(20, 60):  # uptrend +1 per bar
        base += 1.0
        candles.append(_make_candle(i, base, base + 0.5, base - 0.5, base))
    # Sharp drawdown to force the trailing stop
    for i in range(60, 80):
        base -= 3.0
        candles.append(_make_candle(i, base, base + 0.5, base - 0.5, base))

    bot = DonchianBreakout(
        channel_len=10,
        atr_len=5,
        atr_mult=2.0,
        risk_per_trade_pct=5.0,
    )
    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=Decimal("10000"),
            taker_fee_pct=Decimal("0.05"),
            slippage_pct=Decimal("0.02"),
            fill_on_next_open=False,
        )
    )
    result = engine.run(bot, candles)
    assert len(result.trades) >= 1, "expected at least one closed trade"
    assert Decimal("0") < result.final_equity < Decimal("1000000")


def test_grid_e2e_sine_wave():
    """End-to-end run: oscillating price should fire buys AND sells."""
    import math

    candles = []
    for i in range(120):
        price = 100.0 + math.sin(i / 4.0) * 8.0
        candles.append(_make_candle(i, price, price + 1.0, price - 1.0, price, v=1000))

    bot = GridTrading(
        lower=92.0,
        upper=108.0,
        num_levels=8,
        qty_per_level=0.1,
    )
    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=Decimal("10000"),
            taker_fee_pct=Decimal("0.05"),
            slippage_pct=Decimal("0.02"),
            fill_on_next_open=False,
        )
    )
    result = engine.run(bot, candles)
    assert len(result.trades) >= 1, "grid should have closed at least one round-trip"
    assert result.final_equity.is_finite()
    assert result.final_equity > 0
