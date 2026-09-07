import 'package:flutter/material.dart';

import '../vendor/chuk_ui/chuk_glass.dart';
import '../vendor/chuk_ui/chuk_nav_theme.dart' show kChukPillRadius;
import '../vendor/chuk_ui/chuk_squircle.dart';

/// A floating frosted-glass panel: the vendored [ChukGlass]
/// (`lib/vendor/chuk_ui/`) wired into *this* app's theme.
///
/// This is the same bridge `lib/widgets/app_nav_bar.dart` is for the bottom
/// bar, for everything that is not a nav bar. chuk_ui is deliberately
/// Material-free and resolves its look from chuk_ui colour tokens, which we did
/// not vendor — Besser-Bahn already has a palette. So this widget maps the
/// Material [ColorScheme] (which `AppTheme` seeds from `AppColors.dbRed`) onto
/// [ChukGlass]'s colours: every colour still comes from the single source in
/// `lib/theme/`, and none is defined twice.
///
/// Glass only reads as glass over something. Put a panel *over* scrolling
/// content (a [Stack], not a [Column]) or it is just a tinted box over the
/// scaffold background.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = _radius,
    this.flush = false,
  });

  /// Content laid over the glass.
  final Widget child;

  /// A full-bleed band instead of a floating panel: square corners, no rim, no
  /// drop shadow — so an edge-to-edge strip (the transport filter) reads as
  /// glass laid *behind* its chips, not as a pill hovering over the page (#38).
  final bool flush;

  /// Corner radius of the squircle. [SquircleBorder] clamps it to half the
  /// short edge, so [pillRadius] turns any low strip into a pill without the
  /// caller having to know the strip's height.
  final double radius;

  /// A fully-rounded strip — the bottom nav bar's own shape
  /// (chuk_ui's `ChukRadii.pill`).
  static const pillRadius = kChukPillRadius;

  /// Default corner radius for a *block* of glass (a form, a card). The pill
  /// radius would swallow a tall panel's corners whole.
  static const _radius = 24.0;

  /// Opacity of the panel's tint over the blurred backdrop.
  ///
  /// Deliberately heavier than the nav bar's chrome tint (chuk_ui's
  /// `ChukColors.surfaceOpacity`, 0.58 dark / 0.30 light — mirrored privately
  /// in `AppNavBar`). The nav bar tints four short labels; a panel carries
  /// station names, a date and filter chips over *moving* content, and those
  /// have to stay readable at every scroll offset, not on average.
  ///
  /// Worst case in light mode is a near-black pixel of a result card sitting
  /// behind a label: at 0.70 the tint still keeps `onSurface` text near 6:1
  /// against it, where the nav bar's 0.30 would drop it to ~2.6:1 and fail.
  /// The blur ([_blurSigma]) means that worst case is not actually reachable —
  /// it smears any such pixel across ~34 px first — so this is the pessimistic
  /// bound, and there is still plenty of motion visible through the glass.
  static const _tintOpacityDark = 0.72;
  static const _tintOpacityLight = 0.70;

  /// Gaussian blur of the backdrop — the nav bar's value (`chuk_nav_bar.dart`
  /// hardcodes 34). The blur is what makes the panel read as *glass* rather
  /// than as a film, and what keeps labels legible over a busy backdrop.
  static const _blurSigma = 34.0;

  /// The bright hairline rim, light mode only — the nav bar's own decision
  /// (dark glass lies raw with no border, see `chuk_nav_bar.dart`).
  static const _rimOpacity = 0.55;

  /// Drop-shadow opacity that lifts the floating panel — chuk_ui's nav shadow
  /// (0x57000000 dark / 0x1A000000 light), expressed via [ColorScheme.shadow].
  static const _shadowOpacityDark = 0.34;
  static const _shadowOpacityLight = 0.10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    return ChukGlass(
      shape: SquircleBorder(radius: flush ? 0 : radius),
      fill: colors.surfaceContainerHigh.withValues(
        alpha: isLight ? _tintOpacityLight : _tintOpacityDark,
      ),
      highlight: (isLight && !flush)
          ? colors.surfaceBright.withValues(alpha: _rimOpacity)
          : const Color(0x00000000),
      blurSigma: _blurSigma,
      shadow: flush
          ? const []
          : [
              BoxShadow(
                color: colors.shadow.withValues(
                  alpha: isLight ? _shadowOpacityLight : _shadowOpacityDark,
                ),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
      child: child,
    );
  }
}

/// Round glass button for map chrome — the same pane of glass the search bar
/// and the nav bar are made of, in the footprint of a small FAB.
///
/// Map controls used to be opaque [FloatingActionButton]s and [Material]
/// cards. Over a live map that reads as a stack of unrelated widgets pasted on
/// top, and it hides the very thing the rider is looking at. Everything that
/// floats over content in this app is glass; these are no exception.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 40,
    this.active = false,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  /// Tints the glyph in the app's accent — for a control that is *on*, where
  /// an opaque button would have been filled.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final button = GlassPanel(
      radius: GlassPanel.pillRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(
                  size: 20,
                  color: active ? colors.primary : colors.onSurface,
                ),
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null
        ? button
        : Tooltip(message: tooltip!, child: button);
  }
}

/// Pill-shaped glass button with an icon and a label — the map's "Legende" and
/// "Bahnsteigplan" controls, and anything else that floats over content.
class GlassPillButton extends StatelessWidget {
  const GlassPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? tooltip;

  /// An *on* control keeps the glass and colours its content in the accent,
  /// instead of turning into an opaque block.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = active ? colors.primary : colors.onSurface;
    final pill = GlassPanel(
      radius: GlassPanel.pillRadius,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GlassPanel.pillRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}
