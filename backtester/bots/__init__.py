"""Trading bots for backtesting."""

from typing import Any, Callable

from backtester.bots.bot_base import BotBase
from backtester.bots.bollinger_reversion import BollingerReversion
from backtester.bots.bot_template import ExampleTemplateBot
from backtester.bots.donchian_breakout import DonchianBreakout
from backtester.bots.dorothy_dca import DorothyDCA
from backtester.bots.dsl.dsl_bot import DSLBot
from backtester.bots.elphaba_short import ElphabaShort
from backtester.bots.ema_cross import EMACross
from backtester.bots.grid_trading import GridTrading
from backtester.bots.macd_cross import MACDCross
from backtester.bots.registry import (
    BOT_REGISTRY,
    default_params_for,
    get_bot_class,
    instantiate_bot,
    list_bot_names,
    validate_registry,
)
from backtester.bots.rsi_reversion import RSIReversion

__all__ = [
    "BOT_REGISTRY",
    "BotBase",
    "BollingerReversion",
    "DonchianBreakout",
    "DorothyDCA",
    "DSLBot",
    "EMACross",
    "ElphabaShort",
    "ExampleTemplateBot",
    "GridTrading",
    "MACDCross",
    "RSIReversion",
    "default_params_for",
    "get_bot_class",
    "instantiate_bot",
    "list_bot_names",
    "validate_registry",
]
