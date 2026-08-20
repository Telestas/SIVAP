import 'package:flutter/material.dart';

import 'tokens.dart';

/// Tema global. Deja el color y la tipografía en manos de [T]; aquí solo se
/// conectan al `ThemeData` de Material.
final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  fontFamily: T.sans,
  scaffoldBackgroundColor: T.surface,
  colorScheme: ColorScheme.fromSeed(
    seedColor: T.accent,
    primary: T.accent,
    surface: T.surface,
    onSurface: T.ink,
    error: T.dangerFg,
  ),
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
  textSelectionTheme: const TextSelectionThemeData(cursorColor: T.accent),
  dividerTheme: const DividerThemeData(color: T.lineHair, thickness: 1, space: 1),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: T.ink,
    contentTextStyle: TextStyle(color: T.onInk, fontFamily: T.sans),
  ),
);
