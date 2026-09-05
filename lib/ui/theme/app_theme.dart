import 'package:flutter/material.dart';

/// Telegram-inspired theme styling
class TelegramTheme {
  // Telegram Brand Colors
  static const Color primaryBlue = Color(0xFF2AABEE);
  static const Color primaryDarkBlue = Color(0xFF229ED9);
  static const Color accentCyan = Color(0xFF00C2ED);

  // Light Mode Colors
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSidebar = Color(0xFFF4F4F5);
  static const Color lightChatBg = Color(0xFFE6EEF5);
  static const Color lightOutgoingBubble = Color(0xFFEFFDDE);
  static const Color lightIncomingBubble = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF222222);
  static const Color lightTextSecondary = Color(0xFF707579);

  // Dark Mode Colors
  static const Color darkBackground = Color(0xFF0E1621);
  static const Color darkSidebar = Color(0xFF17212B);
  static const Color darkChatBg = Color(0xFF0E1621);
  static const Color darkOutgoingBubble = Color(0xFF2B5278);
  static const Color darkIncomingBubble = Color(0xFF182533);
  static const Color darkTextPrimary = Color(0xFFF5F5F5);
  static const Color darkTextSecondary = Color(0xFF7E8B99);

  // Status & Badges
  static const Color onlineGreen = Color(0xFF4ECC5F);
  static const Color offlineGrey = Color(0xFF9E9E9E);
  static const Color checkmarkBlue = Color(0xFF4FAE4E);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.light,
      primary: primaryBlue,
      surface: lightBackground,
    ),
    scaffoldBackgroundColor: lightBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: lightBackground,
      elevation: 0.5,
      iconTheme: IconThemeData(color: lightTextPrimary),
      titleTextStyle: TextStyle(
        color: lightTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.dark,
      primary: primaryBlue,
      surface: darkBackground,
    ),
    scaffoldBackgroundColor: darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: darkSidebar,
      elevation: 0.5,
      iconTheme: IconThemeData(color: darkTextPrimary),
      titleTextStyle: TextStyle(
        color: darkTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
