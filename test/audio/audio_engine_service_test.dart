// test/audio/audio_engine_service_test.dart
// Unit tests for AudioEngineService state machine.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:whats_the_frequency/audio/audio_engine_platform_interface.dart';
import 'package:whats_the_frequency/audio/audio_engine_service.dart';
import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/providers/audio_engine_platform_provider.dart';
import 'package:whats_the_frequency/providers/audio_engine_provider.dart';

class _MockPlatform extends Mock implements AudioEnginePlatformInterface {}

// Streams wired up per test.
late StreamController<Map<String, dynamic>> _deviceEventCtrl;

ProviderContainer _buildContainer(_MockPlatform mock) {
  return ProviderContainer(
    overrides: [
      audioEnginePlatformProvider.overrideWithValue(mock),
    ],
  );
}

_MockPlatform _buildMockWithCapture({
  int sampleRate = 48000,
  bool throwDropout = false,
}) {
  final mock = _MockPlatform();
  _deviceEventCtrl = StreamController<Map<String, dynamic>>.broadcast();

  when(() => mock.deviceEventStream).thenAnswer((_) => _deviceEventCtrl.stream);
  when(() => mock.cancelCapture()).thenAnswer((_) async {});

  if (throwDropout) {
    when(() => mock.runCapture(any(), any(), any(), any()))
        .thenThrow(PlatformException(code: 'DROPOUT_DETECTED'));
  } else {
    when(() => mock.runCapture(any(), any(), any(), any()))
        .thenAnswer((_) async => CaptureResult(
              samples: Float32List(sampleRate),
              sampleRate: sampleRate,
              sweepIndex: 0,
              capturedAt: DateTime.now(),
            ));
  }
  return mock;
}

void main() {
  setUpAll(() {
    registerFallbackValue(Float32List(0));
  });

  tearDown(() {
    _deviceEventCtrl.close();
  });

  test('initial state is idle', () {
    final mock = _buildMockWithCapture();
    final container = _buildContainer(mock);
    addTearDown(container.dispose);

    final state = container.read(audioEngineProvider).state;
    expect(state, AudioEngineState.idle);
  });

  test('arm() from idle → armed', () {
    final mock = _buildMockWithCapture();
    final container = _buildContainer(mock);
    addTearDown(container.dispose);

    container.read(audioEngineProvider.notifier).arm();
    expect(container.read(audioEngineProvider).state, AudioEngineState.armed);
  });

  test('arm() from non-idle throws StateError', () {
    final mock = _buildMockWithCapture();
    final container = _buildContainer(mock);
    addTearDown(container.dispose);

    container.read(audioEngineProvider.notifier).arm();
    expect(
      () => container.read(audioEngineProvider.notifier).arm(),
      throwsStateError,
    );
  });

  test('runCapture() transitions armed → analyzing and returns CaptureResult',
      () async {
    final mock = _buildMockWithCapture();
    final container = _buildContainer(mock);
    addTearDown(container.dispose);

    final engine = container.read(audioEngineProvider.notifier);
    engine.arm();
    expect(container.read(audioEngineProvider).state, AudioEngineState.armed);

    const config = SweepConfig();
    final sweepSamples = Float32List(100);
    final result = await engine.runCapture(config, sweepSamples);

    expect(result, isA<CaptureResult>());
    expect(
        container.read(audioEngineProvider).state, AudioEngineState.analyzing);
  });

  test('sample rate mismatch → recoverableError (StateError caught by handler)',
      () async {
    // Platform returns a different sample rate than config.
    // Note: _transitionToDeviceError is called internally, but the subsequent
    // StateError is caught by 'on Object catch' which calls
    // _transitionToRecoverableError with code 'CAPTURE_ERROR', overwriting.
    final mock = _MockPlatform();
    _deviceEventCtrl = StreamController<Map<String, dynamic>>.broadcast();
    when(() => mock.deviceEventStream).thenAnswer((_) => _deviceEventCtrl.stream);
    when(() => mock.runCapture(any(), any(), any(), any()))
        .thenAnswer((_) async => CaptureResult(
              samples: Float32List(48000),
              sampleRate: 44100, // mismatch
              sweepIndex: 0,
              capturedAt: DateTime.now(),
            ));

    final container = _buildContainer(mock);
    addTearDown(container.dispose);

    final engine = container.read(audioEngineProvider.notifier);
    engine.arm();

    const config = SweepConfig(sampleRate: 48000);
    await expectLater(
      engine.runCapture(config, Float32List(100)),
      throwsStateError,
    );
    // The on-Object catch block fires after _transitionToDeviceError,
    // so final state is recoverableError with 'CAPTURE_ERROR' code.
    expect(container.read(audioEngineProvider).state,
        AudioEngineState.recoverableError);
  });

  test('DROPOUT_DETECTED PlatformException → recoverableError', () async {
    final mock = _buildMockWithCapture(throwDropout: true);
    final container = _buildContainer(mock);
    addTearDown(container.dispose);

    final engine = container.read(audioEngineProvider.notifier);
    engine.arm();

    await expectLater(
      engine.runCapture(const SweepConfig(), Float32List(100)),
      throwsA(isA<PlatformException>()),
    );
    expect(container.read(audioEngineProvider).state,
        AudioEngineState.recoverableError);
    expect(container.read(audioEngineProvider).error?.code,
        'DROPOUT_DETECTED');
  });

  test('device removed event → deviceError', () async {
    final mock = _buildMockWithCapture();
    final container = _buildContainer(mock);
    addTearDown(container.dispose);

    // Reading the provider triggers build(), which calls _subscribeToDeviceEvents().
    container.read(audioEngineProvider);
    await Future<void>.delayed(Duration.zero);

    // _activeDeviceUid is null because no capture has been started.
    // Emit the event with uid: null to match _activeDeviceUid == null.
    _deviceEventCtrl.add({'event': 'deviceRemoved', 'uid': null});
    await Future<void>.delayed(Duration.zero);

    expect(container.read(audioEngineProvider).state,
        AudioEngineState.deviceError);
  });

  test('cancelCapture() calls platform and returns to idle', () async {
    final mock = _buildMockWithCapture();
    final container = _buildContainer(mock);
    addTearDown(container.dispose);

    container.read(audioEngineProvider.notifier).arm();
    await container.read(audioEngineProvider.notifier).cancelCapture();

    verify(() => mock.cancelCapture()).called(1);
    expect(container.read(audioEngineProvider).state, AudioEngineState.idle);
  });

  test('reset() from recoverableError → idle', () async {
    final mock = _buildMockWithCapture(throwDropout: true);
    final container = _buildContainer(mock);
    addTearDown(container.dispose);

    final engine = container.read(audioEngineProvider.notifier);
    engine.arm();
    await expectLater(
      engine.runCapture(const SweepConfig(), Float32List(100)),
      throwsA(isA<PlatformException>()),
    );
    expect(container.read(audioEngineProvider).state,
        AudioEngineState.recoverableError);

    engine.reset();
    expect(container.read(audioEngineProvider).state, AudioEngineState.idle);
  });
}
