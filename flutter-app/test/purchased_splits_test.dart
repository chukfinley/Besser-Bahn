import 'package:besser_bahn/models/purchased_split.dart';
import 'package:besser_bahn/providers/purchased_splits_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future.delayed(const Duration(milliseconds: 10));

PurchasedSplit _split(
  String route, {
  double direct = 50,
  double split = 30,
  String? dep,
}) => PurchasedSplit(
  routeLabel: route,
  directPrice: direct,
  splitPrice: split,
  purchasedAtMs: DateTime.now().millisecondsSinceEpoch,
  departureIso: dep,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PurchasedSplit model (#70)', () {
    test('savings never negative', () {
      expect(_split('A→B', direct: 40, split: 30).savings, 10);
      expect(_split('A→B', direct: 20, split: 30).savings, 0);
    });

    test('round-trips through json', () {
      final s = _split('Kiel → Hamburg', dep: '2026-08-01T09:00:00');
      final back = PurchasedSplit.fromJson(s.toJson());
      expect(back.routeLabel, s.routeLabel);
      expect(back.directPrice, s.directPrice);
      expect(back.splitPrice, s.splitPrice);
      expect(back.departureIso, s.departureIso);
    });
  });

  group('purchasedSplitsProvider (#70)', () {
    test('adds and totals savings, survives a restart', () async {
      final c1 = ProviderContainer();
      await c1.read(purchasedSplitsProvider.notifier).add(_split('A→B'));
      await c1.read(purchasedSplitsProvider.notifier).add(_split('C→D'));
      expect(c1.read(purchasedSplitsProvider.notifier).totalSavings, 40);
      c1.dispose();

      final c2 = ProviderContainer();
      c2.read(purchasedSplitsProvider);
      await _settle();
      expect(c2.read(purchasedSplitsProvider).length, 2);
      expect(c2.read(purchasedSplitsProvider.notifier).totalSavings, 40);
      c2.dispose();
    });

    test('same route + departure is not double-counted', () async {
      final c = ProviderContainer();
      final n = c.read(purchasedSplitsProvider.notifier);
      await n.add(
        _split('A→B', direct: 50, split: 30, dep: '2026-08-01T09:00'),
      );
      await n.add(
        _split('A→B', direct: 60, split: 30, dep: '2026-08-01T09:00'),
      );
      expect(c.read(purchasedSplitsProvider).length, 1);
      // The later confirmation wins.
      expect(n.totalSavings, 30);
      expect(n.contains('A→B|2026-08-01T09:00'), isTrue);
      c.dispose();
    });

    test('a different departure is a separate purchase', () async {
      final c = ProviderContainer();
      final n = c.read(purchasedSplitsProvider.notifier);
      await n.add(_split('A→B', dep: '2026-08-01T09:00'));
      await n.add(_split('A→B', dep: '2026-08-02T09:00'));
      expect(c.read(purchasedSplitsProvider).length, 2);
      c.dispose();
    });
  });
}
