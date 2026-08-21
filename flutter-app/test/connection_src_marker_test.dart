import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/screens/connection_search/widgets/journey_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Journey _journey() => Journey(
  legs: [
    JourneyLeg(
      origin: const Station(id: '8011160', name: 'Berlin Hbf'),
      destination: const Station(id: '8000049', name: 'Braunschweig Hbf'),
      plannedDeparture: DateTime(2026, 7, 17, 9),
      departure: DateTime(2026, 7, 17, 9),
      plannedArrival: DateTime(2026, 7, 17, 10, 30),
      arrival: DateTime(2026, 7, 17, 10, 30),
      line: const TransitLine(
        name: 'ICE 599',
        fahrtNr: '599',
        productName: 'ICE',
        product: 'nationalExpress',
      ),
    ),
  ],
);

/// Taps the card and reports what `/connection` saw in `?src=`.
Future<String?> _tapAndReadSrc(
  WidgetTester tester, {
  required bool fromResults,
}) async {
  String? seen;
  var opened = false;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: JourneyCard(journey: _journey(), fromResults: fromResults),
        ),
      ),
      GoRoute(
        path: '/connection',
        builder: (context, state) {
          opened = true;
          seen = state.uri.queryParameters['src'];
          return const Scaffold(body: Text('detail'));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
  await tester.pump();
  await tester.tap(find.byType(InkWell).first, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(opened, isTrue, reason: 'the card must open the connection detail');
  return seen;
}

void main() {
  group('a connection knows whether it came from a result list (#25)', () {
    testWidgets(
      'a card in the search results marks the detail as from search',
      (tester) async {
        // The alternatives are one back-tap away, so the detail hides its
        // "search this route again" action.
        expect(await _tapAndReadSrc(tester, fromResults: true), 'search');
      },
    );

    testWidgets('the same card standing in for a saved trip does not', (
      tester,
    ) async {
      // Opened from Reisen/ticket: there are no results behind it, so the
      // action stays.
      expect(await _tapAndReadSrc(tester, fromResults: false), isNull);
    });
  });
}
