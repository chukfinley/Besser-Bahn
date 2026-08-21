import 'package:besser_bahn/theme/app_theme.dart';
import 'package:besser_bahn/vendor/chuk_ui/chuk_glass.dart';
import 'package:besser_bahn/widgets/glass_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The floating switcher that replaced the Bahnhof screen's AppBar + TabBar.
///
/// It is the nav bar's pill moved to the top, and it makes the nav bar's
/// bargain: it floats over the content, so the content has to be told what it
/// covers. [GlassSwitcher.insetOf] is that number and it is a *constant* — so
/// the test that matters most here is the one that pins it against the real
/// laid-out pill. A drift there would silently strand the top of every view on
/// the screen under the glass.

const _items = [
  GlassSwitcherItem(
    icon: Icons.train_outlined,
    activeIcon: Icons.train,
    label: 'Zug',
  ),
  GlassSwitcherItem(
    icon: Icons.departure_board_outlined,
    activeIcon: Icons.departure_board,
    label: 'Abfahrten',
  ),
  GlassSwitcherItem(
    icon: Icons.map_outlined,
    activeIcon: Icons.map,
    label: 'Karte',
  ),
];

/// Pumps the switcher the way `NearbyScreen` does: floating in a Stack over a
/// body, inside its own SafeArea.
Future<double> _pump(
  WidgetTester tester, {
  int index = 0,
  ValueChanged<int>? onChanged,
  Widget? trailing,
  Brightness brightness = Brightness.dark,
  EdgeInsets viewPadding = EdgeInsets.zero,
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late double inset;
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: Builder(
        builder: (context) => MediaQuery(
          // copyWith, not a fresh MediaQueryData: keep the test surface's size
          // and only fake the system inset (the status bar).
          data: MediaQuery.of(context).copyWith(padding: viewPadding),
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Builder(
                    builder: (context) {
                      inset = GlassSwitcher.insetOf(context);
                      return const ColoredBox(color: Colors.teal);
                    },
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: GlassSwitcher(
                      items: _items,
                      index: index,
                      onChanged: onChanged ?? (_) {},
                      trailing: trailing,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return inset;
}

void main() {
  group('insetOf is what the pill really covers', () {
    testWidgets('to the pixel, with no system inset', (tester) async {
      final inset = await _pump(tester);
      expect(
        tester.getRect(find.byType(GlassSwitcher)).bottom,
        moreOrLessEquals(inset, epsilon: 0.5),
        reason: 'content padded by insetOf must start exactly below the pill',
      );
    });

    testWidgets('and it carries the status bar', (tester) async {
      // A screen with no AppBar keeps the status-bar inset in its body — the
      // switcher wears it via its own SafeArea, so insetOf has to include it or
      // the pill would eat the first 24 px of every view under it.
      const statusBar = EdgeInsets.only(top: 24);
      final inset = await _pump(tester, viewPadding: statusBar);
      expect(
        tester.getRect(find.byType(GlassSwitcher)).bottom,
        moreOrLessEquals(inset, epsilon: 0.5),
      );
    });

    testWidgets('the whole pill is far slimmer than the bar it replaced', (
      tester,
    ) async {
      final inset = await _pump(tester);
      // What was there: kToolbarHeight (56) + an icon-and-text TabBar (72) =
      // 128 px of chrome before the first departure. The number is the entire
      // point of this screen, so it is pinned rather than described.
      expect(inset, moreOrLessEquals(58, epsilon: 0.5));
      expect(
        128 - inset,
        greaterThanOrEqualTo(70),
        reason: 'px of screen handed back to the content',
      );
    });
  });

  group('only the selected segment is labelled', () {
    testWidgets('the label follows the selection', (tester) async {
      await _pump(tester, index: 1);
      expect(find.text('Abfahrten'), findsOneWidget);
      expect(find.text('Zug'), findsNothing);
      expect(find.text('Karte'), findsNothing);
      // Every segment is still *there* — the unselected ones are their icon.
      expect(find.byIcon(Icons.train_outlined), findsOneWidget);
      expect(find.byIcon(Icons.departure_board), findsOneWidget);
      expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    });

    testWidgets('a screen reader still gets every segment by name', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, index: 1);

      // The unlabelled ones name themselves in Semantics; the selected one is
      // named by the Text on screen (naming it twice would make a reader say
      // it twice).
      expect(
        find.bySemanticsLabel('Zug'),
        findsOneWidget,
        reason: 'an icon-only segment must still announce what it is',
      );
      expect(find.bySemanticsLabel('Karte'), findsOneWidget);
      expect(find.bySemanticsLabel('Abfahrten'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('tapping a segment reports it — anywhere in the slot', (
    tester,
  ) async {
    final taps = <int>[];
    await _pump(tester, index: 0, onChanged: taps.add);

    // Not on the glyph: on the slot. The whole third of the pill is the target.
    final pill = tester.getRect(find.byType(GlassSwitcher));
    await tester.tapAt(Offset(pill.width * 5 / 6, pill.center.dy));
    await tester.pumpAndSettle();

    expect(taps, [2]);
  });

  testWidgets('the trailing action sits outside the pill and works', (
    tester,
  ) async {
    var pressed = false;
    await _pump(
      tester,
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () => pressed = true,
      ),
    );

    // Two panes of glass: the pill, and the action's own button.
    expect(find.byType(ChukGlass), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.more_vert));
    expect(pressed, isTrue);
  });

  group('the glass is glass', () {
    testWidgets('translucent and blurred, in both themes', (tester) async {
      for (final brightness in Brightness.values) {
        await _pump(
          tester,
          brightness: brightness,
          trailing: const Icon(Icons.more_vert),
        );
        for (final pane in tester.widgetList<ChukGlass>(
          find.byType(ChukGlass),
        )) {
          // An opaque tint is the massive block again, only shorter.
          expect(pane.fill.a, lessThan(1.0), reason: '$brightness');
          expect(pane.blurSigma, greaterThan(0), reason: '$brightness');
        }
      }
    });
  });

  testWidgets('no overflow on a narrow screen, labels and action and all', (
    tester,
  ) async {
    // 320 px with the longest label selected and the menu next to it — the
    // shape that would find the "3 px overflow" if the pill had one.
    await _pump(
      tester,
      size: const Size(320, 640),
      index: 1,
      trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Abfahrten'), findsOneWidget);
  });
}
