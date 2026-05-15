"""Trading bots for backtesting."""

from backtester.bots.bot_base import BotBase
from backtester.bots.bollinger_reversion import BollingerReversion
from backtester.bots.dorothy_dca import DorothyDCA
from backtester.bots.dsl import DSLBot
from backtester.bots.ema_cross import EMACross
from backtester.bots.macd_cross import MACDCross
from backtester.bots.rsi_reversion import RSIReversion

BOT_REGISTRY: dict[str, type] = {
    "EMACross": EMACross,
    "RSIReversion": RSIReversion,
    "MACDCross": MACDCross,
    "DorothyDCA": DorothyDCA,
    "BollingerReversion": BollingerReversion,
    "DSL": DSLBot,
}

__all__ = [
    "BotBase",
    "DorothyDCA",
    "DSLBot",
    "EMACross",
    "MACDCross",
    "RSIReversion",
    "BollingerReversion",
    "BOT_REGISTRY",
]
