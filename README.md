# cvzBackTestForBotsInHistograms

Plataforma minimalista para **backtesting ágil de bots de trading** sobre históricos de velas (Binance), inspirada en el Strategy Tester de MetaTrader 4/5 pero sin su pesadez.

## Stack

| Capa | Tecnología |
|------|------------|
| **Host de escritorio** | Flutter Desktop (Windows) — `flutter_app/` |
| **Visualización de gráficos** | TradingView Lightweight Charts (vanilla JS) dentro de WebView |
| **Backend** | Python 3.11+ con FastAPI + WebSocket — `backtester/api/` |
| **Motor de backtest** | Engine propio con fees + slippage realistas — `backtester/core/` |
| **Persistencia** | DuckDB (velas columnar) + JSON (resultados) |

## Estructura

```
.
├── backtester/         # Backend Python: core, bots, API, CLI, web assets
│   ├── core/           # Engine, downloader, credentials, metrics
│   ├── bots/           # BotBase + estrategias (EMACross, RSIReversion)
│   ├── experiments/    # Runner paralelo con ProcessPool
│   ├── api/            # FastAPI server (REST + WebSocket)
│   ├── web/            # HTML + JS + Lightweight Charts (servido como /static)
│   ├── ui/             # CLI Rich (alternativa al shell Flutter)
│   ├── legacy_reference/  # Referencias del proyecto original (no usar)
│   ├── README.md       # ← Documentación detallada del backtester
│   ├── SETUP.md
│   ├── GUIDE.md
│   ├── requirements.txt
│   └── main.py
└── flutter_app/        # Shell nativo Flutter Desktop (Windows)
```

## Quick start

Sigue **[`backtester/SETUP.md`](backtester/SETUP.md)** para los pasos completos.

```powershell
# Backend
cd backtester
python -m venv ..\.venv
..\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Configurar credenciales (copiar .env.example a .env y llenar keys)
copy ..\.env.example ..\.env

uvicorn backtester.api.server:app --host 127.0.0.1 --port 8000

# Flutter shell (otra terminal, cuando esté creado)
cd flutter_app
flutter run -d windows
```

## Características

- 📥 Descargar velas históricas desde Binance REST API
- ⚙️ Bots parametrizables — define `param_spec()` y la UI los expone
- ⚡ Backtests paralelos para barridos de parámetros
- 📊 Visualización en vivo: candles + markers + equity curve + drawdown
- 🔐 Credenciales encriptadas con Fernet (local)
- 🖥️ Interfaz nativa Flutter + gráficos profesionales TradingView

## Phase 3 — Decision-Support Tools (2026-05-15)

Funcionalidades para responder las preguntas que un trader hace **antes** de poner capital en un bot:

### Backend (`backtester/analysis/`)
- **Walk-Forward Analysis** — Optimización rolling con validación out-of-sample. Veredicto automático (`robust`/`weak`/`overfit`/`inconclusive`) basado en eficiencia IS→OOS, consistencia y ratio de ventanas rentables.
- **Monte Carlo Simulation** — Resampling de trades (shuffle/bootstrap) con 1000+ trials para obtener percentiles de retorno y drawdown, probabilidad de ruina y Value-at-Risk (VaR/CVaR 95%).
- **Robustness Score** — Ranking multi-métrica ponderada (Sharpe 35% + Profit Factor 20% + Recovery 20% + Win Rate 15% + Penalización por bajo nº trades 10%) para comparar candidatos de forma estable.
- **Métricas avanzadas en el engine**:
  - MAE/MFE por trade (Maximum Adverse/Favorable Excursion) — útil para colocar stops y take-profits
  - Ulcer Index, Recovery Factor, streaks consecutivos (wins/losses), distribución de duración de trades

### Frontend (`flutter_app/lib/screens/analysis_screen.dart`)
Nuevo tab "Analysis" en el sidebar con 4 sub-pestañas:
- **History** — Browser de runs persistidos con filtros symbol/timeframe y vista detallada incluyendo tabla de trades con MAE/MFE
- **Walk-Forward** — Form de configuración + visualización de ventanas y veredicto coloreado
- **Monte Carlo** — Selección de run, percentiles P5/P25/P50/P75/P95, equity curves muestreadas
- **Robustness** — Leaderboard con medallas (oro/plata/bronce) rankando todos los runs guardados

### API endpoints
- `POST /api/analysis/walk-forward` — Lanza WFA con Optuna por ventana
- `POST /api/analysis/monte-carlo` — Lanza MC (acepta `run_id` o `trade_pnls` raw)
- `POST /api/analysis/robustness` — Rankea lista de candidatos

### Tests
+15 tests específicos en `backtester/tests/test_analysis.py` (87 tests totales pasando)

---

## Phase 2 Deliverables (2026-05-15)

Completadas 7 características en dos pistas paralelas (Backend A / Frontend B):

### Backend (Track A)
- **A1 — IndicatorCache** (PR #2): LRU cache con stats para add_indicators() reduciendo cálculos redundantes en barridos de parámetros
- **A2 — Resumable Downloads** (PR #5): Descargas parciales reanudables con progress callbacks y checkpoints de last_timestamp_ms
- **A3 — Result Persistence** (PR #7): SQLite result store para backtests completados con GET/DELETE/LIST endpoints y run_id tracking

### Frontend (Track B)
- **B1 — OptimizationHeatmap** (PR #3): Widget 2D interactivo para sweep de parámetros con cell tap detection y leaderboard sync
- **B2 — ValidationErrorDialog** (PR #6): Modal estructurado para errores HTTP 422 con field-level Pydantic messages
- **B3 — Presets UI** (PR #8): Dropdown toolbar con lazy loading, save/load de configuraciones, y autorefresh
- **B5 — fakeAsync Migration** (PR #4): Flutter tests con fake async + Timer cancellation, flutter promovido a ci-gate

**Status**: ✅ Todas las PRs mergeadas a main, CI verde en todos los checks

## Repositorio

GitHub: https://github.com/CuevazaArt/cvzBackTestForBotsInHistograms

## Licencia

Ver [`LICENSE`](LICENSE).
