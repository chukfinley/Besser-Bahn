import 'dart:convert';

import 'package:besser_bahn/models/walking_route.dart';
import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Live shape of POST /mob/location/calculateroute (#21) — Köln Hbf to a point
/// ~200 m south: 28 points, 683 m, 492 s. The straight line is ~200 m, which is
/// the whole reason for asking.
String _body({int points = 28, int? distance = 683, int? traveltime = 492}) =>
    json.encode({
      'distance': ?distance,
      'traveltime': ?traveltime,
      'gpsPositions': [
        for (var i = 0; i < points; i++)
          {'latitude': 50.9435 - i * 0.0001, 'longitude': 6.9595 + i * 0.00001},
      ],
    });

Future<WalkingRoute?> _route(
  http.Response response, {
  void Function(http.Request)? onRequest,
}) {
  final svc = VendoService(
    client: MockClient((req) async {
      onRequest?.call(req);
      return response;
    }),
  );
  return svc.calculateWalkingRoute(
    fromLat: 50.943029,
    fromLon: 6.958730,
    toLat: 50.941200,
    toLon: 6.958730,
  );
}

void main() {
  group('calculateWalkingRoute (#21)', () {
    test('sends the two points as latitude/longitude, and no WKB', () async {
      // Without desiredCoordinateType the response carries the polyline as
      // plain JSON — verified identical to the WKB one, 28 points either way —
      // so asking for WKB would only buy us a decoder.
      late Map<String, dynamic> body;
      late String url;
      await _route(
        http.Response(_body(), 200),
        onRequest: (req) {
          body =
              json.decode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
          url = req.url.toString();
        },
      );
      expect(url, endsWith('/mob/location/calculateroute'));
      expect(body['gpsPositions'], [
        {'latitude': 50.943029, 'longitude': 6.958730},
        {'latitude': 50.941200, 'longitude': 6.958730},
      ]);
      expect(body.containsKey('desiredCoordinateType'), isFalse);
    });

    test('reads the polyline, the distance and DB\'s walking time', () async {
      final r = await _route(http.Response(_body(), 200));
      expect(r, isNotNull);
      expect(r!.points, hasLength(28));
      expect(r.points.first.lat, closeTo(50.9435, 1e-6));
      expect(r.points.first.lon, closeTo(6.9595, 1e-6));
      expect(r.distanceMetres, 683);
      expect(r.duration, const Duration(seconds: 492));
      expect(r.minutes, 8);
      expect(r.summary, '683 m · 8 min');
    });

    test('a sub-minute walk is 1 min, never 0', () async {
      final r = await _route(
        http.Response(_body(distance: 40, traveltime: 35), 200),
      );
      expect(r!.summary, '40 m · 1 min');
    });

    test('summary uses whatever DB gave', () async {
      final r = await _route(
        http.Response(_body(distance: null, traveltime: null), 200),
      );
      expect(r!.summary, isNull);
      expect(r.points, hasLength(28));
    });

    test('a two-point answer is kept for its distance and time', () async {
      // The line then looks like the straight one, but 683 m / 492 s are still
      // DB's routed numbers rather than our 200 m of crow-flight — and those
      // are most of what the chip shows.
      final r = await _route(http.Response(_body(points: 2), 200));
      expect(r, isNotNull);
      expect(r!.points, hasLength(2));
      expect(r.summary, '683 m · 8 min');
    });

    test('fewer than two points is null — that is not a line', () async {
      expect(await _route(http.Response(_body(points: 1), 200)), isNull);
      expect(await _route(http.Response(_body(points: 0), 200)), isNull);
    });

    test('a failure is null, not an exception — the map still works', () async {
      // The straight line and the blue dot are already on screen; a routing
      // failure must not take the location feature down with it.
      expect(
        await _route(http.Response('{"code":"VALIDIERUNG"}', 400)),
        isNull,
      );
      expect(await _route(http.Response('{"code":"FATAL"}', 500)), isNull);
      expect(
        await _route(http.Response(json.encode({'distance': 5}), 200)),
        isNull,
      );
    });
  });
}
