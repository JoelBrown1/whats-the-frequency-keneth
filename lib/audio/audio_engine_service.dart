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

import 'package:flutter/services.dart';

import '../logging/app_logger.dart';
import '../providers/audio_engine_platform_provider.dart';
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
  late AudioEnginePlatformInterface _platform;

  @override
  AudioEngineServiceState build() {
    _platform = ref.watch(audioEnginePlatformProvider);
    _subscribeToDeviceEvents();
    ref.onDispose(() {
      _deviceEventSubscription?.cancel();
    });
    return const AudioEngineServiceState(state: AudioEngineState.idle);
  }

  void _subscribeToDeviceEvents() {
    _deviceEventSubscription = _platform.deviceEventStream.listen((event) {
      if (event['event'] == 'deviceRemoved' &&
          event['uid'] == _activeDeviceUid) {
        _transitionToDeviceError(
            'DEVICE_DISCONNECTED', 'Active device was disconnected.');
      }
    });
  }

  void _transitionToDeviceError(String code, String message) {
    appLog.e('[AudioEngine] Device error: $code — $message');
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
    appLog.w('[AudioEngine] Recoverable error: $code — $message');
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
    appLog.d('[AudioEngine] → armed');
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

      final capture = await _platform.runCapture(
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
      final code = e is PlatformException ? e.code : 'CAPTURE_ERROR';
      _transitionToRecoverableError(code, e.toString());
      rethrow;
    }
  }

  /// Mark analysis complete. Transitions Analyzing → Complete.
  void completeAnalysis(CaptureResult capture) {
    appLog.i('[AudioEngine] → complete (capturedAt: ${capture.capturedAt})');
    state = AudioEngineServiceState(
      state: AudioEngineState.complete,
      lastCapture: capture,
    );
  }

  /// Cancel an in-progress capture.
  Future<void> cancelCapture() async {
    await _platform.cancelCapture();
    reset();
  }

  /// Transition to recoverableError if the app is backgrounded mid-measurement.
  /// No-op when not in an active measurement state.
  void backgroundInterrupted() {
    if (_isActiveMeasurementState(state.state)) {
      _transitionToRecoverableError(
          'APP_BACKGROUNDED', 'App moved to background during measurement.');
    }
  }

  /// Transition to recoverableError when DSP processing throws.
  /// Called after the capture loop succeeds but Isolate.run fails.
  void processingFailed() {
    _transitionToRecoverableError(
        'DSP_FAILED', 'Signal processing failed. Please retry.');
  }

  static bool _isActiveMeasurementState(AudioEngineState s) =>
      s == AudioEngineState.armed ||
      s == AudioEngineState.playing ||
      s == AudioEngineState.capturing ||
      s == AudioEngineState.analyzing;
}
