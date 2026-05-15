"""cvz-backtester — installable backtester SDK.

This top-level package re-exports the most useful symbols from the internal
submodules so SDK users can do::

    from backtester import BacktestEngine, BacktestConfig, BOT_REGISTRY

without having to remember which sub-module each class lives in. Submodules
remain importable for advanced usage (``from backtester.analysis import
walk_forward``).
"""

from backtester.bots import (
    BOT_REGISTRY,
    BollingerReversion,
    BotBase,
    DorothyDCA,
    DSLBot,
    EMACross,
    MACDCross,
    RSIReversion,
)
from backtester.core import (
    BacktestConfig,
    BacktestEngine,
    BinanceDownloader,
    Candle,
    CredentialManager,
    Portfolio,
    compute_metrics,
)
from backtester.core.engine import BacktestResult, Trade

__version__ = "0.5.1"

__all__ = [
    # Engine
    "BacktestEngine",
    "BacktestConfig",
    "BacktestResult",
    "Candle",
    "Portfolio",
    "Trade",
    # Bots
    "BotBase",
    "BOT_REGISTRY",
    "EMACross",
    "RSIReversion",
    "MACDCross",
    "BollingerReversion",
    "DorothyDCA",
    "DSLBot",
    # Data + infra
    "BinanceDownloader",
    "CredentialManager",
    "compute_metrics",
    "__version__",
]
