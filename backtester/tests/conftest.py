"""Shared pytest fixtures + tiny helpers."""

from __future__ import annotations

from typing import Any

import pytest

from backtester.core.engine import Candle


def make_candle(t: int, o: float, h: float, l: float, c: float, v: float = 100.0) -> Candle:
    """One candle, time in epoch ms."""
    return Candle(timestamp_ms=t, open=o, high=h, low=l, close=c, volume=v)


def linear_candles(prices: list[float], start_ms: int = 1_700_000_000_000,
                   step_ms: int = 3_600_000) -> list[Candle]:
    """Build candles from a list of closes; OHLC are equal to the close."""
    return [
        Candle(timestamp_ms=start_ms + i * step_ms, open=p, high=p, low=p, close=p, volume=1.0)
        for i, p in enumerate(prices)
    ]


@pytest.fixture()
def make_candle_fixture():
    return make_candle


@pytest.fixture()
def linear_candles_fixture():
    return linear_candles
