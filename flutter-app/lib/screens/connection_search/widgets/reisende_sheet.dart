import 'package:flutter/material.dart';

import '../../../models/reisende.dart';

/// Bottom sheet to edit the "Reisende & Klasse" selection — class, the
/// Deutschland-Ticket flag and the list of travellers (persons with optional
/// exact age + BahnCard + Schwerbehindertenausweis, plus bikes and dogs).
///
/// Returns the edited [SearchParty] via `Navigator.pop`, or null if dismissed.
Future<SearchParty?> showReisendeSheet(
  BuildContext context,
  SearchParty party,
) {
  return showModalBottomSheet<SearchParty>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReisendeSheet(initial: party),
  );
}

const _personTypes = [
  TravelerType.erwachsener,
  TravelerType.senior,
  TravelerType.jugendlicher,
  TravelerType.familienkind,
  TravelerType.kleinkind,
];

(int, int) _ageBounds(TravelerType t) => switch (t) {
  TravelerType.erwachsener => (27, 64),
  TravelerType.senior => (65, 120),
  TravelerType.jugendlicher => (15, 26),
  TravelerType.familienkind => (6, 14),
  TravelerType.kleinkind => (0, 5),
  _ => (0, 120),
};

class _ReisendeSheet extends StatefulWidget {
  final SearchParty initial;
  const _ReisendeSheet({required this.initial});

  @override
  State<_ReisendeSheet> createState() => _ReisendeSheetState();
}

class _ReisendeSheetState extends State<_ReisendeSheet> {
  late bool _firstClass = widget.initial.firstClass;
  late bool _dTicket = widget.initial.deutschlandTicket;
  late final List<Traveler> _travelers = List.of(widget.initial.travelers);

  int get _personCount => _travelers.where((t) => t.typ.isPerson).length;

  void _apply() {
    Navigator.of(context).pop(
      SearchParty(
        firstClass: _firstClass,
        deutschlandTicket: _dTicket,
        travelers: _travelers,
      ),
    );
  }

  void _addPerson() => setState(
    () => _travelers.add(const Traveler(typ: TravelerType.erwachsener)),
  );
  void _addBike() =>
      setState(() => _travelers.add(const Traveler(typ: TravelerType.fahrrad)));
  void _addDog() =>
      setState(() => _travelers.add(const Traveler(typ: TravelerType.hund)));

  void _remove(int i) => setState(() => _travelers.removeAt(i));
  void _update(int i, Traveler t) => setState(() => _travelers[i] = t);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxH = MediaQuery.of(context).size.height * 0.85;

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
                  Text('Reisende & Klasse', style: theme.textTheme.titleLarge),
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
                  // Class
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('2. Klasse')),
                      ButtonSegment(value: true, label: Text('1. Klasse')),
                    ],
                    selected: {_firstClass},
                    onSelectionChanged: (v) =>
                        setState(() => _firstClass = v.first),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.confirmation_number_outlined),
                    title: const Text('Deutschland-Ticket'),
                    subtitle: const Text('Regionalverkehr inklusive'),
                    value: _dTicket,
                    onChanged: (v) => setState(() => _dTicket = v),
                  ),
                  const Divider(),
                  // Travellers
                  for (var i = 0; i < _travelers.length; i++)
                    _TravelerTile(
                      key: ValueKey(i),
                      traveler: _travelers[i],
                      // Keep at least one person in the party.
                      canRemove:
                          !(_travelers[i].typ.isPerson && _personCount == 1),
                      onChanged: (t) => _update(i, t),
                      onRemove: () => _remove(i),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.person_add_alt, size: 18),
                        label: const Text('Person'),
                        onPressed: _addPerson,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.directions_bike, size: 18),
                        label: const Text('Fahrrad'),
                        onPressed: _addBike,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.pets, size: 18),
                        label: const Text('Hund'),
                        onPressed: _addDog,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _apply,
                  child: const Text('Übernehmen'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelerTile extends StatelessWidget {
  final Traveler traveler;
  final bool canRemove;
  final ValueChanged<Traveler> onChanged;
  final VoidCallback onRemove;

  const _TravelerTile({
    super.key,
    required this.traveler,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final t = traveler;

    // Bike / dog: just a labelled row with a remove button.
    if (!t.typ.isPerson) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: Icon(t.typ.isBike ? Icons.directions_bike : Icons.pets),
          title: Text(t.typ.label),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Entfernen',
            onPressed: onRemove,
          ),
        ),
      );
    }

    final (minAge, maxAge) = _ageBounds(t.typ);
    final age = t.alter ?? t.typ.defaultAge!;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<TravelerType>(
                    value: t.typ,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      for (final pt in _personTypes)
                        DropdownMenuItem(
                          value: pt,
                          child: Text(
                            pt.fullLabel,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                    ],
                    onChanged: (pt) {
                      if (pt == null) return;
                      // New band → reset the explicit age to the band default
                      // and drop reductions the type can't hold.
                      onChanged(
                        t.copyWith(
                          typ: pt,
                          alter: pt.defaultAge,
                          bahnCard: pt.discountable ? null : Reduction.none,
                          weitere: pt.discountable ? null : Reduction.none,
                          sba: pt.discountable ? null : SbaOption.none,
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Entfernen',
                  onPressed: canRemove ? onRemove : null,
                ),
              ],
            ),
            // Exact age
            Row(
              children: [
                const SizedBox(width: 28),
                Text('Alter', style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Alter verringern',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: age > minAge
                      ? () => onChanged(t.copyWith(alter: age - 1))
                      : null,
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$age',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Alter erhöhen',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: age < maxAge
                      ? () => onChanged(t.copyWith(alter: age + 1))
                      : null,
                ),
              ],
            ),
            if (t.typ.discountable) ...[
              const SizedBox(height: 8),
              // BahnCard (DB's own railcards, with class).
              _LabeledDropdown<Reduction>(
                icon: Icons.credit_card,
                label: 'BahnCard',
                value: t.bahnCard,
                items: [
                  for (final r in Reduction.bahnCardOptions)
                    DropdownMenuItem(
                      value: r,
                      child: Text(
                        r.label,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
                onChanged: (r) =>
                    onChanged(t.copyWith(bahnCard: r ?? Reduction.none)),
              ),
              const SizedBox(height: 8),
              // Schwerbehindertenausweis.
              _LabeledDropdown<SbaOption>(
                icon: Icons.accessible,
                label: 'Schwerbehindertenausweis',
                value: t.sba,
                items: [
                  for (final s in SbaOption.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(
                        s.label,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
                onChanged: (s) =>
                    onChanged(t.copyWith(sba: s ?? SbaOption.none)),
              ),
              const SizedBox(height: 8),
              // Weitere Ermäßigungen — foreign railcards (CH/AT/NL).
              _LabeledDropdown<Reduction>(
                icon: Icons.card_membership,
                label: 'Weitere Ermäßigungen',
                value: t.weitere,
                items: [
                  for (final r in Reduction.weitereOptions)
                    DropdownMenuItem(
                      value: r,
                      child: Text(
                        r.label,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
                onChanged: (r) =>
                    onChanged(t.copyWith(weitere: r ?? Reduction.none)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _LabeledDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                underline: const SizedBox(),
                items: items,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
