import 'package:flutter_test/flutter_test.dart';

import 'package:besser_bahn/core/network/network_policy.dart';

void main() {
  group('NetworkPolicy', () {
    test('standard policy has expected defaults', () {
      expect(NetworkPolicy.standard.timeout, const Duration(seconds: 15));
      expect(NetworkPolicy.standard.maxRetries, 2);
      expect(
        NetworkPolicy.standard.initialBackoff,
        const Duration(milliseconds: 500),
      );
    });

    test('critical policy allows more retries', () {
      expect(
        NetworkPolicy.critical.maxRetries,
        greaterThan(NetworkPolicy.standard.maxRetries),
      );

      expect(
        NetworkPolicy.critical.timeout,
        greaterThan(NetworkPolicy.standard.timeout),
      );
    });
  });
}
