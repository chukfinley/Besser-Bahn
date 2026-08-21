import 'dart:convert';

import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/service_providers.dart';
import 'package:besser_bahn/providers/stopover_plan_provider.dart';
import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two-search wiring behind "Aufenthalt einplanen": one arrival search for
/// the leg that has to make the appointment, a second one for getting to the hub
/// early enough to still catch it with time to spare.
///
/// The requests are asserted, not just the outcome: both halves MUST be arrival
/// searches (`zeitPunktArt: ANKUNFT`), and the second one's time is derived from
/// the first one's result — get that wrong and the plan silently becomes a normal
/// chained connection again. The /mob backend also rate-limits per client
/// (project_vendo_rate_limit), so the number of requests is a correctness
/// property: changing the stay must re-search one half, not both.

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

final _deadline = DateTime(2026, 7, 27, 9, 48);

DateTime _at(int h, int m) => DateTime(2026, 7, 27, h, m);

String _iso(DateTime t) => t.toIso8601String();

/// One vendo connection: a single direct run from [from] to [to].
Map<String, dynamic> _conn(
  Station from,
  Station to,
  DateTime departure,
  DateTime arrival,
) => {
  'verbindung': {
    'verbindungsAbschnitte': [
      {
        'typ': 'FAHRZEUG',
        'zuglaufId': '${from.id}-${departure.hour}${departure.minute}',
        'abgangsOrt': {'evaNr': from.id, 'name': from.name},
        'ankunftsOrt': {'evaNr': to.id, 'name': to.name},
        'abgangsDatum': _iso(departure),
        'ankunftsDatum': _iso(arrival),
        'mitteltext': 'RE 72',
        'kurztext': 'RE',
        'zugNummer': '72',
        'produktGattung': 'REGIONALZUG',
        'halte': [
          {
            'ort': {'evaNr': from.id, 'name': from.name},
            'abgangsDatum': _iso(departure),
          },
          {
            'ort': {'evaNr': to.id, 'name': to.name},
            'ankunftsDatum': _iso(arrival),
          },
        ],
      },
    ],
  },
};

String _body(List<Map<String, dynamic>> conns, {String? earlier}) =>
    json.encode({'verbindungen': conns, 'frueherContext': ?earlier});

/// What one captured search asked for.
typedef Ask = ({String from, String to, String when, String kind, String? ctx});

class _Backend {
  _Backend(this.answer);

  /// Called with each captured request; returns the response body.
  final String Function(Ask ask) answer;

  final asks = <Ask>[];

  VendoService get service => VendoService(
    client: MockClient((req) async {
      final body =
          json.decode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
      final wunsch =
          (body['reiseHin'] as Map<String, dynamic>)['wunsch']
              as Map<String, dynamic>;
      final zeit = wunsch['zeitWunsch'] as Map<String, dynamic>;
      final ask = (
        from: wunsch['abgangsLocationId'] as String,
        to: wunsch['zielLocationId'] as String,
        when: zeit['reiseDatum'] as String,
        kind: zeit['zeitPunktArt'] as String,
        ctx: wunsch['context'] as String?,
      );
      asks.add(ask);
      return http.Response.bytes(utf8.encode(answer(ask)), 200);
    }),
  );
}

/// Selent → Kiel Hbf, three candidates for the ride to the hub.
final _toHub = [
  _conn(_selent, _kiel, _at(7, 20), _at(7, 55)), // 1 h 35 at the hub
  _conn(_selent, _kiel, _at(8, 20), _at(8, 55)), // 35 min
  _conn(_selent, _kiel, _at(9, 5), _at(9, 25)), // 5 min — too tight
];

/// Kiel Hbf → the practice. 09:30 is the latest that still makes 09:48.
final _toGoal = [
  _conn(_kiel, _praxis, _at(9, 0), _at(9, 12)),
  _conn(_kiel, _praxis, _at(9, 30), _at(9, 42)),
  _conn(_kiel, _praxis, _at(9, 45), _at(9, 57)), // too late
];

ProviderContainer _container(_Backend backend) {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [vendoServiceProvider.overrideWithValue(backend.service)],
  );
  addTearDown(container.dispose);
  return container;
}

/// A backend that answers the hub leg with [_toGoal] and the first leg with
/// [_toHub], told apart by where the search starts.
_Backend _twoLegBackend({String? earlier}) => _Backend((ask) {
  final toGoal = ask.from == _kiel.vendoLocationId;
  return _body(toGoal ? _toGoal : _toHub, earlier: toGoal ? null : earlier);
});

Future<StopoverPlanState> _plan(
  ProviderContainer container, {
  int stayMinutes = 60,
}) async {
  container
      .read(stopoverPlanProvider.notifier)
      .start(
        StopoverPlanArgs(
          from: _selent,
          hub: _kiel,
          to: _praxis,
          deadline: _deadline,
        ),
        stayMinutes: stayMinutes,
      );
  // start() kicks off load(); let both searches settle.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container.read(stopoverPlanProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plans both halves: the latest train to the appointment, and rides to '
      'the hub that leave time before it', () async {
    final backend = _twoLegBackend();
    final state = await _plan(_container(backend), stayMinutes: 30);

    // Leg 2 is the latest that still makes 09:48 — not the fastest.
    expect(state.secondLeg?.departure, _at(9, 30));
    expect(state.hubDeparture, _at(9, 30));

    // Leg 1: both roomy rides, the 5-minute one filtered out and counted.
    expect(
      [for (final j in state.firstOptions) j.departure],
      [_at(7, 20), _at(8, 20)],
    );
    expect(state.hiddenFirstCount, 1);
    expect(state.error, isNull);
    expect(state.isLoading, isFalse);
  });

  test(
    'both halves are arrival searches, and the hub one asks for "stay before '
    'the onward train leaves"',
    () async {
      final backend = _twoLegBackend();
      await _plan(_container(backend), stayMinutes: 60);

      expect(backend.asks.length, 2);
      expect(backend.asks.every((a) => a.kind == 'ANKUNFT'), isTrue);

      // First request: hub → goal, by the appointment.
      expect(backend.asks[0].from, _kiel.vendoLocationId);
      expect(backend.asks[0].to, _praxis.vendoLocationId);
      expect(backend.asks[0].when, startsWith('2026-07-27T09:48'));

      // Second: home → hub, by 09:30 minus the wanted hour = 08:30.
      expect(backend.asks[1].from, _selent.vendoLocationId);
      expect(backend.asks[1].to, _kiel.vendoLocationId);
      expect(backend.asks[1].when, startsWith('2026-07-27T08:30'));
    },
  );

  test('a stay too long for the timetable empties the list and says so, '
      'instead of quietly handing back a tight change', () async {
    final backend = _twoLegBackend();
    final state = await _plan(_container(backend), stayMinutes: 180);

    expect(state.secondLeg, isNotNull);
    expect(state.firstOptions, isEmpty);
    // All three rides exist — they just don't leave three hours.
    expect(state.hiddenFirstCount, 3);
  });

  test('an unreachable appointment is an error, not an empty plan', () async {
    // Only a connection that gets in at 09:57 — after the 09:48 appointment.
    final backend = _Backend(
      (_) => _body([_conn(_kiel, _praxis, _at(9, 45), _at(9, 57))]),
    );
    final state = await _plan(_container(backend));

    expect(state.secondLeg, isNull);
    expect(state.error, contains('09:48'));
    expect(state.error, contains('Kiel Professor-Peters-Platz'));
    // No point searching the ride to the hub when there is nothing to catch.
    expect(backend.asks.length, 1);
  });

  test('changing the stay re-searches only the ride to the hub', () async {
    final backend = _twoLegBackend();
    final container = _container(backend);
    await _plan(container, stayMinutes: 30);
    expect(backend.asks.length, 2);

    container.read(stopoverPlanProvider.notifier).setStayMinutes(90);
    await Future<void>.delayed(Duration.zero);

    // One more request, and it is the first leg's — the train to the
    // appointment did not change, so re-fetching it would only burn rate limit.
    expect(backend.asks.length, 3);
    expect(backend.asks.last.from, _selent.vendoLocationId);
    // 09:30 minus 90 min.
    expect(backend.asks.last.when, startsWith('2026-07-27T08:00'));

    final state = container.read(stopoverPlanProvider);
    expect(state.stayMinutes, 90);
    expect([for (final j in state.firstOptions) j.departure], [_at(7, 20)]);
  });

  test(
    'changing the stay drops the picked ride — it may no longer qualify',
    () async {
      final backend = _twoLegBackend();
      final container = _container(backend);
      final state = await _plan(container, stayMinutes: 30);
      final notifier = container.read(stopoverPlanProvider.notifier);

      notifier.selectFirstLeg(state.firstOptions.last); // the 35-minute one
      expect(
        container.read(stopoverPlanProvider).plannedStay,
        const Duration(minutes: 35),
      );

      notifier.setStayMinutes(90);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(stopoverPlanProvider).firstLeg, isNull);
    },
  );

  test('a later appointment re-plans both halves', () async {
    final backend = _twoLegBackend();
    final container = _container(backend);
    await _plan(container, stayMinutes: 30);

    container
        .read(stopoverPlanProvider.notifier)
        .setDeadline(DateTime(2026, 7, 27, 11, 0));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(backend.asks.length, 4);
    expect(backend.asks[2].when, startsWith('2026-07-27T11:00'));
    expect(backend.asks[2].from, _kiel.vendoLocationId);
  });

  test(
    '"Früher" walks the ride to the hub further back, deduped and in order',
    () async {
      final backend = _Backend((ask) {
        if (ask.from == _kiel.vendoLocationId) return _body(_toGoal);
        // The paged window overlaps the first one by the 07:20 ride.
        if (ask.ctx != null) {
          return _body([
            _conn(_selent, _kiel, _at(6, 20), _at(6, 55)),
            _toHub.first,
          ]);
        }
        return _body(_toHub, earlier: 'frueher-1');
      });
      final container = _container(backend);
      await _plan(container, stayMinutes: 30);
      expect(container.read(stopoverPlanProvider).firstEarlierRef, 'frueher-1');

      await container
          .read(stopoverPlanProvider.notifier)
          .loadEarlierFirstLegs();

      expect(backend.asks.last.ctx, 'frueher-1');
      final state = container.read(stopoverPlanProvider);
      expect(
        [for (final j in state.firstOptions) j.departure],
        [_at(6, 20), _at(7, 20), _at(8, 20)],
      );
    },
  );

  test('a failed search leaves an error, not a half-built plan', () async {
    final container = _container(_Backend((_) => 'not json'));
    final state = await _plan(container);

    expect(state.error, isNotNull);
    expect(state.isLoading, isFalse);
    expect(state.secondLeg, isNull);
  });
}
