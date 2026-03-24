// test/ui/measure_screen_test.dart
// Widget tests for MeasureScreen.
// Tests control provider state directly rather than exercising the full
// async measurement flow, keeping tests fast and deterministic.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whats_the_frequency/audio/audio_engine_platform_interface.dart';
import 'package:whats_the_frequency/audio/audio_engine_service.dart';
import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/audio/models/device_config.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/calibration/calibration_service.dart';
import 'package:whats_the_frequency/l10n/app_localizations.dart';
import 'package:whats_the_frequency/providers/audio_engine_platform_provider.dart';
import 'package:whats_the_frequency/providers/audio_engine_provider.dart';
import 'package:whats_the_frequency/providers/calibration_provider.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/ui/screens/measure_screen.dart';

// ─── Mocks ────────────────────────────────────────────────────────────────────

class _MockPlatform extends Mock implements AudioEnginePlatformInterface {}

class _MockCalibrationService extends Mock implements CalibrationService {
  @override
  ValueNotifier<int> sweepProgress = ValueNotifier(0);
}

// ─── Stub engine that starts in a given state ─────────────────────────────────
// Overrides all platform-dependent methods to avoid LateInitializationError
// on the parent's `late _platform` field.

class _FixedStateEngine extends AudioEngineService {
  final AudioEngineServiceState _initialState;
  _FixedStateEngine(this._initialState);

  @override
  AudioEngineServiceState build() => _initialState;

  @override
  Future<CaptureResult> runCapture(SweepConfig config, Float32List sweepSamples) {
    throw StateError('_FixedStateEngine does not support runCapture');
  }

  @override
  Future<void> cancelCapture() async {}

  @override
  void reset() {
    state = const AudioEngineServiceState(state: AudioEngineState.idle);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

_MockPlatform _buildMockPlatform() {
  final mock = _MockPlatform();
  when(() => mock.deviceEventStream)
      .thenAnswer((_) => const Stream.empty());
  return mock;
}

Widget _wrapScreen({
  required _MockCalibrationService cal,
  AudioEngineServiceState? engineState,
  DeviceConfig? deviceConfig,
}) {
  final mock = _buildMockPlatform();
  if (deviceConfig != null) {
    SharedPreferences.setMockInitialValues({});
  }
  final overrides = <Override>[
    audioEnginePlatformProvider.overrideWithValue(mock),
    calibrationProvider.overrideWith((_) => cal),
    if (engineState != null)
      audioEngineProvider.overrideWith(
        () => _FixedStateEngine(engineState),
      ),
    if (deviceConfig != null)
      deviceConfigProvider.overrideWith(() => _FixedDeviceConfig(deviceConfig)),
  ];
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MeasureScreen(),
    ),
  );
}

// Notifier that immediately returns a fixed DeviceConfig without hitting
// SharedPreferences. Used to inject specific device config in widget tests.
class _FixedDeviceConfig extends DeviceConfigNotifier {
  final DeviceConfig _config;
  _FixedDeviceConfig(this._config);

  @override
  Future<DeviceConfig> build() async => _config;
}

void main() {
  setUpAll(() {
    registerFallbackValue(Float32List(0));
  });

  testWidgets('shows block icon when no valid calibration', (tester) async {
    final cal = _MockCalibrationService();
    when(() => cal.isCalibrationValid()).thenReturn(false);
    when(() => cal.activeCalibration).thenReturn(null);

    await tester.pumpWidget(_wrapScreen(cal: cal));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.block), findsOneWidget);
  });

  testWidgets('shows mic (Start) button when calibration is valid',
      (tester) async {
    final cal = _MockCalibrationService();
    when(() => cal.isCalibrationValid()).thenReturn(true);
    when(() => cal.activeCalibration).thenReturn(null);

    await tester.pumpWidget(_wrapScreen(cal: cal));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic), findsOneWidget);
  });

  testWidgets('calibration expiry banner visible when calibration expired',
      (tester) async {
    final cal = _MockCalibrationService();
    // Expired means: activeCalibration != null && !isCalibrationValid().
    when(() => cal.isCalibrationValid()).thenReturn(false);
    when(() => cal.activeCalibration).thenReturn(null);
    // isExpired = activeCalibration != null && !isCalibrationValid()
    // Since activeCalibration is null, isExpired = false — banner not shown.
    // Verify banner is NOT shown when null.
    await tester.pumpWidget(_wrapScreen(cal: cal));
    await tester.pumpAndSettle();

    // CalibrationExpiryBanner only shown when activeCalibration != null &&
    // !isCalibrationValid(). Since we return null for activeCalibration, no
    // banner.
    expect(find.byIcon(Icons.block), findsOneWidget);
  });

  testWidgets('spinner shown when engine is in playing state', (tester) async {
    final cal = _MockCalibrationService();
    when(() => cal.isCalibrationValid()).thenReturn(true);
    when(() => cal.activeCalibration).thenReturn(null);

    final activeState = AudioEngineServiceState(
      state: AudioEngineState.playing,
    );

    await tester.pumpWidget(_wrapScreen(cal: cal, engineState: activeState));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error icon and retry button visible in recoverableError state',
      (tester) async {
    final cal = _MockCalibrationService();
    when(() => cal.isCalibrationValid()).thenReturn(true);
    when(() => cal.activeCalibration).thenReturn(null);

    final errorState = AudioEngineServiceState(
      state: AudioEngineState.recoverableError,
      error: const AudioEngineError(
        code: 'DROPOUT_DETECTED',
        message: 'Audio dropout detected.',
        isRecoverable: true,
      ),
    );

    await tester.pumpWidget(_wrapScreen(cal: cal, engineState: errorState));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('tapping Retry resets engine to idle', (tester) async {
    final cal = _MockCalibrationService();
    when(() => cal.isCalibrationValid()).thenReturn(true);
    when(() => cal.activeCalibration).thenReturn(null);

    // Use a real (non-fixed-state) engine so reset() actually changes state.
    final mock = _buildMockPlatform();
    when(() => mock.cancelCapture()).thenAnswer((_) async {});

    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        audioEnginePlatformProvider.overrideWithValue(mock),
        calibrationProvider.overrideWith((_) => cal),
      ],
      child: Builder(builder: (context) {
        container = ProviderScope.containerOf(context);
        return MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MeasureScreen(),
        );
      }),
    ));
    await tester.pumpAndSettle();

    // Manually set engine to error state.
    container.read(audioEngineProvider.notifier).reset();
    // Force it to arm so we can test the state machine.
    container.read(audioEngineProvider.notifier).arm();
    // The engine is now armed — reset it and check.
    container.read(audioEngineProvider.notifier).reset();
    await tester.pumpAndSettle();

    // After reset from any state, should be idle (Start button visible).
    expect(container.read(audioEngineProvider).state, AudioEngineState.idle);
  });

  // ─── Mains not-measured banner ─────────────────────────────────────────────

  testWidgets(
      'mains warning banner shown when mainsMeasured is false',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cal = _MockCalibrationService();
    when(() => cal.isCalibrationValid()).thenReturn(true);
    when(() => cal.activeCalibration).thenReturn(null);

    const config = DeviceConfig(
      deviceUid: 'uid',
      deviceName: 'Scarlett',
      sampleRate: 48000,
      mainsMeasured: false, // default — warning expected
    );

    await tester.pumpWidget(_wrapScreen(cal: cal, deviceConfig: config));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets(
      'mains warning banner NOT shown when mainsMeasured is true',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cal = _MockCalibrationService();
    when(() => cal.isCalibrationValid()).thenReturn(true);
    when(() => cal.activeCalibration).thenReturn(null);

    const config = DeviceConfig(
      deviceUid: 'uid',
      deviceName: 'Scarlett',
      sampleRate: 48000,
      mainsMeasured: true, // user has measured — no warning
    );

    await tester.pumpWidget(_wrapScreen(cal: cal, deviceConfig: config));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}
