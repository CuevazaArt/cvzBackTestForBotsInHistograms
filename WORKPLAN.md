# Revisión de críticas y plan de trabajo — v0.5.0

> Generado: 2026-05-15 | Referencia: `v0.5.0` (commit `3b06252`)
> Contexto: auditoría profunda del proyecto + crítica externa + verificación contra código actual.

> Actualización `v0.6.0`:
> - Resueltos en esta jornada: A1 (MARKET en open N+1 configurable), A2 (SHORT),
>   D2/D4 (PSR/DSR + stress battery), C1 (Donchian/Grid), B3/B5 (data quality +
>   weight thread-safe), G1/G3 (docker + pre-commit), F4 (command palette),
>   A8/A9 (property + benchmarks).

---

## 1. Estado de las críticas (qué ya se resolvió vs qué sigue vigente)

### Ya resuelto (Phase 4 + sprint de calidad)

| Crítica original | Estado actual |
|------------------|---------------|
| "Sin SL/TP a nivel motor; cada bot reimplementa en `on_candle`" | `orders.py` + pending-order queue; SL/TP/trailing como brackets nativos |
| "Solo BUY/SELL market; sin órdenes pendientes" | LIMIT, STOP, STOP_LIMIT, TRAILING_STOP, OCO-like brackets |
| "SL no dispara intra-vela; usa `candle.close`" | Pending orders resuelven con **high/low** intra-bar |
| "No veo ruff/mypy en CI" | Ruff check + format **bloqueantes**; mypy **bloqueante**; ambos en `ci-gate` |
| "`duckdb`/`pandas` sin pinear" | `duckdb==1.5.2`, `pandas==2.2.2` |
| "`ResultStore` reads sin lock" | `get()` y `list_recent()` ahora bajo `self._lock` |
| "`max_position_qty` campo muerto" | Enforced en `_process_buy` |
| "`engine.run([])` ZeroDivisionError" | Guard retorna `BacktestResult` vacío |
| "WFA/MC bloquean el thread FastAPI" | Ahora son jobs asíncronos via `JobRegistry` |
| "Token comparison no constant-time" | `hmac.compare_digest` en `security.py` |
| "Optuna no se instala en CI" | `requirements-optimize.txt` en CI `test-backend` |

### Sigue vigente (backlog confirmado)

| # | Crítica | Severidad | Notas |
|---|---------|-----------|-------|
| **C1** | **Solo LONG / spot** — sin shorts, futuros, funding, liquidación, apalancamiento | Alta | ~80% del mercado cripto hoy es futuros |
| **C2** | **Look-ahead bias en MARKET** — el bot decide en vela N y rellena al close de N; debería ser open de N+1 | Alta | Los stops/limit SÍ se resuelven bien intra-bar; el problema es solo la ruta MARKET |
| **C3** | **`profit_factor` en `summary()` inconsistente** — usa `avg_win / |avg_loss|` en vez de `gross_profit / gross_loss` como en `build_per_bot_breakdown` | Media | Bug numérico real |
| **C4** | **`sum()` sobre Decimal vacío** — `sum([], start=0)` devuelve `int(0)`, no `Decimal(0)` | Baja | Latente; no ha roto nada aún |
| **C5** | **`compute_max_drawdown_pct` con `running_peak = 0`** — debería arrancar con `equity_curve[0]` | Baja | Funciona en la práctica pero semánticamente incorrecto |
| **C6** | **Slippage fijo %** — sin modelo de profundidad de libro ni impacto por tamaño | Media | OK como baseline; parametrizable por símbolo sería mejor |
| **C7** | **Decimal vs float híbrido en bots** — indicadores en float, motor en Decimal | Media | Decisión de diseño pendiente |
| **C8** | **Equity curve incluye warm-up** — infla varianza, desinfla Sharpe | Baja | Corregible filtrando barras sin trades |
| **C9** | **Sin multi-exchange** — solo Binance spot REST | Media | Adapter pattern planificado |
| **C10** | **Sin calidad de datos** — gaps, velas faltantes, outliers | Media | Validador pre-backtest |
| **C11** | **Sin paper-trading / live / monitoring** | Alta | Define si es "herramienta de análisis" o "producto de trading" |
| **C12** | **Solo Windows** (Flutter) — macOS/Linux/Web factibles | Baja | Flutter multi-platform con poco esfuerzo |
| **C13** | **Sin Dockerfile / docker-compose** | Baja | Un `docker-compose up` resolvería onboarding |
| **C14** | **Docs dispersos** — README, SETUP, GUIDE, PHASE*_HANDOFF | Baja | Consolidar en mkdocs |
| **C15** | **Sin benchmarks de performance del engine** | Baja | pytest-benchmark para velas/seg |
| **C16** | **`BINANCE_USED_WEIGHT_1M` global mutable** — no thread-safe | Baja | Mover a instancia de Downloader |

---

## 2. Plan de trabajo por pistas (priorizado por ROI)

### Sprint inmediato — Bugs confirmados (< 1 día)

```
[ ] C3: Fix profit_factor en BacktestResult.summary() → usar gross_profit / gross_loss
[ ] C4: Añadir start=Decimal("0") en sum() sobre iterables de Decimal (engine.py)
[ ] C5: Inicializar running_peak con equity_curve[0] en compute_max_drawdown_pct
```

### Pista A — Realismo del motor (máximo ROI)

```
[ ] A1: Regla anti look-ahead para MARKET (señal en vela N → fill en open N+1)
        Config flag: fill_on_next_open = True (default) vs legacy mode
[ ] A2: Soporte SHORT (Position.side, margen, liquidación simplificada)
[ ] A3: Modo futuros perpetuos (funding rate, leverage)
[ ] A4: Slippage parametrizable por símbolo/timeframe; modelo de impacto por qty
[ ] A5: Unificar Decimal/float — propuesta: float64 en hot path + Decimal en reportes
[ ] A6: Sizing avanzado: VolatilityTarget(ATR), KellyFraction, RiskPerTradeWithStop
        (size_by_risk ya existe; faltan ATR/Kelly)
[ ] A7: Multi-símbolo / portfolio con asignación de capital y rebalanceo
[ ] A8: Property-based tests con hypothesis (cash + positions == equity, fees >= 0)
[ ] A9: Benchmark con pytest-benchmark (objetivo: >= 1M velas/seg float hot-path)
```

### Pista B — Datos

```
[ ] B1: Adapter pattern: BinanceSpot, BinanceFutures, Bybit, ccxt genérico
[ ] B2: Normalizador a esquema OHLCV + funding/borrow rates
[ ] B3: Validador de calidad (gaps, duplicados, outliers, fechas faltantes)
[ ] B4: Pre-pack datasets populares descargables on-demand
[ ] B5: Mover BINANCE_USED_WEIGHT_1M a instancia (thread-safe)
```

### Pista C — Bots y estrategias

```
[ ] C1: Plantillas: Donchian breakout, grid configurable, ATR mean reversion,
        momentum multi-TF, pairs/cointegración
[ ] C2: Librería de indicadores reutilizable que los bots consuman vía DI
        (IndicatorCache existe pero los bots no la usan directamente)
[ ] C3: DSL declarativo (YAML/JSON): "BUY when EMA(12) > EMA(26) AND RSI < 70"
        → genera un bot automáticamente
[ ] C4: Plugin system (entry_points) para bots de paquetes externos
[ ] C5: Bot ML (sklearn/lightgbm): recibe features, devuelve señal/probabilidad
```

### Pista D — Análisis estadístico (ya fuerte → nivel 11)

```
[ ] D1: Walk-Forward CPCV (Combinatorial Purged Cross-Validation, López de Prado)
[ ] D2: Deflated Sharpe Ratio / Probabilistic Sharpe para corregir sesgo de selección
[ ] D3: Mesetas estables en espacio de parámetros (no solo picos overfitteados)
[ ] D4: Stress tests (fees ×2, slippage ×3, gaps, remover top 5% trades)
[ ] D5: Análisis bayesiano (posterior de Sharpe con credible intervals)
[ ] D6: Benchmark vs HODL / buy-and-hold; alpha/beta/information ratio
[ ] D7: Explainability: breakdown PnL por régimen / hora / día
[ ] D8: Filtrar barras warm-up de la equity curve antes de calcular Sharpe (C8)
```

### Pista E — Cerrar el ciclo: paper → live → monitoring

```
[ ] E1: Paper-trading en tiempo real (bot contra WebSocket Binance, sin dinero)
[ ] E2: Adapter de ejecución (ccxt) con interface Broker (dry-run / paper / live)
[ ] E3: Monitoring: Prometheus + alertas Telegram/Discord cuando bot se desvía
[ ] E4: Journal unificado trades reales vs simulados (slippage observado vs modelo)
```

### Pista F — UX y plataforma

```
[ ] F1: Multi-plataforma: habilitar macOS + Linux + Web (PWA)
[ ] F2: CLI completo + SDK publicable en PyPI (cvz-backtester)
[ ] F3: Cliente OpenAPI generado para Flutter (y Python/JS terceros)
[ ] F4: Command palette / atajos teclado / tema claro-oscuro
[ ] F5: Reportes exportables HTML/PDF (resumen, equity, WFA, MC, robustness)
[ ] F6: Comparador side-by-side de N runs
[ ] F7: "Strategy Lab": workflow guiado descarga → backtest → optimize → WFA → MC → paper → live
```

### Pista G — DevEx y distribución

```
[ ] G1: Dockerfile + docker-compose (backend en un comando)
[ ] G2: Instaladores firmados (MSIX Windows, .dmg mac, AppImage Linux)
[ ] G3: Pre-commit hooks (ruff + mypy + dart analyze)
[ ] G4: Docs unificados con mkdocs-material + video de bienvenida
[ ] G5: Galería comunitaria de estrategias (repo cvz-strategies)
[ ] G6: Limpiar legacy_reference/, consolidar PHASE*_HANDOFF.md en docs/changelog/
```

### Pista H — Seguridad

```
[ ] H1: Auditoría rotación claves Fernet
[ ] H2: Modelo de amenazas: API local no debe exponerse sin TLS + auth
[ ] H3: Rate limiting en API; sandboxing del runner de bots
[ ] H4: Reproducibilidad: run_id guarda git SHA + Python version + deps hash + hash velas
```

---

## 3. Orden de ejecución sugerido (máximo ROI)

| Prioridad | Items | Razón |
|-----------|-------|-------|
| **P0** (hoy/mañana) | Sprint bugs: C3, C4, C5 | Bugs numéricos confirmados, triviales de arreglar |
| **P1** | A1 (anti look-ahead) + A2 (shorts) | Sin esto, WFA/MC/robustness miden una realidad ficticia |
| **P2** | D2 + D4 (Deflated Sharpe, stress tests) | "¿Confío en este resultado?" — pregunta #1 del trader |
| **P3** | E1 + E2 (paper-trading, broker adapter) | Convierte la herramienta en producto |
| **P4** | C3 (DSL) + F5 (reportes PDF) | Multiplica la base de usuarios |
| **P5** | B1–B3 (multi-exchange + calidad datos) | Ampliar el espectro de datos |
| **P6** | F1 + G1 + G2 (multi-plataforma, Docker, instaladores) | Distribución |
| **P7** | A7 (multi-símbolo/portfolio) | Feature avanzada |
| **P8** | Todo lo demás iterativo | Según feedback de usuarios |

---

## 4. Métricas del proyecto al cierre de v0.5.0

| Métrica | Valor |
|---------|-------|
| Backend tests | **103 passed** |
| Flutter tests | **10 passed** |
| Ruff lint | clean |
| Ruff format | clean |
| Mypy | clean (non-strict) |
| CI matrix | Ubuntu + Windows × Py 3.11/3.12 + Flutter |
| PRs mergeadas | #1–#10 (todas cerradas) |
| PRs abiertas | 0 |
| Tags | v0.1.0 → v0.5.0 |
| Bots disponibles | 5 (EMACross, RSI, MACD, Bollinger, DorothyDCA) |
| Tipos de orden | MARKET, LIMIT, STOP, STOP_LIMIT, TRAILING_STOP, brackets |
| Análisis | WFA, Monte Carlo, Robustness Score, MAE/MFE, Ulcer, Recovery |
