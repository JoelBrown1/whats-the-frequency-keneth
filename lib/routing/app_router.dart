// lib/routing/app_router.dart
// Type-safe routing via go_router.
//
// Route table:
//   /              → SplashScreen (redirects to /home or /onboarding)
//   /onboarding    → OnboardingScreen
//   /home          → HomeScreen (bottom-nav shell: Setup / Measure / History)
//   /calibration   → CalibrationScreen
//   /results       → ResultsScreen  (extra: FrequencyResponse?)
//   /history       → HistoryScreen

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/main.dart';
import 'package:whats_the_frequency/ui/screens/calibration_screen.dart';
import 'package:whats_the_frequency/ui/screens/history_screen.dart';
import 'package:whats_the_frequency/ui/screens/onboarding_screen.dart';
import 'package:whats_the_frequency/ui/screens/results_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/calibration',
        builder: (context, state) => const CalibrationScreen(),
      ),
      GoRoute(
        path: '/results',
        builder: (context, state) => ResultsScreen(
          frequencyResponse: state.extra as FrequencyResponse?,
        ),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
    ],
  );
});
