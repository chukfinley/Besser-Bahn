import 'dart:convert';

import 'package:besser_bahn/models/best_price.dart';
import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shape captured live from POST /mob/angebote/tagesbestpreis (#21).
Map<String, dynamic> _interval({
  required String ab,
  required String bis,
  double? betrag,
  bool istBestpreis = false,
  bool istTeilpreis = false,
  int conns = 1,
}) => {
  'intervallAb': ab,
  'intervallBis': bis,
  'istBestpreis': istBestpreis,
  'istTeilpreis': istTeilpreis,
  'hinRueckPauschalpreis': false,
  if (betrag != null) 'angebotsPreis': {'waehrung': 'EUR', 'betrag': betrag},
  'verbindungen': [
    for (var i = 0; i < conns; i++)
      {
        'verbindung': {
          'kontext': 'ctx-$i',
          'verbindungsAbschnitte': [
            {
              'typ': 'FAHRZEUG',
              'kurztext': 'ICE',
              'zugNummer': '541',
              'abgangsOrt': {'name': 'Köln Hbf', 'evaNr': '8000207'},
              'ankunftsOrt': {'name': 'Berlin Hbf', 'evaNr': '8011160'},
              'abgangsDatum': ab,
              'ankunftsDatum': bis,
              'halte': const [],
            },
          ],
        },
        'angebote': {
          'preise': {
            'gesamt': {
              'ab': {'betrag': betrag ?? 0, 'waehrung': 'EUR'},
            },
          },
        },
      },
  ],
};

String _body(List<Map<String, dynamic>> intervals) =>
    json.encode({'tagesbestPreisIntervalle': intervals, 'nachrichten': []});

Future<BestPriceDay> _fetch(
  List<Map<String, dynamic>> intervals, {
  void Function(http.Request)? onRequest,
}) async {
  final svc = VendoService(
    client: MockClient((req) async {
      onRequest?.call(req);
      return http.Response.bytes(utf8.encode(_body(intervals)), 200);
    }),
  );
  return svc.fetchBestPrices(
    fromLocationId: 'A=1@L=8000207@',
    toLocationId: 'A=1@L=8011160@',
    date: DateTime(2026, 7, 22, 14, 37),
  );
}

/// The live Köln→Berlin day from the issue.
final _liveDay = [
  _interval(
    ab: '2026-07-22T00:00:00+02:00',
    bis: '2026-07-22T07:00:00+02:00',
    betrag: 47.99,
    conns: 5,
  ),
  _interval(
    ab: '2026-07-22T07:00:00+02:00',
    bis: '2026-07-22T10:00:00+02:00',
    betrag: 67.99,
    conns: 5,
  ),
  _interval(
    ab: '2026-07-22T19:00:00+02:00',
    bis: '2026-07-23T00:00:00+02:00',
    betrag: 29.99,
    istBestpreis: true,
    conns: 4,
  ),
];

void main() {
  group('fetchBestPrices (#21)', () {
    test('asks for the day at midnight, whatever time was passed', () async {
      // The endpoint prices the whole day, so the hour is noise — pinning it
      // keeps two visits to the same day one cache entry, on a backend that
      // rate-limits hard.
      late Map<String, dynamic> body;
      await _fetch(
        _liveDay,
        onRequest: (req) {
          body =
              json.decode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
        },
      );
      final wunsch = (body['reiseHin'] as Map)['wunsch'] as Map;
      final datum = (wunsch['zeitWunsch'] as Map)['reiseDatum'] as String;
      expect(
        datum,
        startsWith('2026-07-22T00:00:00'),
        reason: 'the 14:37 in the request must not reach the backend',
      );
      expect(
        wunsch.containsKey('context'),
        isFalse,
        reason: 'tagesbestpreis has no pagination to replay',
      );
    });

    test(
      'reads the price, the interval and DB\'s own Bestpreis flag',
      () async {
        final day = await _fetch(_liveDay);
        expect(day.intervals, hasLength(3));

        final first = day.intervals.first;
        expect(first.price, 47.99);
        expect(first.currency, 'EUR');
        expect(first.formattedPrice, '47.99 €');
        expect(first.from.hour, 0);
        expect(first.to.hour, 7);
        expect(first.isBest, isFalse);

        final best = day.intervals.last;
        expect(
          best.isBest,
          isTrue,
          reason: 'istBestpreis is read, not recomputed',
        );
        expect(best.price, 29.99);
      },
    );

    test(
      'carries the connections, with kontext, ready for the detail screen',
      () async {
        final day = await _fetch(_liveDay);
        expect(day.intervals.first.journeys, hasLength(5));
        final j = day.intervals.first.journeys.first;
        expect(
          j.refreshToken,
          'ctx-0',
          reason: 'no kontext → no detail, no share, no split',
        );
        expect(j.legs.single.line?.fahrtNr, '541');
        expect(j.legs.single.origin.name, 'Köln Hbf');
      },
    );

    test('cheapest/dearest span the day and drive the bars', () async {
      final day = await _fetch(_liveDay);
      expect(day.cheapest, 29.99);
      expect(day.dearest, 67.99);
      expect(day.hasPrices, isTrue);
    });

    test('a part-trip price is left out of cheapest/dearest', () async {
      // istTeilpreis covers only a leg, so treating it as the day's low would
      // advertise a price nobody can buy for this trip.
      final day = await _fetch([
        _interval(
          ab: '2026-07-22T00:00:00+02:00',
          bis: '2026-07-22T07:00:00+02:00',
          betrag: 9.99,
          istTeilpreis: true,
        ),
        _interval(
          ab: '2026-07-22T07:00:00+02:00',
          bis: '2026-07-22T10:00:00+02:00',
          betrag: 67.99,
        ),
      ]);
      expect(day.cheapest, 67.99);
      expect(day.dearest, 67.99);
    });

    test('a priceless interval keeps its connections', () async {
      // Normal for late trains: no offer, but the trains run — dropping them
      // would make the slot look like it has no service.
      final day = await _fetch([
        _interval(
          ab: '2026-07-22T00:00:00+02:00',
          bis: '2026-07-22T07:00:00+02:00',
          conns: 3,
        ),
      ]);
      expect(day.intervals.single.price, isNull);
      expect(day.intervals.single.formattedPrice, isNull);
      expect(day.intervals.single.journeys, hasLength(3));
      expect(day.hasPrices, isFalse);
    });

    test('an interval without bounds is dropped, not rendered blank', () async {
      final day = await _fetch([
        {'istBestpreis': false, 'verbindungen': []},
        _interval(
          ab: '2026-07-22T07:00:00+02:00',
          bis: '2026-07-22T10:00:00+02:00',
          betrag: 67.99,
        ),
      ]);
      expect(day.intervals, hasLength(1));
    });

    test('an empty day is empty, not an error', () async {
      final day = await _fetch([]);
      expect(day.intervals, isEmpty);
      expect(day.hasPrices, isFalse);
      expect(day.cheapest, isNull);
    });
  });

  test('a non-200 surfaces as a VendoException', () async {
    final svc = VendoService(
      client: MockClient((_) async => http.Response('{"code":"RETRY"}', 429)),
    );
    expect(
      () => svc.fetchBestPrices(
        fromLocationId: 'A=1@L=8000207@',
        toLocationId: 'A=1@L=8011160@',
        date: DateTime(2026, 7, 22),
      ),
      throwsA(isA<VendoException>()),
    );
  });
}
