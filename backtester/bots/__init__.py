"""Trading bots for backtesting."""

from typing import Any, Callable

from backtester.bots.bot_base import BotBase
from backtester.bots.dorothy_dca import DorothyDCA
from backtester.bots.elphaba_short import ElphabaShort

BOT_REGISTRY: dict[str, Callable[..., Any]] = {
    "DorothyDCA": DorothyDCA,
    "ElphabaShort": ElphabaShort,
}

__all__ = [
    "BOT_REGISTRY",
    "BotBase",
    "DorothyDCA",
    "ElphabaShort",
]
