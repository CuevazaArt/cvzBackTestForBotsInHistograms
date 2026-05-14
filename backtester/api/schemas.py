"""Pydantic models for HTTP/WebSocket payloads."""

from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel, Field


# ───────────────────────── Bots ─────────────────────────


class BotInfo(BaseModel):
    name: str
    description: Optional[str] = None


class ParamSpec(BaseModel):
    type: str  # "int" | "float" | "str"
    default: Any
    min: Optional[float] = None
    max: Optional[float] = None
    step: Optional[float] = None


class BotParamsResponse(BaseModel):
    name: str
    params: dict[str, ParamSpec]


# ───────────────────────── Candles ─────────────────────────


class CandleDTO(BaseModel):
    """Lightweight Charts expects `time` in seconds (epoch)."""
    time: int
    open: float
    high: float
    low: float
    close: float
    volume: float


class SymbolEntry(BaseModel):
    symbol: str
    timeframe: str
    candles: int
    first_ms: Optional[int] = None
    last_ms: Optional[int] = None


class DownloadRequest(BaseModel):
    symbol: str
    timeframe: str
    date_from: str    # "YYYY-MM-DD"
    date_to: str      # "YYYY-MM-DD"


class DownloadZipRequest(BaseModel):
    symbol: str
    timeframe: str
    year: int
    month: int


class JobStatus(BaseModel):
    id: str
    kind: str          # "download" | "experiment"
    status: str        # "pending" | "running" | "done" | "error"
    progress: float = 0.0
    message: Optional[str] = None
    result: Optional[dict[str, Any]] = None


# ───────────────────────── Backtest ─────────────────────────


class IndicatorSpec(BaseModel):
    name: str
    period: int


class BotRunSpec(BaseModel):
    name: str
    params: dict[str, Any] = Field(default_factory=dict)


class BacktestRequest(BaseModel):
    bots: list[BotRunSpec]
    indicators: list[IndicatorSpec] = Field(default_factory=list)
    symbol: str
    timeframe: str
    start_ms: Optional[int] = None
    end_ms: Optional[int] = None
    initial_cash: float = 10000.0
    taker_fee_pct: float = 0.1
    slippage_pct: float = 0.05


class TradeDTO(BaseModel):
    entry_time: int     # epoch seconds
    exit_time: int      # epoch seconds
    entry_price: float
    exit_price: float
    qty: float
    pnl: float
    pnl_pct: float
    fee_usdt: float
    reason: str


class EquityPoint(BaseModel):
    time: int           # epoch seconds
    value: float


class BacktestResponse(BaseModel):
    symbol: str
    timeframe: str
    bots: list[BotRunSpec]
    summary: dict[str, Any]
    trades: list[TradeDTO]
    equity_curve: list[EquityPoint]


# ───────────────────────── Experiments ─────────────────────────


class ExperimentSpec(BaseModel):
    name: str                          # bot class
    configs: list[dict[str, Any]]      # list of param sets


class ExperimentsRequest(BaseModel):
    symbol: str
    timeframe: str
    bots: list[ExperimentSpec]
    workers: int = 4


# ───────────────────────── Credentials ─────────────────────────


class CredentialsRequest(BaseModel):
    api_key: str
    api_secret: str


class CredentialsStatus(BaseModel):
    exists: bool
