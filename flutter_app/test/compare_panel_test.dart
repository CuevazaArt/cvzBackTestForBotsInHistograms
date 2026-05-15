// Widget test for ComparePanel — verifies that:
//
// * The metrics table renders one column per run plus a label column.
// * The "best" metric in each row is highlighted (bold + colored).
// * The empty state shows when no runs are passed.
// * Two runs with downsampled equity curves render the chart area.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:backtester_shell/widgets/compare_panel.dart';


Map<String, dynamic> _syntheticRun({
  required String label,
  required double finalEquity,
  required double maxDdPct,
}) {
  // 10 equity points spaced 1s apart so the painter has data to draw.
  final equity = List.generate(10, (i) {
    return {
      'time': 1_000_000 + i,
      'value': 10_000 + (finalEquity - 10_000) * (i / 9),
    };
  });
  return {
    'run_id': 'run-$label',
    'symbol': 'TESTUSDT',
    'timeframe': '1h',
    'label': label,
    'created_at': 1.0,
    'summary': {
      'total_return_pct': (finalEquity - 10000) / 100,
      'win_rate_pct': 55.0,
      'profit_factor': 1.4,
      'max_drawdown_pct': maxDdPct,
      'final_equity': finalEquity,
      'trades': 7,
    },
    'equity_curve_downsampled': equity,
  };
}


void main() {
  testWidgets('renders empty state when no runs provided',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ComparePanel(runs: [])),
      ),
    );
    expect(find.text('No runs selected.'), findsOneWidget);
  });

  testWidgets('renders metrics table and equity chart for 2 runs',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final runs = [
      _syntheticRun(label: 'Alpha',  finalEquity: 11_000, maxDdPct: 8.2),
      _syntheticRun(label: 'Bravo',  finalEquity:  9_500, maxDdPct: 4.0),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ComparePanel(runs: runs)),
      ),
    );
    await tester.pump();

    // Header summary line.
    expect(find.text('2 runs compared'), findsOneWidget);
    // Both run labels appear in the column headers.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);

    // Section title for the equity chart.
    expect(find.text('Equity curves'), findsOneWidget);

    // The metrics table renders our default metrics — sanity check on the
    // most prominent one.
    expect(find.text('Final equity'), findsOneWidget);
    expect(find.text('Max DD %'), findsOneWidget);
  });

  testWidgets('highlights the best value per metric row',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final runs = [
      _syntheticRun(label: 'A', finalEquity: 12_000, maxDdPct: 9.0),
      _syntheticRun(label: 'B', finalEquity: 10_500, maxDdPct: 3.0),
    ];
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ComparePanel(runs: runs))),
    );
    await tester.pump();

    // Final equity: A is higher → A's "12000.00" is bold.
    final finalEqA = tester.widget<Text>(find.text('12000.00'));
    expect(finalEqA.style?.fontWeight, FontWeight.bold);

    // Max DD: B is lower (better) → B's "3.00%" is bold.
    final ddB = tester.widget<Text>(find.text('3.00%'));
    expect(ddB.style?.fontWeight, FontWeight.bold);

    // And the losing values are NOT bold.
    final finalEqB = tester.widget<Text>(find.text('10500.00'));
    expect(finalEqB.style?.fontWeight, isNot(FontWeight.bold));
  });
}
