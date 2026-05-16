# Backlog refrescado — v0.6.0

> Generado: 2026-05-15 · Estado verificado contra el árbol de código a tag `v0.6.0`.
>
> **Este documento sustituye a la sección "Sigue vigente (backlog confirmado)" y a la
> sección "2. Plan de trabajo por pistas" de `WORKPLAN.md` a partir de `v0.6.0`.**
> `WORKPLAN.md` se conserva como documento histórico (instantánea del análisis al
> cierre de `v0.5.0`). Para decidir qué se trabaja a continuación, usar **esta**
> tabla.

Items auditados: **64** (16 críticas C1–C16 + 9 A + 5 B + 5 C + 8 D + 4 E + 7 F + 6 G + 4 H).

| Estado   | Conteo |
|----------|--------|
| DONE     | 20     |
| PARTIAL  | 7      |
| OPEN     | 37     |

---

## DONE en v0.6.0 (20)

Evidencia verificada en el árbol de código actual.

| ID | Pista | Descripción | Evidencia |
|----|-------|-------------|-----------|
| **C2** (Crit.) | Crítica | Look-ahead bias en MARKET (fill en open N+1) | `backtester/core/engine.py:251` (`BacktestConfig.fill_on_next_open: bool = True`) y `backtester/core/engine.py:564-590` (ruta MARKET pone el fill en el siguiente bar) |
| **C3** (Crit.) | Crítica | `profit_factor` consistente (`gross_profit / gross_loss`) | `backtester/core/engine.py:271-305` (`BacktestResult.summary`) — coincide con `build_per_bot_breakdown` |
| **C4** (Crit.) | Crítica | `sum()` sobre Decimal con `start=Decimal("0")` | `backtester/core/engine.py:147-167, 291-295, 477-489, 816-823` (siempre con `start=Decimal("0")`) |
| **C5** (Crit.) | Crítica | `compute_max_drawdown_pct` semilla `equity_curve[0]` | `backtester/core/engine.py:308-329` (`running_peak = equity_curve[0]`) |
| **C10** (Crit.) | Crítica | Validador de calidad de datos | `backtester/core/data_quality.py:134` (`validate_ohlcv`: gaps, duplicados, OHLC consistency, IQR outliers, completeness) |
| **C13** (Crit.) | Crítica | Dockerfile + docker-compose | `Dockerfile` (multi-stage, non-root, healthcheck), `docker-compose.yml` |
| **C15** (Crit.) | Crítica | Benchmarks de performance | `backtester/tests/test_benchmark.py` (pytest-benchmark) |
| **C16** (Crit.) | Crítica | `BINANCE_USED_WEIGHT_1M` thread-safe | `backtester/core/downloader.py:24-80` (clase `WeightTracker` con `threading.Lock`) |
| **A1** | A — Motor | Anti look-ahead MARKET (fill en open N+1, configurable) | `BacktestConfig.fill_on_next_open` (default `True`) en `backtester/core/engine.py:251` |
| **A2** | A — Motor | Soporte SHORT (lifecycle completo) | `Position.side` (`engine.py:67`), `_process_short_at` (`engine.py:953-995`), `_process_cover_at` (`engine.py:1127-1213`), equity short-aware en `Portfolio.total_equity` (`engine.py:145-155`) |
| **A8** | A — Motor | Property-based tests (hypothesis) | `backtester/tests/test_property.py`, dependencia `hypothesis` en `pyproject.toml` (extra `test`) |
| **A9** | A — Motor | Benchmark con pytest-benchmark | `backtester/tests/test_benchmark.py`, dependencia `pytest-benchmark` en `pyproject.toml` (extra `test`) |
| **B3** | B — Datos | Validador de calidad (gaps/dup/outliers) | `backtester/core/data_quality.py:134` (mismo `validate_ohlcv` que C10) |
| **B5** | B — Datos | Weight Binance thread-safe | `backtester/core/downloader.py:24-80` (clase `WeightTracker`) |
| **C3 (track C)** | C — Bots | DSL declarativo YAML/JSON | `backtester/bots/dsl/dsl_bot.py:22` (`DSLBot`), parser en `backtester/bots/dsl/parser.py`, evaluador en `backtester/bots/dsl/evaluator.py`, expuesto como `"DSL"` en `BOT_REGISTRY` (`backtester/bots/__init__.py:17`) |
| **D2** | D — Análisis | PSR + DSR (Deflated Sharpe Ratio) | `backtester/core/metrics.py:64` (`probabilistic_sharpe_ratio`), `:81` (`deflated_sharpe_ratio`), exportado desde `backtester/__init__.py:37` |
| **D4** | D — Análisis | Stress tests (fees ×N, slippage ×N, drop best %) | `backtester/analysis/stress.py:83` (`run_stress_battery`) + `StressMatrix` |
| **F4** | F — UX | Command palette + atajos teclado | `flutter_app/lib/widgets/command_palette.dart` (Ctrl/Cmd+K, fuzzy filter, `ShortcutHooks`) + test en `flutter_app/test/command_palette_test.dart` |
| **F6** | F — UX | Comparador side-by-side de N runs | UI: `flutter_app/lib/widgets/compare_panel.dart`. Backend: `POST /api/backtest/compare` en `backtester/api/routes/results.py:113-115` |
| **G1** | G — DevEx | Docker + docker-compose | `Dockerfile`, `docker-compose.yml`, job `docker-smoke` en `.github/workflows/ci.yml:136` (requerido por `ci-gate`) |

---

## PARTIAL (7)

Tienen una parte hecha; lo que falta se indica en "Siguiente paso".

| ID | Pista | Descripción | Qué ya hay | Siguiente paso |
|----|-------|-------------|-----------|----------------|
| **C1** (Crit.) | Crítica | "Solo LONG / spot" | SHORT completo (A2 DONE). Spot sigue como único modo. | Implementar **A3** (futures perpetuos con funding + leverage) para cerrar la crítica original. |
| **A6** | A — Motor | Sizing avanzado: VolatilityTarget(ATR), KellyFraction, RiskPerTradeWithStop | `size_by_risk` (RiskPerTradeWithStop) en `backtester/core/engine.py:211` y tests en `test_orders.py:306-326`. | Añadir helpers `size_by_atr_target(volatility_target_pct, atr)` y `size_by_kelly(win_rate, win_loss_ratio, fraction)` en `BotBase` o `BacktestBot` con sus tests. |
| **C1 (track C)** | C — Bots | Plantillas: Donchian, grid, ATR mean-reversion, momentum multi-TF, pairs/cointegración | 2 de 5: `DonchianBreakout` (`backtester/bots/donchian_breakout.py:23`), `GridTrading` (`backtester/bots/grid_trading.py:34`). | Añadir `ATRMeanReversion`, `MomentumMultiTF` y `PairsCointegration` y registrarlos en `BOT_REGISTRY`. |
| **C2 (track C)** | C — Bots | Librería de indicadores reutilizable consumida por bots vía DI | `IndicatorCache` (`backtester/core/cache.py`), `add_indicators` en `backtester/core/indicators.py`, usado por DSLBot (`backtester/bots/dsl/dsl_bot.py`) y por la capa de optimización/experiments. | Refactorizar `EMACross`, `MACDCross`, `RSIReversion`, `BollingerReversion` para que el motor inyecte series precomputadas (o un `IndicatorService`) en vez de cada bot mantener su propio warm-up. |
| **F2** | F — UX | CLI completo + SDK publicable en PyPI (`cvz-backtester`) | Console script `cvz-backtester = backtester.main:main` en `pyproject.toml:64`, CLI Rich en `backtester/ui/cli.py`, metadata y `dependencies` listos en `pyproject.toml`. | Añadir workflow de release (`twine upload` con `OIDC` / Trusted Publishing), `CHANGELOG.md` por release y publicar `0.6.0` en PyPI. |
| **F5** | F — UX | Reportes exportables HTML/PDF | Reporte HTML self-contained en `backtester/reporting/html_report.py` con Chart.js + tabla de trades. | Añadir generador PDF (vía `weasyprint` o `playwright`) sobre el mismo template Jinja2 y exponerlo en la API (`GET /api/runs/{id}/report.pdf`). |
| **G3** | G — DevEx | Pre-commit hooks (ruff + mypy + **dart analyze**) | `.pre-commit-config.yaml` con `ruff`, `ruff-format` y `mypy` (mirrors-mypy v1.11.2), corre en CI (`pre-commit` job). | Añadir hook local que ejecute `flutter analyze` sobre `flutter_app/` antes de commit (similar a lo que ya hace el CI job `flutter`). |

---

## OPEN (37)

Sin implementación encontrada (búsqueda por keywords y revisión de los módulos relevantes).

| ID | Pista | Descripción | Siguiente paso sugerido |
|----|-------|-------------|--------------------------|
| **C6** (Crit.) | Crítica | Slippage fijo % (sin profundidad de libro ni impacto por tamaño) | Parametrizar `BacktestConfig.slippage_pct` por símbolo y añadir modelo de impacto `f(qty, avg_volume)`. Misma área que A4. |
| **C7** (Crit.) | Crítica | Decimal vs float híbrido (indicadores float, motor Decimal) | Misma área que A5. Decidir: o (a) migrar hot path a `float64` y reportes a `Decimal`, o (b) unificar todo a `Decimal`. Documentar la decisión en `ARCHITECTURE.md`. |
| **C8** (Crit.) | Crítica | Equity curve incluye warm-up → infla varianza, deflate Sharpe | Idéntico a D8. Filtrar barras anteriores al primer trade antes de calcular Sharpe / Sortino / DD. |
| **C9** (Crit.) | Crítica | Sin multi-exchange (solo Binance spot REST) | Idéntico a B1. Definir interfaz `ExchangeAdapter` y migrar `BinanceDownloader` a una implementación concreta. |
| **C11** (Crit.) | Crítica | Sin paper-trading / live / monitoring | Mismo bloque que track E (E1–E4). Es lo que convierte la herramienta en producto. |
| **C12** (Crit.) | Crítica | Solo Windows en Flutter | Idéntico a F1. `flutter create . --platforms=macos,linux,web` (no existen `flutter_app/{macos,linux,web}`). |
| **C14** (Crit.) | Crítica | Docs dispersos (README, SETUP, GUIDE, PHASE*_HANDOFF) | Idéntico a G4. Migrar todo a `mkdocs-material` con navegación clara y mover los `PHASE*_HANDOFF.md` a `docs/changelog/`. |
| **A3** | A — Motor | Modo futuros perpetuos (funding rate, leverage) | Modelar `Position.leverage`, `funding_rate_per_bar`, liquidación simplificada (margen mantenimiento). Sin esto, sigue cubierto solo ~20% del mercado cripto real. |
| **A4** | A — Motor | Slippage parametrizable por símbolo/timeframe; impacto por qty | Sustituir `BacktestConfig.slippage_pct: Decimal` por `SlippageModel` (estrategia con `fixed_pct`, `volume_impact`, `book_depth`) seleccionable por símbolo. |
| **A5** | A — Motor | Unificar Decimal/float | Propuesta original del WORKPLAN: `float64` en hot path + `Decimal` en reportes. Requiere reescribir `_process_*_at` y benchmark de regresión. |
| **A7** | A — Motor | Multi-símbolo / portfolio (asignación capital + rebalanceo) | Extender `BacktestEngine.run` para aceptar `dict[symbol, list[Candle]]` y una `Allocation` (pesos / rebalance schedule). |
| **B1** | B — Datos | Adapter pattern: `BinanceSpot`, `BinanceFutures`, `Bybit`, `ccxt` | Crear `backtester/data/adapters/` con interfaz `ExchangeAdapter`; implementar primero `BinanceSpotAdapter` envolviendo el actual `BinanceDownloader`. |
| **B2** | B — Datos | Normalizador a esquema OHLCV + funding/borrow rates | Definir `NormalizedCandle` + `FundingPoint`. Cada adapter emite a este esquema. |
| **B4** | B — Datos | Pre-pack datasets populares descargables on-demand | Subir bundles (BTC/ETH 1h 2020-2025) a un mirror estático y añadir `cvz-backtester datasets pull btc-1h`. |
| **C4 (track C)** | C — Bots | Plugin system (`entry_points`) para bots externos | Añadir `[project.entry-points."cvz.bots"]` en `pyproject.toml` y descubrirlos en `backtester/bots/__init__.py` vía `importlib.metadata.entry_points`. |
| **C5 (track C)** | C — Bots | Bot ML (sklearn/lightgbm): features → señal/probabilidad | Crear `MLBot(model_path, feature_fn)` con interfaz de inferencia incremental por vela. |
| **D1** | D — Análisis | Walk-Forward CPCV (Combinatorial Purged Cross-Validation) | `backtester/analysis/cpcv.py` con purging + embargo (López de Prado, AFML cap. 7). Se apoya en el `run_walk_forward` existente. |
| **D3** | D — Análisis | Mesetas estables en espacio de parámetros | Heatmap suavizado en `optimize/`, detectar regiones donde una vecindad ±1 step mantiene rendimiento. |
| **D5** | D — Análisis | Análisis bayesiano (posterior de Sharpe con CIs) | Posterior conjugado / MCMC ligero (sin sampler externo) sobre retornos por trade. |
| **D6** | D — Análisis | Benchmark vs HODL / buy-and-hold; alpha/beta/IR | Calcular curva HODL del mismo símbolo y reportar `alpha`, `beta`, `information_ratio` en `compute_metrics`. |
| **D7** | D — Análisis | Explainability: PnL por régimen / hora / día | Bucketizar `Trade.entry_time` y agrupar PnL por bucket; añadir vista UI en `analysis_screen`. |
| **D8** | D — Análisis | Filtrar warm-up de la equity curve antes de Sharpe | Identificar el índice del primer trade en `result.trades[0].entry_idx` y recortar `equity_curve[:first_entry_idx]` para los cálculos de Sharpe/Sortino. |
| **E1** | E — Producto | Paper-trading en tiempo real (WebSocket Binance) | Cliente WS que alimente el `BacktestEngine` candle-a-candle con `paper=True` (no fills reales). |
| **E2** | E — Producto | Broker adapter (ccxt) `Broker(dry-run/paper/live)` | Interfaz `Broker` con tres implementaciones; reutiliza el `OrderType` del motor. |
| **E3** | E — Producto | Monitoring (Prometheus + alertas Telegram/Discord) | Endpoint `/metrics` con `prometheus_client`, plus un módulo `alerts.py` con `TelegramSink`. |
| **E4** | E — Producto | Journal trades reales vs simulados (slippage observado vs modelo) | Tabla `live_trades` en DuckDB y reporte `slippage_attribution`. |
| **F1** | F — UX | Multi-plataforma: macOS + Linux + Web (PWA) | No existen `flutter_app/{macos,linux,web}`. Ejecutar `flutter create . --platforms=macos,linux,web` y añadir jobs CI por plataforma. |
| **F3** | F — UX | Cliente OpenAPI generado para Flutter/Python/JS | Añadir `openapi-generator-cli` al CI y publicar artefactos `clients/{dart,python,ts}`. |
| **F7** | F — UX | "Strategy Lab": workflow guiado (download → backtest → optimize → WFA → MC → paper → live) | Wizard de N pasos en Flutter encima de los endpoints ya existentes. |
| **G2** | G — DevEx | Instaladores firmados (MSIX Windows, .dmg mac, AppImage Linux) | Bloqueado por F1. Workflow GitHub Actions con `dart-lang/setup-dart` + `flutter build` por plataforma. |
| **G4** | G — DevEx | Docs unificados con `mkdocs-material` | Idéntico a C14. |
| **G5** | G — DevEx | Galería comunitaria de estrategias (`cvz-strategies`) | Repo aparte con DSLs YAML; depende de C4 (plugin system) o de un README curado. |
| **G6** | G — DevEx | Limpiar `legacy_reference/`, consolidar `PHASE*_HANDOFF.md` en `docs/changelog/` | `backtester/legacy_reference/` aún contiene 3 archivos (`accesoAPI.py`, `config.example.py`, `README.md`) y `PHASE2_HANDOFF.md` + `PHASE3_HANDOFF.md` siguen en la raíz. |
| **H1** | H — Seguridad | Auditoría rotación claves Fernet | Documentar y testear el procedimiento `rotate_master_key` en `CredentialManager`. |
| **H2** | H — Seguridad | Modelo de amenazas: API local debe ir con TLS + auth si se expone | `backtester/api/security.py` ya valida tokens con `hmac.compare_digest`; falta documentación + ejemplo `uvicorn --ssl-keyfile`. |
| **H3** | H — Seguridad | Rate limiting en API; sandboxing del runner de bots | Añadir middleware (`slowapi`) y aislar la ejecución de bots (subprocess + `resource.setrlimit`). |
| **H4** | H — Seguridad | Reproducibilidad: `run_id` guarda git SHA + Python version + deps hash + hash velas | Hoy `run_id` solo contiene timestamp + params. Extender `result_store` para anexar `git_sha`, `python_version`, `pip_freeze_hash`, `candles_sha256`. |

---

## Prioridades para el próximo sprint (top 5 por ROI)

Ordenado por impacto / esfuerzo, tomando como punto de partida que los bugs P0 y los hitos P1–P2 del WORKPLAN ya están resueltos:

1. **E1 + E2 — Paper-trading + broker adapter (`ccxt`).** Convierte la herramienta de análisis en producto end-to-end (la pregunta más frecuente del usuario después de un buen backtest). Habilita E3/E4 como derivados. Esfuerzo alto pero ROI máximo: desbloquea casos de uso reales.
2. **A3 — Futures perpetuos (funding + leverage).** Sin esto el motor solo modela ~20% del mercado cripto actual. Necesario para que WFA / Monte Carlo / Stress sean accionables sobre el contrato más operado.
3. **B1 + B2 — Adapter pattern multi-exchange + normalizador OHLCV/funding.** Bloquea B4, E1/E2 y D6 (HODL benchmark cross-exchange). Sin esfuerzo desproporcionado: el `BinanceDownloader` actual ya es el primer adapter — solo hay que extraer la interfaz.
4. **F1 — Multi-plataforma Flutter (macOS + Linux + Web).** `flutter create . --platforms=macos,linux,web` cuesta horas, no días, y multiplica audiencia. Desbloquea G2.
5. **D8 / C8 + A6 (PARTIAL) — Filtrar warm-up de equity curve + ATR/Kelly sizing.** Fixes de correctitud baratos pero con efecto directo sobre Sharpe reportado y sobre la calidad de las decisiones de tamaño. Cierran dos huecos de calidad que afectan transversalmente al output del backtester.

> Lo que **NO** entraría en este sprint (deuda fría): F3 (cliente OpenAPI generado), G5 (galería comunitaria), H1 (auditoría Fernet) — no hay evidencia de bloqueo y el coste de oportunidad es mayor en los 5 anteriores.
