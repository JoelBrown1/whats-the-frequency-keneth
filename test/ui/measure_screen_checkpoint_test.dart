// test/ui/measure_screen_checkpoint_test.dart
// Widget tests for MeasureScreen checkpoint resume behaviour.
//
// Coverage:
//   Config mismatch — checkpoint.clear() called before sweep loop
//   All captures preloaded (sweepCount == preloaded) — engine never called
//   Partial preload (1 of 2) — engine called exactly once
//
// Design notes:
//   • _FakeCheckpointService is fully in-memory to eliminate real file-I/O
//     races with the FakeAsync test zone.
//   • pumpAndSettle is not used (CircularProgressIndicator has infinite
//     animation; GoRouter animations can also prevent settling).
//     Fixed pump(duration) calls advance the fake clock instead.
//   • alignmentComputerProvider is overridden with a synchronous stub
//     (offset = 0) so no real Isolate.run is needed in tests.
//   • Tests 1–2 do not need GoRouter (context.push is not reached).
//     Test 3 uses GoRouter so the push to /results does not throw.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whats_the_frequency/audio/audio_engine_platform_interface.dart';
import 'package:whats_the_frequency/audio/audio_engine_service.dart';
import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/audio/models/device_config.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/calibration/calibration_service.dart';
import 'package:whats_the_frequency/calibration/models/chain_calibration.dart';
import 'package:whats_the_frequency/data/capture_checkpoint_service.dart';
import 'package:whats_the_frequency/dsp/dsp_pipeline_service.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/l10n/app_localizations.dart';
import 'package:whats_the_frequency/providers/audio_engine_platform_provider.dart';
import 'package:whats_the_frequency/providers/audio_engine_provider.dart';
import 'package:whats_the_frequency/providers/calibration_provider.dart';
import 'package:whats_the_frequency/providers/alignment_provider.dart';
import 'package:whats_the_frequency/providers/capture_checkpoint_provider.dart';
import 'package:whats_the_frequency/providers/device_config_provider.dart';
import 'package:whats_the_frequency/providers/dsp_provider.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';
import 'package:whats_the_frequency/providers/sweep_config_provider.dart';
import 'package:whats_the_frequency/ui/screens/measure_screen.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kSweepCount1 = SweepConfig(
  f1Hz: 20.0,
  f2Hz: 20000.0,
  durationSeconds: 0.1,
  sampleRate: 48000,
  sweepCount: 1,
  preRollMs: 10,
  postRollMs: 20,
);

const _kSweepCount2 = SweepConfig(
  f1Hz: 20.0,
  f2Hz: 20000.0,
  durationSeconds: 0.1,
  sampleRate: 48000,
  sweepCount: 2,
  preRollMs: 10,
  postRollMs: 20,
);

const _kDifferentConfig = SweepConfig(
  f1Hz: 40.0, // different f1 — reliably triggers config-mismatch branch
  f2Hz: 18000.0,
  durationSeconds: 0.2,
  sampleRate: 44100,
  sweepCount: 3,
);

const _kDeviceConfig = DeviceConfig(
  deviceUid: 'uid',
  deviceName: 'Scarlett',
  sampleRate: 48000,
  mainsMeasured: true,
);

// ─── In-memory fake checkpoint ────────────────────────────────────────────────
// Overrides all I/O methods so tests are fully deterministic within the
// FakeAsync zone — no real file system operations.

class _FakeCheckpointService extends CaptureCheckpointService {
  SweepConfig? _config;
  final List<CaptureResult> _captures;
  int clearCallCount = 0;

  _FakeCheckpointService({
    SweepConfig? config,
    List<CaptureResult>? captures,
  })  : _config = config,
        _captures = captures ?? [];

  @override
  Future<bool> hasCheckpoint() async =>
      _config != null && _captures.isNotEmpty;

  @override
  Future<SweepConfig?> readConfig() async => _config;

  @override
  Future<List<CaptureResult>> readCaptures(SweepConfig config) async =>
      List.from(_captures);

  @override
  Future<void> writeConfig(SweepConfig config) async => _config = config;

  @override
  Future<void> writeCapture(int index, CaptureResult capture) async =>
      _captures.add(capture);

  @override
  Future<void> clear() async {
    clearCallCount++;
    _config = null;
    _captures.clear();
  }
}

// ─── Mocks ────────────────────────────────────────────────────────────────────

class _MockPlatform extends Mock implements AudioEnginePlatformInterface {}

class _MockCalibrationService extends Mock implements CalibrationService {
  @override
  ValueNotifier<int> sweepProgress = ValueNotifier(0);
}

class _MockDspService extends Mock implements DspPipelineService {}

// ─── Recording engine ─────────────────────────────────────────────────────────

class _RecordingEngine extends AudioEngineService {
  final bool throwOnCapture;
  int runCaptureCallCount = 0;

  _RecordingEngine({this.throwOnCapture = false});

  @override
  AudioEngineServiceState build() =>
      const AudioEngineServiceState(state: AudioEngineState.idle);

  @override
  Future<CaptureResult> runCapture(
      SweepConfig config, Float32List sweepSamples) async {
    if (throwOnCapture) {
      state = AudioEngineServiceState(
        state: AudioEngineState.recoverableError,
        error: const AudioEngineError(
          code: 'TEST_ERROR',
          message: 'Forced failure',
          isRecoverable: true,
        ),
      );
      throw StateError('Forced runCapture failure');
    }
    runCaptureCallCount++;
    state = const AudioEngineServiceState(state: AudioEngineState.capturing);
    // 100 zero samples → computeAlignmentOffset returns 0 (< 500 threshold)
    return CaptureResult(
      samples: Float32List(100),
      sampleRate: config.sampleRate,
      sweepIndex: runCaptureCallCount - 1,
      capturedAt: DateTime.now(),
    );
  }

  @override
  Future<void> cancelCapture() async {}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

ChainCalibration _flatCalibration() => ChainCalibration(
      id: 'cal-001',
      timestamp: DateTime(2025),
      hChainReal: Float64List(kHChainBins)..fillRange(0, kHChainBins, 1.0),
      hChainImag: Float64List(kHChainBins),
      sweepConfig: _kSweepCount1,
    );

FrequencyResponse _fakeDspResponse() {
  const peak = ResonancePeak(
    frequencyHz: 4000,
    magnitudeDb: 0,
    qFactor: 2,
    fLowHz: 3000,
    fHighHz: 5000,
  );
  return FrequencyResponse(
    frequencyHz: computeFrequencyAxis(),
    magnitudeDb: List.filled(kFrequencyBins, 0.0),
    peaks: [peak],
    primaryPeak: peak,
    sweepConfig: _kSweepCount1,
    analyzedAt: DateTime(2025),
  );
}

CaptureResult _miniCapture(int index) => CaptureResult(
      samples: Float32List(100),
      sampleRate: 48000,
      sweepIndex: index,
      capturedAt: DateTime(2025),
    );

// Plain MaterialApp — used when context.push('/results') is not reached.
Widget _wrapPlain({required List<Override> overrides}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MeasureScreen(),
      ),
    );

// Router-aware wrapper — used when the full flow reaches context.push.
Widget _wrapRouter({required List<Override> overrides}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const MeasureScreen()),
      GoRoute(
          path: '/results',
          builder: (_, __) => const Scaffold(body: Text('Results'))),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

// Synchronous alignment stub — always returns offset 0 (within the ±500 sample
// plausibility window) so no real Isolate.run is needed in tests.
Future<int> _syncAlignment(Float32List _, Float64List __) async => 0;

// Pump several frames to drain fake-async microtasks without triggering the
// pumpAndSettle hang from CircularProgressIndicator or GoRouter animations.
Future<void> _pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // Fallback values required by mocktail when any() is used for these types
    // as arguments to processMultiple().
    registerFallbackValue(_FakeChainCalibration());
    registerFallbackValue(const ResonanceSearchBand());
    registerFallbackValue(const SweepConfig());
    registerFallbackValue(<CaptureResult>[]);
  });

  late _MockPlatform platform;
  late _MockCalibrationService cal;

  setUp(() {
    platform = _MockPlatform();
    when(() => platform.deviceEventStream)
        .thenAnswer((_) => const Stream.empty());

    cal = _MockCalibrationService();
    when(() => cal.isCalibrationValid()).thenReturn(true);
    when(() => cal.activeCalibration).thenReturn(_flatCalibration());

    SharedPreferences.setMockInitialValues({});
  });

  // ── Config mismatch → clear() called ─────────────────────────────────────
  // Checkpoint has _kDifferentConfig + 2 captures.  runCapture throws so the
  // sweep loop is aborted after the checkpoint clear.
  // Assertion: checkpoint.clearCallCount == 1 (clear was called once).

  testWidgets('config mismatch: checkpoint.clear() called before any capture',
      (tester) async {
    final checkpoint = _FakeCheckpointService(
      config: _kDifferentConfig,
      captures: [_miniCapture(0), _miniCapture(1)],
    );
    final mockDsp = _MockDspService();
    final engine = _RecordingEngine(throwOnCapture: true);

    await tester.pumpWidget(_wrapPlain(
      overrides: [
        audioEnginePlatformProvider.overrideWithValue(platform),
        calibrationProvider.overrideWith((_) => cal),
        sweepConfigProvider.overrideWithValue(_kSweepCount2),
        captureCheckpointProvider.overrideWithValue(checkpoint),
        dspProvider.overrideWithValue(mockDsp),
        audioEngineProvider.overrideWith(() => engine),
        deviceConfigProvider.overrideWith(() => _FixedDeviceConfig(_kDeviceConfig)),
      ],
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.mic), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mic));
    await _pumpFrames(tester, count: 15);

    expect(checkpoint.clearCallCount, 1,
        reason: 'Config mismatch must invoke clear() exactly once');
    verifyNever(() => mockDsp.processMultiple(any(), any(), any(), any(),
        mainsHz: any(named: 'mainsHz')));
  });

  // ── All captures preloaded — engine never called ──────────────────────────
  // sweepCount=1, 1 preloaded → while loop never entered → runCapture=0.

  testWidgets('all captures preloaded: engine.runCapture never called',
      (tester) async {
    final checkpoint = _FakeCheckpointService(
      config: _kSweepCount1,
      captures: [_miniCapture(0)],
    );
    final mockDsp = _MockDspService();
    when(() => mockDsp.processMultiple(any(), any(), any(), any(),
            mainsHz: any(named: 'mainsHz')))
        .thenAnswer((_) async => _fakeDspResponse());

    final engine = _RecordingEngine();

    // Use GoRouter so context.push('/results') succeeds.
    await tester.pumpWidget(_wrapRouter(
      overrides: [
        audioEnginePlatformProvider.overrideWithValue(platform),
        calibrationProvider.overrideWith((_) => cal),
        sweepConfigProvider.overrideWithValue(_kSweepCount1),
        captureCheckpointProvider.overrideWithValue(checkpoint),
        dspProvider.overrideWithValue(mockDsp),
        audioEngineProvider.overrideWith(() => engine),
        deviceConfigProvider.overrideWith(() => _FixedDeviceConfig(_kDeviceConfig)),
      ],
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // GoRouter init
    expect(find.byIcon(Icons.mic), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mic));
    // No Isolate.run (loop skipped) and no inter-sweep delay.
    // Only fake I/O + mocked DSP — pure microtask resolution.
    await _pumpFrames(tester, count: 15);

    expect(engine.runCaptureCallCount, 0,
        reason: 'Loop skipped when preloaded == sweepCount');
    verify(() => mockDsp.processMultiple(any(), any(), any(), any(),
        mainsHz: any(named: 'mainsHz'))).called(1);
  });

  // ── Partial preload — engine called exactly once ──────────────────────────
  // sweepCount=2, 1 preloaded → loop runs once.
  // The last capture (sweepCount reached) does NOT trigger an inter-sweep
  // delay (the delay is only inserted between sweeps, not after the last one).
  // Isolate.run(computeAlignmentOffset) runs outside FakeAsync; tester.runAsync
  // gives it real time to complete.

  testWidgets('partial preload: engine.runCapture called once (not twice)',
      (tester) async {
    final checkpoint = _FakeCheckpointService(
      config: _kSweepCount2,
      captures: [_miniCapture(0)],
    );
    final mockDsp = _MockDspService();
    when(() => mockDsp.processMultiple(any(), any(), any(), any(),
            mainsHz: any(named: 'mainsHz')))
        .thenAnswer((_) async => _fakeDspResponse());

    final engine = _RecordingEngine();

    await tester.pumpWidget(_wrapRouter(
      overrides: [
        audioEnginePlatformProvider.overrideWithValue(platform),
        calibrationProvider.overrideWith((_) => cal),
        sweepConfigProvider.overrideWithValue(_kSweepCount2),
        captureCheckpointProvider.overrideWithValue(checkpoint),
        dspProvider.overrideWithValue(mockDsp),
        audioEngineProvider.overrideWith(() => engine),
        deviceConfigProvider.overrideWith(() => _FixedDeviceConfig(_kDeviceConfig)),
        // Replace Isolate.run(computeAlignmentOffset) with a synchronous
        // stub so no real isolate is needed in the FakeAsync test zone.
        alignmentComputerProvider.overrideWithValue(_syncAlignment),
      ],
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // GoRouter init
    expect(find.byIcon(Icons.mic), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mic));
    await _pumpFrames(tester, count: 15);

    expect(engine.runCaptureCallCount, 1,
        reason: 'With 1 preloaded and sweepCount=2, engine called exactly once');
    verify(() => mockDsp.processMultiple(any(), any(), any(), any(),
        mainsHz: any(named: 'mainsHz'))).called(1);
  });
}

// ─── Fakes / fallbacks ────────────────────────────────────────────────────────

class _FakeChainCalibration extends Fake implements ChainCalibration {}

// ─── Fixed DeviceConfig notifier ──────────────────────────────────────────────

class _FixedDeviceConfig extends DeviceConfigNotifier {
  final DeviceConfig _config;
  _FixedDeviceConfig(this._config);

  @override
  Future<DeviceConfig> build() async => _config;
}
