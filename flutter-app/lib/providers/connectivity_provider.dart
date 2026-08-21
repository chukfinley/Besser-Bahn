import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Online/offline state of the device, streamed from `connectivity_plus`.
///
/// This reflects whether a network *interface* is up (Wi-Fi/mobile), not
/// whether DB's servers are reachable — good enough to tell the user "you're
/// offline, this is cached" and to skip doomed requests. The app's saved data
/// (favorites, recents, saved Reisen/trains) lives in SharedPreferences and the
/// map tiles/polylines are cached on disk, so those screens keep working.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final conn = Connectivity();
  bool isOnline(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);
  // Seed with the current state, then follow changes.
  yield isOnline(await conn.checkConnectivity());
  yield* conn.onConnectivityChanged.map(isOnline);
});

/// Convenience: true when we believe the device is offline. Defaults to online
/// while the first reading is in flight (don't flash an offline banner on
/// startup).
final isOfflineProvider = Provider<bool>((ref) {
  return ref
      .watch(connectivityProvider)
      .maybeWhen(data: (online) => !online, orElse: () => false);
});
