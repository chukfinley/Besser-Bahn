import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/journey_prediction.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/journey_search_provider.dart';
import 'package:besser_bahn/providers/service_providers.dart';
import 'package:besser_bahn/screens/connection_search/connection_search_screen.dart';
import 'package:besser_bahn/services/hafas_service.dart';
import 'package:besser_bahn/services/prediction_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the rider sees once the search is an appointment ("An 09:48"): the
/// buffer bar, and the slack written on every connection.

const _selent = Station(
  id: '8005292',
  name: 'Selent',
  locationId: 'A=1@L=8005292@',
);
const _kiel = Station(
  id: '8000199',
  name: 'Kiel Hbf',
  locationId: 'A=1@L=8000199@',
);

/// Tomorrow, so the connections are never in the past (delay badges and the
/// live progress bar read the clock).
final _deadline = DateTime.now()
    .add(const Duration(days: 1))
    .copyWith(hour: 9, minute: 48, second: 0, millisecond: 0, microsecond: 0);

Journey _arrivingAt(Duration beforeDeadline) {
  final arrival = _deadline.subtract(beforeDeadline);
  return Journey(
    refreshToken: 'b${beforeDeadline.inMinutes}',
    legs: [
      JourneyLeg(
        origin: _selent,
        destination: _kiel,
        departure: arrival.subtract(const Duration(minutes: 40)),
        plannedDeparture: arrival.subtract(const Duration(minutes: 40)),
        arrival: arrival,
        plannedArrival: arrival,
      ),
    ],
  );
}

class _NoPredictions extends PredictionService {
  @override
  Future<JourneyPrediction?> predict(Journey journey) async => null;
}

class _NoStations extends HafasService {
  @override
  Future<List<Station>> searchStations(
    String query, {
    bool stopsOnly = false,
  }) async => [];
}

/// Seeded state only — no search is run, and "Früher" is recorded rather than
/// fetched.
class _Seeded extends JourneySearchNotifier {
  _Seeded(this.seed);

  final JourneySearchState seed;
  int loadEarlierCalls = 0;

  @override
  JourneySearchState build() => seed;

  @override
  Future<void> loadEarlier() async => loadEarlierCalls++;
}

Future<_Seeded> _pump(WidgetTester tester, JourneySearchState seed) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final notifier = _Seeded(seed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        journeySearchProvider.overrideWith(() => notifier),
        predictionServiceProvider.overrideWithValue(_NoPredictions()),
        hafasServiceProvider.overrideWithValue(_NoStations()),
      ],
      child: const MaterialApp(home: ConnectionSearchScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

JourneySearchState _seed({
  List<Journey> journeys = const [],
  bool isArrival = true,
  int? minBufferMinutes,
  String? earlierRef,
  bool withResult = true,
}) => JourneySearchState(
  from: _selent,
  to: _kiel,
  dateTime: _deadline,
  isArrival: isArrival,
  minBufferMinutes: minBufferMinutes,
  result: withResult
      ? JourneyResult(journeys: journeys, earlierRef: earlierRef)
      : null,
);

void main() {
  testWidgets(
    'the appointment bar appears with the deadline, not with results',
    (tester) async {
      await _pump(tester, _seed(withResult: false));

      expect(find.text('Da sein um 09:48'), findsOneWidget);
      expect(find.text('Puffer egal'), findsOneWidget);
      expect(find.text('≥ 30 min'), findsOneWidget);
      expect(find.text('≥ 1 h'), findsOneWidget);
    },
  );

  testWidgets('a departure search shows no appointment bar', (tester) async {
    await _pump(tester, _seed(isArrival: false));

    expect(find.text('Puffer egal'), findsNothing);
  });

  testWidgets('every result says what it leaves before the appointment', (
    tester,
  ) async {
    await _pump(
      tester,
      _seed(
        journeys: [
          _arrivingAt(const Duration(minutes: 9)),
          _arrivingAt(const Duration(hours: 1, minutes: 9)),
        ],
      ),
    );

    // DB's own answer — the tight one — is labelled as such, and the earlier
    // train's slack is spelled out rather than left to be worked out from the
    // arrival time.
    expect(find.text('9 min Puffer'), findsOneWidget);
    expect(find.text('1 h 09 Puffer'), findsOneWidget);
  });

  testWidgets('tapping a minimum applies it to the list', (tester) async {
    final notifier = await _pump(
      tester,
      _seed(
        journeys: [
          _arrivingAt(const Duration(minutes: 9)),
          _arrivingAt(const Duration(hours: 1, minutes: 9)),
        ],
      ),
    );

    // The bar scrolls horizontally on a phone — reach the chip the way a thumb
    // would, instead of tapping where it isn't.
    await tester.ensureVisible(find.text('≥ 30 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('≥ 30 min'));
    await tester.pumpAndSettle();

    expect(notifier.state.minBufferMinutes, 30);
    // The tight connection is gone from the list, the roomy one stayed.
    expect(find.text('9 min Puffer'), findsNothing);
    expect(find.text('1 h 09 Puffer'), findsOneWidget);
  });

  testWidgets(
    'an emptied list says the filter did it — and offers the way on',
    (tester) async {
      final notifier = await _pump(
        tester,
        _seed(
          journeys: [_arrivingAt(const Duration(minutes: 9))],
          minBufferMinutes: 60,
          earlierRef: 'ctx0',
        ),
      );

      expect(
        find.textContaining('Keine Verbindung mit mindestens 60 min Puffer'),
        findsOneWidget,
      );
      // "1 knappere gibt es" — the connection exists, it is just filtered.
      expect(find.textContaining('1 knappere'), findsOneWidget);

      await tester.tap(find.text('Früher suchen'));
      await tester.pumpAndSettle();
      expect(notifier.loadEarlierCalls, 1);
    },
  );

  testWidgets('the sort menu offers "Puffer vor Termin" with a deadline', (
    tester,
  ) async {
    await _pump(
      tester,
      _seed(journeys: [_arrivingAt(const Duration(hours: 1))]),
    );
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();

    expect(find.text('Puffer vor Termin'), findsOneWidget);
  });

  testWidgets('and hides it for a departure search — nothing to rank slack '
      'against', (tester) async {
    await _pump(
      tester,
      _seed(
        journeys: [_arrivingAt(const Duration(hours: 1))],
        isArrival: false,
      ),
    );
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();

    expect(find.text('Abfahrt'), findsOneWidget); // the menu did open
    expect(find.text('Puffer vor Termin'), findsNothing);
  });
}
