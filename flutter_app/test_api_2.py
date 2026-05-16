import urllib.request
print(len(urllib.request.urlopen('http://127.0.0.1:8002/api/candles/BTCUSDT/1h?limit=5').read().decode()))
