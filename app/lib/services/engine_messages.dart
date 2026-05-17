import '../core/models/candle.dart';
import '../core/models/trade.dart';
import '../core/models/backtest_result.dart';
import '../core/config.dart';

// ─── Commands (UI → Isolate) ──────────────────────────────────────────────

sealed class EngineCommand {
  const EngineCommand();
}

/// Start a new backtest.
class StartBacktest extends EngineCommand {
  final List<Candle> candles;
  final List<BotSpec> bots;
  final BacktestConfig config;
  final int initialSpeedMs;
  const StartBacktest({
    required this.candles,
    required this.bots,
    required this.config,
    this.initialSpeedMs = 0,
  });
}

/// Lightweight spec for a bot to be instantiated inside the isolate.
class BotSpec {
  final String name;
  final Map<String, dynamic> params;
  const BotSpec({required this.name, this.params = const {}});
}

class PauseRun extends EngineCommand {
  const PauseRun();
}

class ResumeRun extends EngineCommand {
  const ResumeRun();
}

class StepRun extends EngineCommand {
  const StepRun();
}

class CancelRun extends EngineCommand {
  const CancelRun();
}

class SetSpeed extends EngineCommand {
  final int speedMs;
  const SetSpeed(this.speedMs);
}

// ─── Events (Isolate → UI) ────────────────────────────────────────────────

sealed class EngineEvent {
  const EngineEvent();
}

class RunStarted extends EngineEvent {
  final int totalCandles;
  const RunStarted(this.totalCandles);
}

class CandleProcessed extends EngineEvent {
  final int index;
  final Candle candle;
  final double equity;
  const CandleProcessed(this.index, this.candle, this.equity);
}

class TradeExecuted extends EngineEvent {
  final Trade trade;
  const TradeExecuted(this.trade);
}

class RunPaused extends EngineEvent {
  const RunPaused();
}

class RunResumed extends EngineEvent {
  const RunResumed();
}

class RunProgress extends EngineEvent {
  final int processed;
  final int total;
  const RunProgress(this.processed, this.total);
  double get percent => total > 0 ? processed / total * 100 : 0;
}

class RunCompleted extends EngineEvent {
  final BacktestResult result;
  const RunCompleted(this.result);
}

class RunCancelled extends EngineEvent {
  const RunCancelled();
}

class RunFailed extends EngineEvent {
  final String message;
  final String? stackTrace;
  const RunFailed(this.message, [this.stackTrace]);
}
