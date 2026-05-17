import 'dart:async';
import 'dart:isolate';

import '../bots/registry.dart';
import '../core/engine.dart';
import '../core/run_controller.dart';
import 'engine_messages.dart';

/// Manages a backtest running inside an isolate.
///
/// Lifecycle:
///   - [spawn] creates the worker isolate
///   - [send] dispatches commands (StartBacktest, Pause, etc.)
///   - [events] streams engine events back to the UI
///   - [dispose] kills the isolate and closes streams
///
/// All cross-isolate traffic is via typed sealed classes — no raw maps.
class EngineIsolateClient {
  Isolate? _isolate;
  SendPort? _toWorker;
  late ReceivePort _fromWorker;
  final _eventController = StreamController<EngineEvent>.broadcast();
  bool _ready = false;
  Completer<void>? _readyCompleter;

  Stream<EngineEvent> get events => _eventController.stream;
  bool get isReady => _ready;

  Future<void> spawn() async {
    _fromWorker = ReceivePort();
    _readyCompleter = Completer<void>();
    _fromWorker.listen(_handleWorkerMessage);
    _isolate = await Isolate.spawn(
      _engineWorkerEntry,
      _fromWorker.sendPort,
      debugName: 'cvz-engine-worker',
    );
    await _readyCompleter!.future;
  }

  void _handleWorkerMessage(dynamic msg) {
    if (msg is SendPort) {
      _toWorker = msg;
      _ready = true;
      _readyCompleter?.complete();
      return;
    }
    if (msg is EngineEvent) {
      _eventController.add(msg);
    }
  }

  void send(EngineCommand cmd) {
    if (!_ready || _toWorker == null) {
      throw StateError('EngineIsolate not ready — call spawn() first');
    }
    _toWorker!.send(cmd);
  }

  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _fromWorker.close();
    await _eventController.close();
    _ready = false;
  }
}

// ─── Worker entry point (runs in the spawned isolate) ─────────────────────

/// Top-level isolate entry. Receives the parent's SendPort, then loops on
/// incoming EngineCommand messages.
void _engineWorkerEntry(SendPort toParent) async {
  final fromParent = ReceivePort();
  toParent.send(fromParent.sendPort);

  RunController? activeController;

  await for (final msg in fromParent) {
    if (msg is StartBacktest) {
      // Cancel any in-flight run before starting a new one.
      activeController?.cancel();

      final controller = RunController();
      controller.setSpeed(msg.initialSpeedMs);
      activeController = controller;

      // Forward state changes from the controller to the parent.
      final stateSub = controller.stateChanges.listen((change) {
        switch (change) {
          case RunStateChange.paused:
            toParent.send(const RunPaused());
            break;
          case RunStateChange.resumed:
            toParent.send(const RunResumed());
            break;
          case RunStateChange.cancelled:
            toParent.send(const RunCancelled());
            break;
          case RunStateChange.speedChanged:
            // Not surfaced as an event; UI tracks speed locally.
            break;
        }
      });

      // Run the backtest.
      _runBacktest(msg, controller, toParent).whenComplete(() async {
        await stateSub.cancel();
        await controller.dispose();
        if (identical(activeController, controller)) activeController = null;
      });
    } else if (msg is PauseRun) {
      activeController?.pause();
    } else if (msg is ResumeRun) {
      activeController?.resume();
    } else if (msg is StepRun) {
      activeController?.step();
    } else if (msg is CancelRun) {
      activeController?.cancel();
    } else if (msg is SetSpeed) {
      activeController?.setSpeed(msg.speedMs);
    }
  }
}

Future<void> _runBacktest(
  StartBacktest cmd,
  RunController controller,
  SendPort toParent,
) async {
  try {
    final bots = cmd.bots
        .map((spec) => BotRegistry.create(spec.name, spec.params))
        .toList();
    toParent.send(RunStarted(cmd.candles.length));

    final engine = BacktestEngine(config: cmd.config);
    final result = await engine.runAsync(
      bots: bots,
      candles: cmd.candles,
      controller: controller,
      perCandle: (i, candle, pf) async {
        // Throttle progress events to every 1% to avoid flooding the port.
        if (i == 0 ||
            i == cmd.candles.length - 1 ||
            i % (cmd.candles.length ~/ 100 + 1) == 0) {
          toParent.send(RunProgress(i + 1, cmd.candles.length));
        }
        toParent.send(CandleProcessed(i, candle, pf.equity(candle.close)));
      },
      onTrade: (trade) {
        toParent.send(TradeExecuted(trade));
      },
    );

    if (result != null) {
      toParent.send(RunCompleted(result));
    } else {
      toParent.send(const RunCancelled());
    }
  } catch (e, st) {
    toParent.send(RunFailed(e.toString(), st.toString()));
  }
}
