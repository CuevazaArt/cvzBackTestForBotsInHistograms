"""Tests for SQLite-backed JobStore (Sprint 1: persistence)."""

from __future__ import annotations

import tempfile
import time
from pathlib import Path

from backtester.core.job_store import JobStore


def _make_store() -> tuple[JobStore, str]:
    tmp = tempfile.mkdtemp()
    return JobStore(Path(tmp) / "jobs.sqlite"), tmp


def test_create_and_get_roundtrip():
    store, _ = _make_store()
    job = store.create("download")
    assert job.id and job.kind == "download" and job.status == "pending"
    got = store.get(job.id)
    assert got is not None and got.id == job.id


def test_update_persists_fields():
    store, _ = _make_store()
    job = store.create("experiment")
    store.update(job.id, status="running", progress=0.5, message="halfway")
    got = store.get(job.id)
    assert got.status == "running" and got.progress == 0.5 and got.message == "halfway"


def test_update_result_serialises_json():
    store, _ = _make_store()
    job = store.create("download")
    store.update(job.id, status="done", result={"candles_added": 42, "nested": {"k": 1}})
    got = store.get(job.id)
    assert got.result == {"candles_added": 42, "nested": {"k": 1}}


def test_persistence_across_instances():
    tmp = tempfile.mkdtemp()
    db = Path(tmp) / "jobs.sqlite"
    s1 = JobStore(db)
    job = s1.create("download")
    s1.update(job.id, status="done", result={"x": 1})
    s1.close()

    s2 = JobStore(db)
    got = s2.get(job.id)
    assert got is not None and got.status == "done" and got.result == {"x": 1}


def test_list_filtered_by_kind_and_status():
    store, _ = _make_store()
    a = store.create("download")
    store.update(a.id, status="done")
    b = store.create("experiment")
    store.update(b.id, status="running")
    c = store.create("download")
    store.update(c.id, status="error")
    _ = c  # keep reference

    done_downloads = store.list_filtered(kind="download", status="done")
    assert len(done_downloads) == 1 and done_downloads[0]["id"] == a.id

    all_experiments = store.list_filtered(kind="experiment")
    assert len(all_experiments) == 1 and all_experiments[0]["id"] == b.id


def test_delete_removes_job():
    store, _ = _make_store()
    job = store.create("download")
    assert store.delete(job.id) is True
    assert store.get(job.id) is None
    assert store.delete(job.id) is False  # idempotent


def test_cleanup_older_than_only_terminal_states():
    store, _ = _make_store()
    old_done = store.create("download")
    store.update(old_done.id, status="done")
    old_running = store.create("download")
    store.update(old_running.id, status="running")
    # backdate updated_at directly
    with store._lock:
        store._conn.execute(
            "UPDATE jobs SET updated_at = ? WHERE id IN (?, ?)",
            (time.time() - 100, old_done.id, old_running.id),
        )
    deleted = store.cleanup_older_than(50)
    assert deleted == 1  # only the 'done' one
    assert store.get(old_done.id) is None
    assert store.get(old_running.id) is not None


def test_pagination():
    store, _ = _make_store()
    for _ in range(5):
        store.create("download")
    page1 = store.list_filtered(limit=2, offset=0)
    page2 = store.list_filtered(limit=2, offset=2)
    assert len(page1) == 2 and len(page2) == 2
    assert {j["id"] for j in page1}.isdisjoint({j["id"] for j in page2})


def test_in_memory_registry_fallback():
    from backtester.api.jobs import JobRegistry
    reg = JobRegistry()  # no path → in-memory
    job = reg.create("download")
    reg.update(job.id, status="done", result={"k": 1})
    assert reg.get(job.id).status == "done"
    assert reg.get(job.id).result == {"k": 1}
    assert reg.delete(job.id) is True
