# Developer Guide

## Contrato del Engine (production-grade)

Antes de escribir bots, lee esto. El engine se comporta así por diseño:

| Aspecto | Comportamiento |
|---------|----------------|
| **Tipos numéricos** | `float64` en todo el pipeline. ~15 dígitos significativos, suficiente para crypto. Si necesitas `Decimal` para live trading, conviértelo en el conector del broker, no aquí. |
| **Modelo de fill** | Default `next_open`: una orden emitida en la vela `i` se ejecuta al **open** de la vela `i+1` (sin lookahead). Modo `close` disponible pero produce resultados optimistas. |
| **Última vela + next_open** | Si el bot emite una orden en la última vela del histórico, **se descarta** (no hay vela siguiente). |
| **Slippage** | Adverso, en %. BUY paga `price × (1 + slip)`, SELL recibe `price × (1 − slip)`. Default 0.05%. |
| **Fees** | Taker fee % en ambos lados. La fee de un `Trade` cerrado es **proporcional** al qty cerrado cuando hay múltiples posiciones (FIFO). `Trade.pnl` viene **neto** de fees. |
| **Cierre FIFO** | Una orden SELL cierra primero las posiciones más viejas. Soporta cierres parciales. |
| **Cash insuficiente** | Por default rechaza la orden (`rejected_orders += 1`). Con `allow_partial_buys=True`, escala el qty para que entre exactamente. |
| **Equity curve** | Una muestra por vela, marcada a precio de cierre. Misma longitud que `candles`. |
| **Max drawdown** | Running peak-to-trough en %. Se trackea durante la corrida, **no** post-hoc. |
| **Profit factor** | `sum(winning_pnls) / abs(sum(losing_pnls))`. `inf` si no hay losers; `0.0` si no hay winners. |
| **Estado del bot** | El bot **no debe** trackear su propia posición. Pregunta a `portfolio.is_long()`, `portfolio.open_qty()`, `portfolio.avg_entry_price()`. La fuente de verdad es el portfolio. |

### Cosas que el engine **no** hace (por ahora)

- ❌ Shorts (solo long-only spot)
- ❌ Órdenes LIMIT (solo market — fill al open o close, slip aplicado)
- ❌ Cross-asset (un solo símbolo por corrida)
- ❌ Apalancamiento / margen
- ❌ Validación de LOT_SIZE / tickSize por símbolo (Binance filters)

Si alguno te bloquea, hablémoslo antes de extenderlo: la decisión de mantener `next_open` y long-only fue deliberada para evitar bugs sutiles.

### Tests obligatorios

Cualquier cambio al engine debe pasar `pytest backtester/tests/` (36 tests cubriendo fees, FIFO, MDD, slippage, edge cases). Si agregas un comportamiento nuevo, agrega su test.

```bash
pip install -r backtester/requirements-dev.txt
pytest backtester/tests/ -v
```

---

## Arquitectura

```
┌─────────────────────────────────────────────┐
│         CLI (main.py + cli.py)              │
│  Interface minimalista con Rich             │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ Core (downloader, engine, credentials)      │
│ Lógica de backtest, descarga y credenciales │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ Bots (bot_base, ema_cross, rsi_reversion)   │
│ Implementaciones de estrategias de trading  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ ExperimentRunner (parallelización)          │
│ Corre múltiples configs en paralelo         │
└─────────────────────────────────────────────┘
```

## Crear tu propio bot

### Paso 1: Heredar de `BotBase`

```python
from backtester.bots import BotBase
from backtester.core.engine import Candle, Portfolio

class MyAwesomeBot(BotBase):
    """Tu descripción aquí."""
    
    def __init__(self, param1=10, param2=0.05):
        self.param1 = param1
        self.param2 = param2
    
    def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict]:
        """Lógica de trading aquí."""
        orders = []
        
        # Tu código
        # if [condición]:
        #     orders.append({"side": "BUY", "qty": 1.0})
        
        return orders
```

### Paso 2: Definir parámetros editables

```python
@classmethod
def param_spec(cls) -> dict[str, dict]:
    """Define qué parámetros puedes ajustar en la UI."""
    return {
        "param1": {
            "type": "int",
            "default": 10,
            "min": 1,
            "max": 100,
            "step": 1
        },
        "param2": {
            "type": "float",
            "default": 0.05,
            "min": 0.001,
            "max": 0.5,
            "step": 0.001
        }
    }
```

### Paso 3: Implementar `on_candle()`

```python
def on_candle(self, candle: Candle, portfolio: Portfolio) -> list[dict]:
    # candle.{open, high, low, close, volume, timestamp_ms}
    # portfolio API (fuente de verdad — NO trackees posición en el bot):
    #   portfolio.cash               → USDT disponible
    #   portfolio.is_long()          → True si hay posición abierta
    #   portfolio.open_qty()         → qty total abierta
    #   portfolio.avg_entry_price()  → VWAP de las posiciones abiertas
    #   portfolio.total_equity(p)    → valor mark-to-market a precio p
    #   portfolio.closed_trades      → historial de trades cerrados

    orders = []
    if not portfolio.is_long() and candle.close > candle.open:
        orders.append({"side": "BUY", "qty": 1.0, "reason": "MY_SIGNAL"})
    elif portfolio.is_long() and candle.close < candle.open:
        # Cierra todo lo abierto en un solo SELL
        orders.append({"side": "SELL", "qty": portfolio.open_qty(),
                       "reason": "EXIT_SIGNAL"})
    return orders
```

> ⚠️ **No uses flags privados como `self._in_position`** para trackear el estado.
> Si el engine rechaza un BUY (cash insuficiente), tu flag quedará desincronizado
> con la realidad del portfolio y el bot dejará de operar. Siempre deriva del
> `portfolio`.

### Paso 4: Registrar el bot

En `backtester/ui/cli.py`, agrega a `BOT_REGISTRY`:

```python
from backtester.bots import MyAwesomeBot

BOT_REGISTRY = {
    "EMACross": EMACross,
    "RSIReversion": RSIReversion,
    "MyAwesomeBot": MyAwesomeBot,  # ← Agregado aquí
}
```

### Paso 5: Usar

```bash
python backtester/main.py --backtest

# Selecciona MyAwesomeBot y ajusta parámetros
```

## Patrones comunes

### Llevar histórico de precios

```python
class MyBot(BotBase):
    def __init__(self):
        self._prices = []
    
    def on_candle(self, candle, portfolio):
        self._prices.append(float(candle.close))
        
        # Mantener solo últimas N velas para memoria
        if len(self._prices) > 1000:
            self._prices.pop(0)
        
        return []
```

### Usar indicadores técnicos

```python
def _sma(self, prices, period):
    """Simple Moving Average."""
    if len(prices) < period:
        return sum(prices) / len(prices)
    return sum(prices[-period:]) / period

def _ema(self, prices, period):
    """Exponential Moving Average."""
    if len(prices) < period:
        return sum(prices) / len(prices)
    
    k = 2 / (period + 1)
    ema = sum(prices[:period]) / period
    for p in prices[period:]:
        ema = p * k + ema * (1 - k)
    return ema

def _rsi(self, prices, period):
    """Relative Strength Index."""
    if len(prices) < period + 1:
        return 50
    
    deltas = [prices[i] - prices[i-1] for i in range(1, len(prices))]
    ups = [d for d in deltas[-period:] if d > 0]
    downs = [-d for d in deltas[-period:] if d < 0]
    
    avg_up = sum(ups) / period if ups else 0
    avg_down = sum(downs) / period if downs else 0
    
    rs = avg_up / avg_down if avg_down > 0 else 0
    return 100 - (100 / (1 + rs)) if rs > 0 else 50
```

### Posiciones y P&L

```python
def on_candle(self, candle, portfolio):
    # Ver posiciones abiertas
    for pos in portfolio.positions:
        print(f"Entrada: ${pos.entry_price}, Qty: {pos.qty}")
    
    # Ver trades cerrados
    for trade in portfolio.closed_trades:
        print(f"P&L: ${trade.pnl}, ROI: {trade.pnl_pct}%")
    
    # Efectivo disponible
    print(f"Cash: ${portfolio.cash}")
    
    return []
```

### Controlar posiciones

```python
def on_candle(self, candle, portfolio):
    orders = []
    
    # No entrar si ya tengo posición
    if portfolio.positions:
        return orders
    
    # No entrar si el saldo es bajo
    if portfolio.cash < 100:
        return orders
    
    # Buy si condición
    if candle.close > self.threshold:
        # Invertir % del efectivo
        qty = (portfolio.cash * 0.5) / float(candle.close)
        orders.append({"side": "BUY", "qty": qty})
    
    return orders
```

## Testing local

```python
# test_my_bot.py
from backtester.core.engine import BacktestEngine, Candle
from backtester.bots import MyAwesomeBot
from decimal import Decimal

candles = [
    Candle(
        timestamp_ms=1704067200000,
        open=Decimal("42000"),
        high=Decimal("42500"),
        low=Decimal("41500"),
        close=Decimal("42100"),
        volume=Decimal("100"),
    ),
    # ... más velas
]

bot = MyAwesomeBot(param1=10, param2=0.05)
engine = BacktestEngine()
result = engine.run(bot, candles, symbol="BTCUSDT")

print(result.summary())
```

## Debugging

Usa logging:

```python
import logging

_LOG = logging.getLogger("mybot")

class MyBot(BotBase):
    def on_candle(self, candle, portfolio):
        _LOG.info(f"Price: {candle.close}, Cash: {portfolio.cash}")
        
        orders = []
        # ...
        if orders:
            _LOG.debug(f"Orders: {orders}")
        
        return orders
```

Luego corre con debug:

```bash
# En el archivo main.py, añade al inicio:
logging.basicConfig(level=logging.DEBUG)
```

## Optimización de parámetros

Usa `--experiments` para probar múltiples configuraciones:

```json
{
  "symbol": "BTCUSDT",
  "timeframe": "1h",
  "bots": [
    {
      "name": "MyAwesomeBot",
      "configs": [
        {"param1": 5, "param2": 0.01},
        {"param1": 10, "param2": 0.02},
        {"param1": 15, "param2": 0.03},
        {"param1": 20, "param2": 0.05}
      ]
    }
  ]
}
```

```bash
python backtester/main.py --experiments experiments.json --workers 4
```

Luego analiza los resultados:

```python
import json

results = json.load(open("backtester/results/experiments_BTCUSDT_1h.json"))
for r in sorted(results, key=lambda x: x.get("total_return_pct", 0), reverse=True)[:5]:
    print(f"Params: {r['params']}, Return: {r['total_return_pct']}%")
```

## Performance tips

1. **Usa `_prices` eficientemente**: mantén solo lo que necesitas
2. **Evita cálculos pesados cada vela**: cachea resultados
3. **Limita tamaño de posiciones**: el engine limita por defecto
4. **Prueba primero con pocos datos**: 100 velas antes de 10,000

## Limitaciones actuales

- Single-asset (no cross-asset hedging)
- Market orders only (no limit orders)
- No shorting (solo long)
- Fees fijos (no estructura de tiering)

## Roadmap

- [ ] Limit orders
- [ ] Shorting
- [ ] Cross-asset correlation
- [ ] Machine learning integration
- [ ] Web dashboard
- [ ] Real-time paper trading

¡Feliz backtesting! 🚀
