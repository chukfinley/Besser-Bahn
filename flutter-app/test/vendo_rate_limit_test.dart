import 'dart:convert';

import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A minimal but real `zuglauf` body — enough for _parseTripFromZuglauf.
String _zuglaufBody() => json.encode({
  'mitteltext': 'ICE 844',
  'halte': [
    {
      'ort': {'evaNr': '8011160', 'name': 'Berlin Hbf'},
      'abgangsDatum': '2026-07-14T10:00:00+02:00',
      'gleis': '7',
    },
    {
      'ort': {'evaNr': '8000152', 'name': 'Hannover Hbf'},
      'ankunftsDatum': '2026-07-14T11:38:00+02:00',
      'gleis': '9',
    },
  ],
});

/// What the backend actually answers with when the per-client limit trips —
/// captured live from app.services-bahn.de.
final _retryBody = json.encode({
  'domain': 'MOB',
  'code': 'RETRY',
  'status': 'ERROR',
});

void main() {
  group('getTrip rate limiting (#14)', () {
    test(
      '429 with Retry-After is retried, not surfaced as a failure',
      () async {
        var calls = 0;
        final svc = VendoService(
          client: MockClient((req) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                _retryBody,
                429,
                headers: {'retry-after': '1'},
              );
            }
            return http.Response.bytes(utf8.encode(_zuglaufBody()), 200);
          }),
        );

        final trip = await svc.getTrip('2|#VN#1#ST#123');

        expect(calls, 2, reason: 'should retry once after the 429');
        expect(trip.stopovers, hasLength(2));
        expect(trip.stopovers.first.stop.name, 'Berlin Hbf');
      },
    );

    test('gives up after _maxRetries and throws rather than hanging', () async {
      var calls = 0;
      final svc = VendoService(
        client: MockClient((req) async {
          calls++;
          return http.Response(_retryBody, 429, headers: {'retry-after': '1'});
        }),
      );

      await expectLater(
        svc.getTrip('2|#VN#1#ST#123'),
        throwsA(isA<VendoException>()),
      );
      // Initial attempt + 2 retries.
      expect(calls, 3);
    });

    test('a non-429 error is not retried', () async {
      var calls = 0;
      final svc = VendoService(
        client: MockClient((req) async {
          calls++;
          return http.Response('nope', 500);
        }),
      );

      await expectLater(
        svc.getTrip('2|#VN#1#ST#123'),
        throwsA(isA<VendoException>()),
      );
      expect(calls, 1);
    });

    test(
      'concurrent getTrip calls are capped, and all still complete',
      () async {
        var active = 0;
        var peak = 0;
        final svc = VendoService(
          client: MockClient((req) async {
            active++;
            peak = active > peak ? active : peak;
            await Future.delayed(const Duration(milliseconds: 20));
            active--;
            return http.Response.bytes(utf8.encode(_zuglaufBody()), 200);
          }),
        );

        // A long connection fires one of these per leg at once.
        final trips = await Future.wait(
          List.generate(10, (i) => svc.getTrip('2|#VN#1#ST#$i')),
        );

        expect(trips, hasLength(10), reason: 'queued calls must still resolve');
        expect(
          peak,
          lessThanOrEqualTo(3),
          reason: 'the gate must cap in-flight zuglauf requests',
        );
      },
    );
  });
}
