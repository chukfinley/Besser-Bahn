import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/coach_sequence.dart';
import '../../../models/journey.dart';
import '../../../providers/service_providers.dart';
import '../../../utils/transfer_coach_advice.dart';

/// "Für den Umstieg in Abschnitt C" under a transfer (#27).
///
/// Deliberately quiet: a thin outlined row, not a banner. It's a time-saver,
/// not a warning — the loud red block is reserved for the wing-train split,
/// where boarding wrong means not arriving.
///
/// Renders NOTHING at all (zero-height) whenever [transferCoachAdvice] can't
/// back a recommendation — see that function for every silence. This widget
/// adds one of its own: it never shows a spinner or a placeholder, because a
/// hint that might still turn out to be nothing shouldn't reserve space and
/// make the transfer jump around while it loads.
class TransferCoachHint extends ConsumerStatefulWidget {
  /// The train being left. Its Wagenreihung is fetched AT THE TRANSFER STOP —
  /// its composition at its own origin says nothing about the section it stops
  /// in here.
  final JourneyLeg arriving;

  /// The train being caught. The transfer stop is this leg's origin, so its
  /// sequence is the one the leg section already fetches — the service cache
  /// hands it over without a second request.
  final JourneyLeg departing;

  /// DB's `weiterfahrtAmGleichenBahnsteig` for this change.
  final bool samePlatform;

  const TransferCoachHint({
    super.key,
    required this.arriving,
    required this.departing,
    required this.samePlatform,
  });

  @override
  ConsumerState<TransferCoachHint> createState() => _TransferCoachHintState();
}

class _TransferCoachHintState extends ConsumerState<TransferCoachHint> {
  TransferCoachAdvice? _advice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TransferCoachHint old) {
    super.didUpdateWidget(old);
    if (widget.arriving.tripId != old.arriving.tripId ||
        widget.departing.tripId != old.departing.tripId) {
      _advice = null;
      _load();
    }
  }

  Future<void> _load() async {
    final arr = widget.arriving;
    final dep = widget.departing;
    // The transfer stop: where the first train stops and the second starts.
    final eva = dep.origin.id;
    if (eva.isEmpty) return;

    final service = ref.read(coachSequenceServiceProvider);
    // SCHEDULED times, not live ones: the endpoint resolves a run by its
    // timetable slot, so handing it a delayed time just misses. For an on-time
    // train the two are identical anyway — which also means the departing
    // train's lookup usually reuses the sequence the leg section already
    // fetched (same service cache key) instead of costing a request.
    //
    // The arriving train is keyed by its ARRIVAL here: this stop is mid-run for
    // it and the leg's stop list ends at the rider's alight, so there's no
    // onward departure time to ask with. Verified live — RJ 175 asked for by
    // its Berlin Hbf arrival returns its Gleis-3 sequence. Where a train/stop
    // isn't served the endpoint 404s and we simply stay quiet.
    final arrivingFuture = service
        .getCoachSequenceForDeparture(
          category: arr.line?.productName ?? '',
          trainNumber: arr.line?.fahrtNr ?? '',
          stationEva: eva,
          departureTime: arr.plannedArrival ?? arr.arrival,
        )
        .catchError((_) => null);
    final departingFuture = service
        .getCoachSequenceForDeparture(
          category: dep.line?.productName ?? '',
          trainNumber: dep.line?.fahrtNr ?? '',
          stationEva: eva,
          departureTime: dep.plannedDeparture ?? dep.departure,
        )
        .catchError((_) => null);

    CoachSequence? arriving;
    CoachSequence? departing;
    try {
      arriving = await arrivingFuture;
      departing = await departingFuture;
    } catch (_) {
      return; // optional garnish — never surface a failure here
    }
    if (!mounted) return;

    final advice = transferCoachAdvice(
      arriving: arriving,
      departing: departing,
      samePlatformPerDb: widget.samePlatform,
    );
    if (advice != null) setState(() => _advice = advice);
  }

  @override
  Widget build(BuildContext context) {
    final advice = _advice;
    if (advice == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    // No "vorne"/"hinten" anywhere: which end of the platform is the front
    // depends on the train's direction, and that isn't proven here. The section
    // letter is painted on the platform and needs no orientation.
    final line =
        '${widget.departing.line?.name ?? 'Dein Anschluss'} hält in '
        'Abschnitt ${advice.departingSectorLabel}';
    final coaches = advice.coachLabel;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(90)),
        color: accent.withAlpha(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.my_location, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Für den Umstieg in Abschnitt ${advice.sectorLabel} '
                  '${coaches == null ? 'einsteigen' : 'einsteigen · $coaches'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$line · ${advice.reason.label}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
