class Candle {
  final int timestampMs;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.timestampMs,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);

  double get typicalPrice => (high + low + close) / 3;

  Map<String, dynamic> toJson() => {
        'timestamp_ms': timestampMs,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
      };

  factory Candle.fromJson(Map<String, dynamic> json) => Candle(
        timestampMs: json['timestamp_ms'] as int,
        open: (json['open'] as num).toDouble(),
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        close: (json['close'] as num).toDouble(),
        volume: (json['volume'] as num).toDouble(),
      );

  factory Candle.fromBinanceKline(List<dynamic> kline) => Candle(
        timestampMs: kline[0] as int,
        open: double.parse(kline[1] as String),
        high: double.parse(kline[2] as String),
        low: double.parse(kline[3] as String),
        close: double.parse(kline[4] as String),
        volume: double.parse(kline[5] as String),
      );
}
