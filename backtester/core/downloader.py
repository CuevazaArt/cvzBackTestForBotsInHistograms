"""Binance REST API downloader for historical candles."""

from __future__ import annotations

import logging
import sqlite3
import time
from datetime import datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Optional

import requests

_LOG = logging.getLogger("backtester.downloader")

# Binance rate limit: 1200 requests per minute
REQUEST_DELAY = 0.1  # 100ms between requests (safe margin)


class BinanceDownloader:
    """Download historical OHLCV data from Binance REST API."""

    BASE_URL = "https://api.binance.com/api/v3"
    TIMEFRAMES = {
        "1m": 1,
        "5m": 5,
        "15m": 15,
        "1h": 60,
        "4h": 240,
        "1d": 1440,
    }

    def __init__(self, db_path: Path, api_key: Optional[str] = None) -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.api_key = api_key
        self._init_db()

    def _init_db(self) -> None:
        """Create candles table if not exists."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS candles (
                    symbol TEXT,
                    timeframe TEXT,
                    timestamp_ms INTEGER PRIMARY KEY,
                    open REAL,
                    high REAL,
                    low REAL,
                    close REAL,
                    volume REAL,
                    UNIQUE(symbol, timeframe, timestamp_ms)
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_symbol_tf
                ON candles (symbol, timeframe)
            """)

    def download(
        self,
        symbol: str,
        timeframe: str,
        date_from: str,
        date_to: str,
        batch_size: int = 1000,
    ) -> int:
        """
        Download candles from Binance.

        Args:
            symbol: e.g., "BTCUSDT"
            timeframe: "1m", "5m", "15m", "1h", "4h", "1d"
            date_from: "2024-01-01"
            date_to: "2024-12-31"
            batch_size: candles per request (max 1000)

        Returns:
            Number of candles downloaded.
        """
        if timeframe not in self.TIMEFRAMES:
            raise ValueError(f"Invalid timeframe: {timeframe}")

        start_ts = self._parse_date(date_from)
        end_ts = self._parse_date(date_to) + 86400000  # Include full end date
        candles_added = 0

        current_ts = start_ts
        while current_ts < end_ts:
            batch = self._fetch_batch(symbol, timeframe, current_ts, batch_size)
            if not batch:
                break

            inserted = self._save_batch(symbol, timeframe, batch)
            candles_added += inserted

            # Update timestamp for next batch
            current_ts = int(batch[-1][0]) + (self.TIMEFRAMES[timeframe] * 60 * 1000)

            # Rate limiting
            time.sleep(REQUEST_DELAY)

            progress = (current_ts - start_ts) / (end_ts - start_ts)
            _LOG.info(
                f"{symbol} {timeframe}: {candles_added} candles "
                f"({progress*100:.1f}% complete)"
            )

        return candles_added

    def _fetch_batch(
        self,
        symbol: str,
        timeframe: str,
        start_time: int,
        limit: int = 1000,
    ) -> list[list]:
        """Fetch a batch of candles from Binance API."""
        params = {
            "symbol": symbol,
            "interval": timeframe,
            "startTime": start_time,
            "limit": min(limit, 1000),
        }
        headers = {}
        if self.api_key:
            headers["X-MBX-APIKEY"] = self.api_key

        try:
            resp = requests.get(
                f"{self.BASE_URL}/klines",
                params=params,
                headers=headers,
                timeout=10,
            )
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            _LOG.error(f"Failed to fetch {symbol}: {e}")
            return []

    def _save_batch(
        self,
        symbol: str,
        timeframe: str,
        klines: list[list],
    ) -> int:
        """Save batch to SQLite, returning inserted count."""
        if not klines:
            return 0

        with sqlite3.connect(self.db_path) as conn:
            inserted = 0
            for k in klines:
                try:
                    conn.execute("""
                        INSERT INTO candles
                        (symbol, timeframe, timestamp_ms, open, high, low, close, volume)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        symbol,
                        timeframe,
                        int(k[0]),
                        float(k[1]),
                        float(k[2]),
                        float(k[3]),
                        float(k[4]),
                        float(k[7]),
                    ))
                    inserted += 1
                except sqlite3.IntegrityError:
                    pass  # Candle already exists
            conn.commit()
        return inserted

    def load_candles(
        self,
        symbol: str,
        timeframe: str,
        start_ms: Optional[int] = None,
        end_ms: Optional[int] = None,
        limit: Optional[int] = None,
    ) -> list[dict]:
        """Load candles from database.

        Args:
            symbol: e.g. "BTCUSDT"
            timeframe: e.g. "1h"
            start_ms: optional inclusive lower bound (epoch ms)
            end_ms: optional inclusive upper bound (epoch ms)
            limit: optional row cap
        """
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            clauses = ["symbol = ?", "timeframe = ?"]
            params: list = [symbol, timeframe]
            if start_ms is not None:
                clauses.append("timestamp_ms >= ?")
                params.append(int(start_ms))
            if end_ms is not None:
                clauses.append("timestamp_ms <= ?")
                params.append(int(end_ms))
            query = (
                "SELECT timestamp_ms, open, high, low, close, volume "
                "FROM candles WHERE " + " AND ".join(clauses) +
                " ORDER BY timestamp_ms ASC"
            )
            if limit:
                query += " LIMIT ?"
                params.append(int(limit))
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def list_symbols(self) -> list[dict]:
        """List distinct (symbol, timeframe) pairs available with row counts."""
        with sqlite3.connect(self.db_path) as conn:
            rows = conn.execute(
                "SELECT symbol, timeframe, COUNT(*) AS n, "
                "MIN(timestamp_ms) AS first_ms, MAX(timestamp_ms) AS last_ms "
                "FROM candles GROUP BY symbol, timeframe ORDER BY symbol, timeframe"
            ).fetchall()
            return [
                {"symbol": r[0], "timeframe": r[1], "candles": r[2],
                 "first_ms": r[3], "last_ms": r[4]}
                for r in rows
            ]

    def _parse_date(self, date_str: str) -> int:
        """Convert "2024-01-01" to milliseconds since epoch."""
        dt = datetime.strptime(date_str, "%Y-%m-%d")
        return int(dt.timestamp() * 1000)
