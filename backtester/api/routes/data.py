"""Data quality endpoints (OHLCV validation)."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import (
    DataQualityGap,
    DataQualityReportDTO,
    DataValidateRequest,
)
from backtester.core.data_quality import validate_ohlcv
from backtester.core.engine import Candle

_LOG = logging.getLogger("backtester.api.data")

router = APIRouter(tags=["data"])


_TIMEFRAME_SECONDS = {
    "1m": 60,
    "3m": 3 * 60,
    "5m": 5 * 60,
    "15m": 15 * 60,
    "30m": 30 * 60,
    "1h": 60 * 60,
    "2h": 2 * 60 * 60,
    "4h": 4 * 60 * 60,
    "6h": 6 * 60 * 60,
    "8h": 8 * 60 * 60,
    "12h": 12 * 60 * 60,
    "1d": 24 * 60 * 60,
    "3d": 3 * 24 * 60 * 60,
    "1w": 7 * 24 * 60 * 60,
}


def _timeframe_to_seconds(timeframe: str) -> int | None:
    return _TIMEFRAME_SECONDS.get(timeframe.lower())


@router.post("/data/validate", response_model=DataQualityReportDTO)
def validate_data(
    req: DataValidateRequest,
    ctx: AppContext = Depends(get_ctx),
) -> DataQualityReportDTO:
    """Run :func:`validate_ohlcv` over candles loaded from the local store.

    Returns the report as JSON so the Flutter UI can render a summary modal
    right after a download finishes.
    """
    rows = ctx.downloader.load_candles(
        req.symbol.upper(),
        req.timeframe,
        start_ms=req.start_ms,
        end_ms=req.end_ms,
    )
    if not rows:
        raise HTTPException(
            404,
            f"No candles for {req.symbol} {req.timeframe}",
        )

    candles = [Candle.from_dict(r) for r in rows]
    timeframe_seconds = _timeframe_to_seconds(req.timeframe)
    report = validate_ohlcv(candles, timeframe_seconds=timeframe_seconds)

    return DataQualityReportDTO(
        total_candles=report.total_candles,
        expected_candles=report.expected_candles,
        completeness_pct=report.completeness_pct,
        gaps=[DataQualityGap(**g) for g in report.gaps],
        duplicates=list(report.duplicates),
        monotonic_ok=report.monotonic_ok,
        ohlc_consistency_violations=list(report.ohlc_consistency_violations),
        outliers_iqr=list(report.outliers_iqr),
        summary_ok=report.summary_ok,
        timeframe_seconds=report.timeframe_seconds,
    )
