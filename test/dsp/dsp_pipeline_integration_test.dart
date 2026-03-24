// test/dsp/dsp_pipeline_integration_test.dart
// Integration tests for the full 10-stage DSP pipeline.
// Session 7 goal: validate each pipeline stage against known synthetic inputs.
//
// Coverage:
//   DspPipelineService — async dispatch via Isolate.run (stages 1–10 end-to-end)
//   applyHumSuppression — Stage 7b unit tests on crafted spectra
//   chain correction — Stage 4: non-flat H_chain attenuates the boosted band
//   Tikhonov regularisation — Stage 4: near-zero H_chain must not produce NaN/Inf

import 'dart:math';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whats_the_frequency/audio/models/capture_result.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/calibration/models/chain_calibration.dart';
import 'package:whats_the_frequency/dsp/dsp_isolate.dart';
import 'package:whats_the_frequency/dsp/dsp_pipeline_service.dart';
import 'package:whats_the_frequency/dsp/log_sine_sweep.dart';
import 'package:whats_the_frequency/dsp/models/dsp_pipeline_input.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';
import 'package:whats_the_frequency/dsp/models/resonance_search_band.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kSampleRate = 48000;
const _kDuration = 0.5; // seconds — short sweep for test speed
const _kF1 = 20.0;
const _kF2 = 20000.0;

const _kSweepConfig = SweepConfig(
  f1Hz: _kF1,
  f2Hz: _kF2,
  durationSeconds: _kDuration,
  sampleRate: _kSampleRate,
);

const _kSearchBand = ResonanceSearchBand(lowHz: 200.0, highHz: 15000.0);

// ─── Helpers ──────────────────────────────────────────────────────────────────

int _nextPow2(int n) {
  int p = 1;
  while (p < n) p <<= 1;
  return p;
}

/// Synthetic "capture": creates a signal whose frequency response has a
/// resonant bandpass peak at [f0] Hz with quality factor [q].
///
/// The function places the frequency-domain bandpass shape into the FFT bins
/// of an N-point buffer (N = next-power-of-2 ≥ sweep length), then IFFTs to
/// produce a time-domain signal.  The deconvolution stage then convolves this
/// with the inverse filter, producing an IR whose peak falls within
/// _hannWindow's first-quarter search range.
Float32List _makeCaptureDirect(
    LogSineSweep sweep, double f0, double q, int sampleRate) {
  final captureLen = sweep.sweep.length;
  final n = _nextPow2(captureLen);
  final fft = FFT(n);
  final binHz = sampleRate / n;

  // Bandpass H(f) = (jf/f0/Q) / (1−(f/f0)² + j(f/f0)/Q).
  // Real: (f/f0/Q)² / D,  Imag: (1−(f/f0)²)(f/f0/Q) / D,
  // where D = (1−(f/f0)²)² + (f/f0/Q)².  H(0)=0; peak magnitude = 1 at f=f0.
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
  final h = fft.realInverseFft(hSpec);
  return Float32List.fromList(
      h.sublist(0, captureLen).map((v) => v.toDouble()).toList());
}

/// Build a [DspPipelineInput] with a flat (identity) H_chain by default.
DspPipelineInput _buildInput({
  required Float32List capturedSamples,
  double durationSeconds = _kDuration,
  Float64List? hChainReal,
  Float64List? hChainImag,
  double searchLow = 200.0,
  double searchHigh = 15000.0,
  double? mainsHz,
}) {
  final real =
      hChainReal ?? (Float64List(kHChainBins)..fillRange(0, kHChainBins, 1.0));
  final imag = hChainImag ?? Float64List(kHChainBins);
  return DspPipelineInput(
    capturedSamples: capturedSamples,
    sampleRate: _kSampleRate,
    f1Hz: _kF1,
    f2Hz: _kF2,
    durationSeconds: durationSeconds,
    preRollMs: 10,
    postRollMs: 200,
    hChainReal: real,
    hChainImag: imag,
    searchBandLowHz: searchLow,
    searchBandHighHz: searchHigh,
    mainsHz: mainsHz,
  );
}

/// Flat (identity) calibration: real=1, imag=0 across all bins.
ChainCalibration _flatCalibration() => ChainCalibration(
      id: 'test-cal',
      timestamp: DateTime(2025),
      hChainReal: Float64List(kHChainBins)..fillRange(0, kHChainBins, 1.0),
      hChainImag: Float64List(kHChainBins),
      sweepConfig: _kSweepConfig,
    );

/// Wrap samples in a [CaptureResult].
CaptureResult _capture(Float32List samples) => CaptureResult(
      samples: samples,
      sampleRate: _kSampleRate,
      sweepIndex: 0,
      capturedAt: DateTime(2025),
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late LogSineSweep sweep;
  late Float32List captured;

  setUp(() {
    sweep = LogSineSweep(
        f1: _kF1,
        f2: _kF2,
        durationSeconds: _kDuration,
        sampleRate: _kSampleRate);
    captured = _makeCaptureDirect(sweep, 4000.0, 3.0, _kSampleRate);
  });

  // ─── Full async integration via DspPipelineService ──────────────────────────
  // These tests exercise the complete async dispatch path (Isolate.run) and
  // validate end-to-end behaviour across all 10 pipeline stages.

  group('DspPipelineService', () {
    late DspPipelineService service;
    setUp(() => service = DspPipelineService());

    test('processMultiple returns a 361-bin FrequencyResponse', () async {
      final response = await service.processMultiple(
        [_capture(captured)],
        _flatCalibration(),
        _kSweepConfig,
        _kSearchBand,
      );
      expect(response.frequencyHz.length, kFrequencyBins);
      expect(response.magnitudeDb.length, kFrequencyBins);
    });

    test('processMultiple: primaryPeak falls within the search band', () async {
      final response = await service.processMultiple(
        [_capture(captured)],
        _flatCalibration(),
        _kSweepConfig,
        _kSearchBand,
      );
      expect(
        response.primaryPeak.frequencyHz,
        inInclusiveRange(_kSearchBand.lowHz, _kSearchBand.highHz),
        reason: 'Primary peak must be within 200–15000 Hz search band',
      );
    });

    test('processMultiple: qFactor is positive and finite', () async {
      final response = await service.processMultiple(
        [_capture(captured)],
        _flatCalibration(),
        _kSweepConfig,
        _kSearchBand,
      );
      expect(response.primaryPeak.qFactor.isFinite, isTrue);
      expect(response.primaryPeak.qFactor, greaterThan(0.0));
    });

    test('processMultiple: all magnitudeDb values are finite', () async {
      final response = await service.processMultiple(
        [_capture(captured)],
        _flatCalibration(),
        _kSweepConfig,
        _kSearchBand,
      );
      expect(
        response.magnitudeDb.every((v) => v.isFinite),
        isTrue,
        reason: 'No NaN or Infinity in output spectrum',
      );
    });

    test('processMultiple 2 captures: peak matches single-capture result',
        () async {
      final single = await service.processMultiple(
        [_capture(captured)],
        _flatCalibration(),
        _kSweepConfig,
        _kSearchBand,
      );
      final averaged = await service.processMultiple(
        [_capture(captured), _capture(captured)],
        _flatCalibration(),
        _kSweepConfig,
        _kSearchBand,
      );
      expect(
        averaged.primaryPeak.frequencyHz,
        closeTo(single.primaryPeak.frequencyHz, 10.0),
        reason: 'Averaging two identical captures must not shift the peak',
      );
    });

    test('processMultiple with mainsHz set produces a different spectrum',
        () async {
      final noSupp = await service.processMultiple(
        [_capture(captured)],
        _flatCalibration(),
        _kSweepConfig,
        _kSearchBand,
      );
      final withSupp = await service.processMultiple(
        [_capture(captured)],
        _flatCalibration(),
        _kSweepConfig,
        _kSearchBand,
        mainsHz: 50.0,
      );
      final anyDiff = List.generate(kFrequencyBins, (i) => i)
          .any((i) => (withSupp.magnitudeDb[i] - noSupp.magnitudeDb[i]).abs() > 1e-9);
      expect(anyDiff, isTrue,
          reason: 'Hum suppression (mainsHz=50) must alter at least one bin');
    });
  });

  // ─── Stage 7b: applyHumSuppression ──────────────────────────────────────────
  // Direct unit tests on crafted Float64List spectra — no pipeline overhead.

  group('applyHumSuppression', () {
    test('interpolates a spike at a mains harmonic to the surrounding level',
        () {
      final freqAxis = computeFrequencyAxis();
      final db = Float64List(freqAxis.length); // flat at 0 dB

      // Find bin nearest to 100 Hz (2nd harmonic of 50 Hz).
      int center = 0;
      double minDist = double.infinity;
      for (int i = 0; i < freqAxis.length; i++) {
        final d = (freqAxis[i] - 100.0).abs();
        if (d < minDist) {
          minDist = d;
          center = i;
        }
      }

      // Inject a +30 dB spike at the 100 Hz bin.
      db[center] = 30.0;

      applyHumSuppression(db, freqAxis, 50.0, halfWindow: 5);

      // The spike bin is now linearly interpolated between its ±5 neighbours,
      // which are all 0 dB → result must be ≈ 0 dB.
      expect(db[center], lessThan(2.0),
          reason: 'Harmonic spike must be suppressed to ≈0 dB by linear interpolation; '
              'got ${db[center].toStringAsFixed(2)} dB');
    });

    test('flat input remains flat after suppression (interpolation preserves level)',
        () {
      final freqAxis = computeFrequencyAxis();
      // Flat spectrum at 5 dB — linear interpolation of a flat signal returns
      // the same level, so every bin stays at exactly 5 dB.
      final db = Float64List(freqAxis.length)..fillRange(0, freqAxis.length, 5.0);

      applyHumSuppression(db, freqAxis, 50.0);

      expect(
        db.every((v) => (v - 5.0).abs() < 1e-9),
        isTrue,
        reason: 'Flat input at 5 dB must remain flat after hum suppression',
      );
    });

    test('does not throw when harmonic exceeds the highest frequency bin', () {
      final freqAxis = computeFrequencyAxis();
      final db = Float64List(freqAxis.length); // all 0.0

      // mainsHz=2000 Hz → 11th harmonic is 22000 Hz > 20000 Hz (max axis).
      // _applyHumSuppression must break cleanly when harmonicHz > freqAxis.last.
      expect(() => applyHumSuppression(db, freqAxis, 2000.0), returnsNormally);
      expect(db.every((v) => v.isFinite), isTrue);
    });
  });

  // ─── Stage 4: chain correction ───────────────────────────────────────────────

  group('chain correction', () {
    test('H_chain boosted ×10 at 8–12 kHz attenuates that band by ≥10 dB', () {
      // Build an H_chain that is flat (×1) everywhere except 8–12 kHz where
      // it is ×10 (20 dB boost).  The Tikhonov-corrected output at 10 kHz
      // should be ≈20 dB lower than the flat-chain result.
      final boostedReal = Float64List(kHChainBins)..fillRange(0, kHChainBins, 1.0);
      final boostedImag = Float64List(kHChainBins);
      final bin8k = (8000.0 / kHChainMaxHz * (kHChainBins - 1)).round();
      final bin12k = (12000.0 / kHChainMaxHz * (kHChainBins - 1)).round();
      for (int i = bin8k; i <= bin12k; i++) {
        boostedReal[i] = 10.0; // ×10 magnitude → ≈20 dB in the denominator
      }

      final flatOut = runPipeline(_buildInput(capturedSamples: captured));
      final corrected = runPipeline(_buildInput(
        capturedSamples: captured,
        hChainReal: boostedReal,
        hChainImag: boostedImag,
      ));

      // Locate the bin closest to 10 kHz (centre of the boosted band).
      final freqAxis = computeFrequencyAxis();
      int idx10k = 0;
      double minDist = double.infinity;
      for (int i = 0; i < freqAxis.length; i++) {
        final d = (freqAxis[i] - 10000.0).abs();
        if (d < minDist) {
          minDist = d;
          idx10k = i;
        }
      }

      expect(
        corrected.magnitudeDb[idx10k],
        lessThan(flatOut.magnitudeDb[idx10k] - 10.0),
        reason: '×10 H_chain at 10 kHz should reduce output by ≥10 dB; '
            'flat=${flatOut.magnitudeDb[idx10k].toStringAsFixed(1)} dB, '
            'corrected=${corrected.magnitudeDb[idx10k].toStringAsFixed(1)} dB',
      );
    });
  });

  // ─── Stage 4: Tikhonov regularisation ────────────────────────────────────────

  group('Tikhonov regularisation', () {
    test('near-zero H_chain produces no NaN or Infinity in output', () {
      // All-zero H_chain: denominator = 0² + 0² + lambda (1e-6).
      // Result magnitudes are very large but finite.
      final zeroReal = Float64List(kHChainBins); // all 0.0
      final zeroImag = Float64List(kHChainBins); // all 0.0

      final response = runPipeline(_buildInput(
        capturedSamples: captured,
        hChainReal: zeroReal,
        hChainImag: zeroImag,
      ));

      expect(
        response.magnitudeDb.every((v) => v.isFinite),
        isTrue,
        reason: 'Tikhonov lambda=1e-6 must prevent NaN/Infinity when H_chain=0',
      );
    });

    test('primary peak and Q-factor remain finite with zero H_chain', () {
      final zeroReal = Float64List(kHChainBins);
      final zeroImag = Float64List(kHChainBins);

      final response = runPipeline(_buildInput(
        capturedSamples: captured,
        hChainReal: zeroReal,
        hChainImag: zeroImag,
      ));

      expect(response.primaryPeak.frequencyHz.isFinite, isTrue);
      expect(response.primaryPeak.magnitudeDb.isFinite, isTrue);
      expect(response.primaryPeak.qFactor, greaterThan(0.0));
    });
  });
}
