"""Sanity checks that the S5 DevEx assets ship at the expected paths.

These tests do **not** invoke `docker build` — they only verify the files
exist and that the Dockerfile contains a couple of well-known lines we
care about (Python base image and the exposed port). The goal is to catch
accidental deletions / renames of the Docker / pre-commit assets without
requiring Docker on the test runner.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

EXPECTED_ASSETS: tuple[str, ...] = (
    "Dockerfile",
    "docker-compose.yml",
    ".dockerignore",
    ".pre-commit-config.yaml",
    ".github/CI_DOCKER_SMOKE_PROPOSAL.md",
)


@pytest.mark.parametrize("relpath", EXPECTED_ASSETS)
def test_devex_asset_exists(relpath: str) -> None:
    """Each S5 asset must exist at the repo root (relative to the package)."""
    path = REPO_ROOT / relpath
    assert path.is_file(), f"Missing DevEx asset: {path} (relative: {relpath})"
    assert path.stat().st_size > 0, f"DevEx asset is empty: {path}"


def test_dockerfile_uses_python_312_slim() -> None:
    """The runtime base image must be python:3.12-slim (per S5 spec)."""
    dockerfile = (REPO_ROOT / "Dockerfile").read_text(encoding="utf-8")
    assert (
        "python:3.12-slim" in dockerfile
        or "python:${PYTHON_VERSION}-slim" in dockerfile
    ), (
        "Dockerfile must reference python:3.12-slim "
        "(directly or via a PYTHON_VERSION ARG defaulted to 3.12)"
    )
    if "python:${PYTHON_VERSION}-slim" in dockerfile:
        assert "ARG PYTHON_VERSION=3.12" in dockerfile, (
            "When using ${PYTHON_VERSION}, the ARG must default to 3.12 so the "
            "smoke check still pins the base image to 3.12."
        )


def test_dockerfile_exposes_port_8000() -> None:
    """Container must expose the FastAPI port 8000."""
    dockerfile = (REPO_ROOT / "Dockerfile").read_text(encoding="utf-8")
    assert "EXPOSE 8000" in dockerfile, "Dockerfile must contain `EXPOSE 8000`"


def test_dockerfile_runs_as_non_root_appuser() -> None:
    """Per S5 spec: the runtime stage must drop to a non-root `appuser`."""
    dockerfile = (REPO_ROOT / "Dockerfile").read_text(encoding="utf-8")
    assert "USER appuser" in dockerfile, "Dockerfile must switch to USER appuser"
    assert "useradd" in dockerfile, "Dockerfile must create the appuser system account"


def test_dockerfile_is_multi_stage_with_venv() -> None:
    """Builder + runtime stages with a copied venv from /opt/venv."""
    dockerfile = (REPO_ROOT / "Dockerfile").read_text(encoding="utf-8")
    assert "AS builder" in dockerfile, "Dockerfile must declare a builder stage"
    assert "AS runtime" in dockerfile, "Dockerfile must declare a runtime stage"
    assert (
        "COPY --from=builder /opt/venv /opt/venv" in dockerfile
    ), "Runtime stage must copy the prebuilt venv from the builder stage"


def test_compose_defines_backend_service_with_volume_and_ports() -> None:
    """docker-compose must wire the backend service per S5 spec."""
    compose = (REPO_ROOT / "docker-compose.yml").read_text(encoding="utf-8")
    assert "backend:" in compose, "compose must define a `backend` service"
    assert '"8000:8000"' in compose, "compose must publish port 8000:8000"
    assert (
        "./backtester/data:/app/backtester/data" in compose
    ), "compose must mount ./backtester/data as a persistent volume"
    assert (
        "restart: unless-stopped" in compose
    ), "compose must use restart: unless-stopped"
    assert "env_file" in compose, "compose must reference an env_file (.env, optional)"


def test_dockerignore_excludes_build_noise() -> None:
    """.dockerignore must exclude the noisy paths from the spec."""
    dockerignore = (
        (REPO_ROOT / ".dockerignore").read_text(encoding="utf-8").splitlines()
    )
    required = {
        ".venv",
        ".git",
        "flutter_app",
        "examples",
        "__pycache__",
        "*.pyc",
        ".pytest_cache",
        ".mypy_cache",
        ".ruff_cache",
        "node_modules",
        "build",
        "dist",
        "*.egg-info",
    }
    present = {
        line.strip()
        for line in dockerignore
        if line.strip() and not line.startswith("#")
    }
    missing = required - present
    assert not missing, f".dockerignore is missing required entries: {sorted(missing)}"


def test_precommit_config_has_required_hooks_and_python_312() -> None:
    """.pre-commit-config.yaml must pin python3.12 and include the spec'd hooks."""
    cfg = (REPO_ROOT / ".pre-commit-config.yaml").read_text(encoding="utf-8")
    assert (
        "python: python3.12" in cfg
    ), "pre-commit must pin default_language_version to python3.12"
    for hook_id in (
        "check-yaml",
        "check-toml",
        "end-of-file-fixer",
        "trailing-whitespace",
        "check-merge-conflict",
        "check-added-large-files",
        "ruff",
        "ruff-format",
        "mypy",
    ):
        assert hook_id in cfg, f"pre-commit config missing hook id: {hook_id}"
    for repo_url in (
        "https://github.com/pre-commit/pre-commit-hooks",
        "https://github.com/astral-sh/ruff-pre-commit",
        "https://github.com/pre-commit/mirrors-mypy",
    ):
        assert repo_url in cfg, f"pre-commit config missing repo: {repo_url}"


def test_ci_docker_smoke_proposal_mentions_required_jobs() -> None:
    """The CI proposal MD must describe both new jobs by name."""
    proposal = (REPO_ROOT / ".github" / "CI_DOCKER_SMOKE_PROPOSAL.md").read_text(
        encoding="utf-8"
    )
    assert (
        "docker-smoke:" in proposal
    ), "Proposal must contain a `docker-smoke:` YAML job"
    assert "pre-commit:" in proposal, "Proposal must contain a `pre-commit:` YAML job"
    assert (
        "ci-gate" in proposal
    ), "Proposal must explain how to update the ci-gate aggregate"


def test_readme_documents_docker_and_precommit() -> None:
    """backtester/README.md must surface the new Docker + pre-commit workflow."""
    readme = (REPO_ROOT / "backtester" / "README.md").read_text(encoding="utf-8")
    assert (
        "docker-compose up --build" in readme
    ), "README must show `docker-compose up --build`"
    assert (
        "docker exec backend python -m pytest" in readme
    ), "README must show how to run pytest inside the container"
    assert "pre-commit install" in readme, "README must show `pre-commit install`"
    assert (
        "pre-commit run --all-files" in readme
    ), "README must show `pre-commit run --all-files`"
