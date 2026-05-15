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
    cancel_requested: bool = False
    run_id: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "status": self.status,
            "progress": self.progress,
            "message": self.message,
            "result": self.result,
            "cancel_requested": self.cancel_requested,
            "run_id": self.run_id,
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
            str(self.db_path),
            check_same_thread=False,
            isolation_level=None,
        )
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._conn.row_factory = sqlite3.Row
        with self._lock:
            self._conn.executescript(_SCHEMA)
            self._ensure_extended_schema()

    def _ensure_extended_schema(self) -> None:
        """Add cancel/run_id columns and job_events for API tracing (idempotent)."""
        cols = {r[1] for r in self._conn.execute("PRAGMA table_info(jobs)").fetchall()}
        if "cancel_requested" not in cols:
            self._conn.execute(
                "ALTER TABLE jobs ADD COLUMN cancel_requested INTEGER NOT NULL DEFAULT 0",
            )
        if "run_id" not in cols:
            self._conn.execute("ALTER TABLE jobs ADD COLUMN run_id TEXT")
        self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS job_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                payload_json TEXT,
                created_at REAL NOT NULL
            )
            """
        )

    # ── core CRUD ────────────────────────────────────────────────

    def create(self, kind: str) -> Job:
        now = time.time()
        job = Job(id=str(uuid.uuid4()), kind=kind, created_at=now, updated_at=now)
        with self._lock:
            self._conn.execute(
                "INSERT INTO jobs(id, kind, status, progress, message, result_json, created_at, updated_at) "
                "VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    job.id,
                    job.kind,
                    job.status,
                    job.progress,
                    job.message,
                    None,
                    now,
                    now,
                ),
            )
        return job

    def get(self, job_id: str) -> Optional[Job]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM jobs WHERE id = ?",
                (job_id,),
            ).fetchone()
        return self._row_to_job(row) if row else None

    def update(self, job_id: str, **kwargs: Any) -> None:
        if not kwargs:
            return
        allowed = {"status", "progress", "message", "result", "run_id"}
        fields: list[str] = []
        values: list[Any] = []
        for k, v in kwargs.items():
            if k not in allowed:
                continue
            if k == "result":
                fields.append("result_json = ?")
                values.append(json.dumps(v) if v is not None else None)
            elif k == "run_id":
                fields.append("run_id = ?")
                values.append(v)
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
                f"UPDATE jobs SET {', '.join(fields)} WHERE id = ?",
                values,
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
                "DELETE FROM jobs WHERE updated_at < ? AND status IN ('done', 'error', 'cancelled')",
                (cutoff,),
            )
            return cur.rowcount

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    def create_run(self, kind: str, config: dict[str, Any]) -> str:
        run_id = str(uuid.uuid4())
        now = time.time()
        with self._lock:
            self._conn.execute(
                "INSERT INTO job_events (job_id, event_type, payload_json, created_at) "
                "VALUES (?, ?, ?, ?)",
                (
                    run_id,
                    "run_created",
                    json.dumps({"kind": kind, "config": config}),
                    now,
                ),
            )
        return run_id

    def request_cancel(self, job_id: str) -> bool:
        now = time.time()
        with self._lock:
            cur = self._conn.execute(
                "UPDATE jobs SET cancel_requested = 1, updated_at = ? "
                "WHERE id = ? AND status IN ('pending', 'running')",
                (now, job_id),
            )
            return cur.rowcount > 0

    def is_cancel_requested(self, job_id: str) -> bool:
        with self._lock:
            row = self._conn.execute(
                "SELECT cancel_requested FROM jobs WHERE id = ?",
                (job_id,),
            ).fetchone()
            return bool(row and row[0])

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
        keys = row.keys()
        cancel = bool(row["cancel_requested"]) if "cancel_requested" in keys else False
        run_id = row["run_id"] if "run_id" in keys else None
        return Job(
            id=row["id"],
            kind=row["kind"],
            status=row["status"],
            progress=row["progress"],
            message=row["message"],
            result=json.loads(result_json) if result_json else None,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            cancel_requested=cancel,
            run_id=run_id,
        )
