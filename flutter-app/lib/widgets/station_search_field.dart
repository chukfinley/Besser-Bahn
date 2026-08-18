import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/library_models.dart';
import '../models/station.dart';
import '../providers/library_provider.dart';
import '../providers/station_search_provider.dart';
import '../utils/geo_query.dart';

class StationSearchField extends ConsumerStatefulWidget {
  final String hint;
  final Station? initialStation;
  final ValueChanged<Station> onSelected;
  final IconData? prefixIcon;
  final TextEditingController? controller;

  /// Compact rendering: smaller height, tighter padding, smaller icons — used
  /// where the form must stay tight (the connection search header).
  final bool dense;

  /// Saved from→to routes to surface at the top of the suggestion menu (before
  /// favorites/recents). Only shown when [onRouteSelected] is wired.
  final List<SavedRoute> savedRoutes;

  /// Picking a saved route — the caller fills *both* the From and To fields.
  final ValueChanged<SavedRoute>? onRouteSelected;

  /// Drop the field's own fill and border — for when it already sits on glass
  /// (the map's floating search), so it doesn't read as a boxed frame over the
  /// panel.
  final bool bare;

  /// Only offer real stops. Set where an EVA number is required downstream —
  /// departure board, station map, train lookup — so the rider can't pick an
  /// address that those screens cannot open. The connection search leaves it
  /// off: there, an address is a perfectly good origin/destination.
  final bool stopsOnly;

  const StationSearchField({
    super.key,
    required this.hint,
    this.initialStation,
    required this.onSelected,
    this.prefixIcon,
    this.controller,
    this.dense = false,
    this.savedRoutes = const [],
    this.onRouteSelected,
    this.bare = false,
    this.stopsOnly = false,
  });

  @override
  ConsumerState<StationSearchField> createState() => _StationSearchFieldState();
}

class _StationSearchFieldState extends ConsumerState<StationSearchField> {
  late TextEditingController _controller;
  bool _ownsController = false;
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  bool _suppressDismiss = false;

  /// True from focusing an already-filled field until the first keystroke. The
  /// field holds a committed station, so re-tapping it must reopen the
  /// favorites/recents menu (not run a fruitless search for the full name) —
  /// otherwise the only visible action is "clear", which hides the saved
  /// stations the user came back for.
  bool _showSavedOnFocus = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }
    if (widget.initialStation != null && _controller.text.isEmpty) {
      _controller.text = widget.initialStation!.name;
    }
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(StationSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStation != oldWidget.initialStation &&
        widget.initialStation != null) {
      _controller.text = widget.initialStation!.name;
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // A field that already holds a committed station reopens the saved menu
      // and highlights its text, so the next keystroke overtypes it (instead
      // of the user only being able to hit the clear button).
      if (_controller.text.isNotEmpty) {
        _showSavedOnFocus = true;
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
      // Surface favorites/recents (or live results) as soon as the field is
      // focused, even before the user types.
      _showOverlay();
      return;
    }
    if (!_suppressDismiss) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focusNode.hasFocus) {
          _removeOverlay();
        }
      });
    }
  }

  void _selectStation(Station station) {
    _suppressDismiss = true;
    _showSavedOnFocus = false;
    _controller.text = station.name;
    ref.read(libraryProvider.notifier).recordStationUse(station);
    widget.onSelected(station);
    _removeOverlay();
    _focusNode.unfocus();
    ref.read(stationSearchProvider.notifier).clear();
    setState(() {});
    Future.delayed(const Duration(milliseconds: 100), () {
      _suppressDismiss = false;
    });
  }

  void _showOverlay() {
    _removeOverlay();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _overlay = OverlayEntry(
      builder: (context) => Positioned(
        width: renderBox.size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: Offset(0, renderBox.size.height + 2),
          showWhenUnlinked: false,
          child: Material(
            // A hairline-bordered, barely-raised sheet reads as an extension of
            // the field. The old elevation-8 drop shadow floated it off as a
            // separate, inconsistent slab (#38).
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Consumer(
              builder: (context, ref, _) {
                final query = _controller.text.trim();
                final geo = parseGeoQuery(query);
                // Short query — or a just-focused committed field — suggests
                // saved favorites and recent stations. A coordinate is exempt:
                // "geo:52.5,13.3" is already complete, and a pasted one can be
                // shorter than a station name.
                if (_showSavedOnFocus || (geo == null && query.length < 2)) {
                  return _buildSuggestions(ref);
                }
                final results = ref.watch(stationSearchProvider);
                return results.when(
                  data: (result) {
                    // Results for an older query are not an answer to what is
                    // in the field now — show the spinner instead of a list
                    // that contradicts the text.
                    if (!result.matches(query)) return _busy();
                    final stations = result.stations;
                    if (stations.isEmpty) {
                      // Say so rather than showing nothing: silence reads as
                      // "still loading", and the rider is left guessing whether
                      // the term was wrong or the search broken.
                      return _notice(
                        context,
                        geo == null
                            ? 'Keine Treffer für „$query". Haltestelle, '
                                  'Adresse oder Ort eingeben.'
                            : 'Keine Haltestellen in der Nähe dieser Koordinate.',
                        icon: geo == null
                            ? Icons.search_off
                            : Icons.my_location,
                      );
                    }
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (geo != null)
                            _notice(
                              context,
                              geo.label != null
                                  ? 'Haltestellen nahe „${geo.label}"'
                                  : 'Haltestellen in der Nähe der Koordinate',
                            ),
                          Flexible(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: stations.length,
                              itemBuilder: (context, index) =>
                                  _stationTile(ref, stations[index]),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: _busy,
                  error: (_, _) => _notice(
                    context,
                    'Suche gerade nicht erreichbar — bitte erneut versuchen.',
                    icon: Icons.cloud_off,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  Widget _buildSuggestions(WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    // A saved address is a fine origin/destination but has no departure board —
    // hide it where the field only accepts stops, or the rider taps a favorite
    // and lands on an empty screen.
    List<Station> usable(List<Station> list) =>
        widget.stopsOnly ? list.where((s) => s.isStop).toList() : list;
    final favorites = usable(library.favorites);
    final recents = usable(library.recents);
    final routes = widget.onRouteSelected != null
        ? widget.savedRoutes
        : const [];
    if (routes.isEmpty && favorites.isEmpty && recents.isEmpty) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        children: [
          if (routes.isNotEmpty) ...[
            _sectionHeader('Gespeicherte Strecken'),
            ...routes.map((r) => _routeTile(r as SavedRoute)),
          ],
          if (favorites.isNotEmpty) ...[
            _sectionHeader('Favoriten'),
            ...favorites.map((s) => _stationTile(ref, s)),
          ],
          if (recents.isNotEmpty) ...[
            _sectionHeader('Zuletzt gesucht'),
            ...recents.map((s) => _stationTile(ref, s)),
          ],
        ],
      ),
    );
  }

  /// One saved route: "Kiel Hbf → München Hbf". Tapping fills both fields via
  /// [StationSearchField.onRouteSelected] and dismisses the menu.
  Widget _routeTile(SavedRoute route) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.bookmark, size: 20),
      title: Row(
        children: [
          Flexible(
            child: Text(
              route.from.name,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 14),
          ),
          Flexible(
            child: Text(
              route.to.name,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      onTap: () {
        _suppressDismiss = true;
        _showSavedOnFocus = false;
        _removeOverlay();
        _focusNode.unfocus();
        widget.onRouteSelected!(route);
        Future.delayed(const Duration(milliseconds: 100), () {
          _suppressDismiss = false;
        });
      },
    );
  }

  Widget _sectionHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  static Widget _busy() => const Padding(
    padding: EdgeInsets.all(16),
    child: Center(
      child: SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  /// A one-line explanation inside the menu — why this list is nearby stops
  /// rather than name matches, or why there is no list at all.
  Widget _notice(
    BuildContext context,
    String text, {
    IconData icon = Icons.my_location,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _kindIcon(LocationKind kind) => switch (kind) {
    LocationKind.station => Icons.train,
    LocationKind.address => Icons.home_outlined,
    LocationKind.poi => Icons.place_outlined,
  };

  Widget _stationTile(WidgetRef ref, Station station) {
    final isFav = ref.watch(libraryProvider).isStationFavorite(station.id);
    return ListTile(
      dense: true,
      leading: Icon(_kindIcon(station.kind), size: 20),
      title: Text(station.name, style: const TextStyle(fontSize: 14)),
      // Say what the hit is. An address as destination is legitimate — DB
      // routes to the door and walks the last bit — but the rider must be able
      // to tell "Kieler Straße 30" (Adresse) from a stop of the same name.
      subtitle: station.isStop
          ? null
          : Text(
              station.kind.label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: IconButton(
        icon: Icon(
          isFav ? Icons.star : Icons.star_border,
          size: 20,
          color: isFav ? Colors.amber.shade700 : null,
        ),
        tooltip: isFav ? 'Favorit entfernen' : 'Als Favorit speichern',
        onPressed: () {
          _suppressDismiss = true;
          ref.read(libraryProvider.notifier).toggleStationPin(station);
          Future.delayed(const Duration(milliseconds: 100), () {
            _suppressDismiss = false;
          });
        },
      ),
      onTap: () => _selectStation(station),
    );
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// Auto-select a station once the typed/pasted text clearly identifies one:
  /// an exact case-insensitive name match, or a single remaining result that
  /// the text is a prefix of. Saves the user from having to tap the dropdown.
  void _maybeAutoSelect(StationSearchResult result) {
    final typed = _controller.text.trim().toLowerCase();
    // Never act on an answer to a previous query.
    if (!result.matches(_controller.text)) return;
    // Only stops auto-commit: an address list is a list of *candidates*
    // ("Kieler Straße 30" exists in a dozen towns), so picking one for the
    // rider would silently route them somewhere else.
    final stations = result.stations.where((s) => s.isStop).toList();
    if (typed.length < 3 || stations.isEmpty) return;

    // Only one option left → that's the answer.
    if (stations.length == 1 &&
        stations.first.name.toLowerCase().startsWith(typed)) {
      _selectStation(stations.first);
      return;
    }

    // Exact name match — but ONLY if it's unambiguous, i.e. no other result
    // extends it (so "Berlin" doesn't auto-pick while "Berlin Hauptbahnhof",
    // "Berlin Ostbahnhof" … are still candidates; "Kiel Hauptbahnhof" does).
    final exact = stations.where((s) => s.name.toLowerCase() == typed).toList();
    if (exact.length == 1) {
      final extendedByOther = stations.any(
        (s) =>
            s.name.length > typed.length &&
            s.name.toLowerCase().startsWith(typed),
      );
      if (!extendedByOther) _selectStation(exact.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    // React to fresh search results (also after a paste) and auto-match.
    ref.listen(stationSearchProvider, (_, next) {
      next.whenData(_maybeAutoSelect);
    });

    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: widget.dense ? const TextStyle(fontSize: 14) : null,
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: widget.dense,
          // On glass: no fill, no border — the panel is the surface, so the
          // field shouldn't paint its own boxed frame on top.
          filled: widget.bare ? false : null,
          border: widget.bare ? InputBorder.none : null,
          enabledBorder: widget.bare ? InputBorder.none : null,
          focusedBorder: widget.bare ? InputBorder.none : null,
          contentPadding: widget.dense
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
              : null,
          prefixIcon: widget.prefixIcon != null
              ? Icon(widget.prefixIcon, size: widget.dense ? 18 : null)
              : null,
          prefixIconConstraints: widget.dense
              ? const BoxConstraints(minWidth: 36, minHeight: 36)
              : null,
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Eingabe löschen',
                  icon: Icon(Icons.clear, size: widget.dense ? 18 : 20),
                  visualDensity: widget.dense ? VisualDensity.compact : null,
                  onPressed: () {
                    _controller.clear();
                    ref.read(stationSearchProvider.notifier).clear();
                    // Keep the overlay so favorites/recents show again.
                    if (_focusNode.hasFocus) _showOverlay();
                    setState(() {});
                  },
                )
              : null,
          suffixIconConstraints: widget.dense
              ? const BoxConstraints(minWidth: 36, minHeight: 36)
              : null,
        ),
        onChanged: (value) {
          // The user is typing a new query — leave the saved-menu mode.
          _showSavedOnFocus = false;
          ref.read(stationSearchProvider.notifier)
            ..stopsOnly = widget.stopsOnly
            ..search(value);
          _showOverlay();
          setState(() {});
        },
      ),
    );
  }
}
