// lib/audio/models/capture_result.dart
// Result of a single sweep capture from the native audio layer.

import 'dart:typed_data';

class CaptureResult {
  /// Mono Float32 PCM, input channel 1.
  final Float32List samples;

  /// Hz — must equal SweepConfig.sampleRate; verified before processing.
  final int sampleRate;

  /// 0-based index within the N-sweep average.
  final int sweepIndex;

  final DateTime capturedAt;

  const CaptureResult({
    required this.samples,
    required this.sampleRate,
    required this.sweepIndex,
    required this.capturedAt,
  });
}
