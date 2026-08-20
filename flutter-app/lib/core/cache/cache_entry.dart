class CacheEntry<T> {
  final T data;
  final DateTime createdAt;

  const CacheEntry({required this.data, required this.createdAt});

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(createdAt) > ttl;
  }
}
