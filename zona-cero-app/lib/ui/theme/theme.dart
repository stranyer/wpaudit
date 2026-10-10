import 'package:flutter/material.dart';

import 'tokens.dart';

/// Tema Material base con los tokens SUTURA.
ThemeData buildSuturaTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamily: Sutura.fUi);
  return base.copyWith(
    scaffoldBackgroundColor: Sutura.void_,
    canvasColor: Sutura.void_,
    colorScheme: const ColorScheme.dark(
      primary: Sutura.signal,
      onPrimary: Sutura.void_,
      secondary: Sutura.amber,
      onSecondary: Sutura.void_,
      error: Sutura.danger,
      surface: Sutura.surface1Solid,
      onSurface: Sutura.textHi,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Sutura.signal,
      selectionColor: Sutura.signal.withValues(alpha: 0.3),
      selectionHandleColor: Sutura.signal,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Sutura.signal),
  );
}
