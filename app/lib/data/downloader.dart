import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models/candle.dart';

/// Callback fired on each successful batch: (fetched, total estimate)
typedef ProgressCallback = void Function(int fetched, int? total);

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

class DownloadError implements Exception {
  final String message;
  final int? statusCode;
  const DownloadError(this.message, {this.statusCode});
  @override
  String toString() => 'DownloadError: $message (HTTP $statusCode)';
}

/// Timeframe string → milliseconds per bar
const Map<String, int> _timeframeMs = {
  '1m': 60000,
  '3m': 180000,
  '5m': 300000,
  '15m': 900000,
  '30m': 1800000,
  '1h': 3600000,
  '2h': 7200000,
  '4h': 14400000,
  '6h': 21600000,
  '8h': 28800000,
  '12h': 43200000,
  '1d': 86400000,
  '3d': 259200000,
  '1w': 604800000,
};

class BinanceDownloader {
  static const _base = 'https://api.binance.com';
  static const _maxRetries = 5;
  static const _batchSize = 1000;
  static const _requestDelayMs = 100;

  final http.Client _client;
  int _usedWeight = 0;

  BinanceDownloader({http.Client? client})
      : _client = client ?? http.Client();

  void dispose() => _client.close();

  /// Downloads klines for [symbol]/[timeframe] from [fromMs] to [toMs].
  /// Resumes from [resumeFromMs] if provided (skips already-downloaded data).
  /// Calls [onProgress] after each batch with (downloaded, estimated total).
  /// Throws [DownloadCancelled] if [cancelToken] is set to true.
  Stream<List<Candle>> download({
    required String symbol,
    required String timeframe,
    required int fromMs,
    required int toMs,
    int? resumeFromMs,
    ProgressCallback? onProgress,
    ValueNotifier<bool>? cancelToken,
  }) async* {
    final barMs = _timeframeMs[timeframe];
    if (barMs == null) throw DownloadError('Unknown timeframe: $timeframe');

    int currentMs = resumeFromMs != null && resumeFromMs > fromMs
        ? resumeFromMs + barMs
        : fromMs;

    final estimatedTotal = (toMs - fromMs) ~/ barMs;
    int fetched = 0;

    while (currentMs < toMs) {
      if (cancelToken?.value == true) throw const DownloadCancelled();

      final batch = await _fetchBatchWithRetry(
        symbol: symbol,
        timeframe: timeframe,
        startMs: currentMs,
        endMs: toMs,
      );

      if (batch.isEmpty) break;

      fetched += batch.length;
      onProgress?.call(fetched, estimatedTotal);
      yield batch;

      final lastTs = batch.last.timestampMs;
      if (lastTs >= toMs || batch.length < _batchSize) break;
      currentMs = lastTs + barMs;

      await Future.delayed(const Duration(milliseconds: _requestDelayMs));
    }
  }

  Future<List<Candle>> _fetchBatchWithRetry({
    required String symbol,
    required String timeframe,
    required int startMs,
    required int endMs,
  }) async {
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await _fetchBatch(
          symbol: symbol,
          timeframe: timeframe,
          startMs: startMs,
          endMs: endMs,
        );
      } on DownloadError catch (e) {
        if (e.statusCode == 400) rethrow; // not retryable
        if (attempt == _maxRetries - 1) rethrow;
        final delayMs = (1 << attempt) * 1000; // 1s, 2s, 4s, 8s, 16s
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    throw DownloadError('Exhausted retries for $symbol $timeframe');
  }

  Future<List<Candle>> _fetchBatch({
    required String symbol,
    required String timeframe,
    required int startMs,
    required int endMs,
  }) async {
    final uri = Uri.parse('$_base/api/v3/klines').replace(queryParameters: {
      'symbol': symbol,
      'interval': timeframe,
      'startTime': startMs.toString(),
      'endTime': endMs.toString(),
      'limit': _batchSize.toString(),
    });

    final response = await _client.get(uri, headers: {'Accept': 'application/json'});

    // Track rate-limit weight
    final weight = response.headers['x-mbx-used-weight-1m'];
    if (weight != null) _usedWeight = int.tryParse(weight) ?? _usedWeight;

    if (response.statusCode == 429 || response.statusCode == 418) {
      final retryAfter = response.headers['retry-after'];
      final delayMs = retryAfter != null
          ? int.parse(retryAfter) * 1000
          : 60000;
      await Future.delayed(Duration(milliseconds: delayMs));
      throw DownloadError('Rate limited', statusCode: response.statusCode);
    }

    if (response.statusCode != 200) {
      throw DownloadError(
        response.body,
        statusCode: response.statusCode,
      );
    }

    final raw = jsonDecode(response.body) as List<dynamic>;
    return raw
        .map((k) => Candle.fromBinanceKline(k as List<dynamic>))
        .toList();
  }

  int get currentUsedWeight => _usedWeight;
}

/// Simple mutable bool wrapper used as a cancel token.
class ValueNotifier<T> {
  T value;
  ValueNotifier(this.value);
}
