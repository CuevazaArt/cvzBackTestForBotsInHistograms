import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cvz_backtester/app.dart';

void main() {
  testWidgets('App renders scaffold text', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: CvzBacktesterApp()),
    );
    expect(find.text('CVZ Backtester — Phase 0 scaffold complete'), findsOneWidget);
  });
}
