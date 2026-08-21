import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/extensions.dart';
import '../models/journey.dart';
import '../providers/service_providers.dart';
import '../services/location_service.dart';

/// Pre-departure companion for an upcoming trip: the live "Abfahrt in X Min"
/// countdown and the door-to-door "wann musst du los" walk estimate folded into
/// ONE compact card. It removes itself the moment the train has departed.
class DepartureCard extends ConsumerStatefulWidget {
  final Journey journey;
  const DepartureCard({super.key, required this.journey});

  @override
  ConsumerState<DepartureCard> createState() => _DepartureCardState();
}

class _DepartureCardState extends ConsumerState<DepartureCard> {
  static const _walkSpeedMps = 1.35; // ≈ 4.9 km/h
  static const _bufferMinutes = 3;

  Timer? _timer;
  bool _loading = false;
  int? _walkMinutes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DateTime? get _departure =>
      widget.journey.departure ?? widget.journey.plannedDeparture;

  Future<void> _computeWalk() async {
    final origin = widget.journey.origin;
    if (origin == null || !origin.hasLocation) {
      setState(() => _error = 'Für diese Station fehlen Koordinaten.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fix = await ref.read(locationServiceProvider).currentFix();
      final metres = const Distance().as(
        LengthUnit.Meter,
        fix.latLng,
        LatLng(origin.latitude!, origin.longitude!),
      );
      final mins = (metres / _walkSpeedMps / 60).ceil() + _bufferMinutes;
      if (mounted) {
        setState(() {
          _walkMinutes = mins;
          _loading = false;
        });
      }
    } on LocationException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Standort nicht verfügbar.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dep = _departure;
    final now = DateTime.now();
    // Gone once the train has left.
    if (dep == null || !dep.isAfter(now)) return const SizedBox.shrink();

    final mins = dep.difference(now).inMinutes;
    final origin = widget.journey.origin?.name ?? 'Start';
    final plat = widget.journey.legs
        .where((l) => !l.isWalking)
        .map((l) => l.departurePlatform ?? l.plannedDeparturePlatform)
        .firstWhere((p) => p != null, orElse: () => null);

    final walk = _walkMinutes;
    final leaveBy = walk != null ? dep.subtract(Duration(minutes: walk)) : null;
    final lateAlready = leaveBy != null && leaveBy.isBefore(now);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Countdown row.
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mins <= 0
                            ? 'Fährt jetzt ab'
                            : 'Abfahrt in ${_dur(mins)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      Text(
                        'ab $origin · ${dep.hhmm}'
                        '${plat != null ? ' · Gleis $plat' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(
              height: 18,
              color: theme.colorScheme.onSecondaryContainer.withValues(
                alpha: 0.2,
              ),
            ),
            // Leave-by row (door-to-door).
            Row(
              children: [
                Icon(
                  Icons.directions_walk,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: walk == null
                      ? Text(
                          _error ??
                              'Wann musst du los? Fußweg zu $origin berechnen.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _error != null
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSecondaryContainer,
                          ),
                        )
                      : Text(
                          lateAlready
                              ? 'Beeil dich — eigentlich schon los! (~$walk Min Fußweg)'
                              : 'Losgehen um ${leaveBy!.hhmm} · ~$walk Min Fußweg',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: lateAlready
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                ),
                _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        color: theme.colorScheme.onSecondaryContainer,
                        icon: Icon(
                          walk == null ? Icons.my_location : Icons.refresh,
                        ),
                        tooltip: 'Standort verwenden',
                        onPressed: _computeWalk,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dur(int minutes) {
    if (minutes < 60) return '$minutes Min';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m Min';
  }
}
