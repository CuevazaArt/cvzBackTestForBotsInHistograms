# Mini MetaTrader: Backtester Ágil para Bots de Trading

Una plataforma **mínima, rápida y flexible** para backtesting de bots de trading en Python, similar a MT4/MT5 pero sin la complejidad. Diseñada para iterar rápidamente sobre estrategias y parámetros.

## 🎯 Características

- **Descargador de velas** desde Binance REST API
- **Engine de backtest** realista (fees, slippage, fill probability)
- **Bots parametrizables** que puedes modificar en la interfaz
- **Runner paralelo** para probar cientos de configuraciones rápidamente
- **CLI minimalista** con editor interactivo de parámetros
- **Almacén de resultados** en DuckDB para análisis analítico de alto rendimiento

## 📁 Estructura

```
backtester/
├── data/
│   └── candles.duckdb      # Históricos de velas (DuckDB columnar)
├── results/
│   └── backtests.db        # Resultados de backtests
├── core/
│   ├── __init__.py
│   ├── downloader.py       # Descargador Binance REST
│   ├── engine.py           # Motor de backtest
│   ├── credentials.py      # Manejo de credenciales
│   └── metrics.py          # Cálculo de métricas
├── bots/
│   ├── __init__.py
│   ├── bot_base.py         # Clase base para bots
│   ├── ema_cross.py        # EMA crossover (ejemplo)
│   └── rsi_reversion.py    # RSI reversion (ejemplo)
├── experiments/
│   ├── __init__.py
│   └── runner.py           # Ejecutor paralelo de experimentos
├── ui/
│   ├── __init__.py
│   └── cli.py              # Interface minimalista (Rich)
├── config.example.json     # Template de configuración
└── main.py                 # Punto de entrada
```

## 🚀 Quick Start

### 1. Instalar dependencias

```bash
pip install -r backtester/requirements.txt
```

### 2. Configurar credenciales

```bash
python backtester/main.py --setup-credentials
```

Esto abrirá un prompt para ingresar tu API key y secret de Binance (encriptados).

### 3. Descargar velas

```bash
python backtester/main.py --download-candles BTCUSDT 1h 2024-01-01 2024-12-31
```

### 4. Correr backtest interactivo

```bash
python backtester/main.py --backtest
```

Esto abre un editor interactivo donde puedes:
- Seleccionar símbolo y período
- Elegir bot y ajustar parámetros en tiempo real
- Ver resultados en tabla HTML
- Guardar configuración para reproducir

### 5. Paralelizar experimentos

```bash
python backtester/main.py --experiments config.json --workers 4
```

Donde `config.json` contiene múltiples seteos a probar en paralelo.

## 🐳 Docker

El repo trae un `Dockerfile` multi-stage (builder + runtime slim) y un
`docker-compose.yml` listos para levantar el backend FastAPI sin tener que
instalar Python local.

### Levantar el stack

```bash
# Build + run (la primera vez tarda ~1–2 min; las siguientes usan cache).
docker-compose up --build

# La API queda en http://localhost:8000 — pega el WebSocket /ws/runs/{id}
# desde la app de Flutter apuntando a esa URL.
```

El servicio se llama `backend` y monta `./backtester/data` y
`./backtester/results` como volúmenes, así los datos persisten entre
reinicios. La política `restart: unless-stopped` lo levanta de nuevo si el
contenedor cae solo.

### Tests dentro del contenedor

```bash
# Mismo set de tests que CI corre en host, pero ejecutados sobre la imagen
# empaquetada — útil para detectar drift de dependencias / wheels.
docker exec backend python -m pytest -q
```

> Si el contenedor todavía no está corriendo, `docker compose run --rm
> backend python -m pytest -q` también funciona y se limpia solo al salir.

### Variables de entorno (opcional)

El compose intenta cargar `.env` si existe; el archivo no se commitea (es
`.gitignored`). Plantilla mínima:

```env
BINANCE_API_KEY=...
BINANCE_API_SECRET=...
BACKTESTER_LOG_LEVEL=INFO
```

### pre-commit

Para formateo / lint / mypy automático antes de cada commit:

```bash
# Una sola vez por clone (instala el hook .git/hooks/pre-commit).
pre-commit install

# Forzar el set completo sobre todo el repo (típicamente al sumar un hook).
pre-commit run --all-files
```

Hooks configurados (ver `.pre-commit-config.yaml`):

- `pre-commit-hooks` (check-yaml, check-toml, end-of-file-fixer,
  trailing-whitespace, check-merge-conflict, check-added-large-files).
- `ruff` lint con `--fix` + `ruff format` sobre `backtester/`.
- `mypy` sobre `backtester/` (mismas flags que CI).

`default_language_version.python: python3.12` — si tu venv local usa 3.11,
ajustá esa línea o instalá Python 3.12 con `pyenv` / `uv python install`.

## 📚 Ejemplo: EMA Crossover Bot

```python
from backtester.bots import EMACross

bot = EMACross(
    fast_ema=12,
    slow_ema=26,
    profit_factor=0.02,
    stop_loss_pct=0.05
)

# El engine llama bot.on_candle(candle) en cada vela
# Bot retorna órdenes: [{"side": "BUY", "qty": 1}, ...]
```

## 🔧 Crear tu propio bot

1. Hereda de `BotBase`
2. Implementa `on_candle(candle, portfolio) -> List[Dict]`
3. Retorna órdenes: `{"side": "BUY"/"SELL", "qty": ..., "reason": "..."}`

```python
from backtester.bots import BotBase

class MyBot(BotBase):
    def __init__(self, param1=10, param2=20):
        self.param1 = param1
        self.param2 = param2
    
    def on_candle(self, candle, portfolio):
        orders = []
        # Tu lógica aquí
        if candle.close > self.ma:
            orders.append({"side": "BUY", "qty": 1})
        return orders
```

## 🪄 Strategy DSL (sin Python)

¿Querés probar una estrategia sin escribir Python? El backtester incluye un
DSL declarativo en YAML. Definí indicadores, condiciones de entrada/salida y
parámetros de riesgo en un único bloque y corré el bot con `BOT_REGISTRY["DSL"]`.

```yaml
name: "EMA cross + RSI filter"
indicators:
  - ema(close, 12) as fast
  - ema(close, 26) as slow
  - rsi(close, 14) as rsi14
entry:
  long: "fast > slow AND rsi14 < 70"
exit:
  long: "fast < slow OR rsi14 > 80"
risk:
  stop_loss_pct: 0.05      # 5 % bajo el entry
  take_profit_pct: 0.10    # 10 % sobre el entry
  size_pct: 2.0            # 2 % de cash por entrada
```

Uso desde Python:

```python
from backtester.bots import DSLBot

dsl = open("strategy.yml").read()
bot = DSLBot(dsl_text=dsl)
result = engine.run(bot, candles, bot_names=["My DSL"])
```

Uso desde el backend (validación previa, sin correr backtest):

```bash
curl -X POST http://localhost:8002/api/bots/dsl/validate \
  -H 'Content-Type: application/json' \
  -d '{"dsl_text": "indicators: [\"ema(close, 12) as fast\"]\nentry:\n  long: fast > 0\nexit:\n  long: fast < 0"}'
```

**Indicadores soportados**: `ema`, `sma`, `rsi`, `macd`, `bb`, `vwap`.

**Operadores en condiciones**: `>`, `<`, `>=`, `<=`, `==`, `!=`, `AND`, `OR`,
`NOT`, paréntesis, aritmética básica con literales (`fast * 0.99`).

**Limitaciones intencionales**:

- Stateless por barra (sólo valores actuales). Si necesitás "3 cierres seguidos
  sobre la EMA" o secuencias, escribilo en Python como bot custom.
- Long-only por ahora; short selling y hedging quedan para una iteración futura.

Ver `backtester/tests/test_dsl.py` para más ejemplos de YAMLs aceptados.

## 🎮 Editor interactivo de parámetros

Cuando corres `--backtest`, la CLI te permite:

```
┌─────────────────────────────────────┐
│  BACKTESTER INTERACTIVO             │
├─────────────────────────────────────┤
│ Símbolo: BTCUSDT                    │
│ Período: 1h                         │
│ Rango: 2024-01-01 a 2024-12-31      │
│ Bot: EMACross                       │
│                                     │
│ Parámetros:                         │
│  fast_ema:     [12] ← ↔ →           │
│  slow_ema:     [26] ← ↔ →           │
│  profit_factor: [0.02] ← ↔ →        │
│                                     │
│ [RUN] [SAVE] [EXPORT] [EXIT]        │
└─────────────────────────────────────┘
```

- Navega con **flechas** o ratón
- Modifica valores en tiempo real
- **RUN**: ejecuta backtest
- **SAVE**: guarda configuración
- **EXPORT**: exporta a JSON

## 📊 Resultados

Cada backtest guarda:
- **Equity curve** (evolución de capital)
- **Trades**: entrada, salida, P&L de cada operación
- **Métricas**: Sharpe, max drawdown, win rate, profit factor
- **Parámetros**: configuración exacta usada

Accede en: `backtester/results/` (JSON exports)

## ⚡ Paralelizar experimentos

Archivo `experiments.json`:

```json
{
  "symbol": "BTCUSDT",
  "timeframe": "1h",
  "date_from": "2024-01-01",
  "date_to": "2024-12-31",
  "bots": [
    {
      "name": "EMACross",
      "configs": [
        {"fast_ema": 12, "slow_ema": 26, "profit_factor": 0.02},
        {"fast_ema": 12, "slow_ema": 26, "profit_factor": 0.03},
        {"fast_ema": 10, "slow_ema": 20, "profit_factor": 0.02}
      ]
    }
  ]
}
```

```bash
python backtester/main.py --experiments experiments.json --workers 4
```

Esto corre 3 configuraciones en paralelo (4 workers). Muestra progreso en tiempo real y exporta tabla de resultados.

## 🧬 Optimización de parámetros (opcional)

Para hacer **búsqueda automática** de la mejor combinación de parámetros (en vez de probar mallas manuales), instala las dependencias opcionales:

```bash
pip install -r backtester/requirements-optimize.txt   # Optuna + Nevergrad
```

Define un archivo `optimize.json` (ver [`optimize.example.json`](optimize.example.json)):

```json
{
  "symbol": "BTCUSDT",
  "timeframe": "1h",
  "bot_class": "EMACross",
  "objective": "total_return_pct",
  "fixed_params": {},
  "search_space": {
    "fast_ema":      {"type": "int",   "low": 5,    "high": 30,  "step": 1},
    "slow_ema":      {"type": "int",   "low": 20,   "high": 100, "step": 1},
    "profit_factor": {"type": "float", "low": 0.005,"high": 0.10,"step": 0.001},
    "stop_loss_pct": {"type": "float", "low": 0.01, "high": 0.20,"step": 0.005}
  }
}
```

Y corre la optimización:

```bash
# Optuna (Bayesian, TPE por defecto)
python -m backtester.main --optimize backtester/optimize.example.json \
    --backend optuna --trials 200 --sampler tpe

# Nevergrad (CMA-ES, alternativa evolutiva)
python -m backtester.main --optimize backtester/optimize.example.json \
    --backend nevergrad --trials 300 --sampler CMA
```

**Samplers disponibles:**
| Backend | Samplers |
|---------|----------|
| `optuna` | `tpe` (default), `cma`, `random`, `nsga2` |
| `nevergrad` | `NGOpt` (default), `CMA`, `DE`, `OnePlusOne`, `PSO`, `TBPSA` |

**Métricas objetivo (`objective`):**
- `total_return_pct` (max)
- `win_rate_pct` (max)
- `profit_factor` (max)
- `max_drawdown_pct` (min — el optimizador lo minimiza)
- `trades` (max)

Los resultados (ranking de trials) se guardan en `backtester/results/optimize_*.json`.

## 🔐 Credenciales

Las credenciales se guardan cifradas en `backtester/.vault/` usando **Fernet**. No se comitean.

Para usar en CI/CD: establece variables de entorno:
```bash
export BINANCE_API_KEY="..."
export BINANCE_API_SECRET="..."
```

## 📈 Next Steps

- [x] Optimización automática de parámetros (Optuna + Nevergrad)
- [x] **DuckDB como motor analítico nativo** — storage columnar para velas históricas
- [ ] Agregar más indicadores (Bollinger, MACD, Stochastic)
- [ ] Soporte para órdenes limitadas vs market
- [ ] Dashboard nativo (Flutter Desktop + TradingView Lightweight Charts + Canvas custom)
- [ ] Exportar a PDF/Excel

## 🛠️ Troubleshooting

**"API rate limit exceeded"**
- El downloader respeta límites de Binance. Intenta mañana o reduce rango.

**"Credenciales inválidas"**
- Ejecuta `python backtester/main.py --setup-credentials` de nuevo.

**"Backtest lento"**
- Usa `--workers 8` para paralelizar, reduce rango de fechas, o usa menos parámetros.

---

**Made for traders who want to iterate fast.** No UI pesada, pura eficiencia.
