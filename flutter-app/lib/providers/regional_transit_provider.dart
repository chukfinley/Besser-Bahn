import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/journey.dart';
import '../models/station.dart';
import '../services/regional_transit_service.dart';

final regionalTransitServiceProvider =
    Provider<RegionalTransitService>((ref) => RegionalTransitService());

/// One "which bay does this bus really leave from" question.
class BayQuery {
  final Station stop;
  final String? line;
  final String? towards;
  final DateTime plannedDeparture;
  final String? product;

  const BayQuery({
    required this.stop,
    required this.plannedDeparture,
    this.line,
    this.towards,
    this.product,
    this.dbPlatform,
  });

  /// What DB itself says the platform is — kept so a disagreement can be shown
  /// as one ("NAH.SH: B2 · DB: B1") instead of silently replacing a value.
  final String? dbPlatform;

  /// The question a journey leg asks at its own origin.
  static BayQuery? forLeg(JourneyLeg leg) {
    final planned = leg.plannedDeparture ?? leg.departure;
    if (planned == null || leg.isWalking) return null;
    return BayQuery(
      stop: leg.origin,
      line: leg.line?.name,
      towards: leg.direction ?? leg.destination.name,
      plannedDeparture: planned,
      product: leg.line?.product,
      dbPlatform: leg.departurePlatform ?? leg.plannedDeparturePlatform,
    );
  }

  /// Whether it is worth asking at all — the cheap gates, so a Reiseplan full of
  /// ICEs anywhere but Schleswig-Holstein fires no requests.
  bool get worthAsking =>
      RegionalTransitService.coversProduct(product) &&
      RegionalTransitService.servesStop(stop);

  @override
  bool operator ==(Object other) =>
      other is BayQuery &&
      other.stop.id == stop.id &&
      other.line == line &&
      other.towards == towards &&
      other.plannedDeparture == plannedDeparture &&
      other.product == product &&
      other.dbPlatform == dbPlatform;

  @override
  int get hashCode =>
      Object.hash(stop.id, line, towards, plannedDeparture, product, dbPlatform);
}

/// The bay a bus has been moved to, or null when it has not been (which is the
/// overwhelming majority — see [NahShService]).
///
/// Never keeps the UI waiting and never fails it: unresolved and error both read
/// as "no correction", and the Reiseplan shows the timetable's bay as before.
final bayCorrectionProvider =
    FutureProvider.autoDispose.family<PlatformCorrection?, BayQuery>(
  (ref, query) async {
    if (!query.worthAsking) return null;
    // Hold the answer for the life of the screen rather than re-asking on every
    // rebuild; the board behind it is cached per quarter hour anyway.
    ref.keepAlive();
    return ref.read(regionalTransitServiceProvider).platformCorrection(
          stop: query.stop,
          line: query.line,
          towards: query.towards,
          plannedDeparture: query.plannedDeparture,
          product: query.product,
          dbPlatform: query.dbPlatform,
        );
  },
);
