// lib/main.dart
// App entry point. Registers mock platform in debug mode.
// Routes to onboarding or home based on lastCompletedOnboardingStep.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/l10n/app_localizations.dart';

import 'audio/audio_engine_method_channel.dart';
import 'audio/audio_engine_platform_interface.dart';
import 'audio/mock_audio_engine_platform.dart';
import 'ui/screens/calibration_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/measure_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/results_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  // Register mock platform in debug/test mode; real channel in release.
  if (kDebugMode) {
    AudioEnginePlatformInterface.instance = MockAudioEnginePlatform();
  } else {
    AudioEnginePlatformInterface.instance = AudioEngineMethodChannel();
  }

  runApp(const ProviderScope(child: WtfkApp()));
}

class WtfkApp extends StatelessWidget {
  const WtfkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "What's the Frequency, Kenneth",
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: '/onboarding',
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/home': (_) => const HomeScreen(),
        '/setup': (_) => const SetupScreen(),
        '/calibration': (_) => const CalibrationScreen(),
        '/measure': (_) => const MeasureScreen(),
        '/results': (_) => const ResultsScreen(),
        '/history': (_) => const HistoryScreen(),
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    SetupScreen(),
    MeasureScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.settings), label: 'Setup'),
          NavigationDestination(icon: Icon(Icons.mic), label: 'Measure'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}
