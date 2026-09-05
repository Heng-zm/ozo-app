import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/chat_provider.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Check CLI arguments for instance index / profile
  int? instanceIndex;
  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--instance=')) {
      instanceIndex = int.tryParse(arg.split('=').last);
    } else if (arg == '-i' && i + 1 < args.length) {
      instanceIndex = int.tryParse(args[i + 1]);
    } else if (arg.startsWith('--profile=')) {
      instanceIndex = int.tryParse(arg.split('=').last);
    }
  }

  // 2. Check environment variable for instance index
  if (instanceIndex == null) {
    final envVal = Platform.environment['OZO_INSTANCE'] ?? Platform.environment['APP_INSTANCE'];
    if (envVal != null) {
      instanceIndex = int.tryParse(envVal);
    }
  }

  // 3. Auto-detect if Instance 1 is already active on this machine
  if (instanceIndex == null && !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    instanceIndex = await _detectLocalInstance();
  }

  final activeInstance = instanceIndex ?? 1;

  final chatProvider = ChatProvider();
  await chatProvider.initialize(instanceIndex: activeInstance);

  runApp(
    ChangeNotifierProvider.value(
      value: chatProvider,
      child: LanTelegramApp(instanceIndex: activeInstance),
    ),
  );
}

/// Detects if another instance is already running on port 45455
Future<int> _detectLocalInstance() async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 300);
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:45455/api/health'));
    final resp = await req.close().timeout(const Duration(milliseconds: 300));
    if (resp.statusCode == HttpStatus.ok) {
      final text = await utf8.decodeStream(resp);
      if (text.contains('ozo-p2p')) {
        client.close(force: true);
        return 2;
      }
    }
    client.close(force: true);
  } catch (_) {}
  return 1;
}

class LanTelegramApp extends StatelessWidget {
  final int instanceIndex;
  const LanTelegramApp({super.key, this.instanceIndex = 1});

  @override
  Widget build(BuildContext context) {
    final title = instanceIndex > 1 ? 'OZO (Device $instanceIndex)' : 'OZO';
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: TelegramTheme.lightTheme,
      darkTheme: TelegramTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
