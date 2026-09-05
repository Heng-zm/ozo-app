import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/chat_provider.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final chatProvider = ChatProvider();
  await chatProvider.initialize();

  runApp(
    ChangeNotifierProvider.value(
      value: chatProvider,
      child: const LanTelegramApp(),
    ),
  );
}

class LanTelegramApp extends StatelessWidget {
  const LanTelegramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LAN Telegram',
      debugShowCheckedModeBanner: false,
      theme: TelegramTheme.lightTheme,
      darkTheme: TelegramTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
