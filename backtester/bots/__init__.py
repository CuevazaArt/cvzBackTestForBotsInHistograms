"""Trading bots for backtesting."""

from backtester.bots.bot_base import BotBase
from backtester.bots.dorothy_dca import DorothyDCA
from backtester.bots.ema_cross import EMACross
from backtester.bots.macd_cross import MACDCross
from backtester.bots.rsi_reversion import RSIReversion

__all__ = ["BotBase", "DorothyDCA", "EMACross", "MACDCross", "RSIReversion"]
