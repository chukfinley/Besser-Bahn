import 'dart:convert';

import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Mirrors a live `/mob/bahnhofstafel/abfahrt` row. The board carries no
/// cancellation flag of its own — only the realtime note.
Map<String, dynamic> _row(
  String gattung, {
  List<String> notizen = const [],
  String mitteltext = 'ICE 100',
}) => {
  'zuglaufId': '2|#VN#1#ST#1',
  'abfrageOrt': {'evaNr': '8000207', 'name': 'Köln Hbf'},
  'abgangsDatum': '2026-07-16T09:02:00+02:00',
  'gleis': '4',
  'richtung': 'Berlin Hbf',
  'produktGattung': gattung,
  'kurztext': gattung,
  'mitteltext': mitteltext,
  'zugnummer': '100',
  'wagenreihung': false,
  'echtzeitNotizen': [
    for (final n in notizen) {'prio': 'HOCH', 'text': n},
  ],
};

Future<List<dynamic>> _board(List<Map<String, dynamic>> rows) {
  final svc = VendoService(
    client: MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(json.encode({'bahnhofstafelAbfahrtPositionen': rows})),
        200,
      ),
    ),
  );
  return svc.getDepartures('8000207');
}

void main() {
  group('departure board', () {
    test('"Halt entfällt" marks the row cancelled', () async {
      // 69 of 1367 live rows carried exactly this note, while the parser
      // hardcoded cancelled:false — so a cancelled train looked like a
      // running one and the strike-through never fired.
      final deps = await _board([
        _row('ICE', notizen: ['Halt entfällt']),
        _row('RB', notizen: ['Verspätung aus vorheriger Fahrt']),
        _row('RB'),
      ]);

      expect(deps[0].cancelled, isTrue);
      expect(
        deps[1].cancelled,
        isFalse,
        reason: 'a delay note is not a cancellation',
      );
      expect(deps[2].cancelled, isFalse);
    });

    test('the note still shows up as a remark', () async {
      final deps = await _board([
        _row('ICE', notizen: ['Halt entfällt']),
      ]);
      expect(deps[0].remarks, contains('Halt entfällt'));
    });

    test('IC_EC is long-distance, not regional', () async {
      // Live sends IC_EC; the switch only knew the (never-seen) EC_IC
      // spelling, so all 4 IC rows probed fell into default -> regional and
      // the board's IC/EC filter hid real ICs.
      final deps = await _board([
        _row('IC_EC', mitteltext: 'IC 2046'),
        _row('ICE'),
        _row('RB'),
      ]);

      expect(deps[0].line?.product, 'national');
      expect(deps[1].line?.product, 'nationalExpress');
      expect(deps[2].line?.product, 'regional');
    });
  });
}
