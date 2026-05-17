import 'package:flutter_test/flutter_test.dart';
import 'package:cvz_backtester/widgets/chart/chart_controller.dart';
import 'package:cvz_backtester/core/models/candle.dart';
import 'package:cvz_backtester/core/models/trade.dart';
import 'package:cvz_backtester/core/models/position.dart';
import 'package:cvz_backtester/core/models/order.dart';

void main() {
  Candle bar(int t, double price) => Candle(
        timestampMs: t,
        open: price,
        high: price + 1,
        low: price - 1,
        close: price,
        volume: 100,
      );

  group('ChartController — buffering guarantee', () {
    test('commands sent before ready are buffered, not dropped', () async {
      final ctrl = ChartController();
      final executed = <String>[];
      ctrl.executor = (js) async => executed.add(js);

      // Send commands BEFORE markReady() — they must accumulate.
      await ctrl.setCandles([bar(1000, 100), bar(2000, 110)]);
      await ctrl.addMarker(const ChartMarker(
        timeMs: 1000,
        shape: 'arrowUp',
        position: 'belowBar',
        color: '#22c55e',
      ));
      await ctrl.fitContent();

      expect(executed, isEmpty);
      expect(ctrl.bufferedCount, 3);
      expect(ctrl.isReady, isFalse);

      // Now mark ready — buffer flushes in order.
      await ctrl.markReady();
      expect(ctrl.isReady, isTrue);
      expect(ctrl.bufferedCount, 0);
      expect(executed.length, 3);
      expect(executed[0], contains('setCandles'));
      expect(executed[1], contains('addMarker'));
      expect(executed[2], contains('fitContent'));
    });

    test('commands sent after ready are executed immediately', () async {
      final ctrl = ChartController();
      final executed = <String>[];
      ctrl.executor = (js) async => executed.add(js);
      await ctrl.markReady();

      await ctrl.clear();
      expect(executed.length, 1);
      expect(executed.first, contains('clearChart'));
    });

    test('markReady is idempotent', () async {
      final ctrl = ChartController();
      ctrl.executor = (_) async {};
      await ctrl.markReady();
      await ctrl.markReady();
      expect(ctrl.isReady, isTrue);
    });

    test('resetReady allows re-buffering after a reload', () async {
      final ctrl = ChartController();
      final executed = <String>[];
      ctrl.executor = (js) async => executed.add(js);
      await ctrl.markReady();
      await ctrl.clear();
      expect(executed.length, 1);

      ctrl.resetReady();
      await ctrl.fitContent(); // should buffer again
      expect(executed.length, 1); // not executed yet
      expect(ctrl.bufferedCount, 1);

      await ctrl.markReady();
      expect(executed.length, 2);
    });
  });

  group('ChartMarker factories', () {
    Trade makeTrade({
      required PositionSide side,
      required double pnl,
    }) =>
        Trade(
          id: 1,
          botId: 'b1',
          side: side,
          entryPrice: 100,
          exitPrice: 100 + pnl,
          qty: 1,
          entryTimestampMs: 1000,
          exitTimestampMs: 2000,
          pnl: pnl,
          pnlPct: pnl,
          fees: 0,
          mfe: 0,
          mae: 0,
          exitReason: TriggerReason.manual,
        );

    test('entry marker direction matches side', () {
      final long = ChartMarker.entry(makeTrade(side: PositionSide.long, pnl: 5));
      expect(long.shape, 'arrowUp');
      expect(long.position, 'belowBar');

      final short = ChartMarker.entry(makeTrade(side: PositionSide.short, pnl: 5));
      expect(short.shape, 'arrowDown');
      expect(short.position, 'aboveBar');
    });

    test('exit marker color reflects win/loss', () {
      final win = ChartMarker.exit(makeTrade(side: PositionSide.long, pnl: 5));
      expect(win.color, '#22c55e');

      final loss = ChartMarker.exit(makeTrade(side: PositionSide.long, pnl: -5));
      expect(loss.color, '#ef4444');
    });
  });

  group('ChartCommand JS generation', () {
    test('JS is valid JSON-quoted', () async {
      final ctrl = ChartController();
      final executed = <String>[];
      ctrl.executor = (js) async => executed.add(js);
      await ctrl.markReady();
      await ctrl.setIndicator(
        'fast',
        [(t: 1000, v: 10.5), (t: 2000, v: 11.0)],
        color: '#fb923c',
      );
      expect(executed.first, contains('window.setIndicator'));
      expect(executed.first, contains('"fast"'));
      expect(executed.first, contains('"#fb923c"'));
    });
  });
}
