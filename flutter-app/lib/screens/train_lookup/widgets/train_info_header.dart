import 'package:flutter/material.dart';
import '../../../models/coach_sequence.dart';
import '../../../models/journey.dart' show OccupancyLevel;
import '../../../models/trip.dart';
import '../../../utils/train_operator.dart';
import '../../../widgets/occupancy_indicator.dart';
import '../../../widgets/product_badge.dart';
import 'train_map_view.dart';

class TrainInfoHeader extends StatelessWidget {
  final Trip trip;

  /// The train's Wagenreihung, when known — lets the route map draw the train
  /// to scale (length/width/nose) instead of a generic silhouette.
  final CoachSequence? coachSequence;

  /// Optional action shown to the right of the train name (e.g. the connection
  /// view's compact "Weitere Abfahrten" button). Null on the standalone train
  /// screen, where there's no journey to swap a leg in.
  final Widget? action;

  /// When true, render just the content (no Card / outer margin) so it can be
  /// stacked inside a shared card together with the stop timeline — the train
  /// name and the Halte then read as one block.
  final bool embedded;

  /// Overrides the [embedded] default padding. When the header is rendered
  /// inline on the route spine (connection leg view) the spine column already
  /// supplies the left inset, so the caller passes [EdgeInsets.zero].
  final EdgeInsets? padding;

  /// Per-train reliability strip (Anschluss/Pünktlichkeit for *this* leg),
  /// rendered just below the direction line. Null on the standalone train
  /// screen, where there's no journey context to score a single leg against.
  final Widget? predictionStrip;

  /// EVA / name of the stop the rider boards/alights at on this leg, passed
  /// through to the route map so it dims only the boarding stop's non-boarding
  /// portion. Null on a standalone train lookup → the map dims nothing.
  final String? boardingId;
  final String? alightingId;

  const TrainInfoHeader({
    super.key,
    required this.trip,
    this.coachSequence,
    this.action,
    this.embedded = false,
    this.padding,
    this.predictionStrip,
    this.boardingId,
    this.alightingId,
  });

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    if (embedded) {
      return Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: content,
      );
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(padding: const EdgeInsets.all(16), child: content),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Train name and direction
        Row(
          children: [
            ProductBadge(label: trip.line.productBadge),
            const SizedBox(width: 8),
            Expanded(
              // Product lives in the badge; show the line number plus the
              // train number in parentheses after it (no repeated "RE").
              child: Text(
                trip.line.lineNumberWithFahrt,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Route map: hidden by default, opened fullscreen from here.
            if (trip.stopovers.any((s) => s.stop.hasLocation))
              IconButton(
                icon: const Icon(Icons.map_outlined),
                tooltip: 'Streckenverlauf',
                visualDensity: VisualDensity.compact,
                onPressed: () => openTrainMap(
                  context,
                  trip,
                  coachSequence: coachSequence,
                  boardingId: boardingId,
                  alightingId: alightingId,
                ),
              ),
            if (action != null) ...[const SizedBox(width: 4), action!],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '→ ${trip.direction}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        // Per-train reliability (Anschluss/Pünktlichkeit for this leg).
        if (predictionStrip != null) ...[
          const SizedBox(height: 8),
          predictionStrip!,
        ],

        // Who actually runs this train (erixx, metronom, DB Fernverkehr…) —
        // DB's line label ("RE 83") hides it, so surface it with a small
        // brand-coloured badge (#operator).
        ...(() {
          final op = operatorFor(
            productName: trip.line.productName,
            product: trip.line.product,
            name: trip.line.name,
          );
          final label = op?.name ?? trip.line.operatorName;
          if (label == null) return const <Widget>[];
          final color = op != null
              ? Color(op.color)
              : theme.colorScheme.primary;
          return [
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Betrieben von $label',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ];
        })(),

        // Endpoints/times are NOT repeated here — the Halte timeline below
        // (same card) already shows origin, destination and their times.

        // Live "next stop" — the one piece of run-level info the timeline
        // doesn't surface at a glance.
        if (trip.currentStop != null) ...[
          const SizedBox(height: 8),
          _infoChip(
            Icons.location_on,
            'Nächst: ${trip.currentStop!.stop.name}',
          ),
        ],

        // Expected 2nd-class occupancy for the run.
        if (trip.occupancy != OccupancyLevel.unknown) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              OccupancyIndicator(level: trip.occupancy),
              const SizedBox(width: 6),
              Text(
                trip.occupancy.expectedLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (trip.occupancy.recommendsReservation) ...[
            const SizedBox(height: 6),
            _infoChip(Icons.event_seat, trip.occupancy.reservationHint),
          ],
        ],
      ],
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text, style: const TextStyle(fontSize: 12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
