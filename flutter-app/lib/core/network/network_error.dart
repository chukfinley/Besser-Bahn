enum NetworkErrorType {
  timeout,
  rateLimited,
  unavailable,
  badResponse,
  unknown,
}

class NetworkError implements Exception {
  final NetworkErrorType type;
  final String message;
  final int? statusCode;
  final Object? cause;

  const NetworkError({
    required this.type,
    required this.message,
    this.statusCode,
    this.cause,
  });

  @override
  String toString() {
    final status = statusCode != null ? ' (HTTP $statusCode)' : '';
    return 'NetworkError.${type.name}$status: $message';
  }
}
