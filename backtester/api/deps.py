"""Application context singleton — injected into routes via Depends/Request."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from fastapi import Request

from backtester.api.jobs import JobRegistry
from backtester.bots import BOT_REGISTRY  # re-export
from backtester.core import BinanceDownloader, CredentialManager
from backtester.core.cache import IndicatorCache
from backtester.core.preset_store import PresetStore
from backtester.core.result_store import ResultStore


@dataclass
class AppContext:
    base_dir: Path
    downloader: BinanceDownloader
    credentials: CredentialManager
    bot_registry: dict[str, Callable]
    jobs: JobRegistry
    presets: PresetStore
    indicator_cache: IndicatorCache = None  # type: ignore[assignment]
    result_store: ResultStore = None  # type: ignore[assignment]

    def __post_init__(self) -> None:
        if self.indicator_cache is None:
            self.indicator_cache = IndicatorCache(max_entries=512)
        if self.result_store is None:
            root = (
                Path(self.base_dir)
                if self.base_dir
                else Path(__file__).resolve().parents[1]
            )
            data_dir = root / "data"
            data_dir.mkdir(parents=True, exist_ok=True)
            self.result_store = ResultStore(data_dir / "results.sqlite")

    @classmethod
    def build(cls, base_dir: Path | None = None) -> "AppContext":
        root = Path(base_dir) if base_dir else Path(__file__).resolve().parents[1]
        data_dir = root / "data"
        vault_dir = root / ".vault"
        data_dir.mkdir(parents=True, exist_ok=True)
        vault_dir.mkdir(parents=True, exist_ok=True)

        return cls(
            base_dir=root,
            downloader=BinanceDownloader(data_dir / "candles.db"),
            credentials=CredentialManager(vault_dir),
            bot_registry=dict(BOT_REGISTRY),
            jobs=JobRegistry(data_dir / "jobs.sqlite"),
            presets=PresetStore(data_dir / "presets.sqlite"),
            indicator_cache=IndicatorCache(max_entries=512),
            result_store=ResultStore(data_dir / "results.sqlite"),
        )


def get_ctx(request: Request) -> AppContext:
    """FastAPI dependency to grab the AppContext from app.state."""
    return request.app.state.ctx
