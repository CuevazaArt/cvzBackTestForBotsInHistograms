"""Pydantic models for HTTP/WebSocket payloads."""

from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel, Field, field_validator, model_validator


# Bots whose params include a fast/slow EMA pair that must be ordered correctly.
_EMA_ORDERED_BOTS = {"EMACross", "MACDCross"}


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
    """Flexible indicator spec — passes all fields except 'name' as kwargs."""
    name: str
    # Common period-based params
    period: Optional[int] = None
    # MACD-specific
    fast: Optional[int] = None
    slow: Optional[int] = None
    signal: Optional[int] = None
    # Stochastic-specific
    k_period: Optional[int] = None
    d_period: Optional[int] = None
    # Bollinger std multiplier
    std_dev: Optional[float] = None

    def to_kwargs(self) -> dict[str, Any]:
        """Return all non-None non-name fields as a kwargs dict."""
        return {
            k: v for k, v in self.model_dump().items()
            if k != "name" and v is not None
        }


class BotRunSpec(BaseModel):
    name: str
    params: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def _validate_param_relationships(self) -> "BotRunSpec":
        # Only validate fast/slow EMA pairs for bots that expose both.
        if self.name in _EMA_ORDERED_BOTS:
            fast = self.params.get("fast_ema")
            slow = self.params.get("slow_ema")
            if fast is not None and slow is not None and fast >= slow:
                raise ValueError(
                    f"[{self.name}] fast_ema ({fast}) must be < slow_ema ({slow})"
                )
        return self


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

    @field_validator("initial_cash")
    @classmethod
    def _cash_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("initial_cash must be > 0")
        return v

    @field_validator("taker_fee_pct", "slippage_pct")
    @classmethod
    def _non_negative(cls, v: float) -> float:
        if v < 0:
            raise ValueError("must be >= 0")
        return v

    @model_validator(mode="after")
    def _validate_time_range(self) -> "BacktestRequest":
        if (
            self.start_ms is not None
            and self.end_ms is not None
            and self.start_ms >= self.end_ms
        ):
            raise ValueError(
                f"start_ms ({self.start_ms}) must be < end_ms ({self.end_ms})"
            )
        if not self.bots:
            raise ValueError("at least one bot is required")
        return self


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
    bot_id: str = ""


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
    per_bot: dict[str, Any] = Field(default_factory=dict)


# ───────────────────────── Experiments ─────────────────────────


class ExperimentSpec(BaseModel):
    name: str                          # bot class
    configs: list[dict[str, Any]]      # list of param sets

    @model_validator(mode="after")
    def _validate_configs(self) -> "ExperimentSpec":
        if not self.configs:
            raise ValueError(f"[{self.name}] configs list cannot be empty")
        # If bot uses fast_ema/slow_ema pair, validate each config.
        if self.name in _EMA_ORDERED_BOTS:
            for i, cfg in enumerate(self.configs):
                fast = cfg.get("fast_ema")
                slow = cfg.get("slow_ema")
                if fast is not None and slow is not None and fast >= slow:
                    raise ValueError(
                        f"[{self.name}] config[{i}]: fast_ema ({fast}) must be < slow_ema ({slow})"
                    )
        return self


class ExperimentsRequest(BaseModel):
    symbol: str
    timeframe: str
    bots: list[ExperimentSpec]
    workers: int = 4

    @field_validator("workers")
    @classmethod
    def _workers_range(cls, v: int) -> int:
        if v < 1 or v > 32:
            raise ValueError("workers must be between 1 and 32")
        return v

    @model_validator(mode="after")
    def _validate_total_configs(self) -> "ExperimentsRequest":
        total = sum(len(b.configs) for b in self.bots)
        if total == 0:
            raise ValueError("at least one experiment config is required")
        if total > 1000:
            raise ValueError(
                f"too many experiments ({total}); cap is 1000. "
                "Reduce parameter steps or split the sweep."
            )
        return self


# ───────────────────────── Optimizer (Optuna / Nevergrad) ──────


class SearchSpaceParam(BaseModel):
    """One dimension of the search space."""
    type: str = "float"         # "int" | "float"
    low: float
    high: float
    step: Optional[float] = None
    log: bool = False
    choices: Optional[list[Any]] = None     # categorical override


class OptimizeRequest(BaseModel):
    """Kick off a real Optuna / Nevergrad optimization run."""
    symbol: str
    timeframe: str
    bot: str                                  # single bot name
    search_space: dict[str, SearchSpaceParam]
    fixed_params: dict[str, Any] = Field(default_factory=dict)
    objective: str = "total_return_pct"       # metric to optimize
    trials: int = 100
    sampler: str = "tpe"                      # tpe | cmaes | random
    initial_cash: float = 10000.0
    taker_fee_pct: float = 0.1
    slippage_pct: float = 0.05
    workers: int = 1                          # Optuna is single-threaded by default

    @field_validator("trials")
    @classmethod
    def _trials_range(cls, v: int) -> int:
        if v < 1 or v > 5000:
            raise ValueError("trials must be between 1 and 5000")
        return v

    @field_validator("objective")
    @classmethod
    def _valid_objective(cls, v: str) -> str:
        valid = {"total_return_pct", "win_rate_pct", "profit_factor",
                 "max_drawdown_pct", "trades"}
        if v not in valid:
            raise ValueError(f"objective must be one of {valid}")
        return v


# ───────────────────────── Credentials ─────────────────────────


class CredentialsRequest(BaseModel):
    api_key: str
    api_secret: str


class CredentialsStatus(BaseModel):
    exists: bool
