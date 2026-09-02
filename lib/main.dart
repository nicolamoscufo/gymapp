import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_preferences.dart';
import 'app_theme.dart';
import 'local_notifications.dart';
import 'screens/home_ai_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
    // flutter_gemma applies exponential backoff for retryable network errors.
    // The lifecycle layer persists interrupted state so a killed process can
    // recover safely on the next launch.
    maxDownloadRetries: 10,
  );
  await LocalNotificationService.initialize();
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  ThemeMode _themeMode = AppPreferences.defaultThemeMode;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = AppPreferences.themeModeFromString(
        prefs.getString(AppPreferences.themeModeKey),
      );
    });
  }

  Future<void> _setThemeMode(ThemeMode themeMode) async {
    setState(() {
      _themeMode = themeMode;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppPreferences.themeModeKey,
      AppPreferences.themeModeToString(themeMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gym App',
      themeMode: _themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: HomeAiShell(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}
