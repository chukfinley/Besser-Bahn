import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/library_models.dart';
import '../utils/construction_radar.dart';
import 'library_provider.dart';
import 'service_providers.dart';

/// One saved route that has a known construction disruption on an upcoming day
/// (#62).
class ConstructionAlert {
  final SavedRoute route;

  /// De-duplicated construction notes found across the sampled days.
  final List<String> notes;

  const ConstructionAlert({required this.route, required this.notes});

  String get routeLabel => '${route.from.name} → ${route.to.name}';
}

/// Days ahead to probe for each saved route. Spread out so a closure announced
/// weeks in advance is caught, not just tomorrow's. Kept small — each entry is
/// one connection search per route.
const _kSampleDaysAhead = <int>[1, 7, 14];

/// Scans the user's saved routes for planned construction / replacement-service
/// disruptions on upcoming days (#62). Runs on demand (when the Reisen tab is
/// opened), not in the background — the app has no periodic scheduler — but that
/// still surfaces a closure days before the trip instead of at the platform.
///
/// Non-blocking by construction: every search is wrapped, a dead API just
/// yields no alert for that route rather than hanging the screen, and the DB
/// data the app already shows stays untouched.
final constructionRadarProvider =
    FutureProvider.autoDispose<List<ConstructionAlert>>((ref) async {
      final routes = ref.watch(libraryProvider).routes;
      if (routes.isEmpty) return const [];

      final vendo = ref.read(vendoServiceProvider);
      final now = DateTime.now();

      Future<ConstructionAlert?> scan(SavedRoute route) async {
        if (route.from.id.isEmpty || route.to.id.isEmpty) return null;
        final notes = <String>{};
        for (final days in _kSampleDaysAhead) {
          final when = DateTime(now.year, now.month, now.day + days, 12);
          try {
            final result = await vendo
                .searchJourneys(
                  fromLocationId: route.from.id,
                  toLocationId: route.to.id,
                  dateTime: when,
                )
                .timeout(const Duration(seconds: 8));
            for (final j in result.journeys) {
              notes.addAll(constructionNotes(j.disruptions));
            }
          } catch (_) {
            // Dead/slow API or no connections for that day — skip, don't fail the
            // whole radar.
          }
        }
        if (notes.isEmpty) return null;
        return ConstructionAlert(route: route, notes: notes.toList());
      }

      final results = await Future.wait(routes.map(scan));
      return results.whereType<ConstructionAlert>().toList();
    });
