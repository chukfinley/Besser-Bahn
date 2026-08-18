import 'dart:convert';

import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/transfer_profile.dart';
import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shapes captured live from /mob/angebote/fahrplan (#20, point 6).
///
/// Two transfers that look alike in our own timestamp maths and are not:
///
/// - Köln Messe/Deutz → Köln Messe/Deutz Gl.11-12: a walk BETWEEN stations.
///   DB sends `verfuegbareZeit` 720 (the window) next to `abschnittsDauer` 420
///   (the walk) and `distanz` 59.
/// - Mannheim Hbf → Mannheim Hbf: a change WITHIN one station, on the same
///   platform. DB sends neither `verfuegbareZeit` nor `distanz`, and
///   `abschnittsDauer` 720 is the window again — reading it as a walk would
///   invent a 12-minute stroll across one platform.
Map<String, dynamic> _leg({
  required String typ,
  String? from,
  String? to,
  String? abgang,
  String? ankunft,
  int? dauer,
  int? verfuegbareZeit,
  int? distanz,
  bool weiterfahrtAmGleichenBahnsteig = false,
  String? kurztext,
}) => {
  'typ': typ,
  'kurztext': ?kurztext,
  'abgangsDatum': ?abgang,
  'ankunftsDatum': ?ankunft,
  'abschnittsDauer': ?dauer,
  'verfuegbareZeit': ?verfuegbareZeit,
  'distanz': ?distanz,
  'weiterfahrtAmGleichenBahnsteig': weiterfahrtAmGleichenBahnsteig,
  'halte': const [],
};

String _body(List<Map<String, dynamic>> abschnitte) => json.encode({
  'verbindungen': [
    {
      'verbindung': {'kontext': 'ctx', 'verbindungsAbschnitte': abschnitte},
    },
  ],
});

Future<Journey> _parse(List<Map<String, dynamic>> abschnitte) async {
  final svc = VendoService(
    client: MockClient(
      (_) async => http.Response.bytes(utf8.encode(_body(abschnitte)), 200),
    ),
  );
  final res = await svc.searchJourneys(
    fromLocationId: 'A=1@L=8000207@',
    toLocationId: 'A=1@L=8000261@',
  );
  return res.journeys.single;
}

void main() {
  group('inter-station walk (#20, point 6)', () {
    late Journey journey;

    setUp(() async {
      journey = await _parse([
        _leg(
          typ: 'FAHRZEUG',
          kurztext: 'ICE',
          from: 'Köln Hbf',
          to: 'Köln Messe/Deutz',
          abgang: '2026-07-18T09:00:00+02:00',
          ankunft: '2026-07-18T09:06:00+02:00',
        ),
        _leg(
          typ: 'FUSSWEG',
          from: 'Köln Messe/Deutz',
          to: 'Köln Messe/Deutz Gl.11-12',
          abgang: '2026-07-18T09:06:00+02:00',
          ankunft: '2026-07-18T09:18:00+02:00',
          dauer: 420,
          verfuegbareZeit: 720,
          distanz: 59,
        ),
        _leg(
          typ: 'FAHRZEUG',
          kurztext: 'ICE',
          from: 'Köln Messe/Deutz Gl.11-12',
          to: 'München Hbf',
          abgang: '2026-07-18T09:18:00+02:00',
          ankunft: '2026-07-18T13:30:00+02:00',
        ),
      ]);
    });

    test('reads the window, the walk and the distance', () {
      final walk = journey.legs[1];
      expect(walk.transferAvailable, const Duration(minutes: 12));
      expect(walk.walkingDuration, const Duration(minutes: 7));
      expect(walk.walkingDistance, 59);
    });

    test('buffer is the window minus the walk, not the window', () {
      // The point of the whole field: "12 min" reads as slack, but 7 of them
      // are spent walking.
      expect(journey.legs[1].transferBufferMinutes, 5);
    });
  });

  group('same-station transfer (#20, point 6)', () {
    late Journey journey;

    setUp(() async {
      journey = await _parse([
        _leg(
          typ: 'FAHRZEUG',
          kurztext: 'ICE',
          from: 'Köln Hbf',
          to: 'Mannheim Hbf',
          abgang: '2026-07-18T09:00:00+02:00',
          ankunft: '2026-07-18T11:00:00+02:00',
        ),
        _leg(
          typ: 'FUSSWEG',
          from: 'Mannheim Hbf',
          to: 'Mannheim Hbf',
          abgang: '2026-07-18T11:00:00+02:00',
          ankunft: '2026-07-18T11:12:00+02:00',
          dauer: 720,
          weiterfahrtAmGleichenBahnsteig: true,
        ),
        _leg(
          typ: 'FAHRZEUG',
          kurztext: 'ICE',
          from: 'Mannheim Hbf',
          to: 'München Hbf',
          abgang: '2026-07-18T11:12:00+02:00',
          ankunft: '2026-07-18T14:00:00+02:00',
        ),
      ]);
    });

    test('abschnittsDauer is NOT taken as a walk without verfuegbareZeit', () {
      final walk = journey.legs[1];
      expect(walk.transferAvailable, isNull);
      expect(
        walk.walkingDuration,
        isNull,
        reason:
            'dauer == the whole window here; calling it a 12-min walk '
            'across one platform would be invented',
      );
      expect(walk.transferBufferMinutes, isNull);
    });

    test('same-platform flag is read off the walk leg', () {
      expect(journey.legs[1].samePlatformTransfer, isTrue);
      expect(
        journey.legs[2].samePlatformTransfer,
        isFalse,
        reason: 'DB puts the flag on the FUSSWEG, not on the train',
      );
      // ...and the journey answers for the train you change INTO.
      expect(journey.samePlatformTransferInto(journey.legs[2]), isTrue);
    });

    test('the first leg is never a transfer', () {
      expect(journey.samePlatformTransferInto(journey.legs.first), isFalse);
    });
  });

  group('TransferProfile.effectiveGap samePlatform', () {
    test('same platform means the profile has no walk to price', () {
      // The reported case: "Barrierearm" (1.8) judges a 9-minute change as 5
      // and warns. Across one platform there are no stairs and no lift, so 9
      // minutes really is 9.
      expect(TransferProfile.accessible.effectiveGap(9), 5);
      expect(TransferProfile.accessible.effectiveGap(9, samePlatform: true), 9);
    });

    test('still scales a real walk', () {
      expect(
        TransferProfile.accessible.effectiveGap(9, samePlatform: false),
        5,
      );
    });
  });
}
