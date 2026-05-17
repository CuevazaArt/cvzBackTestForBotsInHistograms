import '../core/engine.dart';
import '../core/config.dart';
import '../core/models/candle.dart';
import '../bots/bot_base.dart';

class WalkForwardWindow {
  final int inSampleStart;
  final int inSampleEnd;
  final int outSampleStart;
  final int outSampleEnd;
  final double inSampleReturn;
  final double outSampleReturn;

  const WalkForwardWindow({
    required this.inSampleStart,
    required this.inSampleEnd,
    required this.outSampleStart,
    required this.outSampleEnd,
    required this.inSampleReturn,
    required this.outSampleReturn,
  });
}

class WalkForwardResult {
  final List<WalkForwardWindow> windows;
  final double avgInSampleReturn;
  final double avgOutSampleReturn;
  final double efficiencyRatio;
  final String verdict;

  const WalkForwardResult({
    required this.windows,
    required this.avgInSampleReturn,
    required this.avgOutSampleReturn,
    required this.efficiencyRatio,
    required this.verdict,
  });
}

class WalkForwardAnalyzer {
  /// Slides a (train, test) window across [candles], evaluating the [botFactory]
  /// on each segment. Reports IS/OOS return ratio and a robustness verdict.
  ///
  /// The simple form here does NOT re-optimize parameters between windows —
  /// that requires a parameter sweep, which lives in the optimization module.
  /// What this DOES surface is whether the same parameter set generalizes.
  static WalkForwardResult analyze({
    required List<Candle> candles,
    required BotBase Function() botFactory,
    required BacktestConfig config,
    int inSampleBars = 1000,
    int outSampleBars = 250,
    int stepBars = 250,
  }) {
    final windows = <WalkForwardWindow>[];
    int start = 0;
    while (start + inSampleBars + outSampleBars <= candles.length) {
      final isStart = start;
      final isEnd = start + inSampleBars;
      final oosStart = isEnd;
      final oosEnd = oosStart + outSampleBars;

      final isResult = BacktestEngine(config: config).run(
        bots: [botFactory()],
        candles: candles.sublist(isStart, isEnd),
      );
      final oosResult = BacktestEngine(config: config).run(
        bots: [botFactory()],
        candles: candles.sublist(oosStart, oosEnd),
      );

      windows.add(WalkForwardWindow(
        inSampleStart: isStart,
        inSampleEnd: isEnd,
        outSampleStart: oosStart,
        outSampleEnd: oosEnd,
        inSampleReturn: isResult.returnPct,
        outSampleReturn: oosResult.returnPct,
      ));
      start += stepBars;
    }

    if (windows.isEmpty) {
      return const WalkForwardResult(
        windows: [],
        avgInSampleReturn: 0,
        avgOutSampleReturn: 0,
        efficiencyRatio: 0,
        verdict: 'insufficient_data',
      );
    }

    final avgIs =
        windows.fold(0.0, (s, w) => s + w.inSampleReturn) / windows.length;
    final avgOos =
        windows.fold(0.0, (s, w) => s + w.outSampleReturn) / windows.length;
    final efficiency = avgIs != 0 ? avgOos / avgIs : 0.0;

    String verdict;
    if (efficiency >= 0.7 && avgOos > 0) {
      verdict = 'robust';
    } else if (efficiency >= 0.3 && avgOos > 0) {
      verdict = 'weak';
    } else {
      verdict = 'overfit';
    }

    return WalkForwardResult(
      windows: windows,
      avgInSampleReturn: avgIs,
      avgOutSampleReturn: avgOos,
      efficiencyRatio: efficiency,
      verdict: verdict,
    );
  }
}
