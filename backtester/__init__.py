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
    BotBase,
    DorothyDCA,
    ElphabaShort,
    get_bot_class,
    instantiate_bot,
    list_bot_names,
    validate_registry,
)
from backtester.analysis import run_stress_battery
from backtester.core import (
    BacktestConfig,
    BacktestEngine,
    BinanceDownloader,
    Candle,
    CredentialManager,
    Portfolio,
    compute_metrics,
)
from backtester.core.data_quality import DataQualityReport, validate_ohlcv
from backtester.core.engine import BacktestResult, Trade
from backtester.core.metrics import deflated_sharpe_ratio

__version__ = "0.6.0"

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
    "DorothyDCA",
    "ElphabaShort",
    "get_bot_class",
    "instantiate_bot",
    "list_bot_names",
    "validate_registry",
    # Data + infra
    "BinanceDownloader",
    "CredentialManager",
    "DataQualityReport",
    "validate_ohlcv",
    "run_stress_battery",
    "deflated_sharpe_ratio",
    "compute_metrics",
    "__version__",
]
