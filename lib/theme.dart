import 'package:flutter/material.dart';

import 'config.dart';
import 'utils.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppConfig.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppConfig.primary,
    onPrimary: Colors.black,
    secondary: AppConfig.accent,
    surface: AppConfig.surface,
    onSurface: AppConfig.textPrimary,
    error: AppConfig.danger,
  );

  final radius = BorderRadius.circular(10);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: AppConfig.background,
    dividerColor: AppConfig.divider,
    // Simple fade between pages: no screenshot of the old page (lighter, avoids
    // crashes on some TV GPUs while a video is on screen).
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    }),
    splashFactory: NoSplash.splashFactory,
    focusColor: fade(AppConfig.primary, 0.30),
    hoverColor: fade(AppConfig.textPrimary, 0.05),
    dividerTheme: const DividerThemeData(color: AppConfig.divider, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppConfig.primary),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppConfig.surfaceHigh, borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: AppConfig.textPrimary, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppConfig.surfaceHigh,
      hintStyle: const TextStyle(color: AppConfig.textSecondary),
      prefixIconColor: AppConfig.textSecondary,
      suffixIconColor: AppConfig.textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppConfig.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppConfig.primary,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppConfig.surfaceHigh,
      contentTextStyle: const TextStyle(color: AppConfig.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6.0),
      thumbColor: WidgetStatePropertyAll(fade(AppConfig.textSecondary, 0.35)),
    ),
  );
}
