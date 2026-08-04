import 'package:flutter/material.dart';

import '../../../models/search_options.dart';
import '../../../models/station.dart';
import '../../../models/transfer_profile.dart';
import '../../../widgets/station_search_field.dart';

/// Bottom sheet for the search options DB enforces server-side: how many
/// changes, how much slack each change needs, and a station to route through
/// (#19).
///
/// Returns the edited [SearchOptions] via `Navigator.pop`, or null if
/// dismissed without applying.
Future<SearchOptions?> showSearchOptionsSheet(
  BuildContext context,
  SearchOptions options, {
  required TransferProfile profile,
}) {
  return showModalBottomSheet<SearchOptions>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SearchOptionsSheet(initial: options, profile: profile),
  );
}

/// Null = "beliebig". Above 3 the cap stops meaning anything on a DB search —
/// the backend rarely offers more, and "max. 4" would read as a promise.
const _transferCaps = <int?>[null, 0, 1, 2, 3];

/// Offered minima, in minutes. Below 10 there is nothing to ask for — DB's own
/// station minimum is already in that range, so it would only look like a
/// setting without being one.
const _transferMinutes = <int?>[null, 10, 15, 20, 30, 45, 60];

/// Minimum stay at the via station. Coarse on purpose: this is "break the trip
/// for a coffee / for lunch", not a departure-precise plan.
const _viaStayMinutes = <int?>[null, 30, 60, 120, 240];

class _SearchOptionsSheet extends StatefulWidget {
  final SearchOptions initial;
  final TransferProfile profile;
  const _SearchOptionsSheet({required this.initial, required this.profile});

  @override
  State<_SearchOptionsSheet> createState() => _SearchOptionsSheetState();
}

class _SearchOptionsSheetState extends State<_SearchOptionsSheet> {
  late int? _maxTransfers = widget.initial.maxTransfers;
  late int? _minTransfer = widget.initial.minTransferMinutes;
  late Station? _via = widget.initial.via;
  late int? _viaStay = widget.initial.viaStayMinutes;

  void _apply() {
    Navigator.of(context).pop(SearchOptions(
      maxTransfers: _maxTransfers,
      minTransferMinutes: _minTransfer,
      via: _via,
      // A stay without a via is meaningless.
      viaStayMinutes: _via == null ? null : _viaStay,
    ));
  }

  void _reset() => setState(() {
        _maxTransfers = null;
        _minTransfer = null;
        _via = null;
        _viaStay = null;
      });

  String _capLabel(int? cap) => switch (cap) {
        null => 'Beliebig',
        0 => 'Direkt',
        1 => 'Max. 1',
        _ => 'Max. $cap',
      };

  /// What the search will actually ask for when "Automatisch" is selected —
  /// the profile's own minimum, or nothing at all for fast/normal riders.
  String get _autoHint {
    final p = widget.profile;
    final min = p.minTransferMinutes;
    if (min == null) {
      return 'Profil „${p.label}" — ohne eigenen Mindestwert, '
          'die Bahn plant den Umstieg.';
    }
    return 'Profil „${p.label}" — sucht Umstiege ab $min min. '
        'Gibt es keine, zeigen wir knappere mit Hinweis.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxH = MediaQuery.of(context).size.height * 0.85;
    final dirty = SearchOptions(
          maxTransfers: _maxTransfers,
          minTransferMinutes: _minTransfer,
          via: _via,
          viaStayMinutes: _via == null ? null : _viaStay,
        ) !=
        widget.initial;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  Text('Suchoptionen', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Schließen',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                shrinkWrap: true,
                children: [
                  _label(theme, Icons.alt_route, 'Umstiege'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final cap in _transferCaps)
                        ChoiceChip(
                          label: Text(_capLabel(cap)),
                          selected: _maxTransfers == cap,
                          onSelected: (_) =>
                              setState(() => _maxTransfers = cap),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _label(theme, Icons.timer_outlined, 'Mindest-Umstiegszeit'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final min in _transferMinutes)
                        ChoiceChip(
                          label: Text(min == null ? 'Automatisch' : '$min min'),
                          selected: _minTransfer == min,
                          onSelected: (_) => setState(() => _minTransfer = min),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _minTransfer == null
                          ? _autoHint
                          : 'Die Bahn sucht nur Verbindungen mit mindestens '
                              '$_minTransfer min pro Umstieg.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label(theme, Icons.place_outlined, 'Über Station'),
                  StationSearchField(
                    hint: 'z. B. Frankfurt(Main)Hbf',
                    initialStation: _via,
                    prefixIcon: Icons.place_outlined,
                    // The field is a fresh widget once the via is cleared, so
                    // its text box empties with it — without the key it keeps
                    // showing the old name.
                    key: ValueKey(_via?.vendoLocationId),
                    onSelected: (s) => setState(() => _via = s),
                  ),
                  if (_via != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Die Verbindung führt über ${_via!.name} — '
                            'umsteigen musst du dort nicht.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Entfernen'),
                          onPressed: () => setState(() {
                            _via = null;
                            _viaStay = null;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _label(theme, Icons.local_cafe_outlined,
                        'Mindestaufenthalt dort'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final stay in _viaStayMinutes)
                          ChoiceChip(
                            label: Text(stay == null
                                ? 'Egal'
                                : stay >= 60
                                    ? '${stay ~/ 60} h'
                                    : '$stay min'),
                            selected: _viaStay == stay,
                            onSelected: (_) => setState(() => _viaStay = stay),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _maxTransfers == null &&
                            _minTransfer == null &&
                            _via == null
                        ? null
                        : _reset,
                    child: const Text('Zurücksetzen'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _apply,
                    child: Text(dirty ? 'Suchen' : 'Fertig'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Text(text,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
}
