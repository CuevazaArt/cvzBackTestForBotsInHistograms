"""Technical indicators calculated over historical candles."""

from __future__ import annotations

from typing import Any, Callable

import pandas as pd
from backtester.core.engine import Candle


def calculate_ema(df: pd.DataFrame, period: int = 20, column: str = "close") -> pd.Series:
    """Calculate Exponential Moving Average."""
    return df[column].ewm(span=period, adjust=False).mean()


def calculate_sma(df: pd.DataFrame, period: int = 20, column: str = "close") -> pd.Series:
    """Calculate Simple Moving Average."""
    return df[column].rolling(window=period).mean()


def calculate_rsi(df: pd.DataFrame, period: int = 14, column: str = "close") -> pd.Series:
    """Calculate Relative Strength Index."""
    delta = df[column].diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    
    avg_gain = gain.rolling(window=period, min_periods=period).mean()
    avg_loss = loss.rolling(window=period, min_periods=period).mean()
    
    rs = avg_gain / avg_loss
    return 100 - (100 / (1 + rs))


# Registry mapping name -> function
INDICATORS: dict[str, Callable[[pd.DataFrame, int], pd.Series]] = {
    "ema": calculate_ema,
    "sma": calculate_sma,
    "rsi": calculate_rsi,
}


def add_indicators(candles: list[Candle], specs: list[dict[str, Any]]) -> dict[str, list[float]]:
    """
    Calculate multiple indicators and return them as a dictionary of lists aligned with candles.
    
    Args:
        candles: List of OHLCV candles
        specs: List of indicator configs, e.g. [{"name": "ema", "period": 9}, ...]
        
    Returns:
        dict where key is the indicator ID (e.g., "ema_9") and value is a list of floats (NaNs as None).
    """
    if not candles or not specs:
        return {}

    df = pd.DataFrame([{
        "open": float(c.open),
        "high": float(c.high),
        "low": float(c.low),
        "close": float(c.close),
        "volume": float(c.volume)
    } for c in candles])

    results: dict[str, list[float | None]] = {}

    for spec in specs:
        name = spec.get("name", "").lower()
        period = int(spec.get("period", 20))
        
        if name not in INDICATORS:
            continue
            
        series = INDICATORS[name](df, period)
        # Convert NaN to None for JSON serialization
        results[f"{name}_{period}"] = [
            None if pd.isna(x) else float(x) for x in series
        ]

    return results
