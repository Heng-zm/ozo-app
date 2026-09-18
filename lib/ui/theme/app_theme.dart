import 'package:flutter/material.dart';

/// Apple iOS / Cupertino inspired theme styling & tokens
class IosTheme {
  // Apple System Palette
  static const Color systemBlueLight = Color(0xFF007AFF);
  static const Color systemBlueDark = Color(0xFF0A84FF);
  static const Color systemGreen = Color(0xFF34C759);
  static const Color systemRed = Color(0xFFFF3B30);
  static const Color systemOrange = Color(0xFFFF9500);
  static const Color systemIndigo = Color(0xFF5856D6);

  // Apple System Grays
  static const Color systemGray = Color(0xFF8E8E93);
  static const Color systemGray2 = Color(0xFFAEAEB2);
  static const Color systemGray3 = Color(0xFFC7C7CC);
  static const Color systemGray4 = Color(0xFFD1D1D6);
  static const Color systemGray5Light = Color(0xFFE9E9EB);
  static const Color systemGray5Dark = Color(0xFF26252A);
  static const Color systemGray6Light = Color(0xFFF2F2F7);
  static const Color systemGray6Dark = Color(0xFF1C1C1E);

  // Hairline & Search
  static const Color hairlineLight = Color(0xFFC6C6C8);
  static const Color hairlineDark = Color(0xFF38383A);
  static const Color searchFieldLight = Color(0xFFE5E5EA);
  static const Color searchFieldDark = Color(0xFF1C1C1E);
}

/// Main app theme mapping to authentic iOS clean chat design
class TelegramTheme {
  // iOS System Accent Colors
  static const Color primaryBlue = Color(0xFF007AFF);
  static const Color primaryDarkBlue = Color(0xFF0A84FF);
  static const Color accentCyan = Color(0xFF007AFF);

  // Light Mode Colors (iOS iMessage Clean Aesthetic)
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSidebar = Color(0xFFF2F2F7);
  static const Color lightChatBg = Color(0xFFFFFFFF);
  static const Color lightOutgoingBubble = Color(0xFF007AFF);
  static const Color lightIncomingBubble = Color(0xFFE9E9EB);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF8E8E93);

  // Dark Mode Colors (iOS True Black & System Gray 5)
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSidebar = Color(0xFF1C1C1E);
  static const Color darkChatBg = Color(0xFF000000);
  static const Color darkOutgoingBubble = Color(0xFF0A84FF);
  static const Color darkIncomingBubble = Color(0xFF26252A);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF8E8E93);

  // Status & Badges
  static const Color onlineGreen = Color(0xFF34C759);
  static const Color offlineGrey = Color(0xFF8E8E93);
  static const Color checkmarkBlue = Color(0xFF007AFF);

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
      elevation: 0,
      scrolledUnderElevation: 0.5,
      iconTheme: IconThemeData(color: primaryBlue),
      titleTextStyle: TextStyle(
        color: lightTextPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: IosTheme.hairlineLight,
      thickness: 0.5,
      space: 0.5,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryDarkBlue,
      brightness: Brightness.dark,
      primary: primaryDarkBlue,
      surface: darkBackground,
    ),
    scaffoldBackgroundColor: darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBackground,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      iconTheme: IconThemeData(color: primaryDarkBlue),
      titleTextStyle: TextStyle(
        color: darkTextPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: IosTheme.hairlineDark,
      thickness: 0.5,
      space: 0.5,
    ),
  );
}
