import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.dbRed,
      brightness: Brightness.light,
    );
    return _buildTheme(colorScheme);
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.dbRed,
      brightness: Brightness.dark,
    );
    return _buildTheme(_calmContainers(colorScheme));
  }

  /// Dark mode reads louder than light from the same recipe: Material's tonal
  /// containers keep their full chroma against a dark surface, so every tinted
  /// card, chip and notice pulls at once and nothing looks more important than
  /// anything else (#38 — "im Light Mode schick, im Dark Mode unruhig").
  ///
  /// Blend only the *area* colours a third of the way back into the surface.
  /// The accents that carry meaning — primary, error, the MessageCard's rule
  /// and title — keep their colour, so the hierarchy gets louder, not quieter:
  /// a cancelled train still shouts, a standing notice no longer does.
  static ColorScheme _calmContainers(ColorScheme s) {
    Color calm(Color c) => Color.alphaBlend(c.withAlpha(158), s.surface);
    return s.copyWith(
      primaryContainer: calm(s.primaryContainer),
      secondaryContainer: calm(s.secondaryContainer),
      tertiaryContainer: calm(s.tertiaryContainer),
      errorContainer: calm(s.errorContainer),
    );
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withAlpha(80),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      // No navigationBarTheme: the bottom bar is no longer Material's
      // NavigationBar but chuk_ui's floating glass bar, which reads this
      // ColorScheme through lib/widgets/app_nav_bar.dart.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
