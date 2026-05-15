"""SQLite-backed job store with same API surface as the legacy in-memory JobRegistry.

Persists jobs across API restarts. WAL mode enabled for concurrent writes from
the experiment runner worker threads.
"""

from __future__ import annotations

import json
import sqlite3
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

_SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id          TEXT PRIMARY KEY,
    kind        TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'pending',
    progress    REAL NOT NULL DEFAULT 0.0,
    message     TEXT,
    result_json TEXT,
    created_at  REAL NOT NULL,
    updated_at  REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_jobs_kind_status ON jobs(kind, status);
CREATE INDEX IF NOT EXISTS idx_jobs_updated_at  ON jobs(updated_at DESC);
"""


@dataclass
class Job:
    id: str
    kind: str
    status: str = "pending"
    progress: float = 0.0
    message: Optional[str] = None
    result: Optional[dict[str, Any]] = None
    created_at: float = 0.0
    updated_at: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "status": self.status,
            "progress": self.progress,
            "message": self.message,
            "result": self.result,
        }


class JobStore:
    """Thread-safe SQLite-backed job store.

    Drop-in replacement for the legacy in-memory `JobRegistry`: exposes
    `create`, `get`, `update`, `list_all`. Adds `delete`, `cleanup_older_than`,
    and richer `list_filtered` for the new API endpoints.
    """

    def __init__(self, db_path: Path | str) -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        # check_same_thread=False because we serialize via _lock ourselves
        self._conn = sqlite3.connect(
            str(self.db_path), check_same_thread=False, isolation_level=None,
        )
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._conn.row_factory = sqlite3.Row
        with self._lock:
            self._conn.executescript(_SCHEMA)

    # ── core CRUD ────────────────────────────────────────────────

    def create(self, kind: str) -> Job:
        now = time.time()
        job = Job(id=str(uuid.uuid4()), kind=kind, created_at=now, updated_at=now)
        with self._lock:
            self._conn.execute(
                "INSERT INTO jobs(id, kind, status, progress, message, result_json, created_at, updated_at) "
                "VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
                (job.id, job.kind, job.status, job.progress, job.message, None, now, now),
            )
        return job

    def get(self, job_id: str) -> Optional[Job]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM jobs WHERE id = ?", (job_id,),
            ).fetchone()
        return self._row_to_job(row) if row else None

    def update(self, job_id: str, **kwargs: Any) -> None:
        if not kwargs:
            return
        allowed = {"status", "progress", "message", "result"}
        fields: list[str] = []
        values: list[Any] = []
        for k, v in kwargs.items():
            if k not in allowed:
                continue
            if k == "result":
                fields.append("result_json = ?")
                values.append(json.dumps(v) if v is not None else None)
            else:
                fields.append(f"{k} = ?")
                values.append(v)
        if not fields:
            return
        fields.append("updated_at = ?")
        values.append(time.time())
        values.append(job_id)
        with self._lock:
            self._conn.execute(
                f"UPDATE jobs SET {', '.join(fields)} WHERE id = ?", values,
            )

    def delete(self, job_id: str) -> bool:
        with self._lock:
            cur = self._conn.execute("DELETE FROM jobs WHERE id = ?", (job_id,))
            return cur.rowcount > 0

    def list_all(self) -> list[dict[str, Any]]:
        return [j.to_dict() for j in self._iter_all()]

    def list_filtered(
        self,
        kind: Optional[str] = None,
        status: Optional[str] = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        clauses: list[str] = []
        params: list[Any] = []
        if kind is not None:
            clauses.append("kind = ?")
            params.append(kind)
        if status is not None:
            clauses.append("status = ?")
            params.append(status)
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        params.extend([limit, offset])
        with self._lock:
            rows = self._conn.execute(
                f"SELECT * FROM jobs {where} ORDER BY updated_at DESC LIMIT ? OFFSET ?",
                params,
            ).fetchall()
        return [self._row_to_job(r).to_dict() for r in rows]

    def cleanup_older_than(self, seconds: float) -> int:
        cutoff = time.time() - seconds
        with self._lock:
            cur = self._conn.execute(
                "DELETE FROM jobs WHERE updated_at < ? AND status IN ('done', 'error')",
                (cutoff,),
            )
            return cur.rowcount

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    # ── internals ────────────────────────────────────────────────

    def _iter_all(self):
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM jobs ORDER BY updated_at DESC"
            ).fetchall()
        for r in rows:
            yield self._row_to_job(r)

    @staticmethod
    def _row_to_job(row: sqlite3.Row) -> Job:
        result_json = row["result_json"]
        return Job(
            id=row["id"],
            kind=row["kind"],
            status=row["status"],
            progress=row["progress"],
            message=row["message"],
            result=json.loads(result_json) if result_json else None,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
