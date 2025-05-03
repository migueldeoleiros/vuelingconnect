import 'package:flutter/material.dart';

// Vueling colors
const vuelingYellow = Color(0xFFFFF000);
const vuelingGray = Color(0xFF58595B);

// Light theme
ThemeData getLightTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: vuelingYellow,
      brightness: Brightness.light,
    ),
  );
}

// Dark theme
ThemeData getDarkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    colorScheme: ColorScheme.dark(
      primary: vuelingYellow,
      secondary: vuelingYellow,
      surface: Colors.black,
      error: Colors.red[700]!,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      foregroundColor: vuelingYellow,
    ),
    cardTheme: const CardTheme(color: Color(0xFF121212)),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: vuelingYellow,
        foregroundColor: Colors.black,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: vuelingYellow),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: vuelingYellow.withOpacity(0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: vuelingYellow, width: 2),
      ),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: const Color(0xFF121212),
      titleTextStyle: TextStyle(
        color: vuelingYellow,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(backgroundColor: Color(0xFF1E1E1E)),
  );
}

// Status colors optimized for dark mode
Color getStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'scheduled':
      return Colors.blue[300]!;
    case 'departed':
      return Colors.green[300]!;
    case 'arrived':
      return Colors.purple[300]!;
    case 'delayed':
      return Colors.orange[300]!;
    case 'cancelled':
      return Colors.red[300]!;
    default:
      return Colors.grey[300]!;
  }
}
