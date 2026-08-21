import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/journey_prediction.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/library_provider.dart';
import 'package:besser_bahn/providers/service_providers.dart';
import 'package:besser_bahn/providers/stopover_plan_provider.dart';
import 'package:besser_bahn/screens/connection_search/stopover_plan_screen.dart';
import 'package:besser_bahn/services/prediction_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The plan screen: two legs that are deliberately NOT one connection, with the
/// gap between them stated as the thing being chosen.

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
const _praxis = Station(
  id: '625109',
  name: 'Kiel Professor-Peters-Platz',
  locationId: 'A=1@L=625109@',
);

/// Tomorrow at 09:48 — future-dated so nothing renders as "already gone".
final _deadline = DateTime.now()
    .add(const Duration(days: 1))
    .copyWith(hour: 9, minute: 48, second: 0, millisecond: 0, microsecond: 0);

DateTime _at(int h, int m) =>
    _deadline.copyWith(hour: h, minute: m, second: 0, millisecond: 0);

Journey _journey(
  Station from,
  Station to,
  DateTime departure,
  DateTime arrival,
) => Journey(
  refreshToken: '${from.id}-${departure.hour}${departure.minute}',
  legs: [
    JourneyLeg(
      origin: from,
      destination: to,
      departure: departure,
      plannedDeparture: departure,
      arrival: arrival,
      plannedArrival: arrival,
    ),
  ],
);

final _second = _journey(_kiel, _praxis, _at(9, 30), _at(9, 42));
final _early = _journey(_selent, _kiel, _at(7, 20), _at(7, 55)); // 1 h 35
final _late = _journey(_selent, _kiel, _at(8, 20), _at(8, 55)); // 35 min

class _NoPredictions extends PredictionService {
  @override
  Future<JourneyPrediction?> predict(Journey journey) async => null;
}

/// A plan handed in ready-made — the searches themselves are covered by
/// stopover_plan_provider_test.
class _Seeded extends StopoverPlanNotifier {
  _Seeded(this.seed);

  final StopoverPlanState seed;
  int loads = 0;
  int earlierLoads = 0;

  @override
  StopoverPlanState build() => seed;

  @override
  Future<void> load() async => loads++;

  @override
  Future<void> loadFirstLegs() async => loads++;

  @override
  Future<void> loadEarlierFirstLegs() async => earlierLoads++;
}

Future<_Seeded> _pump(WidgetTester tester, StopoverPlanState seed) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final notifier = _Seeded(seed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stopoverPlanProvider.overrideWith(() => notifier),
        predictionServiceProvider.overrideWithValue(_NoPredictions()),
      ],
      child: const MaterialApp(home: StopoverPlanScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

StopoverPlanState _seed({
  Journey? secondLeg,
  List<Journey> firstOptions = const [],
  Journey? firstLeg,
  int stayMinutes = 30,
  int hiddenFirstCount = 0,
  String? firstEarlierRef,
}) => StopoverPlanState(
  args: StopoverPlanArgs(
    from: _selent,
    hub: _kiel,
    to: _praxis,
    deadline: _deadline,
  ),
  stayMinutes: stayMinutes,
  secondLeg: secondLeg,
  firstOptions: firstOptions,
  firstLeg: firstLeg,
  hiddenFirstCount: hiddenFirstCount,
  firstEarlierRef: firstEarlierRef,
);

void main() {
  testWidgets('without a plan it says how to start one', (tester) async {
    await _pump(tester, const StopoverPlanState());
    expect(find.textContaining('Kein Zwischenstopp gewählt'), findsOneWidget);
  });

  testWidgets('shows both legs, the appointment and the wanted stay', (
    tester,
  ) async {
    await _pump(
      tester,
      _seed(secondLeg: _second, firstOptions: [_early, _late]),
    );

    expect(find.text('Selent'), findsWidgets);
    expect(find.textContaining('Da sein um 09:48'), findsOneWidget);
    // Leg 2 is the one nailed to the appointment, so it is labelled as such.
    expect(find.textContaining('Etappe 2'), findsOneWidget);
    expect(find.textContaining('Etappe 1'), findsOneWidget);
    // Nothing picked yet → the strip states the minimum, not a fake exact stay.
    expect(find.text('Aufenthalt in Kiel Hbf: mind. 30 min'), findsOneWidget);
  });

  testWidgets('every ride to the hub says what stay it buys', (tester) async {
    await _pump(
      tester,
      _seed(secondLeg: _second, firstOptions: [_early, _late]),
    );

    expect(find.text('1 h 35 Aufenthalt'), findsOneWidget);
    expect(find.text('35 min Aufenthalt'), findsOneWidget);
  });

  testWidgets('picking one turns the minimum into the real stay', (
    tester,
  ) async {
    final notifier = await _pump(
      tester,
      _seed(secondLeg: _second, firstOptions: [_early, _late]),
    );

    await tester.tap(find.text('1 h 35 Aufenthalt'));
    await tester.pumpAndSettle();

    expect(identical(notifier.state.firstLeg, _early), isTrue);
    expect(find.text('Aufenthalt in Kiel Hbf: 1 h 35'), findsOneWidget);
    expect(find.textContaining('Weiter um 09:30'), findsOneWidget);
  });

  testWidgets('saving is blocked until a ride to the hub is picked', (
    tester,
  ) async {
    await _pump(tester, _seed(secondLeg: _second, firstOptions: [_early]));

    final blocked = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(blocked.onPressed, isNull);
    expect(find.text('Hinfahrt wählen'), findsOneWidget);
  });

  testWidgets('saving files the two legs as two separate trips — not as one '
      'connection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final notifier = _Seeded(
      _seed(secondLeg: _second, firstOptions: [_early], firstLeg: _early),
    );
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stopoverPlanProvider.overrideWith(() => notifier),
          predictionServiceProvider.overrideWithValue(_NoPredictions()),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const StopoverPlanScreen();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Beide Etappen speichern'));
    await tester.pumpAndSettle();

    expect(ref.read(libraryProvider).journeys.length, 2);
    expect(find.textContaining('2 einzelne Etappen'), findsOneWidget);
  });

  testWidgets('an empty list blames the stay, not the timetable', (
    tester,
  ) async {
    await _pump(
      tester,
      _seed(secondLeg: _second, stayMinutes: 180, hiddenFirstCount: 3),
    );

    expect(
      find.textContaining('Keine Hinfahrt mit 180 min Aufenthalt'),
      findsOneWidget,
    );
    expect(find.textContaining('3 kämen knapper an'), findsOneWidget);
  });

  testWidgets('"Früher" is offered while there is a window left to page', (
    tester,
  ) async {
    final notifier = await _pump(
      tester,
      _seed(
        secondLeg: _second,
        firstOptions: [_early],
        firstEarlierRef: 'ctx0',
      ),
    );

    await tester.tap(find.text('Früher — noch mehr Zeit'));
    await tester.pumpAndSettle();
    expect(notifier.earlierLoads, 1);
  });

  testWidgets('changing the wanted stay goes through the notifier', (
    tester,
  ) async {
    final notifier = await _pump(
      tester,
      _seed(secondLeg: _second, firstOptions: [_early]),
    );

    await tester.ensureVisible(find.text('1 h 30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 h 30'));
    await tester.pumpAndSettle();

    expect(notifier.state.stayMinutes, 90);
    // Only the ride to the hub is re-searched (the notifier's own test asserts
    // the request count); here: it did trigger a load.
    expect(notifier.loads, 1);
  });
}
