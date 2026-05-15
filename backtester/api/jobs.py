"""Async job registry (downloads, experiments, optimizations).

Backed by SQLite (`backtester.core.job_store.JobStore`) so jobs survive API
restarts. The legacy `JobRegistry` name is preserved for backwards compat.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Optional

from backtester.core.job_store import Job, JobStore

__all__ = ["Job", "JobRegistry"]


class JobRegistry:
    """Thread-safe persistent job store. Wraps `JobStore` for the API layer."""

    def __init__(self, db_path: Path | str | None = None) -> None:
        # In-memory fallback for unit tests that pass no path.
        path = db_path if db_path is not None else ":memory:"
        self._store = JobStore(path) if path != ":memory:" else _InMemoryJobStore()

    # ── delegation ───────────────────────────────────────────────

    def create(self, kind: str) -> Job:
        return self._store.create(kind)

    def get(self, job_id: str) -> Optional[Job]:
        return self._store.get(job_id)

    def update(self, job_id: str, **kwargs: Any) -> None:
        self._store.update(job_id, **kwargs)

    def list_all(self) -> list[dict[str, Any]]:
        return self._store.list_all()

    def list_filtered(self, **kwargs: Any) -> list[dict[str, Any]]:
        return self._store.list_filtered(**kwargs)

    def delete(self, job_id: str) -> bool:
        return self._store.delete(job_id)

    def cleanup_older_than(self, seconds: float) -> int:
        return self._store.cleanup_older_than(seconds)

    def create_run(self, kind: str, config: dict[str, Any]) -> str:
        return self._store.create_run(kind, config)

    def request_cancel(self, job_id: str) -> bool:
        return self._store.request_cancel(job_id)

    def is_cancel_requested(self, job_id: str) -> bool:
        return self._store.is_cancel_requested(job_id)


class _InMemoryJobStore:
    """Lightweight in-memory fallback (no SQLite) for unit tests."""

    def __init__(self) -> None:
        import threading
        self._jobs: dict[str, Job] = {}
        self._lock = threading.Lock()
        self._run_events: list[tuple[str, str, str, float]] = []

    def create(self, kind: str) -> Job:
        import time
        import uuid
        now = time.time()
        job = Job(
            id=str(uuid.uuid4()),
            kind=kind,
            created_at=now,
            updated_at=now,
            cancel_requested=False,
            run_id=None,
        )
        with self._lock:
            self._jobs[job.id] = job
        return job

    def get(self, job_id: str) -> Optional[Job]:
        with self._lock:
            return self._jobs.get(job_id)

    def update(self, job_id: str, **kwargs: Any) -> None:
        import time
        allowed = {"status", "progress", "message", "result", "run_id"}
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                return
            for k, v in kwargs.items():
                if k in allowed:
                    setattr(job, k, v)
            job.updated_at = time.time()

    def list_all(self) -> list[dict[str, Any]]:
        with self._lock:
            return [j.to_dict() for j in self._jobs.values()]

    def list_filtered(
        self,
        kind: Optional[str] = None,
        status: Optional[str] = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        with self._lock:
            items = sorted(self._jobs.values(), key=lambda j: j.updated_at, reverse=True)
        if kind is not None:
            items = [j for j in items if j.kind == kind]
        if status is not None:
            items = [j for j in items if j.status == status]
        return [j.to_dict() for j in items[offset:offset + limit]]

    def delete(self, job_id: str) -> bool:
        with self._lock:
            return self._jobs.pop(job_id, None) is not None

    def cleanup_older_than(self, seconds: float) -> int:
        import time
        cutoff = time.time() - seconds
        with self._lock:
            stale = [
                jid for jid, j in self._jobs.items()
                if j.updated_at < cutoff and j.status in ("done", "error", "cancelled")
            ]
            for jid in stale:
                del self._jobs[jid]
            return len(stale)

    def create_run(self, kind: str, config: dict[str, Any]) -> str:
        import json
        import time
        import uuid
        run_id = str(uuid.uuid4())
        now = time.time()
        with self._lock:
            self._run_events.append(
                (run_id, "run_created", json.dumps({"kind": kind, "config": config}), now),
            )
        return run_id

    def request_cancel(self, job_id: str) -> bool:
        import time
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None or job.status not in ("pending", "running"):
                return False
            job.cancel_requested = True
            job.updated_at = time.time()
            return True

    def is_cancel_requested(self, job_id: str) -> bool:
        with self._lock:
            job = self._jobs.get(job_id)
            return bool(job and job.cancel_requested)
