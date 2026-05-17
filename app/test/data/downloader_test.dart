import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cvz_backtester/data/downloader.dart';

void main() {
  group('BinanceDownloader', () {
    List<dynamic> makeKline(int tsMs, double price) => [
          tsMs, // open time
          price.toString(), // open
          (price + 10).toString(), // high
          (price - 10).toString(), // low
          price.toString(), // close
          '100.0', // volume
          tsMs + 3599999, // close time
          '10000.0', // quote volume
          100, // number of trades
          '50.0', // taker buy base
          '5000.0', // taker buy quote
          '0', // ignore
        ];

    test('downloads single batch of candles', () async {
      final mockClient = MockClient((request) async {
        final klines = [
          makeKline(1_000_000, 100.0),
          makeKline(4_600_000, 110.0),
        ];
        return http.Response(jsonEncode(klines), 200, headers: {
          'x-mbx-used-weight-1m': '5',
        });
      });

      final downloader = BinanceDownloader(client: mockClient);
      final batches = <List>[];

      await for (final batch in downloader.download(
        symbol: 'BTCUSDT',
        timeframe: '1h',
        fromMs: 1_000_000,
        toMs: 10_000_000,
      )) {
        batches.add(batch);
      }

      expect(batches.length, 1);
      expect(batches.first.length, 2);
      expect(batches.first.first.close, 100.0);
      downloader.dispose();
    });

    test('respects cancel token set before iteration', () async {
      final cancelToken = ValueNotifier(true); // pre-cancelled
      var fetchCalled = false;
      final mockClient = MockClient((request) async {
        fetchCalled = true;
        return http.Response(jsonEncode([makeKline(1_000_000, 100.0)]), 200);
      });

      final downloader = BinanceDownloader(client: mockClient);
      await expectLater(
        () async {
          await for (final _ in downloader.download(
            symbol: 'BTCUSDT',
            timeframe: '1h',
            fromMs: 1_000_000,
            toMs: 100_000_000,
            cancelToken: cancelToken,
          )) {}
        },
        throwsA(isA<DownloadCancelled>()),
      );
      expect(fetchCalled, isFalse); // no HTTP call was made
      downloader.dispose();
    });

    test('throws DownloadError on HTTP 400', () async {
      final mockClient = MockClient((request) async =>
          http.Response('{"code":-1121,"msg":"Invalid symbol"}', 400));

      final downloader = BinanceDownloader(client: mockClient);
      await expectLater(
        () async {
          await for (final _ in downloader.download(
            symbol: 'INVALID',
            timeframe: '1h',
            fromMs: 0,
            toMs: 1_000_000,
          )) {}
        },
        throwsA(isA<DownloadError>()),
      );
      downloader.dispose();
    });

    test('throws DownloadError for unknown timeframe', () async {
      final downloader = BinanceDownloader();
      await expectLater(
        () async {
          await for (final _ in downloader.download(
            symbol: 'BTCUSDT',
            timeframe: 'invalid',
            fromMs: 0,
            toMs: 1,
          )) {}
        },
        throwsA(isA<DownloadError>()),
      );
      downloader.dispose();
    });

    test('resume skips already-downloaded range', () async {
      final requestedStarts = <int>[];
      final mockClient = MockClient((request) async {
        final start = int.parse(request.url.queryParameters['startTime']!);
        requestedStarts.add(start);
        return http.Response(jsonEncode([]), 200);
      });

      final downloader = BinanceDownloader(client: mockClient);
      await for (final _ in downloader.download(
        symbol: 'BTCUSDT',
        timeframe: '1h',
        fromMs: 0,
        toMs: 10_000_000,
        resumeFromMs: 3_600_000, // already have up to here
      )) {}

      // First request should start after resumeFromMs + 1 bar
      expect(requestedStarts.first, greaterThan(3_600_000));
      downloader.dispose();
    });
  });
}
