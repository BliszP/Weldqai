// lib/theme/app_theme.dart

import 'package:flutter/material.dart';

class AppTheme {
static ThemeData light() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1E3A5F),
    brightness: Brightness.light,
    // Add this to override the auto-generated surface color:
    surface: const Color(0xFFF0F2F5),
  );
  
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF0F2F5),
    
    // WHITE cards that pop against gray background
    cardTheme: CardThemeData(
      margin: const EdgeInsets.all(8),
      elevation: 0,
      color: Colors.white, // CRITICAL: White cards, not gray
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Color(0xFFE0E0E0), width: 1), // Subtle border for definition
      ),
    ),
    
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1F2937), // Dark text
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.05),
    ),
    
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(const Color(0xFFF5F5F5)),
      dataRowMinHeight: 44,
      dataRowMaxHeight: 56,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: const Color(0xFFE3F2FD), // Light blue tint
      labelStyle: TextStyle(color: scheme.primary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE0E0E0),
      thickness: 1,
    ),
    
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

  static ThemeData dark() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1E3A5F),
    brightness: Brightness.dark,
    surface: const Color(0xFF1A1C1E), // Dark surface override
  );
  
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF111318),
    
    // Cards with proper dark theme colors
    cardTheme: CardThemeData(
      margin: const EdgeInsets.all(8),
      elevation: 0,
      color: const Color(0xFF1E2125), // Dark card background
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Color(0xFF2D3135), width: 1),
      ),
    ),
    
    // Input fields for dark mode
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2A2D31), // Dark input background
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: Colors.grey.shade700),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: Colors.grey.shade700),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF1E2125),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(const Color(0xFF2A2D31)),
      dataRowMinHeight: 44,
      dataRowMaxHeight: 56,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF3D4145)),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: const Color(0xFF2A2D31),
      labelStyle: TextStyle(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    
    dividerTheme: const DividerThemeData(
      color: Color(0xFF3D4145),
      thickness: 1,
    ),
    
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}
}
