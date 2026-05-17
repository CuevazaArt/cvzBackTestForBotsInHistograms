import '../core/models/candle.dart';

/// Streaming indicator: O(1) per-candle update, no full series recompute.
///
/// During warm-up, [value] returns null. Bots must check this before using.
abstract class Indicator {
  String get name;

  /// Number of bars consumed before [value] is reliable.
  int get warmupBars;

  /// True once [warmupBars] bars have been consumed.
  bool get isReady;

  /// Feed a new candle and return the post-update value (null during warm-up).
  double? update(Candle c);

  /// Latest value or null if warm-up not complete.
  double? get value;

  /// Reset all internal state.
  void reset();
}
