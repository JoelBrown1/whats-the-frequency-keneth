// lib/main.dart
// App entry point.
// Routes: SplashScreen decides onboarding vs home based on DeviceConfig.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:whats_the_frequency/l10n/app_localizations.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/routing/app_router.dart';

import 'ui/screens/measure_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: WtfkApp()));
}

class WtfkApp extends ConsumerWidget {
  const WtfkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: "What's the Frequency, Kenneth",
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
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
          final route = config.onboardingComplete ? '/home' : '/onboarding';
          context.go(route);
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
          context.go('/onboarding');
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
