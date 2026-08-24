import 'package:besser_bahn/theme/app_theme.dart';
import 'package:besser_bahn/vendor/chuk_ui/chuk_nav_bar.dart';
import 'package:besser_bahn/widgets/app_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four shell destinations, in the order HomeScreen wires them.
const _items = [
  ChukNavItem(
    icon: Icons.search_outlined,
    activeIcon: Icons.search,
    label: 'Suche',
  ),
  ChukNavItem(
    icon: Icons.bookmark_border,
    activeIcon: Icons.bookmark,
    label: 'Reisen',
  ),
  ChukNavItem(
    icon: Icons.train_outlined,
    activeIcon: Icons.train,
    label: 'Bahnhof',
  ),
  ChukNavItem(
    icon: Icons.account_circle_outlined,
    activeIcon: Icons.account_circle,
    label: 'Profil',
  ),
];

/// Pumps the nav bar exactly as the shell does: floating over a body, inside a
/// Material app so the token bridge has a ColorScheme to read.
Future<void> _pumpShell(
  WidgetTester tester, {
  int index = 0,
  ValueChanged<int>? onChanged,
  Widget? body,
  bool collapsed = false,
  EdgeInsets viewPadding = EdgeInsets.zero,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        // copyWith, not a fresh MediaQueryData: keep the test surface's size and
        // only fake the system inset (e.g. a home indicator).
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: viewPadding),
          child: Scaffold(
            extendBody: true,
            body: body ?? const SizedBox.expand(),
            bottomNavigationBar: AppNavBar(
              items: _items,
              index: index,
              collapsed: collapsed,
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('AppNavBar', () {
    testWidgets('renders every destination label', (tester) async {
      await _pumpShell(tester);

      for (final item in _items) {
        expect(find.text(item.label), findsOneWidget);
      }
    });

    testWidgets('tapping a destination reports its index', (tester) async {
      final tapped = <int>[];
      await _pumpShell(tester, onChanged: tapped.add);

      await tester.tap(find.text('Bahnhof'));
      await tester.tap(find.text('Suche'));
      await tester.pump();

      expect(tapped, [2, 0]);
    });

    testWidgets('shows the active icon only for the selected destination', (
      tester,
    ) async {
      await _pumpShell(tester, index: 1);

      // Selected → filled icon; the rest keep their outline variant.
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsNothing);
      expect(find.byIcon(Icons.search_outlined), findsOneWidget);
      expect(find.byIcon(Icons.search), findsNothing);
    });

    testWidgets(
      'every tab is a labelled button, and only one reads as selected',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpShell(tester, index: 2);

        for (final item in _items) {
          expect(
            tester.getSemantics(find.bySemanticsLabel(item.label)),
            matchesSemantics(
              label: item.label,
              isButton: true,
              hasSelectedState: true,
              isSelected: item.label == 'Bahnhof',
              // A reader must be able to both reach and press the tab, not just
              // read it out.
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
        }
        handle.dispose();
      },
    );

    testWidgets('keyboard focus activates a destination', (tester) async {
      final tapped = <int>[];
      await _pumpShell(tester, onChanged: tapped.add);

      // Tab to the first destination, then activate it like a keyboard user.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(
        tapped,
        isNotEmpty,
        reason: 'the bar must stay operable without a pointer',
      );
    });

    testWidgets(
      'floating bar reports its footprint as the body inset, safe area included',
      (tester) async {
        // The whole padding contract of the shell rests on this: the tabs pad
        // their lists by AppNavBar.insetOf, which is the body's bottom padding.
        late double inset;
        late Size bodySize;
        const homeIndicator = EdgeInsets.only(bottom: 34);

        await _pumpShell(
          tester,
          viewPadding: homeIndicator,
          body: Builder(
            builder: (context) {
              inset = AppNavBar.insetOf(context);
              bodySize = MediaQuery.sizeOf(context);
              return const SizedBox.expand();
            },
          ),
        );

        final barHeight = tester.getSize(find.byType(AppNavBar)).height;
        // 64 bar + 6 bottom margin + 34 home indicator.
        expect(barHeight, 104);
        expect(
          inset,
          barHeight,
          reason: 'lists must pad by exactly what the glass covers',
        );
        // extendBody: the body really does run the full height, under the bar.
        expect(tester.getSize(find.byType(Scaffold)).height, bodySize.height);
      },
    );

    testWidgets('collapsed drops the labels but a reader still gets them', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpShell(tester, index: 1, collapsed: true);
      await tester.pumpAndSettle();

      for (final item in _items) {
        // Nothing left on screen to read out…
        expect(find.text(item.label), findsNothing);
        // …so the tab's own node has to carry the name, or the bar degrades
        // into four unlabelled buttons the moment the user scrolls.
        expect(
          tester.getSemantics(find.bySemanticsLabel(item.label)),
          matchesSemantics(
            label: item.label,
            isButton: true,
            hasSelectedState: true,
            isSelected: item.label == 'Reisen',
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
      }
      handle.dispose();
    });

    testWidgets(
      'collapsing shrinks the pill but never the inset the tabs pad by',
      (tester) async {
        // The anti-feedback contract. Every tab pads its scrollables by
        // AppNavBar.insetOf, so a footprint that shrank mid-scroll would move
        // maxScrollExtent — which is an input to whether the bar collapses at
        // all. The bar reserves its expanded footprint permanently instead and
        // only shrinks the pill inside it.
        const homeIndicator = EdgeInsets.only(bottom: 34);
        late double inset;

        Future<void> pump({required bool collapsed}) => _pumpShell(
          tester,
          collapsed: collapsed,
          viewPadding: homeIndicator,
          body: Builder(
            builder: (context) {
              inset = AppNavBar.insetOf(context);
              return const SizedBox.expand();
            },
          ),
        );

        await pump(collapsed: false);
        await tester.pumpAndSettle();
        final expandedInset = inset;
        final expandedPill = tester.getRect(find.byType(ChukNavBar));

        await pump(collapsed: true);
        await tester.pumpAndSettle();
        final collapsedPill = tester.getRect(find.byType(ChukNavBar));

        // 64 → 52: the pill really does get smaller, which is the whole ask.
        expect(
          collapsedPill.height,
          lessThan(expandedPill.height),
          reason: 'collapsed must actually shrink the glass, not just the text',
        );
        // …upward, from a fixed bottom edge — the pill stays under the thumb.
        expect(collapsedPill.bottom, expandedPill.bottom);
        // …inside an unchanged footprint. These two are what the Scaffold
        // measures and hands the body; if either moves, every list in the app
        // re-lays out mid-scroll.
        expect(tester.getSize(find.byType(AppNavBar)).height, 104);
        expect(
          inset,
          expandedInset,
          reason: 'lists must pad by the same number, collapsed or not',
        );
      },
    );
  });
}
