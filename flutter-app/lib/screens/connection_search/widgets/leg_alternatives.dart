import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions.dart';
import '../../../models/journey.dart';
import '../../../providers/service_providers.dart';
import '../../../services/vendo_service.dart';
import '../../../widgets/occupancy_indicator.dart';

/// Opens the "Weitere Abfahrten" bottom sheet for one journey [leg]: the
/// alternative trains of the same product group running this exact segment.
///
/// Tapping a result offers two actions — replace this leg in the journey
/// ([onReplace], hidden when null) or open its full Zugdetails ([onOpenDetails]).
/// Lives in a sheet (not inline) so the connection view stays compact.
Future<void> showWeitereAbfahrtenSheet(
  BuildContext context, {
  required JourneyLeg leg,
  required void Function(Journey alternative) onOpenDetails,
  void Function(Journey alternative)? onReplace,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WeitereAbfahrtenSheet(
      leg: leg,
      onOpenDetails: onOpenDetails,
      onReplace: onReplace,
    ),
  );
}

/// Compact header button that opens the "Weitere Abfahrten" sheet.
class WeitereAbfahrtenButton extends StatelessWidget {
  final VoidCallback onTap;
  const WeitereAbfahrtenButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Icon-only: the label text overflowed on mobile next to the train name and
    // map button. Pairs visually with the adjacent map IconButton.
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.swap_horiz),
      tooltip: 'Weitere Abfahrten',
      visualDensity: VisualDensity.compact,
      color: theme.colorScheme.primary,
    );
  }
}

class _WeitereAbfahrtenSheet extends ConsumerStatefulWidget {
  final JourneyLeg leg;
  final void Function(Journey alternative) onOpenDetails;
  final void Function(Journey alternative)? onReplace;

  const _WeitereAbfahrtenSheet({
    required this.leg,
    required this.onOpenDetails,
    this.onReplace,
  });

  @override
  ConsumerState<_WeitereAbfahrtenSheet> createState() =>
      _WeitereAbfahrtenSheetState();
}

class _WeitereAbfahrtenSheetState
    extends ConsumerState<_WeitereAbfahrtenSheet> {
  bool _loading = false;
  String? _error;
  String? _laterRef;
  final List<Journey> _alts = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch({String? context}) async {
    final leg = widget.leg;
    final from = leg.origin.vendoLocationId;
    final to = leg.destination.vendoLocationId;
    final an = leg.plannedArrival ?? leg.arrival;
    if (an == null || from.isEmpty || to.isEmpty) {
      setState(() => _error = 'Nicht verfügbar.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(vendoServiceProvider)
          .fetchWeitereAbfahrten(
            abgangsLocationId: from,
            zielLocationId: to,
            ankunft: an,
            produktGattungen: VendoService.produktGattungenFor(
              leg.line?.product,
            ),
            context: context,
          );
      if (!mounted) return;
      setState(() {
        final seen = _alts
            .map((j) => j.legs.firstOrNull?.tripId)
            .whereType<String>()
            .toSet();
        for (final j in res.journeys) {
          final id = j.legs.firstOrNull?.tripId;
          if (id != null && !seen.add(id)) continue;
          _alts.add(j);
        }
        _laterRef = res.laterRef;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Konnte nicht laden.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Tap on an alternative → pick "Fahrt ersetzen" or "Zugdetails öffnen".
  /// The chosen action runs in the caller's (page) context, so the list sheet
  /// is closed first and navigation/state changes happen on a live context.
  Future<void> _chooseAction(Journey alt) async {
    final canReplace = widget.onReplace != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canReplace)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Fahrt ersetzen'),
                subtitle: const Text('Diese Abfahrt in die Reise übernehmen'),
                onTap: () => Navigator.pop(sheetCtx, 'replace'),
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Zugdetails öffnen'),
              subtitle: const Text('Fahrtverlauf, Karte, Wagenreihung'),
              onTap: () => Navigator.pop(sheetCtx, 'details'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    // Close the alternatives list sheet, then run the action on the page.
    Navigator.of(context).pop();
    if (choice == 'replace') {
      widget.onReplace?.call(alt);
    } else {
      widget.onOpenDetails(alt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.departure_board,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Weitere Abfahrten',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading && _alts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null && _alts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      );
    }
    if (_alts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Keine weiteren Abfahrten.')),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _alts.length + (_laterRef != null ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
      itemBuilder: (context, i) {
        if (i >= _alts.length) {
          return InkWell(
            onTap: _loading ? null : () => _fetch(context: _laterRef),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    'Mehr anzeigen',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return _altRow(context, _alts[i]);
      },
    );
  }

  /// One alternative departure: dep/arr times (planned + realtime), the line
  /// badge with occupancy, the train's direction, and its platform.
  Widget _altRow(BuildContext context, Journey alt) {
    final leg = alt.legs.firstOrNull;
    if (leg == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dest = (leg.direction?.trim().isNotEmpty ?? false)
        ? leg.direction!.trim()
        : leg.destination.name;
    final platform = leg.departurePlatform ?? leg.plannedDeparturePlatform;
    final name = leg.line?.titleWithNumber ?? leg.line?.displayName ?? '';

    return InkWell(
      onTap: () => _chooseAction(alt),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              // Grows with the system font: a fixed 54 px cuts the last digit
              // off a scaled-up "15:43" (#98).
              width: 54 * MediaQuery.textScalerOf(context).scale(13) / 13,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _timeCell(
                    theme,
                    leg.plannedDeparture,
                    leg.departure,
                    leg.departureDelay,
                    bold: true,
                  ),
                  const SizedBox(height: 4),
                  _timeCell(
                    theme,
                    leg.plannedArrival,
                    leg.arrival,
                    leg.arrivalDelay,
                    bold: false,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (name.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (leg.occupancy != null) ...[
                        const SizedBox(width: 6),
                        OccupancyIndicator(level: leg.occupancy!.level),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dest,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (platform != null && platform.isNotEmpty) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  'Gl. $platform',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// Planned time, struck through + realtime in red when delayed ≥ 1 min.
  Widget _timeCell(
    ThemeData theme,
    DateTime? planned,
    DateTime? real,
    int? delaySec, {
    required bool bold,
  }) {
    if (planned == null) return const SizedBox.shrink();
    final delayed = (delaySec ?? 0) >= 60;
    final base = bold
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          planned.hhmm,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: delayed ? base.withAlpha(140) : base,
            decoration: delayed ? TextDecoration.lineThrough : null,
          ),
        ),
        if (delayed && real != null)
          Text(
            real.hhmm,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: delaySec.delayColor,
            ),
          ),
      ],
    );
  }
}
