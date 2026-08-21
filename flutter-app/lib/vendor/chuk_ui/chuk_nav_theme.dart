// Vendored from chuk_ui — git@github.com:chukfinley/chuk_ui.git
// Source: lib/src/theme/chuk_theme.dart + lib/src/theme/chuk_theme_data.dart +
// lib/src/tokens/chuk_motion.dart + lib/src/tokens/chuk_radii.dart
// @ commit 3ae5a1e (v0.4.2).
//
// COPIED, NOT A DEPENDENCY: the IzzyOnDroid reproducible build must not gain a
// new external (Git) dependency — see BUILDING.md. Only the slice the nav bar
// needs is vendored, not the whole package.
//
// Edits here are LOCAL and do NOT flow back to chuk_ui. Re-sync by hand against
// upstream and re-apply the deltas noted below.
//
// Delta vs upstream: heavily slimmed. Upstream's ChukThemeData carries the full
// token set (colors/spacing/radii/typography/motion) plus a resolved default
// style for every component, and ChukTheme also installs a DefaultTextStyle.
// ChukNavBar is the only component we vendored, so this scope carries only what
// it reads:
//   ChukColors      -> NOT vendored. Besser-Bahn is a Material app with its own
//                      palette (lib/theme/app_colors.dart -> ColorScheme); the
//                      bridge in lib/widgets/app_nav_bar.dart resolves every
//                      colour into [navStyle]. No second colour source.
//   ChukTypography  -> [ChukNavThemeData.labelStyle] (upstream: typography.caption).
//   ChukMotion      -> [ChukNavMotion] (medium + standard only).
//   ChukRadii.pill  -> [kChukPillRadius].
// The DefaultTextStyle wrapper is dropped: MaterialApp already provides one.

import 'package:flutter/widgets.dart';

import 'chuk_nav_style.dart';

/// Fully-rounded corner radius (pill / nav bar).
///
/// Upstream: `ChukRadii.pill`, 50 by default.
const double kChukPillRadius = 50;

/// The motion tokens [ChukNavBar] animates from.
///
/// Upstream: `ChukMotion` (which also carries fast/slow/emphasized — the nav bar
/// uses neither, so they are not vendored).
@immutable
class ChukNavMotion {
  const ChukNavMotion({
    this.medium = const Duration(milliseconds: 220),
    this.standard = Curves.easeOutCubic,
  });

  /// Duration of the gliding highlight, the icon swap and the label collapse.
  final Duration medium;

  /// Curve of the gliding highlight.
  final Curve standard;

  @override
  bool operator ==(Object other) =>
      other is ChukNavMotion &&
      other.medium == medium &&
      other.standard == standard;

  @override
  int get hashCode => Object.hash(medium, standard);
}

/// The design values [ChukNavBar] resolves against.
///
/// Upstream this is `ChukThemeData`; here it is the nav-bar slice of it. The
/// host app is expected to build this from its own theme (the "token bridge")
/// rather than from chuk_ui colour tokens, which are not vendored.
@immutable
class ChukNavThemeData {
  const ChukNavThemeData({
    required this.isLight,
    required this.navStyle,
    required this.labelStyle,
    this.motion = const ChukNavMotion(),
  });

  /// Whether the surrounding theme is light. Controls the sign of translucent
  /// overlays — and note that the light-mode glass look is upstream's
  /// *experimental* path; dark is the maintained one.
  final bool isLight;

  /// The resolved default style of the bar. Every colour the bar paints should
  /// be set here by the host app.
  final ChukNavStyle navStyle;

  /// Base text style of a tab label. Upstream: `ChukTypography.caption`.
  final TextStyle labelStyle;

  /// Motion tokens.
  final ChukNavMotion motion;

  @override
  bool operator ==(Object other) =>
      other is ChukNavThemeData &&
      other.isLight == isLight &&
      other.navStyle == navStyle &&
      other.labelStyle == labelStyle &&
      other.motion == motion;

  @override
  int get hashCode => Object.hash(isLight, navStyle, labelStyle, motion);
}

/// Provides a [ChukNavThemeData] to the subtree containing a [ChukNavBar].
///
/// Works inside a `MaterialApp` — like everything in chuk_ui it does not depend
/// on Material itself.
class ChukNavTheme extends InheritedWidget {
  const ChukNavTheme({super.key, required this.data, required super.child});

  /// The nav-bar design values exposed to descendants.
  final ChukNavThemeData data;

  /// Returns the nearest [ChukNavThemeData], or throws if there is none.
  ///
  /// Prefer the `context.chukNav` extension for brevity.
  static ChukNavThemeData of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<ChukNavTheme>();
    assert(
      inherited != null,
      'No ChukNavTheme found in context. Wrap the ChukNavBar in a '
      'ChukNavTheme(data: ...) — see lib/widgets/app_nav_bar.dart.',
    );
    return inherited!.data;
  }

  @override
  bool updateShouldNotify(ChukNavTheme oldWidget) => data != oldWidget.data;
}

/// Convenience access to the current [ChukNavThemeData].
extension ChukNavThemeContext on BuildContext {
  /// The nearest [ChukNavThemeData]. Throws if there is no [ChukNavTheme].
  ChukNavThemeData get chukNav => ChukNavTheme.of(this);
}
