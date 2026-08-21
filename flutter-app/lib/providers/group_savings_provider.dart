import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_log.dart';
import '../models/journey.dart';
import 'journey_search_provider.dart';
import 'service_providers.dart';
import 'settings_provider.dart';

/// What one connection costs booked together vs. booked one ticket at a time
/// (#67).
class GroupSaving {
  /// Departure of the connection this is about — the key the UI matches on.
  final DateTime departure;

  /// Total for the whole party in one booking.
  final double groupTotal;

  /// The same party as N separate single-traveller bookings.
  final double singlesTotal;

  const GroupSaving({
    required this.departure,
    required this.groupTotal,
    required this.singlesTotal,
  });

  /// Euros saved by booking separately. Negative means the group booking wins,
  /// which is the normal case and shows nothing.
  double get savings => groupTotal - singlesTotal;
}

/// Whether booking the party separately would be cheaper than one group
/// booking (#67).
///
/// Sounds impossible and isn't: DB prices a booking against the *cheapest
/// contingent that fits everyone*. With three Sparpreis seats left and four
/// travellers, one booking bumps all four to the next fare, while four separate
/// bookings take the three cheap seats and one expensive one. The app already
/// has the group price from the search; this asks the same search once more for
/// a single traveller and multiplies.
///
/// Costs exactly one extra request per search, and only when the party is
/// actually bigger than one person — /mob rate-limits per client, so this is
/// deliberately not per-connection.
///
/// Returns an empty list on any failure: a missing comparison is a missing
/// hint, never an error in the rider's face.
final groupSavingsProvider = FutureProvider.autoDispose<List<GroupSaving>>((
  ref,
) async {
  final settings = ref.watch(settingsProvider);
  final party = settings.searchParty;
  final state = ref.watch(journeySearchProvider);
  final result = state.result;

  if (party.personCount < 2 || result == null) return const [];
  final from = state.from, to = state.to;
  if (from == null || to == null) return const [];

  // Group prices we can compare against, keyed by departure.
  final groupPrices = <DateTime, double>{};
  for (final j in result.journeys) {
    final dep = j.plannedDeparture, price = j.price?.amount;
    if (dep != null && price != null && price > 0) groupPrices[dep] = price;
  }
  if (groupPrices.isEmpty) return const [];

  try {
    final singles = await ref
        .read(vendoServiceProvider)
        .searchJourneys(
          fromLocationId: from.vendoLocationId,
          toLocationId: to.vendoLocationId,
          dateTime: state.dateTime ?? DateTime.now(),
          isArrival: state.useArrival,
          firstClass: party.firstClass,
          // The same trip for exactly one adult, carrying the party's own
          // discounts so the comparison is like-for-like. Bike/dog stay out:
          // those are per-booking extras, not per-person fares.
          reisende: party.toSingleTravellerJson(),
          deutschlandTicket: party.deutschlandTicket,
          verkehrsmittel: ProductCategory.codesFor(state.products),
          nurDeutschlandTicketVerbindungen: state.onlyDeutschlandTicket,
          maxTransfers: state.options.maxTransfers,
          viaLocations: state.options.viaLocationsJson,
        );

    final out = <GroupSaving>[];
    for (final j in singles.journeys) {
      final dep = j.plannedDeparture;
      final single = j.price?.amount;
      final group = dep == null ? null : groupPrices[dep];
      if (dep == null || single == null || group == null || single <= 0) {
        continue;
      }
      out.add(
        GroupSaving(
          departure: dep,
          groupTotal: group,
          singlesTotal: single * party.personCount,
        ),
      );
    }
    return out;
  } catch (e) {
    AppLog.log('group savings check failed: $e', tag: 'price');
    return const [];
  }
});

/// The saving for one connection, or null when there is nothing to say.
///
/// Only speaks above a euro: DB's fares carry rounding, and "spare 0,02 €" is
/// noise that makes the honest hints look cheap too.
GroupSaving? groupSavingFor(List<GroupSaving> all, Journey journey) {
  final dep = journey.plannedDeparture;
  if (dep == null) return null;
  for (final s in all) {
    if (s.departure == dep && s.savings >= 1) return s;
  }
  return null;
}
