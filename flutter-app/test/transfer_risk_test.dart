import 'package:besser_bahn/utils/transfer_risk.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime t(int h, int m) => DateTime(2026, 8, 2, h, m);

void main() {
  group('worstTransferGapMinutes (#live)', () {
    test('null when there is no transfer', () {
      expect(worstTransferGapMinutes([(arr: t(9, 0), dep: t(8, 0))]), isNull);
      expect(worstTransferGapMinutes([]), isNull);
    });

    test('returns the tightest change', () {
      // RE10 arr 16:10 → ICE dep 16:36 (26), ICE arr 17:25 → RE83 dep 17:44 (19)
      final gap = worstTransferGapMinutes([
        (arr: t(16, 10), dep: t(15, 44)),
        (arr: t(17, 25), dep: t(16, 36)),
        (arr: t(20, 16), dep: t(17, 44)),
      ]);
      expect(gap, 19);
    });

    test('goes negative when a live delay blows a change (the #live bug)', () {
      // ICE +23 → arr Lüneburg 17:48, RE83 dep 17:44 → missed by 4.
      final gap = worstTransferGapMinutes([
        (arr: t(16, 10), dep: t(15, 44)),
        (arr: t(17, 48), dep: t(16, 36)),
        (arr: t(20, 16), dep: t(17, 44)),
      ]);
      expect(gap, -4);
    });

    test('skips legs with missing times rather than crashing', () {
      final gap = worstTransferGapMinutes([
        (arr: null, dep: t(15, 44)),
        (arr: t(17, 25), dep: t(16, 36)),
        (arr: t(20, 16), dep: t(17, 44)),
      ]);
      expect(gap, 19); // only the second change is measurable
    });
  });
}
