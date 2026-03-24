// lib/main.dart
// App entry point.
// Routes: SplashScreen decides onboarding vs home based on DeviceConfig.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/l10n/app_localizations.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';

import 'ui/screens/calibration_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/measure_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/results_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
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
      home: const SplashScreen(),
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/home': (_) => const HomeScreen(),
        '/setup': (_) => const SetupScreen(),
        '/calibration': (_) => const CalibrationScreen(),
        '/measure': (_) => const MeasureScreen(),
        '/results': (ctx) => ResultsScreen(
              frequencyResponse: ModalRoute.of(ctx)!.settings.arguments
                  as FrequencyResponse?,
            ),
        '/history': (_) => const HistoryScreen(),
      },
    );
  }
}

/// Async splash — reads DeviceConfig then routes to onboarding or home.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(deviceConfigProvider);
    return configAsync.when(
      data: (config) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final route =
              config.onboardingComplete ? '/home' : '/onboarding';
          Navigator.of(context).pushReplacementNamed(route);
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushReplacementNamed('/onboarding');
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
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
