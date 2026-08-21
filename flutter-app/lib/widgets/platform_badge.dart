import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Small painted rail-track glyph (two rails + sleepers) used as the Gleis
/// marker everywhere — clearer than a generic icon and consistent across the
/// departure/arrival ends so the platform reads the same on both sides.
class TrackIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const TrackIcon({super.key, this.size = 14, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TrackPainter(c)),
    );
  }
}

class _TrackPainter extends CustomPainter {
  final Color color;
  const _TrackPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    // Two slightly converging rails (top-down track in light perspective).
    final railTop = h * 0.08, railBot = h * 0.92;
    canvas.drawLine(Offset(w * 0.30, railTop), Offset(w * 0.22, railBot), p);
    canvas.drawLine(Offset(w * 0.70, railTop), Offset(w * 0.78, railBot), p);
    // Sleepers across the rails.
    for (final t in const [0.22, 0.5, 0.78]) {
      final y = railTop + (railBot - railTop) * t;
      final inset = w * 0.06 * (t - 0.5).abs() * 2; // mirror the convergence
      canvas.drawLine(
        Offset(w * 0.14 + inset, y),
        Offset(w * 0.86 - inset, y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.color != color;
}

/// Gleis shown in a bordered box: blue outline normally, red (with the old
/// platform struck through) when it changed. Same look as the stop timeline, so
/// the platform reads identically in the preview, summary and detail.
class PlatformChip extends StatelessWidget {
  final String? platform;
  final String? plannedPlatform;

  const PlatformChip({super.key, this.platform, this.plannedPlatform});

  @override
  Widget build(BuildContext context) {
    final display = platform ?? plannedPlatform;
    if (display == null || display.isEmpty) return const SizedBox.shrink();
    final changed =
        platform != null &&
        plannedPlatform != null &&
        platform != plannedPlatform;
    final color = changed ? Colors.red : Colors.blue;
    final theme = Theme.of(context);
    return Semantics(
      label: _platformLabel(display, changed ? plannedPlatform : null),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(200)),
          color: color.withAlpha(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrackIcon(
              size: 13,
              color: changed ? Colors.red : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            if (changed && plannedPlatform != null) ...[
              Text(
                plannedPlatform!,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              display,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: changed ? Colors.red : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlatformBadge extends StatelessWidget {
  final String? platform;
  final String? plannedPlatform;

  const PlatformBadge({super.key, this.platform, this.plannedPlatform});

  @override
  Widget build(BuildContext context) {
    final display = platform ?? plannedPlatform;
    if (display == null || display.isEmpty) return const SizedBox.shrink();

    final changed =
        platform != null &&
        plannedPlatform != null &&
        platform != plannedPlatform;

    return Semantics(
      label: _platformLabel(display, changed ? plannedPlatform : null),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TrackIcon(
            size: 14,
            color: changed
                ? AppColors.delay
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 3),
          if (changed && plannedPlatform != null) ...[
            Text(
              plannedPlatform!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            display,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: changed ? AppColors.delay : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a platform chip should *say* out loud (#74).
///
/// On screen a struck-through old number next to a red new one reads as "moved"
/// at a glance; a screenreader gets "7 5" and no hint which is which. Spell the
/// change out, and keep it short enough to sit in a busy departure row.
String _platformLabel(String display, String? changedFrom) =>
    changedFrom == null || changedFrom.isEmpty
    ? 'Gleis $display'
    : 'Gleis $display, geändert von Gleis $changedFrom';
