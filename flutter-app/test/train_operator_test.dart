import 'package:besser_bahn/utils/train_operator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('operatorFor (#operator)', () {
    test('erixx from the vendo kurztext, even when DB labels it RE 83', () {
      final op = operatorFor(
          productName: 'erx', product: 'regional', name: 'RE83');
      expect(op?.name, 'erixx');
    });

    test('operator short in the line name is also picked up', () {
      expect(operatorFor(productName: '', product: 'regional', name: 'ME 82')
          ?.name, 'metronom');
    });

    test('DB long-distance and regional fall back by product', () {
      expect(operatorFor(productName: 'ICE', product: 'nationalExpress')?.name,
          'DB Fernverkehr');
      expect(operatorFor(productName: 'RE', product: 'regional')?.name,
          'DB Regio');
      expect(operatorFor(productName: 'S', product: 'suburban')?.name,
          'DB Regio');
    });

    test('every operator carries a brand colour', () {
      final op = operatorFor(productName: 'erx', product: 'regional');
      expect(op, isNotNull);
      expect(op!.color, isNonZero);
    });

    test('unknown → null (no fake operator)', () {
      expect(operatorFor(productName: '', product: 'bus', name: ''), isNull);
    });
  });
}
