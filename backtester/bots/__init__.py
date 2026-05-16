"""Trading bots for backtesting."""

from backtester.bots.bollinger_reversion import BollingerReversion
from backtester.bots.bot_base import BotBase
from backtester.bots.donchian_breakout import DonchianBreakout
from backtester.bots.dorothy_dca import DorothyDCA
from backtester.bots.dsl import DSLBot
from backtester.bots.ema_cross import EMACross
from backtester.bots.grid_trading import GridTrading
from backtester.bots.macd_cross import MACDCross
from backtester.bots.rsi_reversion import RSIReversion

BOT_REGISTRY: dict[str, type] = {
    "BollingerReversion": BollingerReversion,
    "DonchianBreakout": DonchianBreakout,
    "DorothyDCA": DorothyDCA,
    "DSL": DSLBot,
    "EMACross": EMACross,
    "GridTrading": GridTrading,
    "MACDCross": MACDCross,
    "RSIReversion": RSIReversion,
}

__all__ = [
    "BOT_REGISTRY",
    "BollingerReversion",
    "BotBase",
    "DonchianBreakout",
    "DorothyDCA",
    "DSLBot",
    "EMACross",
    "GridTrading",
    "MACDCross",
    "RSIReversion",
]
