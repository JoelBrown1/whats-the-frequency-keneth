// lib/audio/models/sweep_config.dart
// Configuration for a log-sine sweep measurement.
// Two SweepConfig instances are considered equal if all fields match —
// used by the sweepConfig comparability guard on overlay.

class SweepConfig {
  final double f1Hz;
  final double f2Hz;
  final double durationSeconds;
  final int sampleRate;
  final int sweepCount;
  final int preRollMs;
  final int postRollMs;

  const SweepConfig({
    this.f1Hz = 20.0,
    this.f2Hz = 20000.0,
    this.durationSeconds = 3.0,
    this.sampleRate = 48000,
    this.sweepCount = 4,
    this.preRollMs = 512,
    this.postRollMs = 500,
  });

  Map<String, dynamic> toJson() => {
        'f1Hz': f1Hz,
        'f2Hz': f2Hz,
        'durationSeconds': durationSeconds,
        'sampleRate': sampleRate,
        'sweepCount': sweepCount,
        'preRollMs': preRollMs,
        'postRollMs': postRollMs,
      };

  factory SweepConfig.fromJson(Map<String, dynamic> json) => SweepConfig(
        f1Hz: (json['f1Hz'] as num?)?.toDouble() ?? 20.0,
        f2Hz: (json['f2Hz'] as num?)?.toDouble() ?? 20000.0,
        durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 3.0,
        sampleRate: (json['sampleRate'] as int?) ?? 48000,
        sweepCount: (json['sweepCount'] as int?) ?? 4,
        preRollMs: (json['preRollMs'] as int?) ?? 512,
        postRollMs: (json['postRollMs'] as int?) ?? 500,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SweepConfig &&
          runtimeType == other.runtimeType &&
          f1Hz == other.f1Hz &&
          f2Hz == other.f2Hz &&
          durationSeconds == other.durationSeconds &&
          sampleRate == other.sampleRate &&
          sweepCount == other.sweepCount &&
          preRollMs == other.preRollMs &&
          postRollMs == other.postRollMs;

  @override
  int get hashCode => Object.hash(
        f1Hz,
        f2Hz,
        durationSeconds,
        sampleRate,
        sweepCount,
        preRollMs,
        postRollMs,
      );
}
