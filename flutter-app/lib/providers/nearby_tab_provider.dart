import 'package:flutter_riverpod/flutter_riverpod.dart';

const nearbyTabTrain = 0;
const nearbyTabDepartures = 1;
const nearbyTabMap = 2;

/// Selected sub-tab of the combined "Bahnhof" screen:
/// 0 = Zug, 1 = Abfahrten, 2 = Karte.
///
/// Lets other screens (e.g. tapping a departure → open that train) jump to a
/// specific sub-tab without route plumbing.
class NearbyTabNotifier extends Notifier<int> {
  @override
  int build() => nearbyTabDepartures;

  void select(int index) => state = index;
}

final nearbyTabProvider = NotifierProvider<NearbyTabNotifier, int>(
  NearbyTabNotifier.new,
);
