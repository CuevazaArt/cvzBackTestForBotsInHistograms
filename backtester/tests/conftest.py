"""Shared pytest configuration for the backtester suite.

Registers custom markers dynamically so they don't have to live in
``pyproject.toml`` (which is owned by the coordinator and shared across
parallel feature slices). Keeping marker registration here means each
slice can introduce its own opt-in markers without touching shared files.

Markers registered:
    benchmark - long-running performance / throughput tests. Opt-in via
                ``pytest -m benchmark``. CI excludes them by default with
                ``-m "not benchmark"``.
    property  - property-based / hypothesis-driven invariant tests. Cheap
                enough to run in CI but tagged so contributors can
                isolate them with ``pytest -m property`` while iterating.
"""

from __future__ import annotations


def pytest_configure(config) -> None:
    """Register custom markers so ``--strict-markers`` stays clean."""
    config.addinivalue_line(
        "markers",
        "benchmark: opt-in performance / throughput tests "
        "(skipped in default CI; run with `-m benchmark`).",
    )
    config.addinivalue_line(
        "markers",
        "property: hypothesis-driven property/invariant tests.",
    )
