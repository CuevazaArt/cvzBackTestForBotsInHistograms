import duckdb
from pathlib import Path

db_path = Path('../backtester/data/candles.duckdb')
if db_path.exists():
    conn = duckdb.connect(str(db_path), read_only=True)
    res = conn.execute("SELECT symbol, timeframe, COUNT(*) as cnt, MIN(timestamp_ms) as min_ms, MAX(timestamp_ms) as max_ms FROM candles GROUP BY symbol, timeframe").df()
    for _, row in res.iterrows():
        print(f"{row['symbol']} {row['timeframe']}: {row['cnt']} candles, from {row['min_ms']} to {row['max_ms']}")
else:
    print(f"Path does not exist: {db_path}")
