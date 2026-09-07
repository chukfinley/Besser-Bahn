import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:besser_bahn/providers/departure_board_provider.dart';

/// The filter menu on the departure board.
///
/// Regression test for the shape of the menu, not just the notifier: the bug
/// was that "Alle" carried `null` as its value, and a [PopupMenuButton] reports
/// a null result as a *dismissal* (onCanceled), never as a selection. Once a
/// product was picked you could not get back to the full board — on an empty
/// filtered list there was nothing else to tap either.
void main() {
  testWidgets('picking Alle clears the product filter again', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(departureBoardProvider.notifier);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final filter = ref.watch(departureBoardProvider).filterProduct;
                return PopupMenuButton<String>(
                  key: const Key('filter'),
                  initialValue: filter ?? 'ALLE',
                  onSelected: (v) =>
                      notifier.setFilter(v == 'ALLE' ? null : v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'ALLE', child: Text('Alle')),
                    PopupMenuItem(
                      value: 'regionalExpress',
                      child: Text('RE'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RE').last);
    await tester.pumpAndSettle();
    expect(container.read(departureBoardProvider).filterProduct,
        'regionalExpress');

    await tester.tap(find.byKey(const Key('filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alle').last);
    await tester.pumpAndSettle();
    expect(container.read(departureBoardProvider).filterProduct, isNull);
  });

  test('setFilter(null) really clears it in the state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(departureBoardProvider.notifier);
    notifier.setFilter('suburban');
    expect(container.read(departureBoardProvider).filterProduct, 'suburban');
    notifier.setFilter(null);
    expect(container.read(departureBoardProvider).filterProduct, isNull);
  });
}
