// lib/audio/audio_engine_platform_interface.dart
// Abstract interface for the audio engine platform channel.
// Implementations: AudioEngineMethodChannel (real), MockAudioEnginePlatform (test/debug).

import 'dart:typed_data';
import 'package:whats_the_frequency/audio/models/capture_result.dart';

/// Device descriptor returned by getAvailableDevices.
class AudioDeviceDescriptor {
  final String uid;
  final String name;
  final double nativeSampleRate;

  const AudioDeviceDescriptor({
    required this.uid,
    required this.name,
    required this.nativeSampleRate,
  });

  factory AudioDeviceDescriptor.fromMap(Map<dynamic, dynamic> map) =>
      AudioDeviceDescriptor(
        uid: map['uid'] as String,
        name: map['name'] as String,
        nativeSampleRate: (map['nativeSampleRate'] as num).toDouble(),
      );
}

abstract class AudioEnginePlatformInterface {
  static AudioEnginePlatformInterface? _instance;

  static AudioEnginePlatformInterface get instance {
    assert(_instance != null,
        'AudioEnginePlatformInterface.instance must be set before use.');
    return _instance!;
  }

  static set instance(AudioEnginePlatformInterface value) {
    _instance = value;
  }

  /// Enumerate available audio devices.
  Future<List<AudioDeviceDescriptor>> getAvailableDevices();

  /// Select an audio device by UID.
  /// Throws PlatformException with code DEVICE_NOT_FOUND if UID unknown.
  Future<void> setDevice(String uid);

  /// Returns the active hardware sample rate in Hz.
  /// Throws PlatformException with code NO_DEVICE_SELECTED if no device set.
  Future<double> getActiveSampleRate();

  /// Play sweep and capture input.
  /// Throws: DROPOUT_DETECTED, DEVICE_DISCONNECTED, SAMPLE_RATE_MISMATCH,
  ///         OUTPUT_CLIPPING.
  Future<CaptureResult> runCapture(
      Float32List sweepSamples, int sampleRate, int postRollMs, int sweepIndex);

  /// Cancel an in-progress capture.
  Future<void> cancelCapture();

  /// Begin streaming level meter values via the level_meter EventChannel.
  Future<void> startLevelMeter();

  /// Stop the level meter stream.
  Future<void> stopLevelMeter();

  /// Stream of dBFS level meter values (~10 Hz).
  Stream<double> get levelMeterStream;

  /// Stream of device add/remove events.
  Stream<Map<String, dynamic>> get deviceEventStream;
}
