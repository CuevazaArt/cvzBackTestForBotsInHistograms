"""SQLite-backed bot-preset store.

Presets pair a bot name with a saved param map and an optional description.
Names are unique. Persists at `data/presets.sqlite` alongside `jobs.sqlite`.
"""

from __future__ import annotations

import json
import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

_SCHEMA = """
CREATE TABLE IF NOT EXISTS presets (
    name        TEXT PRIMARY KEY,
    bot_name    TEXT NOT NULL,
    params_json TEXT NOT NULL,
    description TEXT,
    created_at  REAL NOT NULL,
    updated_at  REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_presets_bot ON presets(bot_name);
"""


@dataclass
class Preset:
    name: str
    bot_name: str
    params: dict[str, Any]
    description: Optional[str] = None
    created_at: float = 0.0
    updated_at: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "bot_name": self.bot_name,
            "params": self.params,
            "description": self.description,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


class PresetStore:
    """Thread-safe preset CRUD backed by SQLite."""

    def __init__(self, db_path: Path | str) -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(
            str(self.db_path), check_same_thread=False, isolation_level=None,
        )
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.row_factory = sqlite3.Row
        with self._lock:
            self._conn.executescript(_SCHEMA)

    def upsert(
        self,
        name: str,
        bot_name: str,
        params: dict[str, Any],
        description: Optional[str] = None,
    ) -> Preset:
        now = time.time()
        with self._lock:
            existing = self._conn.execute(
                "SELECT created_at FROM presets WHERE name = ?", (name,),
            ).fetchone()
            created_at = existing["created_at"] if existing else now
            self._conn.execute(
                "INSERT INTO presets(name, bot_name, params_json, description, "
                "created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(name) DO UPDATE SET "
                "bot_name=excluded.bot_name, params_json=excluded.params_json, "
                "description=excluded.description, updated_at=excluded.updated_at",
                (name, bot_name, json.dumps(params), description, created_at, now),
            )
        return Preset(
            name=name,
            bot_name=bot_name,
            params=params,
            description=description,
            created_at=created_at,
            updated_at=now,
        )

    def get(self, name: str) -> Optional[Preset]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM presets WHERE name = ?", (name,),
            ).fetchone()
        return self._row_to_preset(row) if row else None

    def list_all(self, bot_name: Optional[str] = None) -> list[dict[str, Any]]:
        with self._lock:
            if bot_name is not None:
                rows = self._conn.execute(
                    "SELECT * FROM presets WHERE bot_name = ? ORDER BY updated_at DESC",
                    (bot_name,),
                ).fetchall()
            else:
                rows = self._conn.execute(
                    "SELECT * FROM presets ORDER BY updated_at DESC",
                ).fetchall()
        return [self._row_to_preset(r).to_dict() for r in rows]

    def delete(self, name: str) -> bool:
        with self._lock:
            cur = self._conn.execute("DELETE FROM presets WHERE name = ?", (name,))
            return cur.rowcount > 0

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    @staticmethod
    def _row_to_preset(row: sqlite3.Row) -> Preset:
        return Preset(
            name=row["name"],
            bot_name=row["bot_name"],
            params=json.loads(row["params_json"]),
            description=row["description"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )
