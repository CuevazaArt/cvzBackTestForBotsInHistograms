"""SQLite-backed store for completed backtest results.

Each backtest run (identified by a UUID run_id) stores the full result payload
plus the config so it can be retrieved or re-exported without re-running.
"""

from __future__ import annotations

import json
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any, Optional

_SCHEMA = """
CREATE TABLE IF NOT EXISTS backtest_results (
    run_id     TEXT PRIMARY KEY,
    symbol     TEXT NOT NULL,
    timeframe  TEXT NOT NULL,
    config     TEXT NOT NULL,
    result     TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_bt_symbol_tf ON backtest_results(symbol, timeframe);
CREATE INDEX IF NOT EXISTS idx_bt_created ON backtest_results(created_at DESC);
"""


class ResultStore:
    """Thread-safe CRUD for backtest result blobs."""

    def __init__(self, db_path: Path | str) -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(
            str(self.db_path), check_same_thread=False, isolation_level=None,
        )
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.executescript(_SCHEMA)

    # ── write ──────────────────────────────────────────────────────

    def save(
        self,
        run_id: str,
        symbol: str,
        timeframe: str,
        config: dict[str, Any],
        result: dict[str, Any],
    ) -> None:
        """Upsert a completed backtest result."""
        with self._lock:
            self._conn.execute(
                """
                INSERT INTO backtest_results
                    (run_id, symbol, timeframe, config, result, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(run_id) DO UPDATE SET
                    result = excluded.result,
                    created_at = excluded.created_at
                """,
                (
                    run_id,
                    symbol,
                    timeframe,
                    json.dumps(config),
                    json.dumps(result),
                    time.time(),
                ),
            )

    # ── read ───────────────────────────────────────────────────────

    def get(self, run_id: str) -> Optional[dict[str, Any]]:
        """Return the stored record for run_id, or None."""
        row = self._conn.execute(
            "SELECT run_id, symbol, timeframe, config, result, created_at "
            "FROM backtest_results WHERE run_id = ?",
            (run_id,),
        ).fetchone()
        if row is None:
            return None
        return self._row_to_dict(row)

    def list_recent(
        self,
        limit: int = 50,
        offset: int = 0,
        symbol: Optional[str] = None,
        timeframe: Optional[str] = None,
    ) -> list[dict[str, Any]]:
        """Return summaries (no full result blob) sorted newest-first."""
        clauses: list[str] = []
        params: list[Any] = []
        if symbol:
            clauses.append("symbol = ?")
            params.append(symbol.upper())
        if timeframe:
            clauses.append("timeframe = ?")
            params.append(timeframe)
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        params += [limit, offset]
        rows = self._conn.execute(
            f"SELECT run_id, symbol, timeframe, config, result, created_at "
            f"FROM backtest_results {where} "
            f"ORDER BY created_at DESC LIMIT ? OFFSET ?",
            params,
        ).fetchall()
        return [self._row_to_dict(r) for r in rows]

    # ── delete ─────────────────────────────────────────────────────

    def delete(self, run_id: str) -> bool:
        with self._lock:
            cur = self._conn.execute(
                "DELETE FROM backtest_results WHERE run_id = ?", (run_id,)
            )
            return cur.rowcount > 0

    def cleanup_older_than(self, seconds: float) -> int:
        cutoff = time.time() - seconds
        with self._lock:
            cur = self._conn.execute(
                "DELETE FROM backtest_results WHERE created_at < ?", (cutoff,)
            )
            return cur.rowcount

    # ── helpers ────────────────────────────────────────────────────

    @staticmethod
    def _row_to_dict(row: tuple) -> dict[str, Any]:
        run_id, symbol, timeframe, config_json, result_json, created_at = row
        return {
            "run_id": run_id,
            "symbol": symbol,
            "timeframe": timeframe,
            "config": json.loads(config_json),
            "result": json.loads(result_json),
            "created_at": created_at,
        }
