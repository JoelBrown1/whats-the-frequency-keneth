// test/ui/onboarding_screen_test.dart
// Widget tests for OnboardingScreen.
// Verifies:
//   - Screen starts on Welcome step by default.
//   - Resumes at the persisted step on relaunch (mid-flow resume).
//   - The Mains step shows an Auto-detect button and 50/60 Hz chips.
//   - Next button is disabled on the Level step until checkbox is confirmed.
//   - Back button absent on Welcome, present on subsequent steps.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whats_the_frequency/audio/audio_engine_platform_interface.dart';
import 'package:whats_the_frequency/audio/models/device_config.dart';
import 'package:whats_the_frequency/l10n/app_localizations.dart';
import 'package:whats_the_frequency/providers/audio_engine_platform_provider.dart';
import 'package:whats_the_frequency/ui/screens/onboarding_screen.dart';

// ─── Mocks ────────────────────────────────────────────────────────────────────

class _MockPlatform extends Mock implements AudioEnginePlatformInterface {}

// ─── Helper ───────────────────────────────────────────────────────────────────

/// Builds the OnboardingScreen wrapped in a ProviderScope.
///
/// [deviceConfig] is injected via SharedPreferences so it is available
/// synchronously when _restoreStep() fires in the first frame.
Future<Widget> _wrapOnboarding(WidgetTester tester,
    {DeviceConfig? deviceConfig}) async {
  // Seed SharedPreferences before the provider reads it.
  if (deviceConfig != null) {
    SharedPreferences.setMockInitialValues({
      'device_config': jsonEncode(deviceConfig.toJson()),
    });
  } else {
    SharedPreferences.setMockInitialValues({});
  }

  final mock = _MockPlatform();
  when(() => mock.deviceEventStream).thenAnswer((_) => const Stream.empty());
  when(() => mock.getAvailableDevices()).thenAnswer((_) async => []);
  when(() => mock.levelMeterStream).thenAnswer((_) => Stream.value(-40.0));
  when(() => mock.startLevelMeter()).thenAnswer((_) async {});
  when(() => mock.stopLevelMeter()).thenAnswer((_) async {});
  when(() => mock.startLevelCheckTone()).thenAnswer((_) async {});
  when(() => mock.stopLevelCheckTone()).thenAnswer((_) async {});

  return ProviderScope(
    overrides: [
      audioEnginePlatformProvider.overrideWithValue(mock),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const OnboardingScreen(),
    ),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('starts on Welcome step when no progress persisted',
      (tester) async {
    final widget = await _wrapOnboarding(tester);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // The AppBar title is unique — the body also has "Welcome" but this
    // checks the AppBar specifically.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Welcome'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'resumes at Mains step when lastCompletedOnboardingStep == mains.index',
      (tester) async {
    const config = DeviceConfig(
      deviceUid: 'uid',
      deviceName: 'Scarlett',
      sampleRate: 48000,
      lastCompletedOnboardingStep: 3, // OnboardingStep.mains.index
    );

    final widget = await _wrapOnboarding(tester, deviceConfig: config);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Measure Mains Frequency'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Mains step shows Auto-detect button and 50/60 Hz chips',
      (tester) async {
    const config = DeviceConfig(
      deviceUid: 'uid',
      deviceName: 'Scarlett',
      sampleRate: 48000,
      lastCompletedOnboardingStep: 3,
    );

    final widget = await _wrapOnboarding(tester, deviceConfig: config);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.text('Auto-detect'), findsOneWidget);
    expect(find.text('50 Hz'), findsOneWidget);
    expect(find.text('60 Hz'), findsOneWidget);
  });

  testWidgets('Next button disabled on Level step until checkbox ticked',
      (tester) async {
    const config = DeviceConfig(
      deviceUid: 'uid',
      deviceName: 'Scarlett',
      sampleRate: 48000,
      lastCompletedOnboardingStep: 4, // OnboardingStep.level.index
    );

    final widget = await _wrapOnboarding(tester, deviceConfig: config);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    final nextButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Next'),
    );
    expect(nextButton.onPressed, isNull,
        reason: 'Next must be disabled until level checkbox is confirmed');
  });

  testWidgets('Back button absent on Welcome step', (tester) async {
    final widget = await _wrapOnboarding(tester);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsNothing);
  });

  testWidgets('Back button present on Hardware step and navigates to Welcome',
      (tester) async {
    const config = DeviceConfig(
      deviceUid: 'uid',
      deviceName: 'Scarlett',
      sampleRate: 48000,
      lastCompletedOnboardingStep: 1, // OnboardingStep.hardware.index
    );

    final widget = await _wrapOnboarding(tester, deviceConfig: config);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // After pressing Back, AppBar title should be Welcome.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Welcome'),
      ),
      findsOneWidget,
    );
  });
}
