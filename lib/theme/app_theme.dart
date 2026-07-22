import 'package:flutter/material.dart';
import 'package:geolonia_design_tokens/geolonia_design_tokens.dart';

/// This app's typography scale: matches Flutter's stock Material 3 default
/// text sizes rather than [GeoloniaFontSizes], which read too large for this
/// app's dense desktop layout (e.g. a 56px panel header).
abstract final class _AppFontSizes {
  static const double headingL = 22.0;
  static const double headingM = 16.0;
  static const double headingS = 14.0;
  static const double body = 16.0;
  static const double caption = 12.0;
}

/// Dark-mode chrome colors derived from [GeoloniaColors.structureNavy].
///
/// The geolonia_design_tokens package only ships a light palette, so these
/// are hand-derived to stay on-brand (navy base) while meeting dark-theme
/// contrast expectations.
const Color geoloniaDarkBackground = Color(0xFF141E33);
const Color geoloniaDarkSurface = Color(0xFF202D4A);
const Color geoloniaDarkBorder = Color(0xFF3A4A6B);
const Color geoloniaDarkTextPrimary = Color(0xFFF2F4F7);
const Color geoloniaDarkTextSecondary = Color(0xFFA9B3C4);

/// The Geolonia [ColorScheme], dark variant, built around
/// [GeoloniaColors.structureNavy] with the same brand primary/error accents
/// used by the light theme.
const ColorScheme geoloniaDarkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: GeoloniaColors.actionPrimary,
  onPrimary: Colors.white,
  primaryContainer: GeoloniaColors.actionPrimaryHover,
  onPrimaryContainer: Colors.white,
  secondary: GeoloniaColors.actionAccent,
  onSecondary: Colors.white,
  error: GeoloniaColors.statusDanger,
  onError: Colors.white,
  errorContainer: GeoloniaColors.statusDangerText,
  onErrorContainer: Colors.white,
  surface: geoloniaDarkBackground,
  onSurface: geoloniaDarkTextPrimary,
  surfaceContainerHighest: geoloniaDarkSurface,
  onSurfaceVariant: geoloniaDarkTextSecondary,
  outline: geoloniaDarkBorder,
);

TextTheme _appTextTheme(
  TextTheme base,
  Color textPrimary,
  Color textSecondary,
) {
  return base.copyWith(
    titleLarge: base.titleLarge?.copyWith(
      fontSize: _AppFontSizes.headingL,
      fontWeight: GeoloniaFontWeights.bold,
      color: textPrimary,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: _AppFontSizes.headingM,
      fontWeight: GeoloniaFontWeights.bold,
      color: textPrimary,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontSize: _AppFontSizes.headingS,
      fontWeight: GeoloniaFontWeights.bold,
      color: textPrimary,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontSize: _AppFontSizes.body,
      fontWeight: GeoloniaFontWeights.regular,
      height: geoloniaLineHeightBody,
      color: textPrimary,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: _AppFontSizes.body,
      fontWeight: GeoloniaFontWeights.regular,
      height: geoloniaLineHeightBody,
      color: textPrimary,
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: _AppFontSizes.caption,
      fontWeight: GeoloniaFontWeights.regular,
      color: textSecondary,
    ),
  );
}

/// The app's light theme: Geolonia's default color scheme with this app's
/// compact typography scale in place of the design system's larger sizes.
ThemeData appLightTheme() {
  final ThemeData base = ThemeData(
    useMaterial3: true,
    colorScheme: geoloniaColorScheme,
    scaffoldBackgroundColor: GeoloniaColors.background,
    fontFamily: geoloniaFontFamily,
    fontFamilyFallback: geoloniaFontFamilyBase.sublist(1),
  );

  return base.copyWith(
    textTheme: _appTextTheme(
      base.textTheme,
      GeoloniaColors.textPrimary,
      GeoloniaColors.textSecondary,
    ),
  );
}

/// The app's dark theme, paired with [appLightTheme].
ThemeData appDarkTheme() {
  final ThemeData base = ThemeData(
    useMaterial3: true,
    colorScheme: geoloniaDarkColorScheme,
    scaffoldBackgroundColor: geoloniaDarkBackground,
    fontFamily: geoloniaFontFamily,
    fontFamilyFallback: geoloniaFontFamilyBase.sublist(1),
  );

  return base.copyWith(
    textTheme: _appTextTheme(
      base.textTheme,
      geoloniaDarkTextPrimary,
      geoloniaDarkTextSecondary,
    ),
  );
}
