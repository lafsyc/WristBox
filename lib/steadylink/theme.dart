import 'package:flutter/material.dart';

class SteadyColors {
  const SteadyColors(this.dark);
  final bool dark;
  Color tone(int night, int day) => Color(dark ? night : day);
  Color get ink => tone(0xFFE9EAF0, 0xFF252534);
  Color get muted => tone(0xFF9295A5, 0xFF696979);
  Color get accent => tone(0xFFA69AFF, 0xFF6953D6);
  Color get onAccent => tone(0xFF211A39, 0xFFFFFFFF);
  Color get canvas => tone(0xFF14151A, 0xFFF6F6FA);
  Color get panel => tone(0xFF1B1C23, 0xFFFFFFFF);
  Color get edge => tone(0xFF2C2E38, 0xFFE3E3EC);
  Color get success => tone(0xFF7BD9AD, 0xFF18815B);
  Color get danger => tone(0xFFFF9EAA, 0xFFC03D57);
  Color get sidebar => tone(0xFF101115, 0xFFF0F0F6);
  Color get selected => tone(0xFF24232F, 0xFFE9E5FA);
  Color get selectedEdge => tone(0xFF393448, 0xFFD6CDF3);
  Color get wash => tone(0xFF242131, 0xFFF0ECFF);
  Color get washEnd => tone(0xFF1C1C25, 0xFFFAF9FF);
  Color get washEdge => tone(0xFF3C354E, 0xFFDED6F4);
  Color get iconWash => tone(0xFF332D46, 0xFFE6DFFB);
  Color get iconEdge => tone(0xFF4B4164, 0xFFD6CCF2);
  Color get successWash => tone(0xFF20312B, 0xFFE5F5ED);
  Color get dangerWash => tone(0xFF36232A, 0xFFFFEDF0);
}

extension SteadyContext on BuildContext {
  SteadyColors get colors =>
      SteadyColors(Theme.of(this).brightness == Brightness.dark);
}

ThemeData steadyTheme({Brightness brightness = Brightness.dark}) {
  final p = SteadyColors(brightness == Brightness.dark);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Microsoft YaHei UI',
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.accent,
      surface: p.panel,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      outline: p.edge,
      error: p.danger,
    ),
    scaffoldBackgroundColor: p.canvas,
    dividerColor: p.edge,
    dividerTheme: DividerThemeData(color: p.edge, thickness: 1),
    splashFactory: NoSplash.splashFactory,
    textTheme: TextTheme(
      headlineMedium: TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.w600,
        color: p.ink,
        letterSpacing: -.8,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      bodyMedium: TextStyle(fontSize: 13, color: p.ink, height: 1.5),
      bodySmall: TextStyle(fontSize: 11, color: p.muted, height: 1.5),
    ),
    iconTheme: IconThemeData(color: p.muted, size: 20),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.canvas,
      isDense: true,
      hintStyle: TextStyle(color: p.muted, fontSize: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.edge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.edge),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.accent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        textStyle: const TextStyle(
          fontFamily: 'Microsoft YaHei UI',
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.edge),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        textStyle: const TextStyle(
          fontFamily: 'Microsoft YaHei UI',
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.muted,
        textStyle: const TextStyle(
          fontFamily: 'Microsoft YaHei UI',
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.edge),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.panel,
      contentTextStyle: TextStyle(color: p.ink),
    ),
  );
}
