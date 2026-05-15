import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backtester_shell/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // The desktop app targets a wide viewport; the default 800x600 test
    // surface causes legitimate RenderFlex overflow in BacktestScreen toolbars.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const BacktesterApp());
    expect(find.byType(MaterialApp), findsOneWidget);

    // Unmount so HomeScreen.dispose() runs and the WsService cancels its
    // reconnect/heartbeat timers — otherwise the test framework flags
    // pending timers as a failure.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
