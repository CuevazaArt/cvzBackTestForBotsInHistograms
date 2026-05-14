"""Trading bots for backtesting."""

from backtester.bots.bot_base import BotBase
from backtester.bots.ema_cross import EMACross
from backtester.bots.rsi_reversion import RSIReversion

__all__ = ["BotBase", "EMACross", "RSIReversion"]
