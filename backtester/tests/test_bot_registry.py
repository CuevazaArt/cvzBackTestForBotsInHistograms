"""Registry integrity — every shipped bot is discoverable and instantiable."""

from __future__ import annotations

import inspect

import pytest

from backtester.bots import BOT_REGISTRY, instantiate_bot, validate_registry
from backtester.bots.bot_base import BotBase
from backtester.bots.registry import _BOT_CLASSES, default_params_for
from backtester.core.engine import BacktestEngine, BacktestConfig, Candle
from decimal import Decimal


EXPECTED_BOT_NAMES = {
    "BollingerReversion",
    "DonchianBreakout",
    "DorothyDCA",
    "DSLBot",
    "EMACross",
    "ElphabaShort",
    "GridTrading",
    "MACDCross",
    "RSIReversion",
}


def test_registry_lists_all_bot_classes():
    assert set(BOT_REGISTRY.keys()) == EXPECTED_BOT_NAMES
    assert len(_BOT_CLASSES) == len(EXPECTED_BOT_NAMES)


def test_validate_registry_clean():
    assert validate_registry() == []


@pytest.mark.parametrize("name", sorted(EXPECTED_BOT_NAMES))
def test_each_bot_is_botbase_and_instantiates(name: str):
    cls = BOT_REGISTRY[name]
    assert inspect.isclass(cls)
    assert issubclass(cls, BotBase)
    bot = instantiate_bot(name)
    assert isinstance(bot, BotBase)
    spec = cls.param_spec()
    assert isinstance(spec, dict)
    defaults = default_params_for(cls)
    bot2 = cls(**defaults)
    assert isinstance(bot2, BotBase)


def test_unknown_bot_raises():
    with pytest.raises(KeyError):
        instantiate_bot("NotARealBot")


def test_dsl_bot_requires_dsl_text_default():
    bot = instantiate_bot("DSLBot")
    assert hasattr(bot, "spec")


def test_registry_bot_runs_on_synthetic_candles():
    """Smoke: defaults + engine must not crash (logic may or may not trade)."""
    candles = [
        Candle(
            timestamp_ms=1_700_000_000_000 + i * 3_600_000,
            open=Decimal("100"),
            high=Decimal("101"),
            low=Decimal("99"),
            close=Decimal(str(100 + (i % 5) - 2)),
            volume=Decimal("1000"),
        )
        for i in range(80)
    ]
    engine = BacktestEngine(
        BacktestConfig(initial_cash=Decimal("10000"), fill_on_next_open=False)
    )
    for name in sorted(EXPECTED_BOT_NAMES):
        bot = instantiate_bot(name)
        res = engine.run([bot], candles, symbol="BTCUSDT", timeframe="1h", bot_names=[name])
        assert res.candles_processed == len(candles)
        assert res.final_equity > 0
