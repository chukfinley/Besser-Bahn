import 'package:besser_bahn/models/coach_sequence.dart';
import 'package:besser_bahn/utils/transfer_coach_advice.dart';
import 'package:flutter_test/flutter_test.dart';

// Every sector table below is REAL, read off the live vehicle-sequence endpoint
// (GET bahn.de/web/api/reisebegleitung/wagenreihung/vehicle-sequence) on
// 2026-07-16, so the geometry these tests reason about is the geometry the app
// gets. Sequences are built through CoachSequence.fromJson — the same parse the
// app runs — so a shape change in the model breaks these too.

/// Berlin Hbf, one island: Gleis 3 and Gleis 4 come back with the same
/// letter→metre table (that agreement is what makes the advice possible).
const _berlinG3 = [
  ('G', 0.0, 97.5),
  ('F', 97.5, 149.8),
  ('E', 149.8, 194.6),
  ('D', 194.6, 246.2),
  ('C', 246.2, 310.2),
  ('B', 310.2, 358.8),
  ('A', 358.8, 430.2),
];
const _berlinG4 = [
  ('G', 0.0, 97.5),
  ('F', 97.5, 149.8),
  ('E', 149.8, 195.7),
  ('D', 195.7, 248.3),
  ('C', 248.3, 311.3),
  ('B', 311.3, 358.8),
  ('A', 358.8, 430.2),
];

/// Hamburg Dammtor Gleis 4 — note it runs A(0)→G(420), the reverse of Berlin.
const _dammtorG4 = [
  ('A', 0.0, 93.0),
  ('B', 93.0, 140.0),
  ('C', 140.0, 192.5),
  ('D', 192.5, 242.5),
  ('E', 242.5, 292.5),
  ('F', 292.5, 346.0),
  ('G', 346.0, 420.0),
];

/// Dortmund Hbf Gleis 11 — a DIFFERENT platform from Gl. 16: same ~415 m
/// length, but sector G ends 51 m further along. The frame guard must catch it.
const _dortmundG11 = [
  ('G', 0.0, 114.0),
  ('F', 114.0, 155.0),
  ('E', 155.0, 203.5),
  ('D', 203.5, 251.5),
  ('C', 251.5, 306.5),
  ('B', 306.5, 356.0),
  ('A', 356.0, 416.0),
];
const _dortmundG16 = [
  ('G', 0.0, 63.0),
  ('F', 63.0, 104.0),
  ('E', 104.0, 152.5),
  ('D', 152.5, 200.5),
  ('C', 200.5, 255.5),
  ('B', 255.5, 305.0),
  ('A', 305.0, 415.0),
];

/// The sector letter [table] puts metre [m] in.
String _sectorAt(List<(String, double, double)> table, double m) {
  for (final (name, start, end) in table) {
    if (m >= start && m < end) return name;
  }
  return table.last.$1;
}

/// Build a coach occupying [start]..[end] m, tagged with the section that
/// platform really puts it in — exactly what the endpoint returns.
Map<String, dynamic> _coach(
  List<(String, double, double)> table,
  double start,
  double end, {
  int? wagon,
}) => {
  'wagonIdentificationNumber': ?wagon,
  'vehicleID': 'v$start',
  'orientation': 'FORWARDS',
  'status': 'OPEN',
  'type': {
    'category': 'PASSENGER_COACH',
    'constructionType': 'X',
    'hasFirstClass': false,
    'hasEconomyClass': true,
  },
  'platformPosition': {
    'start': start,
    'end': end,
    'sector': _sectorAt(table, (start + end) / 2),
  },
  'amenities': const [],
};

/// A sequence on [gleis] whose coaches fill [start]..[end] in ~26.8 m cars.
CoachSequence _seq({
  required String gleis,
  required List<(String, double, double)> table,
  required double start,
  required double end,
  String destination = 'Irgendwo',
  int? firstWagon,
  double carLen = 26.8,
}) {
  final vehicles = <Map<String, dynamic>>[];
  var m = start;
  var w = firstWagon;
  while (m < end - 0.5) {
    final to = (m + carLen) > end ? end : m + carLen;
    vehicles.add(_coach(table, m, to, wagon: w));
    if (w != null) w++;
    m = to;
  }
  return CoachSequence.fromJson({
    'journeyID': 'j-$gleis',
    'departurePlatform': gleis,
    'departurePlatformSchedule': gleis,
    'sequenceStatus': 'PLANNED',
    'platform': {
      'name': gleis,
      'start': table.first.$2,
      'end': table.last.$3,
      'sectors': [
        for (final (name, s, e) in table) {'name': name, 'start': s, 'end': e},
      ],
    },
    'groups': [
      {
        'name': 'G1',
        'transport': {
          'category': 'ICE',
          'number': 1,
          'type': 'HIGH_SPEED_TRAIN',
          'destination': {'name': destination},
        },
        'vehicles': vehicles,
      },
    ],
  });
}

void main() {
  group('transferCoachAdvice — fires only on evidence (#27)', () {
    test('short train, long connection: names the sections alongside it', () {
      // Arriving RE fills Dammtor Gl. 4 sections A–C (0–160 m); the ICE it
      // connects to stands further down, C–G (140–364 m). Only the C end of the
      // RE faces it → that's the answer, and it isn't the whole train.
      final advice = transferCoachAdvice(
        arriving: _seq(gleis: '4', table: _dammtorG4, start: 0, end: 160),
        departing: _seq(
          gleis: '4',
          table: _dammtorG4,
          start: 140,
          end: 364,
          firstWagon: 1,
        ),
        samePlatformPerDb: true,
      );

      expect(advice, isNotNull);
      expect(advice!.reason, TransferAdviceReason.alongside);
      expect(advice.sectors, ['C']);
      expect(advice.sectorLabel, 'C');
      expect(advice.departingSectors, ['C', 'D', 'E', 'F', 'G']);
      expect(advice.departingSectorLabel, 'C–G');
    });

    test('no overlap at all: points at the closest end, flagged as such', () {
      // Arriving train sits at A–C (0–160), the departing one at E–G (250–420).
      // Nothing is alongside → the honest answer is "the C end, that's as close
      // as you get", not a section it doesn't reach.
      final advice = transferCoachAdvice(
        arriving: _seq(gleis: '4', table: _dammtorG4, start: 0, end: 160),
        departing: _seq(gleis: '5', table: _dammtorG4, start: 250, end: 420),
        samePlatformPerDb: true,
      );

      expect(advice, isNotNull);
      expect(advice!.reason, TransferAdviceReason.nearest);
      expect(advice.sectors, ['C']);
    });

    test('reports the wagon numbers standing there', () {
      final advice = transferCoachAdvice(
        arriving: _seq(
          gleis: '4',
          table: _dammtorG4,
          start: 0,
          end: 160,
          firstWagon: 21,
        ),
        departing: _seq(gleis: '4', table: _dammtorG4, start: 140, end: 364),
        samePlatformPerDb: true,
      );

      // 0–160 m in 26.8 m cars → wagons 21..26; only the last (134–160.8) is
      // past the ICE's nose at 140 m.
      expect(advice!.coaches, [26]);
      expect(advice.coachLabel, 'Wagen 26');
    });

    test('regional stock without wagon numbers still yields the section', () {
      final advice = transferCoachAdvice(
        arriving: _seq(gleis: '4', table: _dammtorG4, start: 0, end: 160),
        departing: _seq(gleis: '4', table: _dammtorG4, start: 140, end: 364),
        samePlatformPerDb: true,
      );

      expect(advice!.sectors, ['C']);
      expect(advice.coaches, isEmpty);
      expect(advice.coachLabel, isNull);
    });

    test('one island, two tracks: Berlin Gl. 3 → Gl. 4 compares directly', () {
      // The real pair. Arriving RJ occupies E–A (171–427); we shorten the ICE
      // to D–A (195–430) so there IS something to optimise: the RJ's E end
      // sticks out past it.
      final advice = transferCoachAdvice(
        arriving: _seq(gleis: '3', table: _berlinG3, start: 171.2, end: 426.9),
        departing: _seq(gleis: '4', table: _berlinG4, start: 248.3, end: 430.2),
        samePlatformPerDb: true,
      );

      expect(advice, isNotNull);
      expect(advice!.reason, TransferAdviceReason.alongside);
      // The ICE's nose is at 248.3 m; every RJ car from there back faces it —
      // including the one at 224.8–251.6 that straddles the nose and is
      // centred in D. So the answer runs A–D, and the RJ's E tail is the part
      // to avoid.
      expect(advice.sectors, ['A', 'B', 'C', 'D']);
      expect(advice.sectorLabel, 'A–D');
    });
  });

  group('transferCoachAdvice — stays silent rather than guess (#27)', () {
    test('missing Wagenreihung on either side → nothing', () {
      final s = _seq(gleis: '4', table: _dammtorG4, start: 0, end: 160);
      expect(
        transferCoachAdvice(
          arriving: null,
          departing: s,
          samePlatformPerDb: true,
        ),
        isNull,
      );
      expect(
        transferCoachAdvice(
          arriving: s,
          departing: null,
          samePlatformPerDb: true,
        ),
        isNull,
      );
    });

    test(
      'different platforms → nothing (sector letters are unrelated there)',
      () {
        // Dortmund: ICE arrives Gl. 16, IC leaves Gl. 11. Which end of 16 faces
        // 11 needs station geometry — so we say nothing.
        expect(
          transferCoachAdvice(
            arriving: _seq(
              gleis: '16',
              table: _dortmundG16,
              start: 4.5,
              end: 368,
            ),
            departing: _seq(
              gleis: '11',
              table: _dortmundG11,
              start: 181.7,
              end: 335.1,
            ),
            samePlatformPerDb: false,
          ),
          isNull,
        );
      },
    );

    test('same-platform flag contradicted by the geometry → nothing', () {
      // Even if DB claimed one platform, Dortmund Gl. 16 and Gl. 11 put sector
      // G's end 51 m apart. Same length, different platform: the frame guard
      // must refuse rather than compare two unrelated metre axes.
      expect(
        transferCoachAdvice(
          arriving: _seq(
            gleis: '16',
            table: _dortmundG16,
            start: 4.5,
            end: 368,
          ),
          departing: _seq(
            gleis: '11',
            table: _dortmundG11,
            start: 181.7,
            end: 335.1,
          ),
          samePlatformPerDb: true,
        ),
        isNull,
      );
    });

    test(
      'arriving train entirely alongside the connection → nothing to say',
      () {
        // The real Berlin pair: RJ 175 (171–427) inside ICE 1507 (25–426). Every
        // door already faces the ICE — a hint here would be noise.
        expect(
          transferCoachAdvice(
            arriving: _seq(
              gleis: '3',
              table: _berlinG3,
              start: 171.2,
              end: 426.9,
            ),
            departing: _seq(
              gleis: '4',
              table: _berlinG4,
              start: 25.5,
              end: 426.1,
            ),
            samePlatformPerDb: true,
          ),
          isNull,
        );
      },
    );

    test(
      'an answer naming the whole arriving train is not advice → nothing',
      () {
        // Erfurt Hbf, ICE 698 → ICE 604: two long trains at one island. The
        // arriving one pokes ~15 m past the other, so it isn't "contained", but
        // every section it occupies still faces the connection. "Be in A–G" is
        // the train restated — say nothing instead.
        final advice = transferCoachAdvice(
          arriving: _seq(gleis: '10', table: _dammtorG4, start: 0, end: 400),
          departing: _seq(gleis: '9', table: _dammtorG4, start: 20, end: 385),
          samePlatformPerDb: true,
        );
        expect(advice, isNull);
      },
    );

    test('no sector table (endpoint served none) → nothing', () {
      final bare = CoachSequence.fromJson({
        'journeyID': 'x',
        'departurePlatform': '4',
        'sequenceStatus': 'PLANNED',
        'platform': {'name': '4', 'start': 0, 'end': 420, 'sectors': []},
        'groups': [
          {
            'name': 'G',
            'transport': {'category': 'RE', 'number': 1, 'type': 'REGIONAL'},
            'vehicles': [_coach(_dammtorG4, 0, 26.8)],
          },
        ],
      });
      expect(
        transferCoachAdvice(
          arriving: bare,
          departing: _seq(gleis: '4', table: _dammtorG4, start: 140, end: 364),
          samePlatformPerDb: true,
        ),
        isNull,
      );
    });

    test('coaches without metre positions → nothing', () {
      final noPos = CoachSequence.fromJson({
        'journeyID': 'x',
        'departurePlatform': '4',
        'sequenceStatus': 'PLANNED',
        'platform': {
          'name': '4',
          'start': 0,
          'end': 420,
          'sectors': [
            for (final (n, s, e) in _dammtorG4)
              {'name': n, 'start': s, 'end': e},
          ],
        },
        'groups': [
          {
            'name': 'G',
            'transport': {'category': 'RE', 'number': 1, 'type': 'REGIONAL'},
            'vehicles': [
              {
                'wagonIdentificationNumber': 1,
                'vehicleID': 'v',
                'orientation': 'FORWARDS',
                'status': 'OPEN',
                'type': {'category': 'PASSENGER_COACH'},
                'amenities': const [],
              },
            ],
          },
        ],
      });
      expect(
        transferCoachAdvice(
          arriving: noPos,
          departing: _seq(gleis: '4', table: _dammtorG4, start: 140, end: 364),
          samePlatformPerDb: true,
        ),
        isNull,
      );
    });

    test('same track needs no flag — it is one platform by definition', () {
      // Hamburg Dammtor: RE arrives Gl. 4, ICE leaves Gl. 4. Same track, so the
      // sections compare even with DB's flag off.
      final advice = transferCoachAdvice(
        arriving: _seq(gleis: '4', table: _dammtorG4, start: 0, end: 160),
        departing: _seq(gleis: '4', table: _dammtorG4, start: 140, end: 364),
        samePlatformPerDb: false,
      );
      expect(advice, isNotNull);
      expect(advice!.sectors, ['C']);
    });

    test('"7A-D" and "7G-I" are the same Gleis 7', () {
      // Sub-range labels off the departure board must not read as two tracks —
      // without normalisation this would fall out as "different platforms".
      final advice = transferCoachAdvice(
        arriving: _seq(gleis: '7A-D', table: _dammtorG4, start: 0, end: 160),
        departing: _seq(gleis: '7G-I', table: _dammtorG4, start: 250, end: 420),
        samePlatformPerDb: false,
      );
      expect(advice, isNotNull);
      expect(advice!.reason, TransferAdviceReason.nearest);
      expect(advice.sectors, ['C']);
    });
  });
}
