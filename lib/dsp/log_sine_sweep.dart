// lib/dsp/log_sine_sweep.dart
// Generates a log-sine sweep and its pre-computed inverse filter for deconvolution.
//
// Sweep formula:
//   θ(t) = 2π * f1 * T/ln(f2/f1) * (exp(t * ln(f2/f1) / T) - 1)
//   x(t) = sin(θ(t))
//
// Inverse filter = time-reversed sweep with amplitude envelope correction:
//   inv[n] = sweep[N-1-n] * exp(-t[n] * ln(f2/f1) / T)

import 'dart:math';
import 'dart:typed_data';

class LogSineSweep {
  final double f1;
  final double f2;
  final double durationSeconds;
  final int sampleRate;

  late final Float64List sweep;
  late final Float64List inverseFilter;

  LogSineSweep({
    this.f1 = 20.0,
    this.f2 = 20000.0,
    this.durationSeconds = 3.0,
    this.sampleRate = 48000,
  }) {
    _generate();
  }

  void _generate() {
    final n = (durationSeconds * sampleRate).round();
    final t = Float64List(n);
    final s = Float64List(n);

    final logRatio = log(f2 / f1);
    final k = 2 * pi * f1 * durationSeconds / logRatio;

    for (int i = 0; i < n; i++) {
      final ti = i / sampleRate;
      t[i] = ti;
      final theta = k * (exp(ti * logRatio / durationSeconds) - 1.0);
      s[i] = sin(theta);
    }

    sweep = s;

    // Inverse filter: time-reversed sweep with amplitude envelope correction.
    final inv = Float64List(n);
    for (int i = 0; i < n; i++) {
      final ti = t[n - 1 - i];
      final envelope = exp(-ti * logRatio / durationSeconds);
      inv[i] = s[n - 1 - i] * envelope;
    }
    inverseFilter = inv;
  }

  /// Total number of samples.
  int get sampleCount => sweep.length;
}
