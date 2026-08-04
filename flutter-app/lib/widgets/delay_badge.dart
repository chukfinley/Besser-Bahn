import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class DelayBadge extends StatelessWidget {
  final int? delaySeconds;
  final bool cancelled;

  const DelayBadge({super.key, this.delaySeconds, this.cancelled = false});

  @override
  Widget build(BuildContext context) {
    // Screenreader wording (#74): "+5" is read out as "plus five" with no unit
    // and no clue what it counts, and the colour that carries "5 vs 25 minutes"
    // is invisible to TalkBack. Say it in words instead; the visible badge stays
    // as tight as it has to be.
    if (cancelled) {
      return Semantics(
        label: 'Fällt aus',
        excludeSemantics: true,
        child: _cancelledBadge(),
      );
    }
    if (delaySeconds == null || delaySeconds == 0) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: '${delaySeconds! ~/ 60} Minuten Verspätung',
      excludeSemantics: true,
      child: _delayBadge(),
    );
  }

  Widget _cancelledBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.cancelled,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Ausfall',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _delayBadge() {
    final minutes = delaySeconds! ~/ 60;
    final color = minutes <= 5 ? AppColors.warning : AppColors.delay;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        '+$minutes',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
