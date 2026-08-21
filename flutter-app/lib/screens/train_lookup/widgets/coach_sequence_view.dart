import 'package:flutter/material.dart';
import '../../../models/coach_sequence.dart';

// ---------------------------------------------------------------------------
// Wing-train (Flügelzug) split banner. The Wagenreihung itself now lives on the
// dedicated fullscreen screen (see wagenreihung_screen.dart / platform_track_
// view.dart); this banner is still shown inline under the boarding stop and on
// the fullscreen screen. RED on purpose: "board the wrong portion and you don't
// arrive" is a do-this-or-else fact, not a nice-to-know.
// ---------------------------------------------------------------------------

/// Banner that tells the rider which portion of a splitting train to board.
/// Caller must guarantee `sequence.splits` (a real split to distinct
/// destinations) — not merely `groups.length > 1`.
Widget splitTrainBanner(
  BuildContext context,
  CoachSequence sequence, {
  String? targetDestination,
}) {
  final theme = Theme.of(context);
  final groups = sequence.groups;
  final target = targetDestination;
  final mine = (target != null && target.isNotEmpty)
      ? sequence.portionTo(target)
      : null;
  // LOUD red: a fully filled, saturated red block with white text — impossible
  // to miss. This is a "board the wrong portion and you don't arrive" warning.
  const red = Color(0xFFD32011); // strong signal red
  const fg = Colors.white;
  return Container(
    margin: const EdgeInsets.only(top: 8, bottom: 4),
    padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
    decoration: BoxDecoration(
      color: red,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF8E0F06), width: 2),
      boxShadow: [
        BoxShadow(
          color: red.withAlpha(110),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 22, color: fg),
            const SizedBox(width: 7),
            Text(
              'ACHTUNG · Zug teilt sich',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: fg,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        if (mine != null) ...[
          const SizedBox(height: 8),
          _bannerLine(
            context,
            fg,
            primary: true,
            icon: Icons.check_circle,
            text: mine.sectors.isNotEmpty
                ? 'Für $target: in Abschnitt ${mine.sectors.join('–')} einsteigen'
                : 'Für $target: Zugteil Richtung '
                      '${mine.transport.destination ?? target}',
          ),
        ],
        const SizedBox(height: 6),
        for (final g in groups)
          if (!identical(g, mine))
            _bannerLine(
              context,
              fg,
              primary: false,
              icon: Icons.block,
              text: g.sectors.isNotEmpty
                  ? 'Nicht: Richtung ${g.transport.destination ?? "?"} · '
                        'Abschnitt ${g.sectors.join('–')}'
                  : 'Nicht: Richtung ${g.transport.destination ?? "?"}',
            ),
        if (mine == null) ...[
          const SizedBox(height: 4),
          Text(
            'Vor Einstieg Fahrtzielanzeige am Zug beachten.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: fg.withAlpha(230),
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _bannerLine(
  BuildContext context,
  Color fg, {
  required bool primary,
  required IconData icon,
  required String text,
}) {
  final theme = Theme.of(context);
  final secondary = fg.withAlpha(215);
  return Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: primary ? 19 : 15, color: primary ? fg : secondary),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style:
                (primary
                        ? theme.textTheme.bodyMedium
                        : theme.textTheme.bodySmall)
                    ?.copyWith(
                      color: primary ? fg : secondary,
                      fontWeight: primary ? FontWeight.w900 : FontWeight.w500,
                    ),
          ),
        ),
      ],
    ),
  );
}
