import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens from the Figma file.
class EhbrColors {
  static const ink = Color(0xFF1E1E1E);
  static const brand = Color(0xFFC41E3A);
  static const sos = Color(0xFFD32F2F);
  static const brandLight = Color(0xFFFF6B7D);
  static const advisory = Color(0xFF0F4C81);
  static const community = Color(0xFF3F3F46);
  static const muted = Color(0xFF6B7280);
  static const card = Color(0x80DADADA);
  static const green = Color(0xFF34C759);
  static const amber = Color(0xFFF59E0B);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: EhbrColors.brand),
    scaffoldBackgroundColor: Colors.white,
  );
  return base.copyWith(textTheme: GoogleFonts.manropeTextTheme(base.textTheme));
}

TextStyle manrope(double size, FontWeight weight, Color color, {double? spacing}) =>
    GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing ?? size * 0.016,
    );
