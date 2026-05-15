"""Binance REST API downloader for historical candles."""

from __future__ import annotations

import logging
import duckdb
import time
import zipfile
import io
import csv
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional

import requests

_LOG = logging.getLogger("backtester.downloader")

# Binance rate limit: 1200 requests per minute
REQUEST_DELAY = 0.1  # 100ms between requests (safe margin)


# Global variable to track API weight across the application
BINANCE_USED_WEIGHT_1M = 0


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
        if self.db_path.suffix == ".db":
            self.db_path = self.db_path.with_suffix(".duckdb")
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.api_key = api_key
        # Shared connection for thread safety
        self.conn = duckdb.connect(str(self.db_path))
        self._init_db()

    def _init_db(self) -> None:
        """Create candles table if not exists."""
        self.conn.execute("""
            CREATE TABLE IF NOT EXISTS candles (
                symbol VARCHAR,
                timeframe VARCHAR,
                timestamp_ms BIGINT,
                open DOUBLE,
                high DOUBLE,
                low DOUBLE,
                close DOUBLE,
                volume DOUBLE,
                UNIQUE(symbol, timeframe, timestamp_ms)
            )
        """)
        self.conn.execute("""
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
        start_from_ms: Optional[int] = None,
        on_progress: Optional[Callable[[int, int], None]] = None,
    ) -> int:
        """
        Download candles from Binance.

        Args:
            symbol: e.g., "BTCUSDT"
            timeframe: "1m", "5m", "15m", "1h", "4h", "1d"
            date_from: "2024-01-01"
            date_to: "2024-12-31"
            batch_size: candles per request (max 1000)
            start_from_ms: if set, skip ahead to this timestamp (resume support)
            on_progress: optional callback(candles_added, current_ts) called after
                each batch; use to persist progress for resumable downloads

        Returns:
            Number of candles downloaded.
        """
        if timeframe not in self.TIMEFRAMES:
            raise ValueError(f"Invalid timeframe: {timeframe}")

        start_ts = self._parse_date(date_from)
        end_ts = self._parse_date(date_to) + 86400000  # Include full end date
        candles_added = 0

        current_ts = start_from_ms if start_from_ms is not None else start_ts
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

            if on_progress is not None:
                on_progress(candles_added, current_ts)

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

            # Track API Weight
            weight_header = resp.headers.get("X-MBX-USED-WEIGHT-1M")
            if weight_header:
                global BINANCE_USED_WEIGHT_1M
                try:
                    BINANCE_USED_WEIGHT_1M = int(weight_header)
                except ValueError:
                    pass

            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            _LOG.error(f"Failed to fetch {symbol}: {e}")
            return []

    def download_vision_zip(
        self,
        symbol: str,
        timeframe: str,
        year: int,
        month: int,
    ) -> int:
        """
        Download a monthly CSV zip from data.binance.vision and insert to DB.
        URL format: https://data.binance.vision/data/spot/monthly/klines/BTCUSDT/1h/BTCUSDT-1h-2024-01.zip
        """
        if timeframe not in self.TIMEFRAMES:
            raise ValueError(f"Invalid timeframe: {timeframe}")

        month_str = f"{month:02d}"
        filename = f"{symbol}-{timeframe}-{year}-{month_str}.zip"
        url = f"https://data.binance.vision/data/spot/monthly/klines/{symbol}/{timeframe}/{filename}"

        _LOG.info(f"Downloading ZIP: {url}")
        try:
            resp = requests.get(url, timeout=30)
            if resp.status_code == 404:
                _LOG.warning(
                    f"Data not available for {symbol} {timeframe} {year}-{month_str}"
                )
                return 0
            resp.raise_for_status()

            with zipfile.ZipFile(io.BytesIO(resp.content)) as z:
                # The zip should contain one csv file
                csv_filename = z.namelist()[0]
                with z.open(csv_filename) as f:
                    content = f.read().decode("utf-8")

            reader = csv.reader(io.StringIO(content))
            klines = []
            for row in reader:
                if not row:
                    continue
                klines.append(row)

            return self._save_batch(symbol, timeframe, klines)

        except Exception as e:
            _LOG.error(f"Failed to download/process ZIP for {symbol}: {e}")
            return 0

    def _save_batch(
        self,
        symbol: str,
        timeframe: str,
        klines: list[list],
    ) -> int:
        """Save batch to DuckDB, returning inserted count."""
        if not klines:
            return 0

        # Transform to tuple list for executemany
        data = [
            (
                symbol,
                timeframe,
                int(k[0]),
                float(k[1]),
                float(k[2]),
                float(k[3]),
                float(k[4]),
                float(k[7]),
            )
            for k in klines
        ]

        self.conn.executemany(
            """
            INSERT INTO candles
            (symbol, timeframe, timestamp_ms, open, high, low, close, volume)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (symbol, timeframe, timestamp_ms) DO NOTHING
        """,
            data,
        )
        return len(klines)

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
            "FROM candles WHERE " + " AND ".join(clauses) + " ORDER BY timestamp_ms ASC"
        )
        if limit:
            query += " LIMIT ?"
            params.append(int(limit))

        df = self.conn.execute(query, params).df()
        # Convert pandas DataFrame to list of dicts for backward compatibility
        return df.to_dict("records")

    def list_symbols(self) -> list[dict]:
        """List distinct (symbol, timeframe) pairs available with row counts."""
        df = self.conn.execute(
            "SELECT symbol, timeframe, COUNT(*) AS n, "
            "MIN(timestamp_ms) AS first_ms, MAX(timestamp_ms) AS last_ms "
            "FROM candles GROUP BY symbol, timeframe ORDER BY symbol, timeframe"
        ).df()

        return [
            {
                "symbol": r["symbol"],
                "timeframe": r["timeframe"],
                "candles": r["n"],
                "first_ms": r["first_ms"],
                "last_ms": r["last_ms"],
            }
            for _, r in df.iterrows()
        ]

    def _parse_date(self, date_str: str) -> int:
        """Convert "2024-01-01" to milliseconds since epoch."""
        dt = datetime.strptime(date_str, "%Y-%m-%d")
        return int(dt.timestamp() * 1000)
