// Vendored from chuk_ui — git@github.com:chukfinley/chuk_ui.git
// Source: lib/src/components/nav/chuk_nav_bar.dart @ commit 3ae5a1e (v0.4.2).
//
// COPIED, NOT A DEPENDENCY: the IzzyOnDroid reproducible build must not gain a
// new external (Git) dependency — see BUILDING.md. Only the slice the nav bar
// needs is vendored, not the whole package.
//
// Edits here are LOCAL and do NOT flow back to chuk_ui. Re-sync by hand against
// upstream and re-apply the deltas below (upstream formatting is kept as-is, so
// a plain diff against the upstream file shows only these):
//  1. Theme lookup: `context.chuk` (the full ChukThemeData) -> `context.chukNav`
//     (the slimmed ChukNavThemeData in chuk_nav_theme.dart). Colour tokens are
//     not vendored — this app has its own palette — so the token fallbacks
//     (`t.colors.textPrimary` etc.) read from the resolved style instead; the
//     bridge in lib/widgets/app_nav_bar.dart sets every colour.
//     `t.radii.pill` -> `kChukPillRadius`, `t.typography.caption` ->
//     `t.labelStyle`.
//  2. Accessibility (StatelessWidget -> StatefulWidget, for the focus ring):
//     upstream renders bare GestureDetectors — no role, no selected state, no
//     keyboard. This bar replaces a Material NavigationBar, which announced all
//     three, so each tab gets Semantics(button/selected/label) and a
//     FocusableActionDetector (Tab to reach, Enter/Space to activate). Worth
//     upstreaming — chuk_ui's own CLAUDE.md requires exactly this.
//
// DELTA vs the tag: the dark-mode rim is dropped (`highlight` transparent
// unless light). That is upstream's own uncommitted decision from 2026-07-12,
// not ours to reinvent — v0.4.2 predates it. Drop this delta once chuk_ui
// tags it.

import 'package:flutter/widgets.dart';

import 'chuk_glass.dart';
import 'chuk_nav_style.dart';
import 'chuk_nav_theme.dart';
import 'chuk_squircle.dart';

/// One destination in a [ChukNavBar].
@immutable
class ChukNavItem {
  const ChukNavItem({required this.icon, required this.label, this.activeIcon});

  /// Icon shown when the tab is inactive.
  final IconData icon;

  /// Icon shown when the tab is active. Falls back to [icon].
  final IconData? activeIcon;

  /// The tab label.
  final String label;
}

/// A floating bottom navigation bar: a rounded pill with a single highlight
/// that *glides* between tabs (260 ms easeOutCubic). Styled from the
/// [ChukNavThemeData], no Material dependency.
///
/// Ported from the reference app's nav bar. Provide the destinations and the
/// selected index; call [onChanged] to switch. Set [collapsed] true to hide the
/// labels (e.g. on scroll-down), leaving just icons.
///
/// ```dart
/// ChukNavBar(
///   index: tab,
///   onChanged: (i) => setState(() => tab = i),
///   items: const [
///     ChukNavItem(icon: Icons.today_outlined, label: 'Today'),
///     ChukNavItem(icon: Icons.trending_up, label: 'Trends'),
///     ChukNavItem(icon: Icons.settings, label: 'Settings'),
///   ],
/// )
/// ```
class ChukNavBar extends StatefulWidget {
  const ChukNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.collapsed = false,
    this.style,
    this.safeArea = true,
  });

  /// The destinations, left to right.
  final List<ChukNavItem> items;

  /// The selected index.
  final int index;

  /// Called with the tapped index.
  final ValueChanged<int> onChanged;

  /// When true, labels collapse away leaving only icons and the bar shrinks.
  final bool collapsed;

  /// Per-instance style overrides.
  final ChukNavStyle? style;

  /// Whether to pad for the bottom safe area (home indicator).
  final bool safeArea;

  @override
  State<ChukNavBar> createState() => _ChukNavBarState();
}

class _ChukNavBarState extends State<ChukNavBar> {
  /// Which tab currently owns keyboard focus, if any (drives the focus ring).
  int? _focused;

  @override
  Widget build(BuildContext context) {
    final t = context.chukNav;
    final s = t.navStyle.merge(widget.style);

    // Aliased so the rest of the build body stays identical to upstream's,
    // which reads these straight off a StatelessWidget's fields.
    final items = widget.items;
    final index = widget.index;
    final collapsed = widget.collapsed;
    final onChanged = widget.onChanged;
    final safeArea = widget.safeArea;

    final n = items.length;
    final height = collapsed ? (s.collapsedHeight ?? 52) : (s.height ?? 64);
    final barRadius = s.radius ?? kChukPillRadius;
    final radius = BorderRadius.circular(barRadius);
    // Upstream falls back to the colour tokens (textPrimary / textTertiary).
    // Without them an unset colour falls back to the label colour, and a null
    // colour simply inherits from the ambient icon/text theme.
    final Color? activeColor = s.activeColor ?? t.labelStyle.color;
    final Color? inactiveColor = s.inactiveColor ?? activeColor;
    final iconSize = s.iconSize ?? 22;

    // Slot-centre alignment for the sliding highlight: -1 (first) … 1 (last).
    final alignX = n <= 1 ? 0.0 : -1 + 2 * index.clamp(0, n - 1) / (n - 1);

    Widget tab(int i) {
      final item = items[i];
      final active = i == index;
      final color = active ? activeColor : inactiveColor;
      // Only paint a ring while this tab holds keyboard focus.
      final ring = _focused == i && activeColor != null
          ? BorderSide(color: activeColor, width: 1.5)
          : BorderSide.none;
      // One merged node per tab: role + selected state from here, the label from
      // the Text below, the tap action from the GestureDetector, the focus
      // action from the FocusableActionDetector. Merging rather than excluding
      // the subtree is what keeps those actions on the node — without them a
      // reader announces a button it cannot press.
      return MergeSemantics(
        child: Semantics(
          button: true,
          selected: active,
          // Collapsed = no label on screen, so name the tab here instead. While
          // the Text is rendered it supplies the label; setting both would make
          // the reader say it twice.
          label: collapsed ? item.label : null,
          child: FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            onFocusChange: (has) => setState(() => _focused = has ? i : null),
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  onChanged(i);
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: SquircleBorder(radius: barRadius, side: ring),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: t.motion.medium,
                      child: Icon(
                        active ? (item.activeIcon ?? item.icon) : item.icon,
                        key: ValueKey(active),
                        size: iconSize,
                        color: color,
                      ),
                    ),
                    AnimatedSize(
                      duration: t.motion.medium,
                      curve: t.motion.standard,
                      child: collapsed
                          ? const SizedBox(width: 0, height: 0)
                          : Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                item.label,
                                style: t.labelStyle.copyWith(
                                  fontSize: 10,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: color,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final inner = Padding(
      padding: const EdgeInsets.all(3),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedAlign(
            alignment: Alignment(alignX, 0),
            duration: t.motion.medium,
            curve: t.motion.standard,
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: s.highlightColor ?? const Color(0x24FFFFFF),
                  borderRadius: radius,
                ),
              ),
            ),
          ),
          Row(children: [for (var i = 0; i < n; i++) Expanded(child: tab(i))]),
        ],
      ),
    );

    // A frosted-glass pill: the backdrop (content behind it) is blurred, then a
    // translucent chrome tint ([ChukColors.fillRaised]) and a bright rim are
    // laid over it. The blur is what makes it read as *glass* (not a white film)
    // and keeps the labels legible over a busy background.
    // Upstream: `?? t.colors.fillRaised`. The bridge always sets trackColor;
    // this falls through to ChukGlass's own default tint.
    final fill = s.trackColor ?? const Color(0x24FFFFFF);

    Widget bar = ChukGlass(
      shape: SquircleBorder(radius: barRadius),
      fill: fill,
      // No rim in dark (the supported theme) — the bar lies raw with no border.
      // Light/glass keeps a faint rim (experimental).
      highlight: t.isLight
          ? const Color.fromRGBO(255, 255, 255, 0.55)
          : const Color(0x00000000),
      blurSigma: 34,
      shadow: s.shadow,
      child: AnimatedSize(
        duration: t.motion.medium,
        curve: t.motion.standard,
        child: SizedBox(height: height, child: inner),
      ),
    );

    bar = Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: bar);

    if (safeArea) {
      bar = SafeArea(top: false, child: bar);
    }
    return bar;
  }
}
