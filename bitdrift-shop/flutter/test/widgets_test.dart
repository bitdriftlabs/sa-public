import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitdrift_shop_flutter/ui/widgets.dart';

void main() {
  group('money()', () {
    test('formats numbers and falls back to 0.00', () {
      expect(money(12.5), '\u002412.50');
      expect(money('19'), '\u002419.00');
      expect(money(null), '\u00240.00');
      expect(money('nope'), '\u00240.00');
    });
  });

  group('ErrorView', () {
    testWidgets('shows the message and a Retry button that fires the callback',
        (tester) async {
      var retries = 0;
      await tester.pumpWidget(MaterialApp(
        home: ErrorView(message: 'boom', onRetry: () => retries++),
      ));
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('boom'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('omits the Retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ErrorView(message: 'boom')));
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('LoadScreen', () {
    testWidgets('shows error + retry when fetch fails, then renders on retry',
        (tester) async {
      var calls = 0;
      Future<Map<String, dynamic>> fetch() async {
        calls++;
        if (calls == 1) throw StateError('boom');
        return {'n': 42};
      }

      await tester.pumpWidget(MaterialApp(
        home: LoadScreen(
          title: 'T',
          screenView: 't',
          fetch: fetch,
          builder: (context, data) => Text('got ${data['n']}'),
        ),
      ));
      // loading frame, then the error state after the failed fetch
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('boom'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text('got 42'), findsOneWidget);
    });
  });
}
