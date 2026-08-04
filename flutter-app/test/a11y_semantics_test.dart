import 'package:besser_bahn/models/journey.dart' show OccupancyLevel;
import 'package:besser_bahn/widgets/delay_badge.dart';
import 'package:besser_bahn/widgets/occupancy_indicator.dart';
import 'package:besser_bahn/widgets/platform_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The badges that carry meaning in colour and glyph alone (#74). What they say
/// out loud is the whole point, so it is worth pinning: a refactor that drops a
/// Semantics wrapper is invisible on screen and total silence in TalkBack.

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  testWidgets('delay badge says minutes, not "+5"', (tester) async {
    await _pump(tester, const DelayBadge(delaySeconds: 300));
    expect(find.bySemanticsLabel('5 Minuten Verspätung'), findsOneWidget);
  });

  testWidgets('cancelled badge says it falls out', (tester) async {
    await _pump(tester, const DelayBadge(cancelled: true));
    expect(find.bySemanticsLabel('Fällt aus'), findsOneWidget);
  });

  testWidgets('occupancy is spoken, not just coloured', (tester) async {
    await _pump(tester,
        const OccupancyIndicator(level: OccupancyLevel.high));
    expect(
      find.bySemanticsLabel(RegExp('^Auslastung: ')),
      findsOneWidget,
    );
  });

  testWidgets('platform chip names the track', (tester) async {
    await _pump(tester, const PlatformChip(platform: '5'));
    expect(find.bySemanticsLabel('Gleis 5'), findsOneWidget);
  });

  testWidgets('a moved platform says where it moved from', (tester) async {
    await _pump(
        tester, const PlatformChip(platform: '5', plannedPlatform: '7'));
    expect(find.bySemanticsLabel('Gleis 5, geändert von Gleis 7'),
        findsOneWidget);
  });

  testWidgets('platform badge speaks the same sentence as the chip',
      (tester) async {
    await _pump(
        tester, const PlatformBadge(platform: '5', plannedPlatform: '7'));
    expect(find.bySemanticsLabel('Gleis 5, geändert von Gleis 7'),
        findsOneWidget);
  });
}
