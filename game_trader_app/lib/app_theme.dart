import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const primaryColor = Color(0xFF137fec);
  static const backgroundLight = Color(0xFFf6f7f8);
  static const backgroundDark = Color(0xFF0b0e11);
  static const surfaceDark = Color(0xFF161b22);
  static const borderDark = Color(0xFF21262d);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundDark,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        surface: surfaceDark,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryColor),
        ),
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIconColor: Colors.grey,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          minimumSize: const Size(double.infinity, 56),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}
