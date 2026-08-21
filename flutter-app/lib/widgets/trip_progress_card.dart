import 'dart:async';

import 'package:flutter/material.dart';

import '../core/trip_progress.dart';
import '../models/journey.dart';

/// Live "Reisefortschritt" card for an upcoming or in-progress journey, driven
/// by the shared [TripProgress] engine (ticks every 15 s). Before departure it
/// counts down to the train; on board it shows a progress bar to the
/// destination plus the next transfer; after arrival it removes itself.
///
/// [activeOnly] hides it unless the trip is in progress or departs soon — used
/// where the card sits among other content (the Reisen list) rather than on the
/// trip's own detail screen.
///
/// [onBoardOnly] hides the pre-departure countdown phase entirely (used on the
/// connection detail, where [DepartureCard] already shows the countdown + the
/// "wann musst du los" walk — so this only kicks in once the trip is moving).
class TripProgressCard extends StatefulWidget {
  final Journey journey;
  final bool activeOnly;
  final bool onBoardOnly;
  const TripProgressCard({
    super.key,
    required this.journey,
    this.activeOnly = false,
    this.onBoardOnly = false,
  });

  @override
  State<TripProgressCard> createState() => _TripProgressCardState();
}

class _TripProgressCardState extends State<TripProgressCard> {
  Timer? _timer;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = TripProgress.of(widget.journey);
    if (p == null || p.phase == TripPhase.finished) {
      return const SizedBox.shrink();
    }
    if (widget.onBoardOnly && p.phase == TripPhase.upcoming) {
      return const SizedBox.shrink();
    }
    if (widget.activeOnly && !p.isActive()) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: p.phase == TripPhase.upcoming
            ? _beforeDeparture(theme, p)
            : _onBoard(theme, p),
      ),
    );
  }

  Widget _beforeDeparture(ThemeData theme, TripProgress p) {
    final mins = p.minutesToDeparture;
    return Row(
      children: [
        Icon(Icons.schedule, color: theme.colorScheme.onSecondaryContainer),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mins <= 0 ? 'Fährt jetzt ab' : 'Abfahrt in ${_dur(mins)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              Text(
                'ab ${p.originName} → ${p.destinationName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer.withValues(
                    alpha: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _onBoard(ThemeData theme, TripProgress p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.train, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                p.minutesToArrival <= 0
                    ? 'Ankunft jetzt'
                    : 'Noch ${_dur(p.minutesToArrival)} bis ${p.destinationName}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            Text(
              '${(p.fraction * 100).round()} %',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: p.fraction,
            minHeight: 6,
            backgroundColor: theme.colorScheme.onSecondaryContainer.withValues(
              alpha: 0.15,
            ),
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        if (p.nextTransferStation != null) ...[
          const SizedBox(height: 10),
          Text(
            'Umstieg in ${p.nextTransferStation}'
            '${p.minutesToTransfer != null ? ' · in ${_dur(p.minutesToTransfer!)}' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer.withValues(
                alpha: 0.85,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _dur(int minutes) {
    if (minutes < 60) return '$minutes Min';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m Min';
  }
}
