import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/platform_train.dart'
    show ExitSide, exitSideOf, resolveIsland, normalizeGleis;
import '../../../models/journey.dart';
import '../../../models/station.dart';
import '../../../models/station_map.dart';
import '../../../providers/service_providers.dart';

/// A tiny left/right arrow that says which side to get on ([boarding] true) or
/// off ([boarding] false) at [station], in the train's direction of travel —
/// squeezed in right next to the Gleis number.
///
/// The side is pure geometry: the leg's travel direction (its approach or
/// departure segment) crossed with where the platform sits relative to its
/// track, from the bahnhof.de station map. Best-effort and heavily guarded —
/// no map, no island platform, or a platform sitting on the track line all
/// render nothing (an [SizedBox.shrink]), never a guess.
class ExitSideArrow extends ConsumerStatefulWidget {
  /// The train this side is about: the arriving train for an Ausstieg, the
  /// departing train for an Einstieg.
  final JourneyLeg leg;

  /// The stop where it happens (the leg's destination for an Ausstieg, its
  /// origin for an Einstieg).
  final Station station;

  /// The Gleis the train uses at [station].
  final String gleis;

  /// true = Einstieg (get on the departing train), false = Ausstieg.
  final bool boarding;

  const ExitSideArrow({
    super.key,
    required this.leg,
    required this.station,
    required this.gleis,
    required this.boarding,
  });

  @override
  ConsumerState<ExitSideArrow> createState() => _ExitSideArrowState();
}

class _ExitSideArrowState extends ConsumerState<ExitSideArrow> {
  ExitSide _side = ExitSide.unknown;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ExitSideArrow old) {
    super.didUpdateWidget(old);
    if (old.leg.tripId != widget.leg.tripId ||
        old.gleis != widget.gleis ||
        old.boarding != widget.boarding) {
      _side = ExitSide.unknown;
      _load();
    }
  }

  Future<void> _load() async {
    final side = await _compute();
    if (mounted && side != _side) setState(() => _side = side);
  }

  Future<ExitSide> _compute() async {
    try {
      final gleis = normalizeGleis(widget.gleis);
      if (gleis.isEmpty) return ExitSide.unknown;

      // Travel direction: the leg's approach segment (…→station) for an
      // Ausstieg, its departure segment (station→…) for an Einstieg.
      final pts = <LatLng>[
        if (widget.leg.origin.hasLocation)
          LatLng(widget.leg.origin.latitude!, widget.leg.origin.longitude!),
        for (final s in widget.leg.stopovers)
          if (s.stop.hasLocation)
            LatLng(s.stop.latitude!, s.stop.longitude!),
        if (widget.leg.destination.hasLocation)
          LatLng(
            widget.leg.destination.latitude!,
            widget.leg.destination.longitude!,
          ),
      ];
      if (pts.length < 2) return ExitSide.unknown;
      final LatLng travelFrom, travelTo;
      if (widget.boarding) {
        travelFrom = pts.first;
        travelTo = pts[1];
      } else {
        travelFrom = pts[pts.length - 2];
        travelTo = pts.last;
      }

      final svc = ref.read(stationMapServiceProvider);
      final name = widget.station.name;
      StationMap map =
          svc.cachedByName(name) ??
          await svc.fetchByStationName(name, background: true);

      MapPoi? plat;
      for (final p in map.platforms) {
        if (normalizeGleis(p.name) == gleis) {
          plat = p;
          break;
        }
      }
      if (plat == null) return ExitSide.unknown;
      final island = resolveIsland(map, plat, gleis, 0, 8);
      final rail = LatLng(
        plat.latitude + island.dLat,
        plat.longitude + island.dLon,
      );
      return exitSideOf(
        travelFrom: travelFrom,
        travelTo: travelTo,
        track: rail,
        platform: plat.latLng,
      );
    } catch (_) {
      return ExitSide.unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_side == ExitSide.unknown) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final right = _side == ExitSide.right;
    // Einstieg green, Ausstieg red — the same colour language the transfer map
    // uses for the two roles.
    final color = widget.boarding
        ? const Color(0xFF1E8E3E)
        : theme.colorScheme.error;
    final arrow = right
        ? Icons.arrow_forward_rounded
        : Icons.arrow_back_rounded;
    final door = widget.boarding ? Icons.login_rounded : Icons.logout_rounded;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(door, size: 15, color: color),
          const SizedBox(width: 3),
          Icon(arrow, size: 17, color: color),
          const SizedBox(width: 2),
          Text(
            right ? 'rechts' : 'links',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
