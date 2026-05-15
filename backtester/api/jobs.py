"""Persistent async job registry backed by SQLite."""

from __future__ import annotations

import json
import sqlite3
import uuid
from dataclasses import dataclass
from pathlib import Path
from threading import Lock
from typing import Any, Optional


@dataclass
class Job:
    id: str
    kind: str                          # "download" | "experiment"
    status: str = "pending"            # pending | running | done | error
    progress: float = 0.0
    message: Optional[str] = None
    result: Optional[dict[str, Any]] = None
    cancel_requested: bool = False
    run_id: Optional[str] = None
    created_at: str = ""
    updated_at: str = ""
    started_at: Optional[str] = None
    finished_at: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id, "kind": self.kind, "status": self.status,
            "progress": self.progress, "message": self.message, "result": self.result,
            "cancel_requested": self.cancel_requested,
            "run_id": self.run_id,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
        }


class JobRegistry:
    """Thread-safe SQLite-backed job store."""

    def __init__(self, db_path: Path) -> None:
        self._db_path = Path(db_path)
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = Lock()
        self._init_db()

    def _conn(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self._db_path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        with self._conn() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS jobs (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    status TEXT NOT NULL,
                    progress REAL NOT NULL,
                    message TEXT,
                    result_json TEXT,
                    cancel_requested INTEGER NOT NULL DEFAULT 0,
                    run_id TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    started_at TEXT,
                    finished_at TEXT
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS job_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    job_id TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    payload_json TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """
            )

    def _row_to_job(self, row: sqlite3.Row) -> Job:
        return Job(
            id=row["id"],
            kind=row["kind"],
            status=row["status"],
            progress=float(row["progress"] or 0.0),
            message=row["message"],
            result=json.loads(row["result_json"]) if row["result_json"] else None,
            cancel_requested=bool(row["cancel_requested"]),
            run_id=row["run_id"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            started_at=row["started_at"],
            finished_at=row["finished_at"],
        )

    def create(self, kind: str) -> Job:
        job = Job(id=str(uuid.uuid4()), kind=kind)
        with self._lock:
            with self._conn() as conn:
                conn.execute(
                    """
                    INSERT INTO jobs (id, kind, status, progress)
                    VALUES (?, ?, 'pending', 0.0)
                    """,
                    (job.id, kind),
                )
                row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job.id,)).fetchone()
                if row is None:
                    raise RuntimeError(f"Failed to create job {job.id}")
                return self._row_to_job(row)

    def get(self, job_id: str) -> Optional[Job]:
        with self._lock:
            with self._conn() as conn:
                row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
                return self._row_to_job(row) if row else None

    def update(self, job_id: str, **kwargs: Any) -> None:
        if not kwargs:
            return
        with self._lock:
            with self._conn() as conn:
                row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
                if row is None:
                    return

                status = kwargs.get("status", row["status"])
                started_at = row["started_at"]
                finished_at = row["finished_at"]
                if status == "running" and not started_at:
                    started_at = conn.execute(
                        "SELECT datetime('now')",
                    ).fetchone()[0]
                if status in ("done", "error", "cancelled"):
                    finished_at = conn.execute(
                        "SELECT datetime('now')",
                    ).fetchone()[0]

                payload = {
                    "status": status,
                    "progress": float(kwargs.get("progress", row["progress"] or 0.0)),
                    "message": kwargs.get("message", row["message"]),
                    "result_json": (
                        json.dumps(kwargs["result"]) if "result" in kwargs else row["result_json"]
                    ),
                    "cancel_requested": int(
                        kwargs.get("cancel_requested", row["cancel_requested"] or 0)
                    ),
                    "run_id": kwargs.get("run_id", row["run_id"]),
                    "started_at": kwargs.get("started_at", started_at),
                    "finished_at": kwargs.get("finished_at", finished_at),
                }
                conn.execute(
                    """
                    UPDATE jobs
                    SET status = ?,
                        progress = ?,
                        message = ?,
                        result_json = ?,
                        cancel_requested = ?,
                        run_id = ?,
                        started_at = ?,
                        finished_at = ?,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    (
                        payload["status"],
                        payload["progress"],
                        payload["message"],
                        payload["result_json"],
                        payload["cancel_requested"],
                        payload["run_id"],
                        payload["started_at"],
                        payload["finished_at"],
                        job_id,
                    ),
                )

    def append_event(self, job_id: str, event_type: str, payload: Optional[dict[str, Any]] = None) -> None:
        with self._lock:
            with self._conn() as conn:
                conn.execute(
                    """
                    INSERT INTO job_events (job_id, event_type, payload_json)
                    VALUES (?, ?, ?)
                    """,
                    (job_id, event_type, json.dumps(payload or {})),
                )

    def request_cancel(self, job_id: str) -> bool:
        with self._lock:
            with self._conn() as conn:
                cur = conn.execute(
                    """
                    UPDATE jobs
                    SET cancel_requested = 1, updated_at = datetime('now')
                    WHERE id = ? AND status IN ('pending', 'running')
                    """,
                    (job_id,),
                )
                return cur.rowcount > 0

    def is_cancel_requested(self, job_id: str) -> bool:
        with self._lock:
            with self._conn() as conn:
                row = conn.execute(
                    "SELECT cancel_requested FROM jobs WHERE id = ?",
                    (job_id,),
                ).fetchone()
                return bool(row and row["cancel_requested"])

    def create_run(self, kind: str, config: dict[str, Any]) -> str:
        run_id = str(uuid.uuid4())
        with self._lock:
            with self._conn() as conn:
                conn.execute(
                    """
                    INSERT INTO job_events (job_id, event_type, payload_json)
                    VALUES (?, 'run_created', ?)
                    """,
                    (run_id, json.dumps({"kind": kind, "config": config})),
                )
        return run_id

    def list_all(self) -> list[dict[str, Any]]:
        with self._lock:
            with self._conn() as conn:
                rows = conn.execute(
                    "SELECT * FROM jobs ORDER BY created_at DESC"
                ).fetchall()
                return [self._row_to_job(r).to_dict() for r in rows]
