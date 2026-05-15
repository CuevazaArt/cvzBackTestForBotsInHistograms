"""Declarative strategy DSL.

Lets users describe bots in YAML without writing Python::

    name: "EMA cross with RSI filter"
    indicators:
      - ema(close, 12) as fast
      - ema(close, 26) as slow
      - rsi(close, 14) as rsi14
    entry:
      long: "fast > slow AND rsi14 < 70"
    exit:
      long: "fast < slow OR rsi14 > 80"
    risk:
      stop_loss_pct: 0.05
      take_profit_pct: 0.10
      size_pct: 2.0

Public entry points:

* :func:`parse_dsl` — text/dict → :class:`StrategySpec`.
* :class:`DSLBot` — runnable :class:`~backtester.bots.bot_base.BotBase` driven
  by a parsed :class:`StrategySpec`.

The DSL is deliberately stateless **per bar** (the rules see only the current
candle's indicator values). That covers the bulk of common technical setups
without dragging in a full expression engine; multi-bar features such as
``prev(close, n)`` can be added incrementally without breaking existing
strategies.
"""

from backtester.bots.dsl.parser import (
    DSLParseError,
    IndicatorBinding,
    StrategySpec,
    parse_dsl,
)
from backtester.bots.dsl.dsl_bot import DSLBot

__all__ = [
    "DSLBot",
    "DSLParseError",
    "IndicatorBinding",
    "StrategySpec",
    "parse_dsl",
]
