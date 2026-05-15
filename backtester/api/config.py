"""Runtime configuration for the API layer."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class ApiSettings:
    api_token: str | None
    cors_allow_origins: list[str]
    allow_all_cors: bool

    @property
    def auth_enabled(self) -> bool:
        return bool(self.api_token)


def _split_csv(raw: str) -> list[str]:
    return [x.strip() for x in raw.split(",") if x.strip()]


def load_api_settings() -> ApiSettings:
    token = os.getenv("BACKTESTER_API_TOKEN", "").strip() or None
    allow_all = os.getenv("BACKTESTER_CORS_ALLOW_ALL", "1").strip() in {"1", "true", "True"}
    origins_raw = os.getenv(
        "BACKTESTER_CORS_ORIGINS",
        "http://127.0.0.1:8002,http://localhost:8002",
    )
    origins = _split_csv(origins_raw)
    return ApiSettings(api_token=token, cors_allow_origins=origins, allow_all_cors=allow_all)
