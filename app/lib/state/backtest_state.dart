import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/backtest_result.dart';
import '../core/models/candle.dart';
import '../core/models/trade.dart';
import '../core/config.dart';
import '../services/engine_isolate.dart';
import '../services/engine_messages.dart';

/// Public observable state for a backtest run.
sealed class BacktestStatus {
  const BacktestStatus();
}

class BacktestIdle extends BacktestStatus {
  const BacktestIdle();
}

class BacktestRunning extends BacktestStatus {
  final int processed;
  final int total;
  final bool paused;
  final List<Trade> trades;
  final double? lastEquity;
  const BacktestRunning({
    required this.processed,
    required this.total,
    required this.paused,
    required this.trades,
    this.lastEquity,
  });
  double get percent => total > 0 ? processed / total * 100 : 0;
}

class BacktestDone extends BacktestStatus {
  final BacktestResult result;
  const BacktestDone(this.result);
}

class BacktestErrorState extends BacktestStatus {
  final String message;
  const BacktestErrorState(this.message);
}

/// Controller that owns the isolate and exposes status as a Riverpod state.
class BacktestController extends StateNotifier<BacktestStatus> {
  EngineIsolateClient? _client;
  StreamSubscription? _sub;
  int _total = 0;
  int _processed = 0;
  bool _paused = false;
  final List<Trade> _trades = [];
  double? _lastEquity;

  BacktestController() : super(const BacktestIdle());

  Future<void> _ensureClient() async {
    if (_client != null) return;
    _client = EngineIsolateClient();
    await _client!.spawn();
    _sub = _client!.events.listen(_onEvent);
  }

  void _onEvent(EngineEvent ev) {
    switch (ev) {
      case RunStarted(:final totalCandles):
        _total = totalCandles;
        _processed = 0;
        _paused = false;
        _trades.clear();
        _lastEquity = null;
        _emitRunning();
        break;
      case RunProgress(:final processed):
        _processed = processed;
        _emitRunning();
        break;
      case CandleProcessed(:final equity):
        _lastEquity = equity;
        break;
      case TradeExecuted(:final trade):
        _trades.add(trade);
        _emitRunning();
        break;
      case RunPaused():
        _paused = true;
        _emitRunning();
        break;
      case RunResumed():
        _paused = false;
        _emitRunning();
        break;
      case RunCompleted(:final result):
        state = BacktestDone(result);
        break;
      case RunCancelled():
        state = const BacktestIdle();
        break;
      case RunFailed(:final message):
        state = BacktestErrorState(message);
        break;
    }
  }

  void _emitRunning() {
    state = BacktestRunning(
      processed: _processed,
      total: _total,
      paused: _paused,
      trades: List<Trade>.unmodifiable(_trades),
      lastEquity: _lastEquity,
    );
  }

  Future<void> start({
    required List<Candle> candles,
    required List<BotSpec> bots,
    required BacktestConfig config,
    int initialSpeedMs = 0,
  }) async {
    await _ensureClient();
    _client!.send(StartBacktest(
      candles: candles,
      bots: bots,
      config: config,
      initialSpeedMs: initialSpeedMs,
    ));
  }

  void pause() => _client?.send(const PauseRun());
  void resume() => _client?.send(const ResumeRun());
  void step() => _client?.send(const StepRun());
  void cancel() => _client?.send(const CancelRun());
  void setSpeed(int ms) => _client?.send(SetSpeed(ms));

  @override
  void dispose() {
    _sub?.cancel();
    _client?.dispose();
    super.dispose();
  }
}

final backtestControllerProvider =
    StateNotifierProvider<BacktestController, BacktestStatus>(
        (ref) => BacktestController());
