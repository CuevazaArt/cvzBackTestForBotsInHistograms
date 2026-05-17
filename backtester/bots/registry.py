"""Central bot registry — single source of truth for API, CLI, and tests.

Register new strategies here only. The backtester never patches bot source
code: it instantiates your class with UI/API params and calls ``on_candle``.
"""

from __future__ import annotations

import inspect
from typing import Any, Callable, TypeVar

from backtester.bots.bot_base import BotBase
from backtester.bots.bollinger_reversion import BollingerReversion
from backtester.bots.donchian_breakout import DonchianBreakout
from backtester.bots.dorothy_dca import DorothyDCA
from backtester.bots.dsl.dsl_bot import DSLBot
from backtester.bots.elphaba_short import ElphabaShort
from backtester.bots.ema_cross import EMACross
from backtester.bots.grid_trading import GridTrading
from backtester.bots.macd_cross import MACDCross
from backtester.bots.rsi_reversion import RSIReversion

BotT = TypeVar("BotT", bound=BotBase)

# Names must match class names unless noted. Order is UI list order (stable).
_BOT_CLASSES: tuple[type[BotBase], ...] = (
    BollingerReversion,
    DonchianBreakout,
    DorothyDCA,
    DSLBot,
    EMACross,
    ElphabaShort,
    GridTrading,
    MACDCross,
    RSIReversion,
)


def build_bot_registry() -> dict[str, Callable[..., Any]]:
    """Return a fresh name → class map (used by AppContext and tests)."""
    registry: dict[str, Callable[..., Any]] = {}
    for cls in _BOT_CLASSES:
        name = cls.__name__
        if name in registry:
            raise ValueError(f"Duplicate bot registry name: {name}")
        if not issubclass(cls, BotBase):
            raise TypeError(f"{name} must extend BotBase")
        registry[name] = cls
    return registry


BOT_REGISTRY: dict[str, Callable[..., Any]] = build_bot_registry()


def list_bot_names() -> list[str]:
    return sorted(BOT_REGISTRY.keys())


def get_bot_class(name: str) -> type[BotBase] | None:
    cls = BOT_REGISTRY.get(name)
    return cls  # type: ignore[return-value]


def default_params_for(cls: type[BotBase]) -> dict[str, Any]:
    """Build kwargs from ``param_spec()`` defaults (what the UI sends on first load)."""
    spec = cls.param_spec() if hasattr(cls, "param_spec") else {}
    return {key: field.get("default") for key, field in spec.items()}


def instantiate_bot(name: str, params: dict[str, Any] | None = None) -> BotBase:
    """Instantiate a registered bot; raises KeyError / TypeError on bad input."""
    cls = get_bot_class(name)
    if cls is None:
        raise KeyError(f"Unknown bot: {name}")
    kwargs = default_params_for(cls) if params is None else dict(params)
    return cls(**kwargs)


def validate_registry() -> list[str]:
    """Return human-readable problems (empty list = OK)."""
    errors: list[str] = []
    for name, cls in BOT_REGISTRY.items():
        if not inspect.isclass(cls):
            errors.append(f"{name}: registry entry is not a class")
            continue
        if not issubclass(cls, BotBase):
            errors.append(f"{name}: does not extend BotBase")
        if cls.__name__ != name:
            errors.append(
                f"{name}: registry key != class name ({cls.__name__}); "
                "use the class name as the key for predictable API/UI wiring"
            )
        try:
            bot = instantiate_bot(name)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{name}: cannot instantiate with defaults: {exc}")
            continue
        if not hasattr(bot, "on_candle") or not callable(bot.on_candle):
            errors.append(f"{name}: missing callable on_candle")
    return errors
