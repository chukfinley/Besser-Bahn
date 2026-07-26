/// Breaking one trip into two that are *not* chained.
///
/// A normal search treats the ride as one thing: DB picks the fastest chain and
/// the change at the hub is as short as it can make it. Sometimes the trip isn't
/// one thing — "be at the dentist by 09:48, and I don't mind killing an hour in
/// Kiel first". The second leg is then nailed to the appointment and the first
/// one is free to be much earlier, with the gap between them being the point
/// rather than a cost.
///
/// Two independent arrival searches, joined by these rules. Nothing here talks
/// to the network.
library;

import '../models/journey.dart';

/// Default stay at the hub, in minutes — enough to actually leave the station.
const int kDefaultStayMinutes = 60;

/// Stays the UI offers, in minutes.
const List<int> kStayChoices = [15, 30, 60, 90, 120, 180];

/// The connection to nail the plan to: the *latest* one that still gets in by
/// [deadline]. Latest, not fastest — every minute it departs later is a minute
/// the rider keeps for the leg before it.
///
/// Cancelled connections are skipped: a dead train is not a plan, and picking
/// one would silently anchor everything else to it.
Journey? latestArrivingBy(List<Journey> journeys, DateTime deadline) {
  Journey? best;
  DateTime? bestDeparture;
  DateTime? bestArrival;
  for (final j in journeys) {
    if (j.hasCancelledLeg) continue;
    final arrival = j.arrival ?? j.plannedArrival;
    final departure = j.departure ?? j.plannedDeparture;
    if (arrival == null || departure == null) continue;
    if (arrival.isAfter(deadline)) continue;
    if (bestDeparture == null ||
        departure.isAfter(bestDeparture) ||
        // Same departure: prefer the one that gets in later — it is the one with
        // slack of its own, and both leave the first leg the same room.
        (departure == bestDeparture && arrival.isAfter(bestArrival!))) {
      best = j;
      bestDeparture = departure;
      bestArrival = arrival;
    }
  }
  return best;
}

/// How long the rider is at the hub between [first] arriving and [second]
/// leaving. Negative would mean the second train is already gone; null when
/// either end has no time.
Duration? stayBetween(Journey first, Journey second) {
  final arrival = first.arrival ?? first.plannedArrival;
  final departure = second.departure ?? second.plannedDeparture;
  if (arrival == null || departure == null) return null;
  return departure.difference(arrival);
}

/// First-leg candidates that leave at least [minStayMinutes] at the hub before
/// [hubDeparture].
///
/// Chronological, like every other result list in the app — which here also
/// means the longest stay is on top and each row down the list is a later start
/// with less time at the hub. The stay is labelled per row, so the order carries
/// no meaning the rider has to infer.
List<Journey> firstLegOptions(
  List<Journey> journeys,
  DateTime hubDeparture, {
  required int minStayMinutes,
}) {
  final kept = <(Journey, DateTime)>[];
  for (final j in journeys) {
    if (j.hasCancelledLeg) continue;
    final arrival = j.arrival ?? j.plannedArrival;
    if (arrival == null) continue;
    final stay = hubDeparture.difference(arrival);
    if (stay.isNegative || stay.inMinutes < minStayMinutes) continue;
    kept.add((j, arrival));
  }
  kept.sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final e in kept) e.$1];
}

/// "1 h 20" / "45 min" — how a stay reads.
String formatStay(Duration stay) {
  final minutes = stay.inMinutes;
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}
