import 'package:besser_bahn/models/seat_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gsd seat status is easy to invert: 0 is OCCUPIED, 1/2 are FREE. These
/// pin that, plus the "frei in Wagen X" hint that surfaces the space on a
/// nearly-full train (#seat).

Map<String, dynamic> _ssr(Map<String, List<int>> coaches) => {
      'zugfahrt': {
        'zugteile': [
          {
            'wagen': [
              for (final e in coaches.entries)
                {
                  'nummer': e.key,
                  'wagentyp': 'T',
                  'plaetze': [
                    for (var i = 0; i < e.value.length; i++)
                      {'nummer': '${i + 1}', 'status': e.value[i]},
                  ],
                },
            ],
          },
        ],
      },
    };

void main() {
  group('seat status semantics (#seat)', () {
    test('0 = belegt, 1/2 = frei', () {
      expect(seatStatusFromCode(0), SeatStatus.occupied);
      expect(seatStatusFromCode(1), SeatStatus.free);
      expect(seatStatusFromCode(2), SeatStatus.free);
      expect(seatStatusFromCode(9), SeatStatus.unknown);
    });

    test('a nearly-full ICE: only Wagen 6 has a free seat (status 2)', () {
      // Mirrors the real ICE 786 probe: everything status 0, one status-2 seat
      // in Wagen 6.
      final map = SeatMap.fromSsr(_ssr({
        '1': [0, 0, 0],
        '6': [0, 2, 0],
        '11': [0, 0],
      }));
      expect(map.totalFree, 1);
      expect(map.totalSeats, 8);
      expect(map.freeCoachNumbers, ['6']);
      expect(map.freeCoachHint, '  ·  frei in Wagen 6');
    });
  });

  group('freeCoachHint (#seat)', () {
    test('empty when nothing free', () {
      final map = SeatMap.fromSsr(_ssr({'1': [0, 0], '2': [0]}));
      expect(map.totalFree, 0);
      expect(map.freeCoachHint, '');
    });

    test('lists several coaches, but stays quiet when space is everywhere', () {
      final few = SeatMap.fromSsr(_ssr({'3': [2], '7': [2]}));
      expect(few.freeCoachHint, '  ·  frei in Wagen 3, 7');
      // > 5 coaches with space → no point pointing, the whole train is open.
      final many = SeatMap.fromSsr(_ssr({
        for (final n in ['1', '2', '3', '4', '5', '6']) n: [2],
      }));
      expect(many.freeCoachHint, '');
    });
  });
}
