import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/models/trip.dart';
import 'package:besser_bahn/screens/train_lookup/widgets/stop_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Stopover _stop(String name, DateTime at) => Stopover(
  stop: Station(id: name.hashCode.toString(), name: name),
  plannedArrival: at,
  arrival: at,
  plannedDeparture: at,
  departure: at,
);

/// The timeline at a given system font scale.
Future<void> _pump(WidgetTester tester, double scale) async {
  final t = DateTime(2026, 8, 1, 15, 43);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: StopTimeline(
                stopovers: [
                  _stop('Kiel Hbf', t),
                  _stop('Hamburg Hbf', t.add(const Duration(minutes: 55))),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Left edge of the stop name = width of the time gutter plus the fixed gaps
/// and the timeline line. Only the gutter changes with the font scale.
double _nameLeft(WidgetTester tester) =>
    tester.getTopLeft(find.text('Kiel Hbf')).dx;

/// Height of the row the time and the station name share.
double _timeRowHeight(WidgetTester tester) =>
    tester.getSize(find.text('15:43').first).height;

void main() {
  group('#98 — the left time gutter grows with the system font', () {
    testWidgets('a bigger font gets a wider gutter, so "15:43" stays whole', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await _pump(tester, 1.0);
      final left1 = _nameLeft(tester);
      final high1 = _timeRowHeight(tester);

      await _pump(tester, 2.0);
      final left2 = _nameLeft(tester);
      final high2 = _timeRowHeight(tester);

      // The gutter was a hard 40px at every font scale: at 200% the time
      // rendered ~80px wide and the box cut the last digit off ("15:4").
      expect(
        left2 - left1,
        greaterThan(30),
        reason:
            'the gutter must roughly double with the font (was $left1, '
            'now $left2)',
      );
      // And it must not be cut off top and bottom either — the row the time
      // sits in scales too.
      expect(high2, greaterThan(high1));
    });

    testWidgets('the default font scale keeps the tight gutter', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await _pump(tester, 1.0);
      // 40px gutter + 12 gap + 20 line column + 12 gap + 8 outer padding.
      expect(_nameLeft(tester), lessThan(115));
    });
  });
}
