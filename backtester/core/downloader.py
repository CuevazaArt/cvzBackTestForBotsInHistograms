"""Binance REST API downloader for historical candles."""

from __future__ import annotations

import logging
import sqlite3
import time
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional

import requests

_LOG = logging.getLogger("backtester.downloader")

# 100ms between requests → well under Binance 1200 req/min limit
_REQUEST_DELAY = 0.1
_MAX_RETRIES = 5


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
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS candles (
                    symbol    TEXT    NOT NULL,
                    timeframe TEXT    NOT NULL,
                    timestamp_ms INTEGER NOT NULL,
                    open  REAL NOT NULL,
                    high  REAL NOT NULL,
                    low   REAL NOT NULL,
                    close REAL NOT NULL,
                    volume REAL NOT NULL,
                    PRIMARY KEY (symbol, timeframe, timestamp_ms)
                )
            """)
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_symbol_tf "
                "ON candles (symbol, timeframe)"
            )

    def download(
        self,
        symbol: str,
        timeframe: str,
        date_from: str,
        date_to: str,
        batch_size: int = 1000,
        progress_callback: Optional[Callable[[float, int, str], None]] = None,
    ) -> int:
        """Download candles from Binance and store them in SQLite.

        Args:
            symbol:     e.g. "BTCUSDT"
            timeframe:  one of TIMEFRAMES keys
            date_from:  "YYYY-MM-DD" inclusive start
            date_to:    "YYYY-MM-DD" inclusive end (last ms of day)
            batch_size: candles per HTTP request (Binance max 1000)
            progress_callback: optional ``(progress_pct, candles_added, message)``
                callback invoked after each batch. ``progress_pct`` is in [0, 1].
                Use it to forward live status to a job registry or UI.

        Returns:
            Number of new candles inserted (duplicates are skipped).
        """
        if timeframe not in self.TIMEFRAMES:
            raise ValueError(f"Invalid timeframe: {timeframe!r}. "
                             f"Choose from {list(self.TIMEFRAMES)}")

        start_ts = self._parse_date(date_from)
        # end_ts is the last millisecond of date_to (inclusive)
        end_ts = self._parse_date(date_to) + 86_400_000 - 1
        candles_added = 0
        current_ts = start_ts

        while current_ts <= end_ts:
            batch = self._fetch_batch(symbol, timeframe, current_ts, batch_size)
            if not batch:
                break

            # Trim any candles that fall beyond our requested range
            batch = [k for k in batch if int(k[0]) <= end_ts]
            if not batch:
                break

            inserted = self._save_batch(symbol, timeframe, batch)
            candles_added += inserted

            last_ts = int(batch[-1][0])
            if last_ts >= end_ts:
                # Emit a final 100% tick so the UI doesn't end at e.g. 99.7%.
                if progress_callback is not None:
                    progress_callback(
                        1.0, candles_added,
                        f"{symbol} {timeframe} — {candles_added} candles",
                    )
                break

            tf_ms = self.TIMEFRAMES[timeframe] * 60 * 1000
            current_ts = last_ts + tf_ms

            time.sleep(_REQUEST_DELAY)

            span = end_ts - start_ts
            progress = min(1.0, (current_ts - start_ts) / span) if span else 1.0
            _LOG.info(
                "%s %s — %d candles downloaded (%.1f%%)",
                symbol, timeframe, candles_added, progress * 100,
            )
            if progress_callback is not None:
                progress_callback(
                    progress, candles_added,
                    f"{symbol} {timeframe} — {candles_added} candles ({progress * 100:.0f}%)",
                )

        return candles_added

    def _fetch_batch(
        self,
        symbol: str,
        timeframe: str,
        start_time: int,
        limit: int = 1000,
    ) -> list[list]:
        """Fetch one batch from Binance with exponential-backoff retries.

        Handles:
          - 429 Too Many Requests (respects Retry-After header when present)
          - 5xx server errors (exponential backoff up to 60 s)
          - Network-level exceptions
        """
        params = {
            "symbol": symbol,
            "interval": timeframe,
            "startTime": start_time,
            "limit": min(limit, 1000),
        }
        headers: dict[str, str] = {}
        if self.api_key:
            headers["X-MBX-APIKEY"] = self.api_key

        delay = 1.0
        for attempt in range(_MAX_RETRIES):
            try:
                resp = requests.get(
                    f"{self.BASE_URL}/klines",
                    params=params,
                    headers=headers,
                    timeout=15,
                )
                if resp.status_code == 429:
                    wait = float(resp.headers.get("Retry-After", delay))
                    _LOG.warning(
                        "Rate-limited (429) — sleeping %.1f s (attempt %d/%d)",
                        wait, attempt + 1, _MAX_RETRIES,
                    )
                    time.sleep(wait)
                    delay = min(delay * 2, 60.0)
                    continue

                if resp.status_code >= 500:
                    _LOG.warning(
                        "Server error %d — retrying in %.1f s (attempt %d/%d)",
                        resp.status_code, delay, attempt + 1, _MAX_RETRIES,
                    )
                    time.sleep(delay)
                    delay = min(delay * 2, 60.0)
                    continue

                resp.raise_for_status()
                return resp.json()

            except requests.RequestException as exc:
                _LOG.warning(
                    "Network error (attempt %d/%d): %s",
                    attempt + 1, _MAX_RETRIES, exc,
                )
                if attempt < _MAX_RETRIES - 1:
                    time.sleep(delay)
                    delay = min(delay * 2, 60.0)

        _LOG.error("Failed to fetch %s %s after %d attempts", symbol, timeframe, _MAX_RETRIES)
        return []

    def _save_batch(
        self,
        symbol: str,
        timeframe: str,
        klines: list[list],
    ) -> int:
        """Upsert klines into SQLite; returns count of newly inserted rows."""
        if not klines:
            return 0
        inserted = 0
        with sqlite3.connect(self.db_path) as conn:
            for k in klines:
                try:
                    conn.execute(
                        "INSERT INTO candles "
                        "(symbol, timeframe, timestamp_ms, open, high, low, close, volume) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                        (
                            symbol, timeframe,
                            int(k[0]),
                            float(k[1]), float(k[2]), float(k[3]), float(k[4]),
                            float(k[7]),  # quote asset volume at index 7
                        ),
                    )
                    inserted += 1
                except sqlite3.IntegrityError:
                    pass  # already stored
        return inserted

    def load_candles(
        self,
        symbol: str,
        timeframe: str,
        start_ms: Optional[int] = None,
        end_ms: Optional[int] = None,
        limit: Optional[int] = None,
    ) -> list[dict]:
        """Load candles from local DB with optional time-range filter."""
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
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(query, params).fetchall()
            return [dict(row) for row in rows]

    def list_symbols(self) -> list[dict]:
        """List available (symbol, timeframe) pairs with candle counts."""
        with sqlite3.connect(self.db_path) as conn:
            rows = conn.execute(
                "SELECT symbol, timeframe, COUNT(*) AS n, "
                "MIN(timestamp_ms) AS first_ms, MAX(timestamp_ms) AS last_ms "
                "FROM candles GROUP BY symbol, timeframe ORDER BY symbol, timeframe"
            ).fetchall()
            return [
                {
                    "symbol": r[0], "timeframe": r[1], "candles": r[2],
                    "first_ms": r[3], "last_ms": r[4],
                }
                for r in rows
            ]

    @staticmethod
    def _parse_date(date_str: str) -> int:
        """Convert "YYYY-MM-DD" to epoch milliseconds (UTC midnight)."""
        dt = datetime.strptime(date_str, "%Y-%m-%d")
        return int(dt.timestamp() * 1000)
