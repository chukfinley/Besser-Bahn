import 'dart:convert';

import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/services/nahsh_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// "Welcher Steig wirklich?" — the one question the NAH.SH backend is asked.
///
/// The case it exists for, measured at Kiel Hbf on 27.07.2026: bay B1 has been
/// closed since 6 July and lines 22/50/51/52/81/91 leave from B2, while DB Vendo
/// and DELFI both still say B1. This backend carries it as a plain realtime
/// platform change — these tests pin the parsing, the matching, and above all
/// the cases where we must NOT answer.

const _kielHbf = Station(
  id: '699275',
  name: 'Hauptbahnhof, Kiel',
  latitude: 54.315502,
  longitude: 10.13069,
);

/// Kiel Hbf as the board really returns it (shortened, values verbatim).
Map<String, dynamic> _board() => {
      'common': {
        'himL': [
          {'head': 'Sperrung Bussteig B1 am Hauptbahnhof'},
          {'head': 'Vollsperrung Reichenberger Allee'},
        ],
        'prodL': [
          {'name': 'Bus 22'},
          {'name': 'Bus 81'},
          {'name': 'Bus 31'},
          {'name': 'RE 72'},
        ],
      },
      'jnyL': [
        {
          'prodX': 0,
          'dirTxt': 'Schwentinental',
          'stbStop': {
            'dTimeS': '093800',
            'dPlatfS': 'C2',
            'dPlatfR': 'C2',
          },
        },
        {
          'prodX': 0,
          'dirTxt': 'Suchsdorf',
          'msgL': [
            {'type': 'HIM', 'himX': 1},
            {'type': 'HIM', 'himX': 0},
          ],
          'stbStop': {
            'dTimeS': '093900',
            'dTimeR': '094300',
            'dPlatfS': 'B1',
            'dPlatfR': 'B2',
          },
        },
        {
          'prodX': 1,
          'dirTxt': 'Suchsdorf',
          'stbStop': {
            'dTimeS': '094300',
            'dPlatfS': 'B1',
            'dPlatfR': 'B2',
          },
        },
        {
          'prodX': 2,
          'dirTxt': 'Mettenhof',
          'stbStop': {
            'dTimeS': '094900',
            'dPlatfS': 'B2',
            'dPlatfR': 'A1',
          },
        },
        {
          'prodX': 3,
          'dirTxt': 'Eckernförde',
          'stbStop': {
            'dTimeS': '094300',
            'dPltfS': {'txt': '6a'},
            'dPltfR': {'txt': '6a'},
          },
        },
      ],
    };

List<NahShDeparture> _parsed() => NahShService.parseBoard(_board());

DateTime _at(int h, int m) => DateTime(2026, 7, 27, h, m);

/// A service whose HAFAS answers come from [handler], counting requests.
({NahShService service, List<String> methods}) _service(
  String Function(String method, Map<String, dynamic> req) handler,
) {
  final methods = <String>[];
  final client = MockClient((req) async {
    final body = json.decode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
    final svc = (body['svcReqL'] as List).first as Map<String, dynamic>;
    final method = svc['meth'] as String;
    methods.add(method);
    return http.Response.bytes(
      utf8.encode(handler(method, svc['req'] as Map<String, dynamic>)),
      200,
    );
  });
  return (service: NahShService(client: client), methods: methods);
}

String _ok(Map<String, dynamic> res) =>
    json.encode({
      'svcResL': [
        {'meth': 'x', 'err': 'OK', 'res': res},
      ],
    });

String _locMatch() => _ok({
      'match': {
        'locL': [
          {
            'extId': '9049076',
            'name': 'Kiel Hauptbahnhof',
            'crd': {'y': 54315502, 'x': 10130690},
          },
          {
            'extId': '9049113',
            'name': 'Kiel Hbf/Kaistraße',
            'crd': {'y': 54318000, 'x': 10135000},
          },
        ],
      },
    });

void main() {
  group('reading the board', () {
    test('a moved bay comes through as planned → live', () {
      final moved = _parsed().where((d) => d.moved).toList();

      expect(moved.map((d) => '${d.line} ${d.plannedPlatform}→${d.livePlatform}'),
          ['Bus 22 B1→B2', 'Bus 81 B1→B2', 'Bus 31 B2→A1']);
    });

    test('an unchanged bay is not a correction', () {
      final c2 = _parsed().first;
      expect(c2.plannedPlatform, 'C2');
      expect(c2.moved, isFalse, reason: 'nothing to tell the rider');
    });

    test('the newer dPltf object spelling is read too', () {
      final re = _parsed().last;
      expect(re.plannedPlatform, '6a');
      expect(re.livePlatform, '6a');
    });

    test('junk in, empty list out', () {
      expect(NahShService.parseBoard(null), isEmpty);
      expect(NahShService.parseBoard({'jnyL': 'nope'}), isEmpty);
    });
  });

  group('matching the rider\'s own departure', () {
    test('the 09:39 to Suchsdorf really goes from B2', () {
      final hit = NahShService.matchDeparture(_parsed(),
          line: 'Bus 22', towards: 'Suchsdorf', plannedDeparture: _at(9, 39));

      expect(hit, isNotNull);
      expect(hit!.planned, 'B1');
      expect(hit.live, 'B2');
    });

    test('the operator\'s own reason comes along — and the message that names '
        'the closed bay wins over the other one hung on the same ride', () {
      final hit = NahShService.matchDeparture(_parsed(),
          line: 'Bus 22', towards: 'Suchsdorf', plannedDeparture: _at(9, 39));

      expect(hit!.note, 'Sperrung Bussteig B1 am Hauptbahnhof');
    });

    test('no message, no invented explanation', () {
      final hit = NahShService.matchDeparture(_parsed(),
          line: 'Bus 81', towards: 'Suchsdorf', plannedDeparture: _at(9, 43));

      expect(hit!.live, 'B2');
      expect(hit.note, isNull);
    });

    test('matched on the SCHEDULED time — a late bus is still this departure',
        () {
      // The board says dTimeR 09:43 for this ride; both sides only ever agree
      // on the scheduled 09:39.
      final hit = NahShService.matchDeparture(_parsed(),
          line: '22', towards: 'Suchsdorf', plannedDeparture: _at(9, 39));
      expect(hit?.live, 'B2');
    });

    test('"Bus 22" and "22" are the same line', () {
      for (final spelling in ['Bus 22', '22', 'bus 22']) {
        expect(
          NahShService.matchDeparture(_parsed(),
              line: spelling,
              towards: 'Suchsdorf',
              plannedDeparture: _at(9, 39))?.live,
          'B2',
          reason: spelling,
        );
      }
    });

    test('the same line at the same minute in two directions is told apart', () {
      // Line 22 leaves towards Schwentinental at 09:38 from C2 (unmoved) and
      // towards Suchsdorf at 09:39 from B2. Asking about the wrong one must not
      // hand back the other one's bay.
      expect(
        NahShService.matchDeparture(_parsed(),
            line: 'Bus 22',
            towards: 'Schwentinental',
            plannedDeparture: _at(9, 38)),
        isNull,
        reason: 'that bay did not move',
      );
    });

    test('a different line at the same minute is not our ride', () {
      expect(
        NahShService.matchDeparture(_parsed(),
            line: 'Bus 42', towards: 'Suchsdorf', plannedDeparture: _at(9, 43)),
        isNull,
      );
    });

    test('a departure the board does not have is no answer', () {
      expect(
        NahShService.matchDeparture(_parsed(),
            line: 'Bus 22', towards: 'Suchsdorf', plannedDeparture: _at(11, 39)),
        isNull,
      );
    });

    test('ambiguity is failure — two moved candidates, no direction to split '
        'them, nothing is claimed', () {
      final twins = [
        const NahShDeparture(
            line: 'Bus 22',
            direction: 'Suchsdorf',
            plannedTime: 9 * 60 + 39,
            plannedPlatform: 'B1',
            livePlatform: 'B2'),
        const NahShDeparture(
            line: 'Bus 22',
            direction: 'Suchsdorf',
            plannedTime: 9 * 60 + 39,
            plannedPlatform: 'B1',
            livePlatform: 'A1'),
      ];
      expect(
        NahShService.matchDeparture(twins,
            line: 'Bus 22', towards: 'Suchsdorf', plannedDeparture: _at(9, 39)),
        isNull,
      );
    });

    test('a minute either way still matches, five minutes do not', () {
      expect(
          NahShService.matchDeparture(_parsed(),
              line: 'Bus 22',
              towards: 'Suchsdorf',
              plannedDeparture: _at(9, 40))?.live,
          'B2');
      expect(
          NahShService.matchDeparture(_parsed(),
              line: 'Bus 22',
              towards: 'Suchsdorf',
              plannedDeparture: _at(9, 45)),
          isNull);
    });
  });

  group('when we do not even ask', () {
    test('outside Schleswig-Holstein', () {
      const muenchen = Station(
          id: '8000261',
          name: 'München Hbf',
          latitude: 48.140229,
          longitude: 11.558339);
      expect(NahShService.servesStop(muenchen), isFalse);
      expect(NahShService.servesStop(_kielHbf), isTrue);
    });

    test('a stop without coordinates is not guessed at', () {
      expect(
        NahShService.servesStop(const Station(id: '1', name: 'Irgendwo')),
        isFalse,
      );
    });

    test('trains stay DB\'s business', () {
      expect(NahShService.coversProduct('bus'), isTrue);
      expect(NahShService.coversProduct('tram'), isTrue);
      expect(NahShService.coversProduct('nationalExpress'), isFalse);
      expect(NahShService.coversProduct('regional'), isFalse);
      expect(NahShService.coversProduct(null), isFalse);
    });

    test('an out-of-area stop fires no request at all', () async {
      final h = _service((m, r) => _ok(const {}));
      const hamburgFar = Station(
          id: '8000261',
          name: 'München Hbf',
          latitude: 48.14,
          longitude: 11.55);

      final hit = await h.service.platformCorrection(
        stop: hamburgFar,
        line: 'Bus 22',
        towards: 'Suchsdorf',
        plannedDeparture: _at(9, 39),
        product: 'bus',
      );

      expect(hit, isNull);
      expect(h.methods, isEmpty, reason: 'the gate is free, the request is not');
    });

    test('a train fires no request either', () async {
      final h = _service((m, r) => _ok(const {}));

      await h.service.platformCorrection(
        stop: _kielHbf,
        line: 'RE 72',
        towards: 'Eckernförde',
        plannedDeparture: _at(9, 43),
        product: 'regional',
      );

      expect(h.methods, isEmpty);
    });
  });

  group('end to end, against the shapes the backend really returns', () {
    test('a bus in Kiel gets its moved bay', () async {
      final h = _service((method, req) =>
          method == 'LocMatch' ? _locMatch() : _ok(_board()));

      final hit = await h.service.platformCorrection(
        stop: _kielHbf,
        line: 'Bus 22',
        towards: 'Suchsdorf',
        plannedDeparture: _at(9, 39),
        product: 'bus',
      );

      expect(hit?.planned, 'B1');
      expect(hit?.live, 'B2');
      expect(h.methods, ['LocMatch', 'StationBoard']);
    });

    test('a second leg at the same stop reuses both lookups', () async {
      final h = _service((method, req) =>
          method == 'LocMatch' ? _locMatch() : _ok(_board()));

      for (final line in ['Bus 22', 'Bus 81']) {
        await h.service.platformCorrection(
          stop: _kielHbf,
          line: line,
          towards: 'Suchsdorf',
          plannedDeparture: _at(9, 39),
          product: 'bus',
        );
      }

      expect(h.methods, ['LocMatch', 'StationBoard'],
          reason: 'one board answers every leg at that stop');
    });

    test('the stop is matched by coordinate, not just by name', () async {
      // "Kiel Hbf/Kaistraße" is a different stop with a very similar name; the
      // coordinate is what keeps them apart.
      String? asked;
      final h = _service((method, req) {
        if (method == 'LocMatch') return _locMatch();
        asked = (req['stbLoc'] as Map)['extId'] as String?;
        return _ok(_board());
      });

      await h.service.platformCorrection(
        stop: _kielHbf,
        line: 'Bus 22',
        towards: 'Suchsdorf',
        plannedDeparture: _at(9, 39),
        product: 'bus',
      );

      expect(asked, '9049076');
    });

    test('no stop within reach → no board request, no answer', () async {
      final h = _service((method, req) => method == 'LocMatch'
          ? _ok({
              'match': {
                'locL': [
                  {
                    'extId': '9999999',
                    'name': 'Woanders',
                    'crd': {'y': 54900000, 'x': 9000000},
                  },
                ],
              },
            })
          : _ok(_board()));

      final hit = await h.service.platformCorrection(
        stop: _kielHbf,
        line: 'Bus 22',
        towards: 'Suchsdorf',
        plannedDeparture: _at(9, 39),
        product: 'bus',
      );

      expect(hit, isNull);
      expect(h.methods, ['LocMatch']);
    });

    test('a backend that errors changes nothing', () async {
      final client = MockClient((req) async => http.Response('boom', 500));
      final service = NahShService(client: client);

      expect(
        await service.platformCorrection(
          stop: _kielHbf,
          line: 'Bus 22',
          towards: 'Suchsdorf',
          plannedDeparture: _at(9, 39),
          product: 'bus',
        ),
        isNull,
      );
    });
  });
}
