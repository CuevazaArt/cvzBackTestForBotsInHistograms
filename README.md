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

uvicorn backtester.api.server:app --host 127.0.0.1 --port 8002

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

## Phase 4 — Realistic Order Execution (2026-05-15)

Cierra el gap más grande entre backtest y trading real: las órdenes ahora se ejecutan **intra-bar** con tipos que un trader profesional reconocería.

### Tipos de orden soportados
- `MARKET` (default) — fill al close del candle actual con slippage
- `LIMIT` — fill solo si low ≤ limit_price (BUY) o high ≥ limit_price (SELL) dentro del candle
- `STOP` — gatilla MARKET cuando price atraviesa stop_price intra-bar
- `STOP_LIMIT` — gatilla un LIMIT cuando price toca stop_price (más conservador)
- `TRAILING_STOP` — stop que ratchea con cada nuevo high (long) por `trail_pct`%

### Bracket orders (orden compuesta atómica)
Una sola orden BUY puede llevar SL + TP + trailing stop adjuntos:
```python
{"side": "BUY", "qty": 1.0,
 "stop_loss_pct": 2.0,        # auto-creates STOP @ entry*(1 - 2%)
 "take_profit_pct": 4.0,      # auto-creates LIMIT @ entry*(1 + 4%)
 "trailing_stop_pct": 3.0}    # auto-creates TRAILING_STOP at 3%
```
Cuando uno de los hermanos dispara, los otros se **auto-cancelan** (no hay double-fire de SL después de TP).

### Convención "favorable to trader" para trailing stop
El ratchet del anchor ocurre al FINAL del bar, no al principio. Esto significa que un mismo candle que sube y baja no puede simultáneamente ratchear el stop hacia arriba Y dispararlo — el stop usa siempre el nivel del bar anterior. Es la convención estándar de MetaTrader/TradingView.

### Risk-based position sizing (`BacktestBot.size_by_risk`)
Helper estándar para sizing por riesgo: dado equity, precio, stop% y risk%, retorna qty tal que hitting el stop cuesta exactamente `risk_pct` del equity. Ejemplo: $10k equity, 1% risk, 2% stop → 50 unidades a $100 (notional $5k).

### Circuit breaker (`BacktestConfig.max_drawdown_pct_halt`)
Si el drawdown global supera el threshold, el engine rechaza nuevos BUY. Las posiciones abiertas pueden seguir cerrando vía SL/TP/manual. Útil para evitar overtrading en racha perdedora.

### EMACross actualizado
Ahora usa bracket orders con SL + TP attached y opcionalmente trailing stop. Soporta `use_risk_sizing=True` para position sizing profesional. Backward compat: bots viejos que emiten `{"side": "BUY", "qty": ...}` siguen funcionando como MARKET.

### Trade.reason captura el trigger
Los trades cerrados reportan: `STOP_LOSS`, `TAKE_PROFIT`, `TRAILING_STOP`, `LIMIT`, `MARKET` o `MANUAL` — visible como badge coloreado en la tabla de trades del Flutter shell.

### Tests
+11 tests específicos en `backtester/tests/test_orders.py` (95 backend totales pasando).

---

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
