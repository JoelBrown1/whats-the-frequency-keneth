// lib/audio/audio_engine_method_channel.dart
// Real platform channel implementation.
// MethodChannel: com.whatsthefrequency.app/audio_engine
// EventChannel (level meter): com.whatsthefrequency.app/level_meter
// EventChannel (device events): com.whatsthefrequency.app/device_events

import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'audio_engine_platform_interface.dart';
import 'models/capture_result.dart';

class AudioEngineMethodChannel extends AudioEnginePlatformInterface {
  static const _methodChannel =
      MethodChannel('com.whatsthefrequency.app/audio_engine');
  static const _levelMeterChannel =
      EventChannel('com.whatsthefrequency.app/level_meter');
  static const _deviceEventsChannel =
      EventChannel('com.whatsthefrequency.app/device_events');

  @override
  Future<List<AudioDeviceDescriptor>> getAvailableDevices() async {
    final result =
        await _methodChannel.invokeListMethod<Map>('getAvailableDevices');
    return (result ?? [])
        .map((m) => AudioDeviceDescriptor.fromMap(m))
        .toList();
  }

  @override
  Future<void> setDevice(String uid) async {
    await _methodChannel.invokeMethod<void>('setDevice', {'uid': uid});
  }

  @override
  Future<double> getActiveSampleRate() async {
    final result =
        await _methodChannel.invokeMethod<double>('getActiveSampleRate');
    return result ?? 48000.0;
  }

  @override
  Future<CaptureResult> runCapture(
      Float32List sweepSamples, int sampleRate, int postRollMs, int sweepIndex) async {
    // Convert Float32List to Uint8List for platform channel transfer.
    final byteData = sweepSamples.buffer.asByteData();
    final bytes = Uint8List.view(byteData.buffer);

    final result = await _methodChannel.invokeMethod<Uint8List>('runCapture', {
      'sweepSamples': bytes,
      'sampleRate': sampleRate,
      'postRollMs': postRollMs,
    });

    if (result == null) {
      throw PlatformException(code: 'NULL_RESULT', message: 'runCapture returned null');
    }

    // Reinterpret Uint8List as Float32List (Float32LE PCM).
    final capturedSamples = result.buffer.asFloat32List();
    return CaptureResult(
      samples: capturedSamples,
      sampleRate: sampleRate,
      sweepIndex: sweepIndex,
      capturedAt: DateTime.now(),
    );
  }

  @override
  Future<void> cancelCapture() async {
    await _methodChannel.invokeMethod<void>('cancelCapture');
  }

  @override
  Future<void> startLevelMeter() async {
    await _methodChannel.invokeMethod<void>('startLevelMeter');
  }

  @override
  Future<void> stopLevelMeter() async {
    await _methodChannel.invokeMethod<void>('stopLevelMeter');
  }

  @override
  Stream<double> get levelMeterStream =>
      _levelMeterChannel.receiveBroadcastStream().cast<double>();

  @override
  Stream<Map<String, dynamic>> get deviceEventStream =>
      _deviceEventsChannel
          .receiveBroadcastStream()
          .cast<Map<String, dynamic>>();
}
