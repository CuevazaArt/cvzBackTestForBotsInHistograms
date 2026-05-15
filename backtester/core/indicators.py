"""Technical indicators calculated over historical candles.

Supported indicators:
    Price-overlay (plotted on main chart):
        ema   — Exponential Moving Average
        sma   — Simple Moving Average
        bb    — Bollinger Bands (upper, middle, lower)
        vwap  — Volume-Weighted Average Price (session-cumulative)

    Oscillators (plotted on sub-panel below main chart):
        rsi   — Relative Strength Index
        macd  — MACD line, signal line, histogram
        stoch — Stochastic Oscillator (%K, %D)
"""

from __future__ import annotations

from typing import Any

import pandas as pd

from backtester.core.engine import Candle

# Indicators that are plotted on the price axis (overlay)
OVERLAY_INDICATORS = {"ema", "sma", "bb", "vwap"}

# Indicators that are plotted on a separate oscillator panel
OSCILLATOR_INDICATORS = {"rsi", "macd", "stoch"}


# ── Individual calculators ────────────────────────────────────────────────────


def calculate_ema(
    df: pd.DataFrame, period: int = 20, column: str = "close"
) -> dict[str, pd.Series]:
    """Exponential Moving Average."""
    return {f"ema_{period}": df[column].ewm(span=period, adjust=False).mean()}


def calculate_sma(
    df: pd.DataFrame, period: int = 20, column: str = "close"
) -> dict[str, pd.Series]:
    """Simple Moving Average."""
    return {f"sma_{period}": df[column].rolling(window=period).mean()}


def calculate_rsi(
    df: pd.DataFrame, period: int = 14, column: str = "close"
) -> dict[str, pd.Series]:
    """Relative Strength Index (Wilder's SMMA)."""
    delta = df[column].diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
    rs = avg_gain / avg_loss
    return {f"rsi_{period}": 100 - (100 / (1 + rs))}


def calculate_macd(
    df: pd.DataFrame,
    fast: int = 12,
    slow: int = 26,
    signal: int = 9,
    column: str = "close",
) -> dict[str, pd.Series]:
    """MACD: line, signal, histogram."""
    fast_ema = df[column].ewm(span=fast, adjust=False).mean()
    slow_ema = df[column].ewm(span=slow, adjust=False).mean()
    macd_line = fast_ema - slow_ema
    signal_line = macd_line.ewm(span=signal, adjust=False).mean()
    histogram = macd_line - signal_line
    tag = f"macd_{fast}_{slow}_{signal}"
    return {
        f"{tag}_line": macd_line,
        f"{tag}_signal": signal_line,
        f"{tag}_hist": histogram,
    }


def calculate_bollinger(
    df: pd.DataFrame,
    period: int = 20,
    std_dev: float = 2.0,
    column: str = "close",
) -> dict[str, pd.Series]:
    """Bollinger Bands: upper, middle (SMA), lower."""
    middle = df[column].rolling(window=period).mean()
    std = df[column].rolling(window=period).std()
    return {
        f"bb_{period}_upper": middle + std_dev * std,
        f"bb_{period}_middle": middle,
        f"bb_{period}_lower": middle - std_dev * std,
    }


def calculate_stochastic(
    df: pd.DataFrame,
    k_period: int = 14,
    d_period: int = 3,
) -> dict[str, pd.Series]:
    """Stochastic Oscillator (%K, %D)."""
    low_min = df["low"].rolling(window=k_period).min()
    high_max = df["high"].rolling(window=k_period).max()
    k = 100 * (df["close"] - low_min) / (high_max - low_min)
    d = k.rolling(window=d_period).mean()
    return {
        f"stoch_{k_period}_k": k,
        f"stoch_{k_period}_d": d,
    }


def calculate_vwap(df: pd.DataFrame, **_: Any) -> dict[str, pd.Series]:
    """Session-cumulative VWAP (resets on each call — treat as full-period)."""
    typical_price = (df["high"] + df["low"] + df["close"]) / 3
    cum_vol = df["volume"].cumsum()
    cum_tp_vol = (typical_price * df["volume"]).cumsum()
    return {"vwap": cum_tp_vol / cum_vol}


# ── Registry ──────────────────────────────────────────────────────────────────

_REGISTRY: dict[str, Any] = {
    "ema": calculate_ema,
    "sma": calculate_sma,
    "rsi": calculate_rsi,
    "macd": calculate_macd,
    "bb": calculate_bollinger,
    "stoch": calculate_stochastic,
    "vwap": calculate_vwap,
}


# ── Public API ────────────────────────────────────────────────────────────────


def add_indicators(
    candles: list[Candle],
    specs: list[dict[str, Any]],
) -> dict[str, list[float | None]]:
    """Calculate multiple indicators aligned to candles.

    Args:
        candles: List of OHLCV candles.
        specs:   List of indicator configs, e.g.:
                   [{"name": "ema",  "period": 9},
                    {"name": "macd", "fast": 12, "slow": 26, "signal": 9},
                    {"name": "bb",   "period": 20},
                    {"name": "stoch","k_period": 14, "d_period": 3},
                    {"name": "vwap"}]

    Returns:
        Dict where each key is a series ID (e.g. ``"ema_9"``,
        ``"macd_12_26_9_line"``) and each value is a list of floats
        (NaN → None) aligned with ``candles``.
    """
    if not candles or not specs:
        return {}

    df = pd.DataFrame(
        [
            {
                "open": float(c.open),
                "high": float(c.high),
                "low": float(c.low),
                "close": float(c.close),
                "volume": float(c.volume),
            }
            for c in candles
        ]
    )

    results: dict[str, list[float | None]] = {}

    for spec in specs:
        name = spec.get("name", "").lower()
        if name not in _REGISTRY:
            continue

        # Build kwargs from spec (exclude 'name')
        kwargs = {k: v for k, v in spec.items() if k != "name"}

        try:
            series_dict = _REGISTRY[name](df, **kwargs)
        except Exception:  # noqa: BLE001
            continue

        for series_id, series in series_dict.items():
            results[series_id] = [None if pd.isna(x) else float(x) for x in series]

    return results


def is_oscillator(series_id: str) -> bool:
    """Return True if the series belongs to an oscillator (sub-panel) indicator."""
    prefix = series_id.split("_")[0]
    return prefix in OSCILLATOR_INDICATORS
