import 'package:besser_bahn/models/departure.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/models/station_map.dart';
import 'package:besser_bahn/providers/departure_board_provider.dart';
import 'package:besser_bahn/providers/nearby_tab_provider.dart';
import 'package:besser_bahn/providers/service_providers.dart';
import 'package:besser_bahn/providers/station_map_provider.dart';
import 'package:besser_bahn/screens/departure_board/departure_board_screen.dart';
import 'package:besser_bahn/screens/nearby/nearby_screen.dart';
import 'package:besser_bahn/services/hafas_service.dart';
import 'package:besser_bahn/services/station_map_service.dart';
import 'package:besser_bahn/theme/app_theme.dart';
import 'package:besser_bahn/widgets/glass_switcher.dart';
import 'package:besser_bahn/widgets/station_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Bahnhof tab: Zug / Abfahrten / Karte under one floating glass switcher.
///
/// This screen used to wear an AppBar whose only word was "Bahnhof" — which the
/// bottom nav bar already says — over an icon-and-text TabBar, and each of its
/// three views then opened with an action strip of its own. 172 px of chrome on
/// a screen that also gives its bottom to a floating nav bar. These tests pin
/// what replaced it, and the two rules it has to keep: the inner TabBarView
/// stays (TabPager.swipeBlocked depends on it) and the views stay alive.

const _kiel = Station(id: '8000199', name: 'Kiel Hbf');

/// The Abfahrten tab's own "Karte" action, told apart from the switcher's Karte
/// segment above it — deliberately the same glyph, since one points at the
/// other, so a bare `byIcon` would find both.
final _boardKarteAction = find.descendant(
  of: find.byType(DepartureBoardScreen),
  matching: find.byIcon(Icons.map_outlined),
);

/// The board, canned: these tests are about chrome, not about departures.
class _EmptyBoards extends HafasService {
  @override
  Future<List<Departure>> getDepartures(
    String stationId, {
    DateTime? when,
    int duration = 60,
    int results = 40,
  }) async =>
      [];

  @override
  Future<List<Departure>> getArrivals(
    String stationId, {
    DateTime? when,
    int duration = 60,
    int results = 40,
  }) async =>
      [];

  @override
  Future<List<Station>> searchStations(String query, {bool stopsOnly = false}) async => const [_kiel];
}

/// bahnhof.de, canned as "this stop has no indoor plan" — the Karte tab then
/// renders its message instead of a real FlutterMap, which is all these tests
/// need and keeps them off the network and off the tile cache.
class _NoStationMap implements StationMapService {
  @override
  Future<StationMap> fetchByStationName(String name, {bool background = false}) =>
      Future.error(StationMapException('kein Plan', transient: false));

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  Station? station,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      hafasServiceProvider.overrideWithValue(_EmptyBoards()),
      stationMapServiceProvider.overrideWithValue(_NoStationMap()),
    ],
  );
  addTearDown(container.dispose);
  if (station != null) {
    container.read(departureBoardProvider.notifier).setStation(station);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const NearbyScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The screens under here run a silent auto-refresh timer for as long as they
  // are mounted; unmount them so the test does not end on a pending timer.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  return container;
}

void main() {
  group('the chrome is one floating pill', () {
    testWidgets('no AppBar and no TabBar are left', (tester) async {
      await _pump(tester);

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(
        find.text('Bahnhof'),
        findsNothing,
        reason: 'the bottom nav bar already says which tab this is',
      );
      expect(find.byType(GlassSwitcher), findsOneWidget);
    });

    testWidgets('the first thing in a view clears the glass', (tester) async {
      // Abfahrten is the tab this screen opens on; its station field is the
      // top of it, and the field is the one thing that may never be under the
      // glass — you cannot type into a blur.
      await _pump(tester);

      final switcher = tester.getRect(find.byType(GlassSwitcher));
      final field = tester.getRect(find.byType(StationSearchField).first);
      expect(
        field.top,
        greaterThanOrEqualTo(switcher.bottom),
        reason: 'the search field may not sit under the floating switcher',
      );
      // …and not by much: the whole point is that the space came back.
      expect(field.top - switcher.bottom, lessThan(16));
    });

    testWidgets('no view opens with an action strip of its own',
        (tester) async {
      // The actions used to be a 44 px row under the TabBar. They ride in the
      // search row now — same row, no extra height.
      final container = await _pump(tester, station: _kiel);
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(StationSearchField).first);
      final refresh = tester.getRect(find.byIcon(Icons.refresh));
      expect(
        refresh.center.dy,
        moreOrLessEquals(field.center.dy, epsilon: 4),
        reason: 'the actions share the search row, they do not stack above it',
      );
      expect(container.read(departureBoardProvider).station, _kiel);
    });

    testWidgets('renders on a narrow screen without an overflow',
        (tester) async {
      await _pump(tester, size: const Size(320, 640), station: _kiel);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Everything is still reachable — nothing was fixed by hiding it.
      expect(find.byType(StationSearchField), findsOneWidget);
      expect(_boardKarteAction, findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('Abfahrten'), findsWidgets);
    });
  });

  group('the switcher switches', () {
    testWidgets('tapping a segment changes the view and the provider',
        (tester) async {
      final container = await _pump(tester);
      expect(container.read(nearbyTabProvider), nearbyTabDepartures);

      await tester.tap(find.byIcon(Icons.train_outlined));
      await tester.pumpAndSettle();

      expect(container.read(nearbyTabProvider), nearbyTabTrain);
      expect(find.text('Zug'), findsOneWidget, reason: 'now the labelled one');
      expect(find.text('Zugnummer eingeben'), findsOneWidget);
    });

    testWidgets('an external jump drives the switcher', (tester) async {
      // Tapping a departure opens its train: something outside this screen sets
      // the provider and the switcher has to follow.
      final container = await _pump(tester);
      container.read(nearbyTabProvider.notifier).select(nearbyTabMap);
      await tester.pumpAndSettle();

      expect(find.text('Karte'), findsOneWidget);
      expect(find.text('Bahnhof wählen'), findsOneWidget);
    });
  });

  group('the Abfahrten tab sends you to the Karte tab', () {
    testWidgets('it does not open a map of its own', (tester) async {
      final container = await _pump(tester, station: _kiel);
      await tester.pumpAndSettle();

      await tester.tap(_boardKarteAction);
      await tester.pumpAndSettle();

      expect(
        container.read(nearbyTabProvider),
        nearbyTabMap,
        reason: 'the Karte action is a jump to the Karte tab, not a second map',
      );
      // And it is really the Karte tab we are on, not a map inside Abfahrten:
      // the tab's own station field is there.
      expect(find.text('Karte'), findsOneWidget);
    });

    testWidgets('the station comes along', (tester) async {
      // The carry-over the Karte tab has had since "feat(nearby): carry the
      // Abfahrten station over" — the jump must not step around it.
      final container = await _pump(tester, station: _kiel);
      await tester.pumpAndSettle();

      await tester.tap(_boardKarteAction);
      await tester.pumpAndSettle();

      expect(container.read(nearbyTabProvider), nearbyTabMap);
      expect(
        container.read(stationMapProvider).station,
        _kiel,
        reason: 'the map opens on the station the rider was just reading',
      );
    });
  });

  testWidgets('the inner TabBarView is still there — swipeBlocked depends on it',
      (tester) async {
    // `TabPager.swipeBlocked = {2}` refuses the shell's sideways drag on this
    // tab because a TabBarView (and the map in it) owns that axis here. The day
    // this screen stops having one, that refusal has to go with it.
    await _pump(tester);
    expect(find.byType(TabBarView), findsOneWidget);
  });

  testWidgets('a view keeps its state while the other is shown',
      (tester) async {
    // The views are a TabBarView's children and the tab shell keeps the whole
    // screen alive; typing into one and coming back must find the text.
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.train_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ICE 148');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.map_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.train_outlined));
    await tester.pumpAndSettle();

    expect(find.text('ICE 148'), findsOneWidget);
  });
}
