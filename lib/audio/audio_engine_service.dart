// lib/audio/audio_engine_service.dart
// State machine for the measurement capture flow.
//
// State transitions:
//   Idle ←──────────── reset() ──────────────────────────┐
//     ↓                                                    │
//   Armed → Playing → Capturing → Analyzing → Complete   Error
//                                                 ↑       │
//                                         RecoverableError │
//                                         DeviceError ─────┘

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_engine_platform_interface.dart';
import 'models/capture_result.dart';
import 'models/sweep_config.dart';

/// All possible states of the audio engine.
enum AudioEngineState {
  idle,
  armed,
  playing,
  capturing,
  analyzing,
  complete,
  recoverableError,
  deviceError,
  fatalError,
}

/// Error details attached to error states.
class AudioEngineError {
  final String code;
  final String message;
  final bool isRecoverable;

  const AudioEngineError({
    required this.code,
    required this.message,
    required this.isRecoverable,
  });
}

/// State exposed by AudioEngineService.
class AudioEngineServiceState {
  final AudioEngineState state;
  final AudioEngineError? error;
  final CaptureResult? lastCapture;

  const AudioEngineServiceState({
    required this.state,
    this.error,
    this.lastCapture,
  });

  AudioEngineServiceState copyWith({
    AudioEngineState? state,
    AudioEngineError? error,
    CaptureResult? lastCapture,
  }) =>
      AudioEngineServiceState(
        state: state ?? this.state,
        error: error ?? this.error,
        lastCapture: lastCapture ?? this.lastCapture,
      );
}

class AudioEngineService extends Notifier<AudioEngineServiceState> {
  StreamSubscription<Map<String, dynamic>>? _deviceEventSubscription;
  String? _activeDeviceUid;

  @override
  AudioEngineServiceState build() {
    _subscribeToDeviceEvents();
    ref.onDispose(() {
      _deviceEventSubscription?.cancel();
    });
    return const AudioEngineServiceState(state: AudioEngineState.idle);
  }

  void _subscribeToDeviceEvents() {
    _deviceEventSubscription = AudioEnginePlatformInterface.instance
        .deviceEventStream
        .listen((event) {
      if (event['event'] == 'deviceRemoved' &&
          event['uid'] == _activeDeviceUid) {
        _transitionToDeviceError(
            'DEVICE_DISCONNECTED', 'Active device was disconnected.');
      }
    });
  }

  void _transitionToDeviceError(String code, String message) {
    state = AudioEngineServiceState(
      state: AudioEngineState.deviceError,
      error: AudioEngineError(
        code: code,
        message: message,
        isRecoverable: false,
      ),
    );
  }

  void _transitionToRecoverableError(String code, String message) {
    state = AudioEngineServiceState(
      state: AudioEngineState.recoverableError,
      error: AudioEngineError(
        code: code,
        message: message,
        isRecoverable: true,
      ),
    );
  }

  /// Reset state machine to Idle. Call after resolving any error.
  void reset() {
    state = const AudioEngineServiceState(state: AudioEngineState.idle);
  }

  /// Arm for measurement. Transitions Idle → Armed.
  void arm() {
    if (state.state != AudioEngineState.idle) {
      throw StateError('Can only arm from Idle state');
    }
    state = AudioEngineServiceState(state: AudioEngineState.armed);
  }

  /// Start measurement. Transitions Armed → Playing → Capturing → Analyzing.
  Future<CaptureResult> runCapture(SweepConfig config, Float32List sweepSamples) async {
    if (state.state != AudioEngineState.armed) {
      throw StateError('Must be Armed before running capture');
    }

    state = AudioEngineServiceState(state: AudioEngineState.playing);

    try {
      state = AudioEngineServiceState(state: AudioEngineState.capturing);

      final capture = await AudioEnginePlatformInterface.instance.runCapture(
        sweepSamples,
        config.sampleRate,
        config.postRollMs,
        0,
      );

      if (capture.sampleRate != config.sampleRate) {
        _transitionToDeviceError(
          'SAMPLE_RATE_MISMATCH',
          'Device sample rate ${capture.sampleRate} Hz does not match '
              'expected ${config.sampleRate} Hz.',
        );
        throw StateError('Sample rate mismatch');
      }

      state = AudioEngineServiceState(
        state: AudioEngineState.analyzing,
        lastCapture: capture,
      );

      return capture;
    } on Object catch (e) {
      final code = e is Exception ? 'CAPTURE_ERROR' : 'CAPTURE_ERROR';
      _transitionToRecoverableError(code, e.toString());
      rethrow;
    }
  }

  /// Mark analysis complete. Transitions Analyzing → Complete.
  void completeAnalysis(CaptureResult capture) {
    state = AudioEngineServiceState(
      state: AudioEngineState.complete,
      lastCapture: capture,
    );
  }

  /// Cancel an in-progress capture.
  Future<void> cancelCapture() async {
    await AudioEnginePlatformInterface.instance.cancelCapture();
    reset();
  }
}
