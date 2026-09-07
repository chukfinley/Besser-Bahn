import 'package:flutter_test/flutter_test.dart';

import 'package:besser_bahn/models/departure.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/services/iris_service.dart';

/// Trimmed real IRIS plan response for Kiel Hbf.
const _planXml = '''
<?xml version='1.0' encoding='UTF-8'?>
<timetable station='Kiel Hbf'>
  <s id="a-1"><tl f="N" t="p" o="800201" c="RE" n="11225"/>
    <dp pt="2609071537" pp="4" l="RE70"
        ppth="Bordesholm|Neumünster|Brokstedt|Wrist|Elmshorn|Hamburg Dammtor|Hamburg Hbf"/>
  </s>
  <s id="a-2"><tl f="F" t="p" o="80" c="ICE" n="772"/>
    <ar pt="2609071540" pp="3" ppth="Hamburg Hbf|Hamburg Dammtor|Neumünster"/>
  </s>
</timetable>
''';

Departure _dep({
  required String fahrtNr,
  required String line,
  required String product,
  required DateTime planned,
}) => Departure(
  tripId: 't-$fahrtNr',
  stop: const Station(id: '8000199', name: 'Kiel Hbf'),
  plannedWhen: planned,
  when: planned,
  direction: 'Hamburg Hbf',
  line: TransitLine(
    name: line,
    fahrtNr: fahrtNr,
    productName: product,
    product: 'regionalExpress',
  ),
);

void main() {
  group('IRIS plan parsing', () {
    test('reads number, line and the via path of both sides', () {
      final runs = IrisService.parsePlan(_planXml);
      expect(runs.length, 2);

      final dp = runs.firstWhere((r) => !r.arrival);
      expect(dp.trainNumber, '11225');
      expect(dp.line, 'RE70');
      expect(dp.plannedWhen, DateTime(2026, 9, 7, 15, 37));
      expect(dp.via.first, 'Bordesholm');
      expect(dp.via.last, 'Hamburg Hbf');

      final ar = runs.firstWhere((r) => r.arrival);
      expect(ar.trainNumber, '772');
      expect(ar.category, 'ICE');
      expect(ar.via, ['Hamburg Hbf', 'Hamburg Dammtor', 'Neumünster']);
    });

    test('skips entries without a train number', () {
      expect(
        IrisService.parsePlan(
          "<timetable><s><dp pt='2609071537' ppth='A|B'/></s></timetable>",
        ),
        isEmpty,
      );
    });
  });

  group('matching a board row to a plan entry', () {
    late IrisService iris;

    setUp(() => iris = _StubIris(IrisService.parsePlan(_planXml)));

    test('same number and minute → the via stops land on the departure',
        () async {
      final out = await iris.withVia([
        _dep(
          fahrtNr: '11225',
          line: 'RE70',
          product: 'RE',
          planned: DateTime(2026, 9, 7, 15, 37),
        ),
      ], '8000199', arrivals: false);
      expect(out.single.via.first, 'Bordesholm');
    });

    test('a bus whose line number collides keeps an empty via', () async {
      // Kiel's board is mostly buses; bus 11225 at 15:37 must not inherit the
      // RE70's stops just because the numbers match.
      final out = await iris.withVia([
        Departure(
          tripId: 'b',
          stop: const Station(id: '8000199', name: 'Kiel Hbf'),
          plannedWhen: DateTime(2026, 9, 7, 15, 37),
          direction: 'Mettenhof',
          line: const TransitLine(
            name: 'Bus 11225',
            fahrtNr: '11225',
            productName: 'Bus',
            product: 'bus',
          ),
        ),
      ], '8000199', arrivals: false);
      expect(out.single.via, isEmpty);
    });

    test('a different minute does not match', () async {
      final out = await iris.withVia([
        _dep(
          fahrtNr: '11225',
          line: 'RE70',
          product: 'RE',
          planned: DateTime(2026, 9, 7, 15, 38),
        ),
      ], '8000199', arrivals: false);
      expect(out.single.via, isEmpty);
    });

    test('a departure never matches an arrival-side entry', () async {
      final out = await iris.withVia([
        _dep(
          fahrtNr: '772',
          line: 'ICE 772',
          product: 'ICE',
          planned: DateTime(2026, 9, 7, 15, 40),
        ),
      ], '8000199', arrivals: false);
      expect(out.single.via, isEmpty);
    });
  });
}

/// Serves a fixed plan instead of hitting IRIS.
class _StubIris extends IrisService {
  _StubIris(this.runs);

  final List<IrisRun> runs;

  @override
  Future<List<IrisRun>> planWindow(
    String evaId, {
    DateTime? from,
    int hours = 3,
  }) async => runs;
}
