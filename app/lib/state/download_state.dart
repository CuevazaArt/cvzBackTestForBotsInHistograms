import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/candle.dart';
import '../data/downloader.dart';
import 'providers.dart';

sealed class DownloadStatus {
  const DownloadStatus();
}

class DownloadIdle extends DownloadStatus {
  const DownloadIdle();
}

class DownloadRunning extends DownloadStatus {
  final String symbol;
  final String timeframe;
  final int fetched;
  final int? total;
  const DownloadRunning({
    required this.symbol,
    required this.timeframe,
    required this.fetched,
    this.total,
  });
  double get percent => total != null && total! > 0 ? fetched / total! * 100 : 0;
}

class DownloadDone extends DownloadStatus {
  final String symbol;
  final String timeframe;
  final int totalCandles;
  const DownloadDone(this.symbol, this.timeframe, this.totalCandles);
}

class DownloadErrorState extends DownloadStatus {
  final String message;
  const DownloadErrorState(this.message);
}

class DownloadController extends StateNotifier<DownloadStatus> {
  final Ref _ref;
  ValueNotifier<bool>? _cancelToken;
  StreamSubscription? _streamSub;

  DownloadController(this._ref) : super(const DownloadIdle());

  Future<void> start({
    required String symbol,
    required String timeframe,
    required int fromMs,
    required int toMs,
  }) async {
    // Cancel any in-flight download.
    cancel();
    _cancelToken = ValueNotifier(false);

    final db = _ref.read(databaseProvider);
    final downloader = _ref.read(downloaderProvider);
    final dao = db.candles;

    // Resume from last persisted bar.
    final resumeFrom = await dao.lastTimestampMs(symbol, timeframe);

    state = DownloadRunning(symbol: symbol, timeframe: timeframe, fetched: 0);

    try {
      int totalInserted = 0;
      final stream = downloader.download(
        symbol: symbol,
        timeframe: timeframe,
        fromMs: fromMs,
        toMs: toMs,
        resumeFromMs: resumeFrom,
        cancelToken: _cancelToken,
        onProgress: (fetched, total) {
          state = DownloadRunning(
            symbol: symbol,
            timeframe: timeframe,
            fetched: fetched,
            total: total,
          );
        },
      );
      await for (final List<Candle> batch in stream) {
        await dao.insertBatch(symbol, timeframe, batch);
        totalInserted += batch.length;
      }
      state = DownloadDone(symbol, timeframe, totalInserted);
    } on DownloadCancelled {
      state = const DownloadIdle();
    } catch (e) {
      state = DownloadErrorState(e.toString());
    }
  }

  void cancel() {
    _cancelToken?.value = true;
    _streamSub?.cancel();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

final downloadControllerProvider =
    StateNotifierProvider<DownloadController, DownloadStatus>(
        (ref) => DownloadController(ref));
