import 'dart:async';

/// Cooperative pause/step/cancel + speed control for the engine loop.
///
/// The engine calls [waitIfPaused] once per candle. Speed is enforced via
/// [maybeSleep]. Cancellation is checked at every checkpoint so the engine
/// stops promptly even while paused.
class RunController {
  bool _paused = false;
  bool _cancelled = false;
  int _speedMs = 0;
  Completer<void>? _resumeCompleter;
  Completer<void>? _stepCompleter;

  /// Stream of state-change notifications for the orchestrator to forward.
  final _stateController = StreamController<RunStateChange>.broadcast();
  Stream<RunStateChange> get stateChanges => _stateController.stream;

  bool get isPaused => _paused;
  bool get isCancelled => _cancelled;
  int get speedMs => _speedMs;

  Future<void> waitIfPaused() async {
    if (_cancelled) return;
    if (!_paused) return;
    _resumeCompleter ??= Completer<void>();
    _stepCompleter = Completer<void>();
    final stepFuture = _stepCompleter!.future;
    final resumeFuture = _resumeCompleter!.future;
    // Wake on either a step (process one candle) or a resume (continue full).
    await Future.any([stepFuture, resumeFuture]);
  }

  Future<void> maybeSleep() async {
    if (_speedMs > 0) {
      await Future.delayed(Duration(milliseconds: _speedMs));
    }
  }

  void pause() {
    if (_cancelled || _paused) return;
    _paused = true;
    _resumeCompleter = Completer<void>();
    _stateController.add(RunStateChange.paused);
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    _stepCompleter = null;
    _stateController.add(RunStateChange.resumed);
  }

  void step() {
    if (!_paused) return;
    if (_stepCompleter == null || _stepCompleter!.isCompleted) {
      _stepCompleter = Completer<void>();
    }
    _stepCompleter!.complete();
    _stepCompleter = Completer<void>(); // arm for the next step
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (_paused) {
      _resumeCompleter?.complete();
      _stepCompleter?.complete();
    }
    _stateController.add(RunStateChange.cancelled);
  }

  void setSpeed(int speedMs) {
    if (speedMs < 0) speedMs = 0;
    _speedMs = speedMs;
    _stateController.add(RunStateChange.speedChanged);
  }

  Future<void> dispose() => _stateController.close();
}

enum RunStateChange { paused, resumed, cancelled, speedChanged }
