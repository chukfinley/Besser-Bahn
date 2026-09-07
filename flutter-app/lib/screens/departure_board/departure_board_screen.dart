import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/departure.dart';
import '../../providers/departure_board_provider.dart';
import '../../providers/nearby_tab_provider.dart';
import '../../providers/train_lookup_provider.dart';
import '../../widgets/bahnhof_search_bar.dart';
import '../../widgets/app_nav_bar.dart';
import '../../widgets/station_search_field.dart';
import '../../widgets/delay_badge.dart';
import '../../widgets/platform_badge.dart';
import '../../widgets/app_menu_button.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/glass_switcher.dart';
import '../../widgets/measured_height.dart';
import '../../core/extensions.dart';
import '../../core/auto_refresh.dart';

/// Menu value standing for "no product filter". See the filter menu below for
/// why this cannot simply be null.
const _allProducts = 'ALLE';

class DepartureBoardScreen extends ConsumerStatefulWidget {
  /// When embedded in the combined "Bahnhof" screen, drop our own AppBar — the
  /// parent screen's floating switcher is the chrome there.
  final bool embedded;

  const DepartureBoardScreen({super.key, this.embedded = false});

  @override
  ConsumerState<DepartureBoardScreen> createState() =>
      _DepartureBoardScreenState();
}

class _DepartureBoardScreenState extends ConsumerState<DepartureBoardScreen>
    with AutoRefreshMixin {
  /// Height of the floating header, measured (see [MeasuredHeight]). The board
  /// pads itself by it, so rows scroll *under* the glass instead of stopping
  /// at it — which is what makes the search bar read as glass here, exactly as
  /// it already does on the Karte tab.
  double _headerHeight = 0;

  @override
  Future<void> onAutoRefresh() =>
      ref.read(departureBoardProvider.notifier).refreshSilent();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(departureBoardProvider);
    final notifier = ref.read(departureBoardProvider.notifier);
    final theme = Theme.of(context);

    // What this screen can do with the station it has open — in the search
    // row, next to the station they act on, exactly as on the Zug tab.
    final actions = <Widget>[
      if (state.station != null)
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Auf der Karte zeigen',
          icon: const Icon(Icons.map_outlined),
          // Go to the Karte tab rather than opening a second map here. There
          // used to be one — a whole other station map with its own floor
          // switcher, living inside this tab — and it was the same map the tab
          // next door already is. The switcher's listener carries this station
          // over on the way (see `NearbyScreen`), so the map lands on the
          // station the rider was just reading.
          onPressed: () =>
              ref.read(nearbyTabProvider.notifier).select(nearbyTabMap),
        ),
      if (state.station != null)
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Aktualisieren',
          icon: const Icon(Icons.refresh),
          onPressed: notifier.load,
        ),
    ];

    return Scaffold(
      // Station search dropdown is an overlay; don't resize the body when the
      // keyboard opens (avoids the list jumping under the search field).
      resizeToAvoidBottomInset: false,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(state.station?.name ?? 'Abfahrtstafel'),
              actions: const [AppMenuButton()],
            ),
      // Content full-bleed, header floating on glass over it — the Karte
      // tab's layout, so all three Bahnhof views look the same (a Column
      // would put the glass over the scaffold colour, i.e. over nothing).
      body: Stack(
        children: [
          Positioned.fill(child: _buildBoard(context, ref, state)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MeasuredHeight(
              onHeight: (h) {
                if (mounted && h != _headerHeight) {
                  setState(() => _headerHeight = h);
                }
              },
              child: Padding(
                // Embedded, the floating switcher sits above this view; on the
                // standalone route the AppBar already took that space.
                padding: EdgeInsets.only(
                  top: widget.embedded ? GlassSwitcher.insetOf(context) : 0,
                ),
                child: Column(
                  children: [
                    // Station search — the shared Bahnhof search bar (same on
                    // Zug/Karte).
                    BahnhofSearchBar(
                      trailing: actions,
                      child: StationSearchField(
                        hint: 'Bahnhof suchen...',
                        prefixIcon: Icons.location_city,
                        initialStation: state.station,
                        onSelected: notifier.setStation,
                        dense: true,
                        bare: true,
                        // A board needs an EVA — addresses have none.
                        stopsOnly: true,
                      ),
                    ),

                    // Mode toggle, filter and the "last updated" line — on
                    // their own pane of glass, so they stay readable over the
                    // rows sliding underneath.
                    if (state.station != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        child: GlassPanel(
                          radius: GlassPanel.pillRadius,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
                            child: Row(
                              children: [
                                // This row overflowed — the yellow-and-black
                                // stripes — on every phone narrower than
                                // ~440 px, which is every phone. Two fixes,
                                // because one alone would only move the cliff:
                                //
                                //  * the checkmark and the arrows are gone.
                                //    Decoration on top of two words that
                                //    already say which way the trains are
                                //    going, and between them ~90 px of the
                                //    overflow;
                                //  * what is left scales down rather than
                                //    overflowing. A [SegmentedButton] sizes
                                //    itself to its labels and does not care
                                //    what it was given, so *any* fixed layout
                                //    here is one system text scale away from
                                //    the stripes again. scaleDown only bites
                                //    when it has to (the departure tile's own
                                //    trick — see `_DepartureTile`).
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: SegmentedButton<BoardMode>(
                                      showSelectedIcon: false,
                                      style: SegmentedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      segments: const [
                                        ButtonSegment(
                                          value: BoardMode.departures,
                                          label: Text('Abfahrten'),
                                        ),
                                        ButtonSegment(
                                          value: BoardMode.arrivals,
                                          label: Text('Ankünfte'),
                                        ),
                                      ],
                                      selected: {state.mode},
                                      onSelectionChanged: (v) =>
                                          notifier.setMode(v.first),
                                    ),
                                  ),
                                ),
                                if (state.lastUpdated != null) ...[
                                  Icon(
                                    Icons.sync,
                                    size: 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    state.lastUpdated!.hhmm,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                // Product filter
                                // Typed <String>, with a sentinel for "Alle",
                                // NOT <String?> with a null item: a
                                // [PopupMenuButton] treats a null result as a
                                // dismissal and calls onCanceled instead of
                                // onSelected. Picking "Alle" therefore never
                                // reached the notifier and the board stayed
                                // filtered — with RE selected in Berlin, on an
                                // empty list you could not get back at all.
                                PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.filter_list,
                                    color: state.filterProduct != null
                                        ? theme.colorScheme.primary
                                        : null,
                                  ),
                                  tooltip: 'Filter',
                                  initialValue:
                                      state.filterProduct ?? _allProducts,
                                  onSelected: (v) => notifier.setFilter(
                                    v == _allProducts ? null : v,
                                  ),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: _allProducts,
                                      child: Text('Alle'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'nationalExpress',
                                      child: Text('ICE'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'national',
                                      child: Text('IC/EC'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'regionalExpress',
                                      child: Text('RE'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'regional',
                                      child: Text('RB'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'suburban',
                                      child: Text('S-Bahn'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'bus',
                                      child: Text('Bus'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(
    BuildContext context,
    WidgetRef ref,
    DepartureBoardState state,
  ) {
    if (state.station == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Bahnhof eingeben, um Abfahrten zu sehen.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(child: Text(state.error!));
    }

    final departures = state.filteredDepartures;
    if (departures.isEmpty) {
      return const Center(child: Text('Keine Ergebnisse.'));
    }

    return RefreshIndicator(
      // Drop the spinner below the floating header — at the default 40 it
      // spins behind the glass and looks like nothing happened.
      displacement: _headerHeight + 24,
      onRefresh: () =>
          ref.read(departureBoardProvider.notifier).refreshSilent(),
      child: ListView.separated(
        // Clear the floating nav bar — it hovers over this list.
        padding: EdgeInsets.only(
          top: _headerHeight,
          bottom: 32 + AppNavBar.insetOf(context),
        ),
        itemCount: departures.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 14),
        itemBuilder: (context, index) {
          return DepartureTile(
            departure: departures[index],
            onTap: () {
              ref
                  .read(trainLookupProvider.notifier)
                  .lookupByTripId(
                    departures[index].tripId,
                    lineLabel: departures[index].line.name,
                  );
              ref.read(nearbyTabProvider.notifier).select(nearbyTabTrain);
              context.go('/nearby');
            },
          );
        },
      ),
    );
  }
}

/// One row of the board. Public (and [visibleForTesting]) so a golden test can
/// render a whole board's worth of rows without a network.
@visibleForTesting
class DepartureTile extends StatelessWidget {
  final Departure departure;
  final VoidCallback onTap;

  const DepartureTile({super.key, required this.departure, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = departure.plannedWhen?.hhmm ?? '';
    final muted = theme.colorScheme.onSurfaceVariant;
    // A station display's columns — Zeit | Nach | Über | Gleis — in the space a
    // list row can afford: two lines, not four. The line label rides next to
    // the time (a board prints "RB75" under the minute; on a phone the width is
    // the scarce axis, not the height), and the delay badge sits on the same
    // baseline as the time instead of taking a line of its own.
    final via = departure.via.join(' · ');
    final note = departure.remarks.isEmpty ? null : departure.remarks.first;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Zeit + Verspätung, then the line — a fixed width so every row's
            // destination starts on the same x. That alignment is the whole
            // point of a board.
            SizedBox(
              width: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.15,
                          decoration: departure.cancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (departure.cancelled || departure.isDelayed) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: DelayBadge(
                              delaySeconds: departure.delay,
                              cancelled: departure.cancelled,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    departure.line.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Nach + Über.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    departure.direction,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // One line only: the stops on the way are orientation, not a
                  // route listing — the trip screen has the full run. Two lines
                  // here cost a third of the rows on screen.
                  if (via.isNotEmpty || note != null)
                    Text(
                      note ?? via,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        color: departure.cancelled
                            ? theme.colorScheme.error
                            : muted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Gleis — a column, not a trailing widget: fixed width and
            // right-aligned, so the platform numbers line up down the board
            // instead of drifting with the length of the destination. No
            // chevron either; the whole row is tappable, and the arrow only ate
            // the width the destination needed (a real board has no arrows).
            SizedBox(
              width: 54,
              child: Align(
                alignment: Alignment.centerRight,
                child: PlatformBadge(
                  platform: departure.platform,
                  plannedPlatform: departure.plannedPlatform,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
