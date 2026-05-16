# Changelog

## v0.6.0

- Engine realism: added `fill_on_next_open` for MARKET execution and short-selling lifecycle (`open_short` / `close_short`) with short-aware equity and bracket exits.
- Advanced analytics: added probabilistic/deflated Sharpe metrics plus stress battery endpoint (`POST /api/backtest/{run_id}/stress`).
- Strategy set expanded with `DonchianBreakout` and `GridTrading` bots and dedicated tests.
- Data quality vertical slice: added `validate_ohlcv`, thread-safe Binance weight tracker, and `POST /api/data/validate`.
- DevEx: added `Dockerfile`, `docker-compose.yml`, `.dockerignore`, `.pre-commit-config.yaml`, and CI job proposals plus required CI jobs.
- UX: added command palette (`Ctrl/Cmd+K`) with keyboard actions and data validation action from Backtest screen.
- Quality: added property-based tests (`hypothesis`) and opt-in benchmark tests (`pytest-benchmark`).
