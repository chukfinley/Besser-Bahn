import 'package:flutter/material.dart';

import '../core/journey_reliability.dart';
import '../models/journey.dart';

class JourneyReliabilityCard extends StatelessWidget {
  final Journey journey;

  const JourneyReliabilityCard({super.key, required this.journey});

  String _title(JourneyReliabilityLevel level) {
    switch (level) {
      case JourneyReliabilityLevel.veryReliable:
        return 'Sehr zuverlässig';
      case JourneyReliabilityLevel.reliable:
        return 'Zuverlässig';
      case JourneyReliabilityLevel.moderate:
        return 'Mäßig zuverlässig';
      case JourneyReliabilityLevel.risky:
        return 'Risiko vorhanden';
      case JourneyReliabilityLevel.veryRisky:
        return 'Sehr unsicher';
    }
  }

  IconData _icon(JourneyReliabilityLevel level) {
    switch (level) {
      case JourneyReliabilityLevel.veryReliable:
        return Icons.verified_rounded;
      case JourneyReliabilityLevel.reliable:
        return Icons.check_circle_outline_rounded;
      case JourneyReliabilityLevel.moderate:
        return Icons.info_outline_rounded;
      case JourneyReliabilityLevel.risky:
        return Icons.warning_amber_rounded;
      case JourneyReliabilityLevel.veryRisky:
        return Icons.error_outline_rounded;
    }
  }

  Color _color(BuildContext context, JourneyReliabilityLevel level) {
    final scheme = Theme.of(context).colorScheme;

    switch (level) {
      case JourneyReliabilityLevel.veryReliable:
        return Colors.green;
      case JourneyReliabilityLevel.reliable:
        return scheme.primary;
      case JourneyReliabilityLevel.moderate:
        return Colors.orange;
      case JourneyReliabilityLevel.risky:
      case JourneyReliabilityLevel.veryRisky:
        return scheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reliability = JourneyReliabilityAnalyzer.analyze(journey);
    final color = _color(context, reliability.level);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(reliability.level), color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Zuverlässigkeit',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${reliability.score}/100',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _title(reliability.level),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: reliability.score / 100,
                minHeight: 7,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            if (reliability.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final reason in reliability.reasons)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 6,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
