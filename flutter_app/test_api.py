import urllib.request
import json
import duckdb

# Since the API is up, let's use a Python script to query the database using the same connection?
# Wait, the API doesn't expose arbitrary queries.
# Let's write a python script that sends a request to get the number of candles in 2025 for BTCUSDT 1h.
print(urllib.request.urlopen('http://127.0.0.1:8002/api/candles/BTCUSDT/1h?start_ms=1735689600000&end_ms=1767139200000').read().decode())
