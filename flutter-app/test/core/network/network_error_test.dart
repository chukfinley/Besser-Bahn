import 'package:flutter_test/flutter_test.dart';

import 'package:besser_bahn/core/network/network_error.dart';

void main() {
  group('NetworkError', () {
    test('timeout error exposes its type', () {
      const error = NetworkError(
        type: NetworkErrorType.timeout,
        message: 'Request timed out',
      );

      expect(error.type, NetworkErrorType.timeout);
      expect(error.statusCode, isNull);
    });

    test('rate limited error keeps status code', () {
      const error = NetworkError(
        type: NetworkErrorType.rateLimited,
        message: 'Too many requests',
        statusCode: 429,
      );

      expect(error.type, NetworkErrorType.rateLimited);
      expect(error.statusCode, 429);
    });

    test('toString includes type and status code', () {
      const error = NetworkError(
        type: NetworkErrorType.badResponse,
        message: 'Bad response',
        statusCode: 503,
      );

      expect(
        error.toString(),
        'NetworkError.badResponse (HTTP 503): Bad response',
      );
    });
  });
}
