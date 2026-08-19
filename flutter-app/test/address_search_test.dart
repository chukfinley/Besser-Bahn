import 'dart:convert';

import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Searching for a street address is the case where the rider has no stop name
/// to type — "Kieler Straße 30, 24211 Preetz" (the Arbeitsagentur) is not a
/// station, and Google Maps is the only alternative if the app can't take it.
///
/// DB's `/mob/location/search` answers that query with `ADR` hits (and `POI`
/// hits for a named place); the journey API accepts either as origin or
/// destination and adds the footpath from the nearest stop itself. The app used
/// to drop everything but `ST`, so every address search came back empty.
///
/// Rows below are trimmed copies of live responses — see
/// `api-tests/healthcheck.py::check_vendo_address_search`, which asserts the same
/// shapes against the real endpoint.
Map<String, dynamic> _adr(String name, double lat, double lon,
        {String? evaNr = '981033693'}) =>
    {
      'locationType': 'ADR',
      'name': name,
      // An address really does come back with an evaNr — but a pseudo one
      // (98x/99x), with no board and no station map behind it. Only
      // locationType says what this is.
      'evaNr': ?evaNr,
      'locationId': 'A=2@O=$name@X=${(lon * 1e6).round()}@'
          'Y=${(lat * 1e6).round()}@U=91@L=981033693@p=1779965474@',
      'coordinates': {'latitude': lat, 'longitude': lon},
    };

Map<String, dynamic> _poi(String name, double lat, double lon) => {
      'locationType': 'POI',
      'name': name,
      'evaNr': '991007559',
      'locationId': 'A=4@O=$name@U=92@L=991007559@p=1785820257@',
      'coordinates': {'latitude': lat, 'longitude': lon},
    };

Map<String, dynamic> _st(String name, String eva, double lat, double lon) => {
      'locationType': 'ST',
      'name': name,
      'evaNr': eva,
      'locationId': 'A=1@O=$name@U=80@L=$eva@p=1785786650@',
      'coordinates': {'latitude': lat, 'longitude': lon},
    };

VendoService _service(List<Map<String, dynamic>> rows,
        {void Function(Map<String, dynamic> body)? onBody}) =>
    VendoService(
      client: MockClient((req) async {
        onBody?.call(
            json.decode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>);
        return http.Response.bytes(utf8.encode(json.encode(rows)), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

void main() {
  test('address and POI hits survive the search', () async {
    final results = await _service([
      _adr('24211 Preetz, Kieler Straße 30', 54.24456, 10.277403),
      _poi('Kiel, Agentur für Arbeit Kiel', 54.309894, 10.132308),
      _st('Preetz', '8004819', 54.2374, 10.2793),
    ]).searchLocations('Kieler Straße 30, 24211 Preetz');

    expect(results.map((s) => s.name), [
      '24211 Preetz, Kieler Straße 30',
      'Kiel, Agentur für Arbeit Kiel',
      'Preetz',
    ]);
    expect(results.map((s) => s.kind),
        [LocationKind.address, LocationKind.poi, LocationKind.station]);
    expect(results.first.isStop, isFalse);
    expect(results.last.isStop, isTrue);
  });

  test('an address keeps its full locationId — the journey API needs it',
      () async {
    final adr = (await _service([
      _adr('24211 Preetz, Kieler Straße 30', 54.24456, 10.277403),
    ]).searchLocations('Kieler Straße 30'))
        .single;

    expect(adr.locationId, startsWith('A=2@O=24211 Preetz, Kieler Straße 30@'));
    expect(adr.vendoLocationId, adr.locationId);
    expect(adr.latitude, closeTo(54.24456, 1e-6));
  });

  test('an address gets a stable id — favorites/recents are keyed by it',
      () async {
    final adr = (await _service([
      _adr('24211 Preetz, Kieler Straße 30', 54.24456, 10.277403),
    ]).searchLocations('Kieler Straße 30'))
        .single;

    // DB's pseudo-EVA is stable per address, so it is the key — but it is not
    // a station: `isStop` stays false, which is what guards the boards.
    expect(adr.id, '981033693');
    expect(adr.isStop, isFalse);

    final other = (await _service([
      _adr('24211 Preetz, Danziger Straße 30', 54.244138, 10.288199,
          evaNr: '981033643'),
    ]).searchLocations('Danziger Straße 30'))
        .single;
    expect(other.id, isNot(adr.id));
  });

  test('an address without a pseudo-EVA still gets a usable id', () async {
    // Belt and braces: an empty id made every address collide in the library
    // and silently refuse to be starred.
    final adr = (await _service([
      _adr('24211 Preetz, Kieler Straße 30', 54.24456, 10.277403, evaNr: null),
    ]).searchLocations('Kieler Straße 30'))
        .single;
    expect(adr.id, 'address:54.24456,10.27740');
  });

  test('no synthetic EVA locationId is invented for an address', () {
    const adr = Station(
        id: 'address:54.24456,10.27740',
        name: '24211 Preetz, Kieler Straße 30',
        kind: LocationKind.address);
    // 'A=1@L=address:…@' would be nonsense to the backend — better empty.
    expect(adr.vendoLocationId, '');
  });

  test('duplicate addresses are collapsed', () async {
    // The live endpoint returns the same address twice, metres apart.
    final results = await _service([
      _adr('24211 Preetz, Danziger Straße 30', 54.244138, 10.288199),
      _adr('24211 Preetz, Danziger Straße 30', 54.244183, 10.288064),
    ]).searchLocations('Danziger Straße 30');

    expect(results.length, 1);
  });

  test('stopsOnly drops addresses where an EVA is required', () async {
    final results = await _service([
      _adr('24211 Preetz, Kieler Straße 30', 54.24456, 10.277403),
      _st('Preetz', '8004819', 54.2374, 10.2793),
    ]).searchLocations('Preetz', stopsOnly: true);

    expect(results.single.name, 'Preetz');
    expect(results.single.id, '8004819');
  });

  test('the search asks for all location types', () async {
    Map<String, dynamic>? sent;
    await _service([], onBody: (b) => sent = b).searchLocations('Preetz');
    expect(sent?['locationTypes'], ['ALL']);
    expect(sent?['searchTerm'], 'Preetz');
  });

  test('an address round-trips through local storage', () {
    const adr = Station(
      id: 'address:54.24456,10.27740',
      name: '24211 Preetz, Kieler Straße 30',
      latitude: 54.24456,
      longitude: 10.277403,
      locationId: 'A=2@O=24211 Preetz, Kieler Straße 30@',
      kind: LocationKind.address,
    );
    final back = Station.fromJson(adr.toJson());
    expect(back.kind, LocationKind.address);
    expect(back.locationId, adr.locationId);

    // Stations stored by earlier versions carry no 'kind' at all.
    final legacy = Station.fromJson({'id': '8000199', 'name': 'Kiel Hbf'});
    expect(legacy.kind, LocationKind.station);
    expect(legacy.isStop, isTrue);
  });
}
