# syntax=docker/dockerfile:1.7
# Multi-stage build for the cvz-backtester FastAPI service.
#
# Stage 1 (builder): pulls Python 3.12-slim, creates a virtualenv at /opt/venv
# and installs runtime dependencies from backtester/requirements.txt. Wheels are
# cached via BuildKit for fast iterative builds.
#
# Stage 2 (runtime): same slim base, copies the prebuilt venv and the backtester
# package, then installs the project itself with --no-deps in editable mode so
# `import backtester` resolves to /app/backtester. Runs as a non-root user.

ARG PYTHON_VERSION=3.12

# ---------- Stage 1: builder ----------
FROM python:${PYTHON_VERSION}-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv

# Build deps for any wheel that needs compiling (e.g. cryptography on slim).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        libffi-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv "$VIRTUAL_ENV"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /build

COPY backtester/requirements.txt ./requirements.txt

RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# ---------- Stage 2: runtime ----------
FROM python:${PYTHON_VERSION}-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH" \
    APP_HOME=/app

# Tini gives PID 1 signal handling for clean SIGTERM propagation to uvicorn.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system appuser \
    && useradd  --system --gid appuser --create-home --home-dir /home/appuser appuser

COPY --from=builder /opt/venv /opt/venv

WORKDIR ${APP_HOME}

COPY pyproject.toml README.md ./
COPY backtester ./backtester

# Install the project metadata only — runtime deps already live in the venv.
RUN pip install --no-deps -e .

# Persistent state lives here (SQLite store, cached candles, vault, results).
RUN mkdir -p /app/backtester/data /app/backtester/results /app/backtester/.vault \
    && chown -R appuser:appuser /app /opt/venv /home/appuser

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3).status==200 else 1)"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["uvicorn", "backtester.api.server:app", "--host", "0.0.0.0", "--port", "8000"]
