import logging
from backtester.core.downloader import BinanceDownloader

logging.basicConfig(level=logging.DEBUG)

d = BinanceDownloader("test.duckdb")
print("Downloading...")
count = d.download_vision_zip('BTCUSDT', '15m', 2024, 1)
print('COUNT:', count)
