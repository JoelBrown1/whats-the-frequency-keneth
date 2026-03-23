// lib/dsp/models/frequency_response.dart
// Result of the DSP pipeline for a single measurement.
// frequencyHz is computed from constants — not stored in JSON.

import 'dart:math';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';

/// A detected resonance peak within the frequency response.
class ResonancePeak {
  final double frequencyHz;
  final double magnitudeDb;
  final double qFactor;

  /// Lower -3 dB point.
  final double fLowHz;

  /// Upper -3 dB point.
  final double fHighHz;

  const ResonancePeak({
    required this.frequencyHz,
    required this.magnitudeDb,
    required this.qFactor,
    required this.fLowHz,
    required this.fHighHz,
  });
}

/// Constants for the 361 log-spaced frequency bins used throughout the app.
const int kFrequencyBins = 361;
const double kFrequencyMinHz = 20.0;
const double kFrequencyMaxHz = 20000.0;

/// Compute the 361 log-spaced frequency axis.
/// These values are determined by algorithm constants and recomputed at load
/// time — they are never stored in JSON.
List<double> computeFrequencyAxis() {
  final axis = List<double>.filled(kFrequencyBins, 0.0);
  final logMin = log(kFrequencyMinHz) / ln10;
  final logMax = log(kFrequencyMaxHz) / ln10;
  for (int i = 0; i < kFrequencyBins; i++) {
    final logF = logMin + (i / (kFrequencyBins - 1)) * (logMax - logMin);
    axis[i] = pow(10.0, logF).toDouble();
  }
  return axis;
}

class FrequencyResponse {
  /// 361 log-spaced bins, 20–20000 Hz — computed from constants, not persisted.
  final List<double> frequencyHz;

  /// Magnitude at each bin in dB — persisted in Measurement JSON.
  final List<double> magnitudeDb;

  /// All peaks detected above -20 dB relative threshold.
  final List<ResonancePeak> peaks;

  /// Highest peak within ResonanceSearchBand.
  final ResonancePeak primaryPeak;

  /// Config used — stored with result for comparability guard.
  final SweepConfig sweepConfig;

  final DateTime analyzedAt;

  const FrequencyResponse({
    required this.frequencyHz,
    required this.magnitudeDb,
    required this.peaks,
    required this.primaryPeak,
    required this.sweepConfig,
    required this.analyzedAt,
  });
}
