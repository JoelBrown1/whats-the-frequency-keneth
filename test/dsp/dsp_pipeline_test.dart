// test/dsp/dsp_pipeline_test.dart
// Tests for the DSP deconvolution pipeline.
// Calls runPipelineMultiple directly (pure Dart, no isolate overhead).

import 'dart:typed_data';

import 'package:fftea/fftea.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whats_the_frequency/calibration/models/chain_calibration.dart';
import 'package:whats_the_frequency/dsp/dsp_isolate.dart';
import 'package:whats_the_frequency/dsp/log_sine_sweep.dart';
import 'package:whats_the_frequency/dsp/models/dsp_pipeline_input.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

int _nextPow2(int n) {
  int p = 1;
  while (p < n) {
    p <<= 1;
  }
  return p;
}

/// Create a flat (identity) H_chain: real=1, imag=0 everywhere.
DspPipelineInput _buildInput({
  required Float32List capturedSamples,
  int sampleRate = 48000,
  double f1Hz = 20.0,
  double f2Hz = 20000.0,
  double durationSeconds = 0.5,
  Float64List? hChainReal,
  Float64List? hChainImag,
  double searchLow = 200.0,
  double searchHigh = 15000.0,
}) {
  final real = hChainReal ?? (Float64List(kHChainBins)..fillRange(0, kHChainBins, 1.0));
  final imag = hChainImag ?? Float64List(kHChainBins);
  return DspPipelineInput(
    capturedSamples: capturedSamples,
    sampleRate: sampleRate,
    f1Hz: f1Hz,
    f2Hz: f2Hz,
    durationSeconds: durationSeconds,
    preRollMs: 10,
    postRollMs: 200,
    hChainReal: real,
    hChainImag: imag,
    searchBandLowHz: searchLow,
    searchBandHighHz: searchHigh,
  );
}

/// Generate a capture that IS the causal resonant impulse response h(t).
///
/// After ESS deconvolution in the pipeline:
///   ir_freq = FFT(h_resonant_padded) * invFilterFreq
///           ≈ H_resonant * invFilterFreq
///   ir      = h_resonant ⊛ invFilter
///
/// The invFilter has energy at ~4 kHz around index 5579 (time-reversed sweep),
/// so the deconvolved IR peaks near t=5579 — within _hannWindow's first-quarter
/// search range [0, fftSize/4] = [0, 16384].
Float32List _makeCaptureDirect(
    LogSineSweep sweep, double f0, double q, int sampleRate) {
  final captureLen = sweep.sweep.length;
  // Use a power-of-2 FFT large enough to represent h_resonant without wrap.
  final n = _nextPow2(captureLen);
  final fft = FFT(n);
  final binHz = sampleRate / n;

  // Use a true bandpass H(f) = (j*f/f0/Q) / (1-(f/f0)^2 + j*(f/f0)/Q)
  // so that H(0)=0 (no DC component in h). This prevents the low-frequency,
  // high-amplitude part of the invFilter from dominating the deconvolved IR.
  // Real part: (f/f0/Q)^2 / D,  Imag: (1-(f/f0)^2)*(f/f0/Q) / D
  // where D = (1-(f/f0)^2)^2 + (f/f0/Q)^2. Peak magnitude = 1 at f = f0.
  final hSpec = Float64x2List(n);
  for (int k = 0; k <= n ~/ 2; k++) {
    final fHz = k * binHz;
    double hR, hI;
    if (fHz < 1.0) {
      hR = 0.0;
      hI = 0.0;
    } else {
      final fr = fHz / f0;
      final b = fr / q;
      final a = 1.0 - fr * fr;
      final denom = a * a + b * b;
      hR = b * b / denom;
      hI = a * b / denom;
    }
    hSpec[k] = Float64x2(hR, hI);
    if (k > 0 && k < n ~/ 2) {
      hSpec[n - k] = Float64x2(hR, -hI); // conjugate mirror
    }
  }

  // IFFT → causal resonant IR; decay ≈ 10 samples so no wrap-around at n=32768.
  final h = fft.realInverseFft(hSpec);
  return Float32List.fromList(
      h.sublist(0, captureLen).map((v) => v.toDouble()).toList());
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // Use a short sweep to keep tests fast.
  const sampleRate = 48000;
  const duration = 0.5; // seconds — 24 000 samples

  test('pipeline returns FrequencyResponse with 361 bins', () {
    final sweep = LogSineSweep(
        f1: 20, f2: 20000, durationSeconds: duration, sampleRate: sampleRate);
    final captured =
        _makeCaptureDirect(sweep, 4000.0, 3.0, sampleRate);

    final response =
        runPipeline(_buildInput(capturedSamples: captured, durationSeconds: duration));

    expect(response.frequencyHz.length, 361);
    expect(response.magnitudeDb.length, 361);
  });

  test('flat H_chain: pipeline runs without error and peak is in valid range',
      () {
    final sweep = LogSineSweep(
        f1: 20, f2: 20000, durationSeconds: duration, sampleRate: sampleRate);
    final captured =
        _makeCaptureDirect(sweep, 4000.0, 3.0, sampleRate);

    final response = runPipeline(_buildInput(
      capturedSamples: captured,
      durationSeconds: duration,
      // Flat H_chain by default (real=1, imag=0).
    ));

    expect(response.primaryPeak.frequencyHz, greaterThan(50.0));
    expect(response.primaryPeak.frequencyHz, lessThan(20000.0));
  });

  test('4 kHz resonance: primary peak is within ±600 Hz of 4000 Hz', () {
    final sweep = LogSineSweep(
        f1: 20, f2: 20000, durationSeconds: duration, sampleRate: sampleRate);
    final captured =
        _makeCaptureDirect(sweep, 4000.0, 3.0, sampleRate);

    final response = runPipeline(_buildInput(
        capturedSamples: captured,
        durationSeconds: duration,
        searchLow: 200.0,
        searchHigh: 15000.0));

    expect(
      response.primaryPeak.frequencyHz,
      closeTo(4000.0, 600.0),
      reason: 'Expected peak near 4 kHz, '
          'got ${response.primaryPeak.frequencyHz.toStringAsFixed(0)} Hz',
    );
  });

  test('Q-factor is positive and finite', () {
    final sweep = LogSineSweep(
        f1: 20, f2: 20000, durationSeconds: duration, sampleRate: sampleRate);
    final captured =
        _makeCaptureDirect(sweep, 4000.0, 3.0, sampleRate);

    final response =
        runPipeline(_buildInput(capturedSamples: captured, durationSeconds: duration));

    expect(response.primaryPeak.qFactor.isFinite, isTrue);
    expect(response.primaryPeak.qFactor, greaterThan(0.0));
  });

  test('search band exclusion: peak at 4 kHz not found when band is 6–15 kHz',
      () {
    final sweep = LogSineSweep(
        f1: 20, f2: 20000, durationSeconds: duration, sampleRate: sampleRate);
    final captured =
        _makeCaptureDirect(sweep, 4000.0, 3.0, sampleRate);

    final response = runPipeline(_buildInput(
        capturedSamples: captured,
        durationSeconds: duration,
        searchLow: 6000.0,
        searchHigh: 15000.0));

    // Primary peak must be within the specified search band.
    expect(response.primaryPeak.frequencyHz, greaterThanOrEqualTo(6000.0));
    expect(response.primaryPeak.frequencyHz, lessThanOrEqualTo(15000.0));
  });

  test('multiple captures averaged: two identical inputs give same peak', () {
    final sweep = LogSineSweep(
        f1: 20, f2: 20000, durationSeconds: duration, sampleRate: sampleRate);
    final captured =
        _makeCaptureDirect(sweep, 4000.0, 3.0, sampleRate);

    final inp =
        _buildInput(capturedSamples: captured, durationSeconds: duration);
    final single = runPipeline(inp);
    final averaged = runPipelineMultiple([inp, inp]);

    expect(
      averaged.primaryPeak.frequencyHz,
      closeTo(single.primaryPeak.frequencyHz, 10.0),
    );
  });
}
