# Developer Guide

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
    # candle.open, candle.high, candle.low, candle.close, candle.volume
    # candle.timestamp_ms
    
    # portfolio.cash (saldo en USDT)
    # portfolio.positions (lista de posiciones abiertas)
    # portfolio.closed_trades (lista de operaciones cerradas)
    
    orders = []
    
    # Ejemplo: buy si close > open
    if candle.close > candle.open:
        orders.append({
            "side": "BUY",      # "BUY" o "SELL"
            "qty": 1.0,         # cantidad
            "reason": "MY_SIGNAL" # opcional, para logging
        })
    
    return orders
```

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
