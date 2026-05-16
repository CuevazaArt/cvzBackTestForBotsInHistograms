# CI proposal: `docker-smoke` and `pre-commit` jobs

This file is a **proposal** — the S5 subagent does NOT touch
`.github/workflows/ci.yml` directly. The coordinator should paste the YAML
snippets below into `ci.yml` during the integration phase.

## Goals

1. **`docker-smoke`** — fail fast if the `Dockerfile` stops building, or if
   importing the package or hitting `/healthz` breaks inside the runtime
   image. Catches packaging / dependency drift that a host-only test suite
   misses (musl vs glibc wheels, missing system libs, file copies forgotten
   in the build context, etc.).
2. **`pre-commit`** — run the exact same hooks that local devs run before
   committing, so PRs cannot land with formatting / lint / mypy regressions
   even when a contributor forgot `pre-commit install`.

Both jobs are cheap (Ubuntu-only, no matrix) and should be added to the
`ci-gate.needs` list so they become required for branch protection.

## 1. `docker-smoke` job

Paste this block under the existing `flutter:` job in
`.github/workflows/ci.yml`:

```yaml
  # ── Docker image smoke test ────────────────────────────────────
  # Builds the runtime image with BuildKit caching, runs the test suite
  # inside it, and verifies the FastAPI server boots and answers /healthz.
  docker-smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build runtime image (with cache)
        uses: docker/build-push-action@v6
        with:
          context: .
          file: ./Dockerfile
          load: true
          tags: cvz-backtester:ci
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Smoke import inside image
        run: |
          docker run --rm cvz-backtester:ci \
            python -c "from backtester import BacktestEngine, BacktestConfig, BOT_REGISTRY, __version__; \
                       print('SDK', __version__, sorted(BOT_REGISTRY))"

      - name: Run pytest inside image
        run: |
          docker run --rm \
            -e PYTHONPATH=/app \
            cvz-backtester:ci \
            python -m pytest backtester/tests/ -q --maxfail=5

      - name: Boot server and probe /healthz
        run: |
          docker run -d --name cvz-smoke -p 8000:8000 cvz-backtester:ci
          # wait up to 30s for /healthz to come up
          for i in $(seq 1 30); do
            if curl -fsS http://127.0.0.1:8000/healthz >/dev/null 2>&1; then
              echo "healthz OK after ${i}s"; break
            fi
            sleep 1
          done
          curl -fsS http://127.0.0.1:8000/healthz
          docker logs cvz-smoke
          docker rm -f cvz-smoke
```

Notes for the coordinator:

- The `/healthz` probe assumes such an endpoint exists (or returns 200 on
  `/`). If the API doesn't expose `/healthz` yet, swap that step for a
  simpler `python -c "import backtester.api.server"` import check.
- `cache-from: type=gha` reuses GitHub Actions cache between runs and
  typically keeps re-builds under 60s.
- The pytest-inside-image step duplicates `test-backend` somewhat, but
  serves a different purpose: it proves the *packaged* artifact runs, not
  just the source tree on the host.

## 2. `pre-commit` job

Paste this block right after the new `docker-smoke` job:

```yaml
  # ── pre-commit hooks (lint / format / mypy) ────────────────────
  # Mirror what `pre-commit install` does locally so PRs cannot bypass it.
  pre-commit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"
      - name: Install pre-commit
        run: pip install pre-commit==4.0.1
      - name: Cache pre-commit hook envs
        uses: actions/cache@v4
        with:
          path: ~/.cache/pre-commit
          key: pre-commit-${{ runner.os }}-${{ hashFiles('.pre-commit-config.yaml') }}
      - name: Run pre-commit on all files
        run: pre-commit run --all-files --show-diff-on-failure
```

## 3. Update the `ci-gate` aggregate

Extend the `needs:` list and the conditional check so the new jobs are
required:

```yaml
  ci-gate:
    needs: [lint-backend, typecheck-backend, test-backend, sdk-packaging, flutter, docker-smoke, pre-commit]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Verify required jobs succeeded
        run: |
          if [ "${{ needs.lint-backend.result }}"     != "success" ] || \
             [ "${{ needs.typecheck-backend.result }}" != "success" ] || \
             [ "${{ needs.test-backend.result }}"      != "success" ] || \
             [ "${{ needs.sdk-packaging.result }}"     != "success" ] || \
             [ "${{ needs.flutter.result }}"           != "success" ] || \
             [ "${{ needs.docker-smoke.result }}"      != "success" ] || \
             [ "${{ needs.pre-commit.result }}"        != "success" ]; then
            echo "One or more required jobs failed"
            exit 1
          fi
          echo "All required CI checks passed"
```

## Open questions for the coordinator

- Should `docker-smoke` push the image to GHCR on `main` pushes? (Out of
  scope for this slice; flag as a follow-up if desired.)
- `pre-commit` is currently set to `python3.12` in `default_language_version`.
  CI uses 3.11 elsewhere; the pre-commit job above bumps to 3.12 to match
  the hooks. If branch-protection requires staying on 3.11, change
  `default_language_version.python` in `.pre-commit-config.yaml`.
- The `/healthz` step can be promoted to a `docker compose up -d` flow if
  we want the volume mounts exercised in CI too — let me know.
