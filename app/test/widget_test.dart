import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cvz_backtester/app.dart';
import 'package:cvz_backtester/data/database.dart';
import 'package:cvz_backtester/state/providers.dart';

void main() {
  testWidgets('App boots into HomeScreen with NavigationRail', (tester) async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);

    // Use a large window so the desktop layout doesn't overflow.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const CvzBacktesterApp(),
      ),
    );
    // First frame is enough — NavigationRail labels are part of the static
    // tree. pumpAndSettle would hang on the ChartWidget's WebView init,
    // which doesn't work in the headless test environment.
    await tester.pump();

    expect(find.text('Backtest'), findsOneWidget);
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('Optimize'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
