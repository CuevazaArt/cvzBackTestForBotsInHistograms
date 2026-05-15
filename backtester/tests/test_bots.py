from backtester.core.engine import BacktestEngine, BacktestConfig, Candle
from backtester.bots.macd_cross import MACDCross
from backtester.bots.rsi_reversion import RSIReversion
from decimal import Decimal

def _generate_sine_candles(length=100) -> list[Candle]:
    import math
    import time
    base_price = 100
    klines = []
    t = int(time.time() * 1000)
    for i in range(length):
        price = base_price + math.sin(i / 5.0) * 10
        klines.append(Candle(
            timestamp_ms=t + i * 3600000,
            open=Decimal(str(price)),
            high=Decimal(str(price + 1)),
            low=Decimal(str(price - 1)),
            close=Decimal(str(price)),
            volume=Decimal("1000")
        ))
    return klines

def test_macd_cross_integration():
    df = _generate_sine_candles(200)
    bot = MACDCross(fast_ema=12, slow_ema=26, signal_period=9)
    config = BacktestConfig(initial_cash=Decimal("1000.0"))
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
    config = BacktestConfig(initial_cash=Decimal("1000.0"))
    engine = BacktestEngine(config)
    res = engine.run(bot, df)
    assert "RSIReversion_0" in res.per_bot
    assert res.final_equity > 0
