# cvzBackTestForBotsInHistograms

Plataforma minimalista para **backtesting ágil de bots de trading** sobre históricos de velas (Binance), inspirada en el Strategy Tester de MetaTrader 4/5 pero sin su pesadez.

## Stack

| Capa | Tecnología |
|------|------------|
| **Host de escritorio** | Flutter Desktop (Windows) — `flutter_app/` |
| **Visualización de gráficos** | TradingView Lightweight Charts (vanilla JS) dentro de WebView |
| **Backend** | Python 3.11+ con FastAPI + WebSocket — `backtester/api/` |
| **Motor de backtest** | Engine propio con fees + slippage realistas — `backtester/core/` |
| **Persistencia** | SQLite (velas + resultados) |

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

## Repositorio

GitHub: https://github.com/CuevazaArt/cvzBackTestForBotsInHistograms

## Licencia

Ver [`LICENSE`](LICENSE).
