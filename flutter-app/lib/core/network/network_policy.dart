class NetworkPolicy {
  final Duration timeout;
  final int maxRetries;
  final Duration initialBackoff;

  const NetworkPolicy({
    required this.timeout,
    required this.maxRetries,
    required this.initialBackoff,
  });

  Duration backoffForAttempt(int attempt) {
    return initialBackoff * (1 << attempt);
  }

  static const standard = NetworkPolicy(
    timeout: Duration(seconds: 15),
    maxRetries: 2,
    initialBackoff: Duration(milliseconds: 500),
  );

  static const critical = NetworkPolicy(
    timeout: Duration(seconds: 20),
    maxRetries: 3,
    initialBackoff: Duration(milliseconds: 750),
  );
}
