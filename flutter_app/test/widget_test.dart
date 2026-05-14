import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backtester_shell/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const BacktesterApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
