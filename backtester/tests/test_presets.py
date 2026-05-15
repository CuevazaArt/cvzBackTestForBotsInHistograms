"""Tests for PresetStore + /api/presets endpoints (Sprint 5)."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from backtester.api.server import create_app
from backtester.core.preset_store import PresetStore


# ── PresetStore unit tests ─────────────────────────────────────


def test_preset_upsert_and_get(tmp_path):
    store = PresetStore(tmp_path / "presets.sqlite")
    try:
        store.upsert(
            "FastEMA", "EMACross", {"fast_ema": 5, "slow_ema": 15}, "fast scalp"
        )
        got = store.get("FastEMA")
        assert got is not None
        assert got.name == "FastEMA"
        assert got.bot_name == "EMACross"
        assert got.params == {"fast_ema": 5, "slow_ema": 15}
        assert got.description == "fast scalp"
    finally:
        store.close()


def test_preset_upsert_overwrites_same_name(tmp_path):
    store = PresetStore(tmp_path / "presets.sqlite")
    try:
        store.upsert("X", "EMACross", {"fast_ema": 5, "slow_ema": 15})
        store.upsert("X", "EMACross", {"fast_ema": 8, "slow_ema": 20})
        got = store.get("X")
        assert got.params == {"fast_ema": 8, "slow_ema": 20}
    finally:
        store.close()


def test_preset_list_filters_by_bot(tmp_path):
    store = PresetStore(tmp_path / "presets.sqlite")
    try:
        store.upsert("a", "EMACross", {"fast_ema": 5, "slow_ema": 15})
        store.upsert("b", "MACDCross", {"fast_ema": 12, "slow_ema": 26})
        ema_only = store.list_all(bot_name="EMACross")
        assert len(ema_only) == 1 and ema_only[0]["name"] == "a"
        assert len(store.list_all()) == 2
    finally:
        store.close()


def test_preset_delete(tmp_path):
    store = PresetStore(tmp_path / "presets.sqlite")
    try:
        store.upsert("z", "EMACross", {"fast_ema": 5, "slow_ema": 15})
        assert store.delete("z") is True
        assert store.get("z") is None
        assert store.delete("z") is False
    finally:
        store.close()


def test_preset_persistence_across_instances(tmp_path):
    db = tmp_path / "presets.sqlite"
    s1 = PresetStore(db)
    s1.upsert("keep", "EMACross", {"fast_ema": 5, "slow_ema": 15})
    s1.close()
    s2 = PresetStore(db)
    try:
        assert s2.get("keep") is not None
    finally:
        s2.close()


# ── HTTP integration ───────────────────────────────────────────


@pytest.fixture
def client(tmp_path, monkeypatch):
    # Point AppContext at a tmp dir so we don't pollute backtester/data/.
    monkeypatch.chdir(tmp_path)
    app = create_app()
    with TestClient(app) as c:
        yield c


def test_save_and_list_preset_via_api(client):
    body = {
        "name": "EMAFast",
        "bot_name": "EMACross",
        "params": {"fast_ema": 5, "slow_ema": 20},
        "description": "scalp preset",
    }
    r = client.post("/api/presets", json=body)
    assert r.status_code == 200, r.text
    saved = r.json()
    assert saved["name"] == "EMAFast"
    assert saved["params"] == {"fast_ema": 5, "slow_ema": 20}

    r = client.get("/api/presets")
    assert r.status_code == 200
    names = [p["name"] for p in r.json()]
    assert "EMAFast" in names


def test_get_missing_preset_returns_404(client):
    r = client.get("/api/presets/does-not-exist")
    assert r.status_code == 404


def test_save_unknown_bot_returns_422(client):
    body = {"name": "x", "bot_name": "NotARealBot", "params": {}}
    r = client.post("/api/presets", json=body)
    assert r.status_code == 422
    assert "Unknown bot" in r.text


def test_delete_preset_via_api(client):
    client.post(
        "/api/presets",
        json={
            "name": "tmp",
            "bot_name": "EMACross",
            "params": {"fast_ema": 5, "slow_ema": 15},
        },
    )
    r = client.delete("/api/presets/tmp")
    assert r.status_code == 200
    assert r.json() == {"deleted": True}
    assert client.get("/api/presets/tmp").status_code == 404
