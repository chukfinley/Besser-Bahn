import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besser_bahn/models/departure.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/screens/departure_board/departure_board_screen.dart';
import 'package:besser_bahn/theme/app_theme.dart';

Departure _dep({
  required String time,
  required String line,
  required String to,
  required List<String> via,
  String? platform,
  String? plannedPlatform,
  int? delay,
  bool cancelled = false,
  List<String> remarks = const [],
}) {
  final parts = time.split(':');
  final when = DateTime(
    2026,
    9,
    7,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );
  return Departure(
    tripId: '$line-$time',
    stop: const Station(id: '8000199', name: 'Kiel Hbf'),
    plannedWhen: when,
    when: when.add(Duration(seconds: delay ?? 0)),
    delay: delay,
    platform: platform,
    plannedPlatform: plannedPlatform ?? platform,
    direction: to,
    line: TransitLine(
      name: line,
      fahrtNr: '1',
      productName: line.split(' ').first,
      product: 'regional',
    ),
    cancelled: cancelled,
    remarks: remarks,
    via: via,
  );
}

final _board = [
  _dep(
    time: '15:25',
    line: 'RB75',
    to: 'Rendsburg',
    via: ['Kiel-Hassee CITTI-PARK', 'Kiel-Russee', 'Melsdorf', 'Achterwehr'],
    platform: '6a',
  ),
  _dep(
    time: '15:37',
    line: 'RE70',
    to: 'Hamburg Hbf',
    via: ['Bordesholm', 'Neumünster', 'Brokstedt', 'Wrist', 'Elmshorn'],
    platform: '4',
    delay: 300,
  ),
  _dep(
    time: '15:43',
    line: 'RE83',
    to: 'Lübeck Hbf (weiter nach Lüneburg)',
    via: ['Raisdorf', 'Preetz', 'Ascheberg(Holst)', 'Plön', 'Eutin'],
    platform: '1',
  ),
  _dep(
    time: '15:43',
    line: 'RE72',
    to: 'Eckernförde',
    via: ['Suchsdorf', 'Gettorf'],
    platform: '6a',
    cancelled: true,
    remarks: ['Halt entfällt'],
  ),
  _dep(
    time: '16:03',
    line: 'RE74',
    to: 'Husum',
    via: ['Felde', 'Rendsburg', 'Owschlag', 'Schleswig', 'Jübek'],
    platform: '6b',
    plannedPlatform: '5',
  ),
  _dep(
    time: '16:05',
    line: 'RB84',
    to: 'Lübeck Hbf',
    via: ['Plön', 'Bad Malente-Gremsmühlen', 'Eutin', 'Pönitz(Holst)'],
    platform: '1',
    delay: 60,
  ),
  _dep(
    time: '16:16',
    line: 'ICE 775',
    to: 'Stuttgart Hbf',
    via: ['Neumünster', 'Hamburg Hbf', 'Hannover Hbf', 'Frankfurt(Main)Hbf'],
    platform: '3',
  ),
  _dep(
    time: '16:21',
    line: 'Bus 14',
    to: 'Mettenhof',
    via: const [],
    platform: 'A1',
    delay: 120,
  ),
  _dep(
    time: '16:25',
    line: 'RB75',
    to: 'Rendsburg',
    via: ['Kiel-Hassee CITTI-PARK', 'Kiel-Russee', 'Melsdorf'],
    platform: '6b',
  ),
  _dep(
    time: '16:37',
    line: 'RE70',
    to: 'Hamburg Hbf',
    via: ['Bordesholm', 'Neumünster', 'Brokstedt', 'Wrist', 'Elmshorn'],
    platform: '5',
  ),
];

/// Real glyphs in the golden.
///
/// A widget test ships no fonts, so every string renders as a row of boxes and
/// the picture says nothing about how the layout reads. Loading a system font
/// under the family names the theme asks for fixes that — this golden exists to
/// be LOOKED at, not to be diffed byte-wise in CI.
Future<void> _loadFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const faces = {
    'Roboto': [
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    ],
  };
  for (final entry in faces.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final file = File(path);
      if (!file.existsSync()) return;
      loader.addFont(
        file.readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
    }
    await loader.load();
  }
}

void main() {
  // Real file I/O inside `testWidgets` never completes — the test binding fakes
  // time — so the fonts are loaded here, before any test runs.
  setUpAll(_loadFonts);

  testWidgets('board rows, dark', (tester) async {
    tester.view.physicalSize = const Size(1080, 1600);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ListView.separated(
            itemCount: _board.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 14),
            itemBuilder: (_, i) =>
                DepartureTile(departure: _board[i], onTap: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // How tall one row actually is — the number that decides how many
    // departures a rider sees without scrolling.
    final row = tester.getSize(find.byType(DepartureTile).first);
    debugPrint('row height: ${row.height}');

    expect(row.height, lessThan(56), reason: 'a board row must stay compact');

    // The picture is a *development* aid — something to look at when judging
    // the layout — not a CI gate: glyph rasterisation differs per machine, so
    // comparing it elsewhere would fail for no real reason. It is therefore
    // only written on `flutter test --update-goldens`, never compared.
    if (autoUpdateGoldenFiles) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/departure_board.png'),
      );
    }
  });
}
