"""In-memory async job registry (downloads, experiments).

For a single-user local dev tool this is enough; persistence would only be
needed for multi-user/remote deployments.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
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

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id, "kind": self.kind, "status": self.status,
            "progress": self.progress, "message": self.message, "result": self.result,
        }


class JobRegistry:
    """Thread-safe in-memory job store."""

    def __init__(self) -> None:
        self._jobs: dict[str, Job] = {}
        self._lock = Lock()

    def create(self, kind: str) -> Job:
        job = Job(id=str(uuid.uuid4()), kind=kind)
        with self._lock:
            self._jobs[job.id] = job
        return job

    def get(self, job_id: str) -> Optional[Job]:
        with self._lock:
            return self._jobs.get(job_id)

    def update(self, job_id: str, **kwargs: Any) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                return
            for k, v in kwargs.items():
                setattr(job, k, v)

    def list_all(self) -> list[dict[str, Any]]:
        with self._lock:
            return [j.to_dict() for j in self._jobs.values()]
