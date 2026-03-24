// lib/audio/mock_audio_engine_platform.dart
// Mock platform implementation for test/debug mode.
// Returns synthetic data without requiring real hardware.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'audio_engine_platform_interface.dart';
import 'models/capture_result.dart';

class MockAudioEnginePlatform extends AudioEnginePlatformInterface {
  static const _sampleRate = 48000;
  static const _mockDeviceUid = 'mock-device-001';

  final _levelMeterController = StreamController<double>.broadcast();
  final _deviceEventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Timer? _levelMeterTimer;

  @override
  Future<List<AudioDeviceDescriptor>> getAvailableDevices() async {
    return [
      const AudioDeviceDescriptor(
        uid: _mockDeviceUid,
        name: 'Scarlett 2i2 USB (Mock)',
        nativeSampleRate: 48000.0,
      ),
    ];
  }

  @override
  Future<void> setDevice(String uid) async {
    // Success — no-op for mock.
  }

  @override
  Future<double> getActiveSampleRate() async => _sampleRate.toDouble();

  @override
  Future<CaptureResult> runCapture(
      Float32List sweepSamples, int sampleRate, int postRollMs, int sweepIndex) async {
    // Simulate capture latency.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Generate 144,000 samples encoding a 4 kHz sine wave
    // (simulating a pickup resonance at 4 kHz with Q≈3).
    const numSamples = 144000;
    final samples = Float32List(numSamples);
    const f0 = 4000.0;
    const q = 3.0;
    const amplitude = 0.1;

    for (int i = 0; i < numSamples; i++) {
      final t = i / _sampleRate;
      // Damped sine to simulate a resonant pickup response.
      final decay = exp(-pi * f0 * t / q);
      samples[i] = (amplitude * decay * sin(2 * pi * f0 * t)).toDouble();
    }

    return CaptureResult(
      samples: samples,
      sampleRate: sampleRate,
      sweepIndex: sweepIndex,
      capturedAt: DateTime.now(),
    );
  }

  @override
  Future<void> cancelCapture() async {
    // No-op for mock.
  }

  @override
  Future<void> startLevelMeter() async {
    _levelMeterTimer?.cancel();
    _levelMeterTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // Emit a synthetic dBFS value around -12 dBFS.
      _levelMeterController.add(-12.0 + (Random().nextDouble() * 2.0 - 1.0));
    });
  }

  @override
  Future<void> stopLevelMeter() async {
    _levelMeterTimer?.cancel();
    _levelMeterTimer = null;
  }

  @override
  Future<void> startLevelCheckTone() => startLevelMeter();

  @override
  Future<void> stopLevelCheckTone() => stopLevelMeter();

  @override
  Stream<double> get levelMeterStream => _levelMeterController.stream;

  @override
  Stream<Map<String, dynamic>> get deviceEventStream =>
      _deviceEventsController.stream;

  void dispose() {
    _levelMeterTimer?.cancel();
    _levelMeterController.close();
    _deviceEventsController.close();
  }
}
