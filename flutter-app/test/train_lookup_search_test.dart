import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/service_providers.dart';
import 'package:besser_bahn/screens/train_lookup/train_lookup_screen.dart';
import 'package:besser_bahn/services/hafas_service.dart';
import 'package:besser_bahn/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Zug field looks its train up as you type — no button to press, which is
/// what the Bahnhof field next to it has always done. One app, one way to
/// search.
///
/// What the Bahnhof field can take for granted and this one cannot is the
/// network: `findTrainsByNumber` with no stop given sweeps FIVE major departure
/// boards at once, and /mob rate-limits per client for minutes once it has had
/// enough. So the tests that matter here are the ones counting sweeps, not the
/// one finding the train.

/// Counts every sweep the screen asks for, and answers nothing — the point is
/// how often it is called, not what comes back.
class _CountingHafas extends HafasService {
  int sweeps = 0;
  final List<String> queries = [];

  @override
  Future<List<TrainSearchResult>> findTrainsByNumber(
    String input, {
    String? fromStationId,
  }) async {
    sweeps++;
    queries.add(input);
    return [];
  }

  @override
  Future<List<Station>> searchStations(String query, {bool stopsOnly = false}) async => const [];
}

Future<_CountingHafas> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final hafas = _CountingHafas();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [hafasServiceProvider.overrideWithValue(hafas)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const TrainLookupScreen(embedded: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The screen keeps a silent auto-refresh timer while mounted.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  return hafas;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

/// Long enough for the field's debounce to fire.
Future<void> _settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 700));

void main() {
  testWidgets('there is no search button to press any more', (tester) async {
    await _pump(tester);
    // The Bahnhof field has never had one. This one had a FilledButton with a
    // magnifying glass in it, and it was the only thing on the Bahnhof screen
    // that made you press before it would answer.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets('typing a train number looks it up on its own', (tester) async {
    final hafas = await _pump(tester);

    await _type(tester, 'ICE 148');
    expect(hafas.sweeps, 0, reason: 'not while the rider is still typing');

    await _settle(tester);
    expect(hafas.sweeps, 1);
    expect(hafas.queries.single, 'ICE 148');
  });

  testWidgets('a query typed out letter by letter is still one sweep',
      (tester) async {
    // The debounce is the whole rate-limit argument: five boards per keystroke
    // would have the backend refusing us for minutes.
    final hafas = await _pump(tester);

    for (final text in ['I', 'IC', 'ICE', 'ICE 1', 'ICE 14', 'ICE 148']) {
      await _type(tester, text);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(hafas.sweeps, 0);

    await _settle(tester);
    expect(hafas.sweeps, 1, reason: 'one settled query, one sweep');
    expect(hafas.queries.single, 'ICE 148');
  });

  testWidgets('a query with no number in it never reaches the network',
      (tester) async {
    // findTrainsByNumber throws away every non-digit and gives up on an empty
    // number: "ICE" is five requests for a guaranteed empty answer.
    final hafas = await _pump(tester);

    await _type(tester, 'ICE');
    await _settle(tester);
    expect(hafas.sweeps, 0);

    await _type(tester, 'S');
    await _settle(tester);
    expect(hafas.sweeps, 0);

    // …and the moment it could be a train, it goes.
    await _type(tester, 'S3');
    await _settle(tester);
    expect(hafas.sweeps, 1);
  });

  testWidgets('Enter beats the debounce', (tester) async {
    final hafas = await _pump(tester);

    await _type(tester, 'RE 70');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(hafas.sweeps, 1, reason: 'submitting means "I am done typing"');

    // And the debounce it cancelled must not fire a second sweep behind it.
    await _settle(tester);
    expect(hafas.sweeps, 1);
  });

  testWidgets('the same query is not swept twice', (tester) async {
    final hafas = await _pump(tester);

    await _type(tester, 'RE 70');
    await _settle(tester);
    expect(hafas.sweeps, 1);

    // A rebuild that re-runs onChanged with unchanged text (the location
    // toggle, a station pick) must not pay for the same answer again. `.first`
    // is the field's own suffix — the "not found" view offers the same toggle.
    await tester.tap(find.byIcon(Icons.location_on_outlined).first);
    await _settle(tester);
    expect(hafas.sweeps, 1);
  });

  testWidgets('emptying the field clears the result', (tester) async {
    final hafas = await _pump(tester);

    await _type(tester, 'ICE 148');
    await _settle(tester);
    expect(hafas.sweeps, 1);

    await _type(tester, '');
    await _settle(tester);
    expect(hafas.sweeps, 1, reason: 'clearing is not a search');
    expect(
      find.text('Zugnummer eingeben'),
      findsOneWidget,
      reason: 'backspacing out of a train leaves the welcome screen, not a '
          'stale one',
    );
  });
}
