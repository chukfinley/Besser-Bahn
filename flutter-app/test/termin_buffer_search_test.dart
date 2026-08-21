import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/journey_search_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "Termin"-Modus on the search state: an arrival search is a deadline, and
/// the list is then filtered and ranked by the slack in front of it.
///
/// The paging half is what makes the filter usable at all: an arrival search
/// hands back the connections *closest* to the deadline, so asking for an hour
/// of slack can empty the window while the connections that qualify sit one
/// "Früher" away. Doing that by hand is the work the feature removes.

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

final _deadline = DateTime(2026, 7, 27, 9, 48);

Journey _arrivesAt(int h, int m) {
  final arrival = DateTime(2026, 7, 27, h, m);
  return Journey(
    refreshToken: 'a$h$m',
    legs: [
      JourneyLeg(
        origin: _selent,
        destination: _kiel,
        // Every candidate takes 40 minutes, so departure order == arrival order.
        departure: arrival.subtract(const Duration(minutes: 40)),
        plannedDeparture: arrival.subtract(const Duration(minutes: 40)),
        arrival: arrival,
        plannedArrival: arrival,
      ),
    ],
  );
}

JourneySearchState _state({
  required List<Journey> journeys,
  bool isArrival = true,
  int? minBufferMinutes,
  JourneySortMode sortMode = JourneySortMode.departure,
  String? earlierRef,
}) => JourneySearchState(
  from: _selent,
  to: _kiel,
  dateTime: _deadline,
  isArrival: isArrival,
  minBufferMinutes: minBufferMinutes,
  sortMode: sortMode,
  result: JourneyResult(journeys: journeys, earlierRef: earlierRef),
);

/// A notifier whose "Früher" hands back one window earlier each time, so the
/// real [JourneySearchNotifier.setMinBufferMinutes] loop can be driven without
/// the network.
class _PagingSearch extends JourneySearchNotifier {
  _PagingSearch(this.seed, {this.pages = const []});

  final JourneySearchState seed;

  /// One entry per available "Früher" page, oldest window last.
  final List<List<Journey>> pages;

  int loadEarlierCalls = 0;

  @override
  JourneySearchState build() => seed;

  @override
  Future<void> loadEarlier() async {
    loadEarlierCalls++;
    if (pages.length < loadEarlierCalls) {
      // Exhausted: the real notifier answers an empty window by keeping the
      // list and dropping the token.
      state = state.copyWith(
        result: JourneyResult(journeys: state.result!.journeys),
      );
      return;
    }
    final page = pages[loadEarlierCalls - 1];
    state = state.copyWith(
      result: JourneyResult(
        journeys: [...page, ...state.result!.journeys],
        earlierRef: pages.length > loadEarlierCalls
            ? 'ctx$loadEarlierCalls'
            : null,
      ),
    );
  }
}

({ProviderContainer container, _PagingSearch notifier}) _harness(
  JourneySearchState seed, {
  List<List<Journey>> pages = const [],
}) {
  final notifier = _PagingSearch(seed, pages: pages);
  final container = ProviderContainer(
    overrides: [journeySearchProvider.overrideWith(() => notifier)],
  );
  addTearDown(container.dispose);
  return (container: container, notifier: notifier);
}

void main() {
  group('deadline', () {
    test('an arrival search with a time IS a deadline', () {
      expect(_state(journeys: const []).deadline, _deadline);
    });

    test('a departure search has none — nothing to have slack before', () {
      expect(_state(journeys: const [], isArrival: false).deadline, isNull);
    });

    test('"Jetzt" is never a deadline, even with the An toggle left on', () {
      final state = JourneySearchState(isArrival: true);
      expect(state.deadline, isNull);
      expect(state.useArrival, isFalse);
    });
  });

  group('the buffer filter', () {
    final journeys = [
      _arrivesAt(7, 39), // 2 h 09
      _arrivesAt(8, 39), // 1 h 09
      _arrivesAt(9, 18), // 30 min
      _arrivesAt(9, 39), // 9 min — DB's own answer
    ];

    test('off by default: DB\'s tight answer stays visible', () {
      final state = _state(journeys: journeys);
      expect(state.sortedJourneys.length, 4);
      expect(state.hiddenByBufferCount, 0);
    });

    test('a minimum hides the tight ones and counts them', () {
      final state = _state(journeys: journeys, minBufferMinutes: 60);
      expect(state.sortedJourneys.length, 2);
      expect(state.hiddenByBufferCount, 2);
    });

    test('never applied to a departure search', () {
      final state = _state(
        journeys: journeys,
        isArrival: false,
        minBufferMinutes: 60,
      );
      expect(state.sortedJourneys.length, 4);
      expect(state.hiddenByBufferCount, 0);
    });
  });

  group('sorting by buffer', () {
    test('most slack first', () {
      final state = _state(
        journeys: [_arrivesAt(9, 39), _arrivesAt(7, 39), _arrivesAt(9, 18)],
        sortMode: JourneySortMode.buffer,
      );
      expect(
        [for (final j in state.sortedJourneys) j.arrival!.hour],
        [7, 9, 9],
      );
    });

    test(
      'filter and sort compose — the mode does not re-admit hidden ones',
      () {
        final state = _state(
          journeys: [_arrivesAt(9, 39), _arrivesAt(7, 39), _arrivesAt(9, 18)],
          sortMode: JourneySortMode.buffer,
          minBufferMinutes: 30,
        );
        expect(state.sortedJourneys.length, 2);
        expect(state.sortedJourneys.first.arrival!.hour, 7);
      },
    );

    test('without a deadline it falls back to departure order instead of '
        'ranking slack that does not exist', () {
      final state = _state(
        journeys: [_arrivesAt(9, 39), _arrivesAt(7, 39)],
        isArrival: false,
        sortMode: JourneySortMode.buffer,
      );
      expect([for (final j in state.sortedJourneys) j.arrival!.hour], [7, 9]);
    });
  });

  group('setMinBufferMinutes pages backwards when the window has nothing', () {
    test(
      'one page is enough: the qualifying connection is pulled in',
      () async {
        final h = _harness(
          _state(journeys: [_arrivesAt(9, 39)], earlierRef: 'ctx0'),
          pages: [
            [_arrivesAt(8, 39)],
          ],
        );
        await h.container
            .read(journeySearchProvider.notifier)
            .setMinBufferMinutes(60);

        expect(h.notifier.loadEarlierCalls, 1);
        final state = h.container.read(journeySearchProvider);
        expect(state.sortedJourneys.length, 1);
        expect(state.sortedJourneys.single.arrival!.hour, 8);
        // The tight one is still there, just filtered out — not lost.
        expect(state.result!.journeys.length, 2);
        expect(state.hiddenByBufferCount, 1);
      },
    );

    test('does not page when the current window already qualifies', () async {
      final h = _harness(
        _state(journeys: [_arrivesAt(8, 39)], earlierRef: 'ctx0'),
        pages: [
          [_arrivesAt(7, 39)],
        ],
      );
      await h.container
          .read(journeySearchProvider.notifier)
          .setMinBufferMinutes(60);

      expect(h.notifier.loadEarlierCalls, 0);
    });

    test(
      'gives up after maxBufferPages instead of walking the timetable',
      () async {
        final h = _harness(
          _state(journeys: [_arrivesAt(9, 39)], earlierRef: 'ctx0'),
          // Four pages available, none of which ever qualifies for 8 hours.
          pages: [
            [_arrivesAt(9, 30)],
            [_arrivesAt(9, 20)],
            [_arrivesAt(9, 10)],
            [_arrivesAt(9, 0)],
          ],
        );
        await h.container
            .read(journeySearchProvider.notifier)
            .setMinBufferMinutes(480);

        expect(
          h.notifier.loadEarlierCalls,
          JourneySearchNotifier.maxBufferPages,
        );
        expect(h.container.read(journeySearchProvider).sortedJourneys, isEmpty);
      },
    );

    test(
      'stops at the end of the timetable rather than repeating a request',
      () async {
        final h = _harness(
          _state(journeys: [_arrivesAt(9, 39)], earlierRef: 'ctx0'),
          pages: const [], // token set, but the page comes back empty
        );
        await h.container
            .read(journeySearchProvider.notifier)
            .setMinBufferMinutes(60);

        expect(h.notifier.loadEarlierCalls, 1);
      },
    );

    test('no token, no paging', () async {
      final h = _harness(_state(journeys: [_arrivesAt(9, 39)]));
      await h.container
          .read(journeySearchProvider.notifier)
          .setMinBufferMinutes(60);

      expect(h.notifier.loadEarlierCalls, 0);
    });

    test('back to "egal" clears the filter and pages nothing', () async {
      final h = _harness(
        _state(
          journeys: [_arrivesAt(9, 39)],
          minBufferMinutes: 60,
          earlierRef: 'ctx0',
        ),
        pages: [
          [_arrivesAt(8, 39)],
        ],
      );
      await h.container
          .read(journeySearchProvider.notifier)
          .setMinBufferMinutes(null);

      expect(h.notifier.loadEarlierCalls, 0);
      final state = h.container.read(journeySearchProvider);
      expect(state.minBufferMinutes, isNull);
      expect(state.sortedJourneys.length, 1);
    });
  });

  test('back to "Jetzt" drops the deadline AND the buffer filter — a filter '
      'left set would silently narrow the next search', () {
    final h = _harness(_state(journeys: const [], minBufferMinutes: 60));
    h.container.read(journeySearchProvider.notifier).resetToNow();

    final state = h.container.read(journeySearchProvider);
    expect(state.deadline, isNull);
    expect(state.minBufferMinutes, isNull);
  });
}
