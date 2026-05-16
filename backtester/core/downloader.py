"""Binance REST API downloader for historical candles."""

from __future__ import annotations

import logging
import threading
import duckdb
import time
import zipfile
import io
import csv
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional

import requests  # type: ignore[import-untyped]

_LOG = logging.getLogger("backtester.downloader")

# Binance rate limit: 1200 requests per minute
REQUEST_DELAY = 0.1  # 100ms between requests (safe margin)

# Retry policy for transient failures (timeouts, 5xx, 429).
MAX_RETRIES = 5
BACKOFF_BASE_S = 1.0  # 1s, 2s, 4s, 8s, 16s


class DownloaderError(RuntimeError):
    """Raised when a download exhausts its retry budget — surfaces to the
    job store as a real error instead of an empty-but-successful result."""


def _retryable_status(code: int) -> bool:
    return code == 429 or 500 <= code < 600


def _sleep_for_retry(attempt: int, retry_after_hdr: Optional[str]) -> float:
    """Honor `Retry-After` when present, else exponential backoff."""
    if retry_after_hdr:
        try:
            return max(0.5, float(retry_after_hdr))
        except ValueError:
            pass
    return BACKOFF_BASE_S * (2 ** attempt)


class WeightTracker:
    """Thread-safe holder for Binance ``X-MBX-USED-WEIGHT-1M`` rate-limit weight.

    The previous implementation kept the value in a module-level global that
    was mutated from background download threads while the FastAPI ``/health``
    endpoint read it from a worker thread. ``WeightTracker`` wraps the value
    in a lock so concurrent reads/writes are race-free and so the rest of the
    app can ask for an authoritative snapshot.
    """

    __slots__ = ("_value", "_lock")

    def __init__(self, initial: int = 0) -> None:
        self._value = int(initial)
        self._lock = threading.Lock()

    def get(self) -> int:
        with self._lock:
            return self._value

    def set(self, value: int) -> None:
        with self._lock:
            self._value = int(value)

    def increment(self, by: int = 1) -> int:
        with self._lock:
            self._value += int(by)
            return self._value

    def reset(self) -> None:
        with self._lock:
            self._value = 0


BINANCE_WEIGHT_TRACKER = WeightTracker(0)


def get_binance_used_weight_1m() -> int:
    """Return the latest cached Binance ``X-MBX-USED-WEIGHT-1M`` value."""
    return BINANCE_WEIGHT_TRACKER.get()


def set_binance_used_weight_1m(value: int) -> None:
    """Set the cached Binance weight (thread-safe)."""
    BINANCE_WEIGHT_TRACKER.set(value)


def __getattr__(name: str) -> int:  # pragma: no cover - backwards-compat shim
    """Expose ``BINANCE_USED_WEIGHT_1M`` as a live read of the tracker.

    Keeps legacy ``from backtester.core.downloader import BINANCE_USED_WEIGHT_1M``
    imports working — each ``import`` resolves through ``__getattr__`` and gets
    the current value rather than a stale snapshot.
    """
    if name == "BINANCE_USED_WEIGHT_1M":
        return BINANCE_WEIGHT_TRACKER.get()
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


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

    def __init__(self, db_path: Path, api_key: Optional[str] = None, read_only: bool = False) -> None:
        self.db_path = Path(db_path)
        if self.db_path.suffix == ".db":
            self.db_path = self.db_path.with_suffix(".duckdb")
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.api_key = api_key
        # Shared connection for thread safety
        self.conn = duckdb.connect(str(self.db_path), read_only=read_only)
        if not read_only:
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
            # Empty batch (not an error after retries) means Binance has no
            # more candles for this range — stop cleanly, partial results
            # are persisted.
            if not batch:
                _LOG.info(
                    "No more candles available for %s %s past %d — stopping",
                    symbol, timeframe, current_ts,
                )
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
                f"({progress * 100:.1f}% complete)"
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
        """Fetch a batch of candles from Binance API with retry/backoff.

        Retries on transient failures (timeouts, connection errors, 5xx, 429
        rate limits) with exponential backoff. Raises ``DownloaderError`` if
        retries are exhausted — the previous version swallowed errors and
        returned ``[]``, which made the download loop silently stop and report
        success with 0 candles added.
        """
        params: dict[str, str | int] = {
            "symbol": symbol,
            "interval": timeframe,
            "startTime": start_time,
            "limit": min(limit, 1000),
        }
        headers: dict[str, str] = {}
        if self.api_key:
            headers["X-MBX-APIKEY"] = self.api_key

        last_err: Optional[str] = None
        for attempt in range(MAX_RETRIES):
            try:
                resp = requests.get(
                    f"{self.BASE_URL}/klines",
                    params=params,  # type: ignore[arg-type]
                    headers=headers,
                    timeout=15,
                )

                # Track API Weight even when we'll retry — the header is set
                # on rate-limit responses too.
                weight_header = resp.headers.get("X-MBX-USED-WEIGHT-1M")
                if weight_header:
                    try:
                        BINANCE_WEIGHT_TRACKER.set(int(weight_header))
                    except ValueError:
                        pass

                # 400 = bad symbol/interval — never retry, surface error.
                if resp.status_code == 400:
                    raise DownloaderError(
                        f"Binance rejected {symbol} {timeframe}: {resp.text[:200]}"
                    )

                if _retryable_status(resp.status_code):
                    last_err = f"HTTP {resp.status_code}"
                    wait = _sleep_for_retry(attempt, resp.headers.get("Retry-After"))
                    _LOG.warning(
                        "Transient %s for %s — retry %d/%d after %.1fs",
                        last_err, symbol, attempt + 1, MAX_RETRIES, wait,
                    )
                    time.sleep(wait)
                    continue

                resp.raise_for_status()
                data = resp.json()
                if not isinstance(data, list):
                    raise DownloaderError(f"Unexpected response shape: {type(data).__name__}")
                return data

            except (requests.Timeout, requests.ConnectionError) as e:
                last_err = f"{type(e).__name__}: {e}"
                wait = _sleep_for_retry(attempt, None)
                _LOG.warning(
                    "%s for %s — retry %d/%d after %.1fs",
                    last_err, symbol, attempt + 1, MAX_RETRIES, wait,
                )
                time.sleep(wait)
            except DownloaderError:
                raise  # non-retryable, surface as error
            except Exception as e:  # noqa: BLE001
                last_err = f"{type(e).__name__}: {e}"
                _LOG.exception("Unexpected error fetching %s", symbol)
                wait = _sleep_for_retry(attempt, None)
                time.sleep(wait)

        raise DownloaderError(
            f"Failed to fetch {symbol} {timeframe} after {MAX_RETRIES} retries: {last_err}"
        )

    def download_vision_zip(
        self,
        symbol: str,
        timeframe: str,
        year: int,
        month: int,
    ) -> int:
        """Download a monthly CSV zip from data.binance.vision and insert to DB.

        URL format: https://data.binance.vision/data/spot/monthly/klines/BTCUSDT/1h/BTCUSDT-1h-2024-01.zip

        Retries on transient network failures. Returns 0 when the month
        legitimately doesn't exist yet (404) so callers can ignore missing
        future months when downloading a year range. Any other persistent
        failure raises ``DownloaderError``.
        """
        if timeframe not in self.TIMEFRAMES:
            raise ValueError(f"Invalid timeframe: {timeframe}")

        month_str = f"{month:02d}"
        filename = f"{symbol}-{timeframe}-{year}-{month_str}.zip"
        url = f"https://data.binance.vision/data/spot/monthly/klines/{symbol}/{timeframe}/{filename}"

        _LOG.info(f"Downloading ZIP: {url}")
        last_err: Optional[str] = None
        for attempt in range(MAX_RETRIES):
            try:
                resp = requests.get(url, timeout=60)

                # 404 = month not published yet (or wrong symbol). Don't retry.
                if resp.status_code == 404:
                    _LOG.warning(
                        "Data not available for %s %s %s-%s",
                        symbol, timeframe, year, month_str,
                    )
                    return 0

                if _retryable_status(resp.status_code):
                    last_err = f"HTTP {resp.status_code}"
                    wait = _sleep_for_retry(attempt, resp.headers.get("Retry-After"))
                    _LOG.warning(
                        "Transient %s for %s — retry %d/%d after %.1fs",
                        last_err, filename, attempt + 1, MAX_RETRIES, wait,
                    )
                    time.sleep(wait)
                    continue

                resp.raise_for_status()

                # Parse ZIP + CSV inline; bad payload raises and is retried
                # only once (the file probably is malformed at the source).
                with zipfile.ZipFile(io.BytesIO(resp.content)) as z:
                    names = z.namelist()
                    if not names:
                        raise DownloaderError(f"Empty ZIP for {filename}")
                    with z.open(names[0]) as f:
                        content = f.read().decode("utf-8")

                klines = [row for row in csv.reader(io.StringIO(content)) if row]
                if not klines:
                    raise DownloaderError(f"Empty CSV inside {filename}")

                return self._save_batch(symbol, timeframe, klines)

            except (requests.Timeout, requests.ConnectionError) as e:
                last_err = f"{type(e).__name__}: {e}"
                wait = _sleep_for_retry(attempt, None)
                _LOG.warning(
                    "%s for %s — retry %d/%d after %.1fs",
                    last_err, filename, attempt + 1, MAX_RETRIES, wait,
                )
                time.sleep(wait)
            except (zipfile.BadZipFile, UnicodeDecodeError) as e:
                # Payload corruption — likely a partial transfer. One more try.
                last_err = f"{type(e).__name__}: {e}"
                _LOG.warning(
                    "Corrupted payload for %s — retry %d/%d",
                    filename, attempt + 1, MAX_RETRIES,
                )
                time.sleep(_sleep_for_retry(attempt, None))
            except DownloaderError:
                raise
            except Exception as e:  # noqa: BLE001
                last_err = f"{type(e).__name__}: {e}"
                _LOG.exception("Unexpected error downloading %s", filename)
                time.sleep(_sleep_for_retry(attempt, None))

        raise DownloaderError(
            f"Failed to download {filename} after {MAX_RETRIES} retries: {last_err}"
        )

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
