# Setup Guide

## 1. Instalación rápida

### Windows (PowerShell)

```powershell
# Crear virtual environment
python -m venv venv
.\venv\Scripts\Activate.ps1

# Instalar dependencias
pip install -r backtester/requirements.txt
```

### Linux / macOS (Bash)

```bash
# Crear virtual environment
python3 -m venv venv
source venv/bin/activate

# Instalar dependencias
pip install -r backtester/requirements.txt
```

## 2. Configurar credenciales

```bash
python backtester/main.py --setup-credentials
```

Te pedirá:
- **Binance API Key** (puedes dejarla en blanco para modo demo)
- **Binance API Secret** (para modo demo no es obligatorio)

Las credenciales se guardan **encriptadas** en `backtester/.vault/` (no se comitean).

## 3. Descargar velas

```bash
# Descargar velas de 1h para BTC desde 2024-01-01 a 2024-12-31
python backtester/main.py --download-candles BTCUSDT 1h 2024-01-01 2024-12-31

# Otros ejemplos:
python backtester/main.py --download-candles ETHUSDT 4h 2024-06-01 2024-12-31
python backtester/main.py --download-candles BNBUSDT 1d 2023-01-01 2024-12-31
```

Las velas se guardan en `backtester/data/candles.duckdb` (DuckDB columnar).

## 4. Probar interactivamente

```bash
python backtester/main.py --backtest
```

Sigue los prompts:
1. Símbolo (ej: BTCUSDT)
2. Período (ej: 1h)
3. Elige un bot (EMACross o RSIReversion)
4. Ajusta parámetros
5. Ver resultados

## 5. Correr experimentos en paralelo

Primero, copia el archivo de ejemplo:

```bash
cp backtester/experiments.example.json backtester/experiments.json
```

Edítalo según tus parámetros (ej: símbolos, fechas, configuraciones a probar).

Luego corre:

```bash
# Usa 4 workers (paralelo)
python backtester/main.py --experiments backtester/experiments.json --workers 4

# O usa más workers si tu CPU lo permite
python backtester/main.py --experiments backtester/experiments.json --workers 8
```

Resultados se guardan en `backtester/results/experiments_SYMBOL_TIMEFRAME.json`

## Troubleshooting

### "No module named 'backtester'"

Asegúrate de estar en el virtual environment activado:
```bash
# Windows
.\venv\Scripts\Activate.ps1

# Linux/macOS
source venv/bin/activate
```

### "No candles for BTCUSDT 1h"

Descarga primero:
```bash
python backtester/main.py --download-candles BTCUSDT 1h 2024-01-01 2024-12-31
```

### "Credenciales inválidas"

Reconfigura:
```bash
python backtester/main.py --setup-credentials
```

### Rate limit de Binance

El descargador respeta los límites (1200 req/min). Si recibes errores, intenta:
- Reducir el rango de fechas
- Esperar a mañana
- Usar un API key real (rate limit más alto con credenciales)

## Carpetas

```
backtester/
├── .vault/          ← Credenciales encriptadas (no commitear)
├── data/            ← Base de datos de velas (SQLite)
├── results/         ← Resultados de backtests y experimentos
└── core/            ← Módulos internos
    ├── downloader.py    ← Descargar de Binance
    ├── engine.py        ← Motor de backtest
    ├── credentials.py   ← Manejo de credenciales
    └── ...
```

## Próximos pasos

1. **Crea tu propio bot**: copia `ema_cross.py` y modifica la lógica
2. **Optimiza parámetros**: usa `--experiments` con muchas configuraciones
3. **Analiza resultados**: abre `backtester/results/*.json` en tu herramienta favorita
4. **Integra con tu plataforma**: usa el engine desde tu código Python

¡Listo! Ahora tienes un backtester minimalista y ágil. 🚀
