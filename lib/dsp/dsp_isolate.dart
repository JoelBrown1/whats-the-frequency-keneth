// lib/dsp/dsp_isolate.dart
// Pure-Dart DSP pipeline — no Flutter imports, safe to run in any isolate.
//
// Exported entry points:
//   runPipeline(DspPipelineInput)      → FrequencyResponse
//   runPipelineMultiple(List<input>)   → FrequencyResponse (averaged)

import 'dart:math';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/dsp/log_sine_sweep.dart';
import 'package:whats_the_frequency/dsp/models/dsp_pipeline_input.dart';
import 'package:whats_the_frequency/dsp/models/frequency_response.dart';

// ─── Public entry points ────────────────────────────────────────────────────

FrequencyResponse runPipeline(DspPipelineInput input) =>
    runPipelineMultiple([input]);

/// Average complex spectra across captures before converting to dB.
FrequencyResponse runPipelineMultiple(List<DspPipelineInput> inputs) {
  assert(inputs.isNotEmpty);
  final first = inputs.first;

  // Stage 1–4 per capture → accumulate H_cor magnitude-squared per bin.
  // We work at full FFT resolution (windowLength/2 bins).
  // Accumulate as sum-of-mag-squared then divide at the end.

  late double binHz;
  late Float64List sumMagSq;

  for (int ci = 0; ci < inputs.length; ci++) {
    final inp = inputs[ci];

    // Stage 1: Deconvolution → impulse response.
    final ir = _deconvolve(inp);

    // Stage 2: Window the IR peak.
    final sr = inp.sampleRate;
    final wLen = _nextPow2(sr ~/ 10);
    binHz = sr / wLen;
    final windowed = _hannWindow(ir, wLen);

    // Stage 3: FFT → H_dut.
    final fft = FFT(wLen);
    final hDut = fft.realFft(windowed);   // Float64x2List, length wLen/2+1

    // Stage 4: Chain correction (Tikhonov regularisation).
    final hCor = _chainCorrect(hDut, inp.hChainReal, inp.hChainImag,
        inp.sampleRate, wLen);

    // Accumulate magnitude-squared per bin.
    if (ci == 0) {
      sumMagSq = Float64List(hCor.length);
    }
    for (int k = 0; k < hCor.length; k++) {
      final r = hCor[k].x;
      final im = hCor[k].y;
      sumMagSq[k] += r * r + im * im;
    }
  }

  // Average.
  final avgMagSq = Float64List(sumMagSq.length);
  for (int k = 0; k < sumMagSq.length; k++) {
    avgMagSq[k] = sumMagSq[k] / inputs.length;
  }

  // Stage 5: Magnitude in dB (from averaged mag-squared, so use 10*log10).
  final rawMagDb = Float64List(avgMagSq.length);
  for (int k = 0; k < avgMagSq.length; k++) {
    rawMagDb[k] = 10.0 * log(max(avgMagSq[k], 1e-24)) / ln10;
  }

  // Stage 6: Log-frequency interpolation → 361 bins.
  final freqAxis = computeFrequencyAxis();
  final rawDb = _logFreqInterpolate(rawMagDb, binHz, freqAxis);

  // Stage 7: Frequency taper (>15 kHz, 6 dB/oct).
  _applyTaper(rawDb, freqAxis);

  // Stage 8: 1/3-octave smoothing.
  final smoothedDb = _thirdOctaveSmooth(rawDb, freqAxis);

  // Stage 9: Peak detection in search band.
  // Stage 10: Q-factor from −3 dB bandwidth.
  final primaryPeak = _detectPeak(
    smoothedDb,
    freqAxis,
    first.searchBandLowHz,
    first.searchBandHighHz,
  );

  final allPeaks = _collectPeaks(smoothedDb, freqAxis, primaryPeak);

  return FrequencyResponse(
    frequencyHz: freqAxis,
    magnitudeDb: smoothedDb,
    peaks: allPeaks,
    primaryPeak: primaryPeak,
    sweepConfig: _sweepConfigFromInput(first),
    analyzedAt: DateTime.now(),
  );
}

// ─── Stage 1: Deconvolution ─────────────────────────────────────────────────

Float64List _deconvolve(DspPipelineInput inp) {
  // Reconstruct inverse filter from sweep parameters.
  final sweep = LogSineSweep(
    f1: inp.f1Hz,
    f2: inp.f2Hz,
    durationSeconds: inp.durationSeconds,
    sampleRate: inp.sampleRate,
  );
  final invFilter = sweep.inverseFilter; // Float64List

  final captureLen = inp.capturedSamples.length;
  final invLen = invFilter.length;
  final fftSize = _nextPow2(captureLen + invLen - 1);

  // Zero-pad both.
  final captureF64 = Float64List(fftSize);
  for (int i = 0; i < captureLen; i++) {
    captureF64[i] = inp.capturedSamples[i].toDouble();
  }
  final invPadded = Float64List(fftSize);
  for (int i = 0; i < invLen; i++) {
    invPadded[i] = invFilter[i];
  }

  // FFT both.
  final fft = FFT(fftSize);
  final capFreq = fft.realFft(captureF64);
  final invFreq = fft.realFft(invPadded);

  // Complex multiply: IR_freq = Capture_freq * InvFilter_freq
  final irFreq = Float64x2List(capFreq.length);
  for (int k = 0; k < capFreq.length; k++) {
    final ar = capFreq[k].x;
    final ai = capFreq[k].y;
    final br = invFreq[k].x;
    final bi = invFreq[k].y;
    irFreq[k] = Float64x2(ar * br - ai * bi, ar * bi + ai * br);
  }

  // IFFT → time-domain IR.
  return fft.realInverseFft(irFreq);
}

// ─── Stage 2: Window the IR peak ────────────────────────────────────────────

Float64List _hannWindow(Float64List ir, int windowLength) {
  // Find peak magnitude in first quarter (avoids wrap-around artefacts).
  final searchLen = ir.length ~/ 4;
  int peakIdx = 0;
  double peakMag = 0.0;
  for (int i = 0; i < searchLen; i++) {
    final mag = ir[i].abs();
    if (mag > peakMag) {
      peakMag = mag;
      peakIdx = i;
    }
  }

  // Centre the window on the peak.
  final half = windowLength ~/ 2;
  final start = (peakIdx - half).clamp(0, ir.length - windowLength);

  final windowed = Float64List(windowLength);
  for (int i = 0; i < windowLength; i++) {
    final sample = (start + i < ir.length) ? ir[start + i] : 0.0;
    final w = 0.5 * (1.0 - cos(2.0 * pi * i / (windowLength - 1)));
    windowed[i] = sample * w;
  }
  return windowed;
}

// ─── Stage 4: Chain correction (Tikhonov) ───────────────────────────────────

Float64x2List _chainCorrect(
  Float64x2List hDut,
  Float64List hChainReal,
  Float64List hChainImag,
  int sampleRate,
  int windowLength,
) {
  const lambda = 1e-6;
  final numBins = hDut.length; // windowLength/2 + 1
  final chainBins = hChainReal.length;
  const chainMaxHz = 24000.0; // kHChainMaxHz

  final result = Float64x2List(numBins);
  for (int k = 0; k < numBins; k++) {
    final fHz = k * sampleRate / windowLength;

    // Interpolate H_chain to this frequency.
    final chainIdx = (fHz / chainMaxHz * (chainBins - 1)).clamp(0.0, chainBins - 1.0);
    final lo = chainIdx.floor().clamp(0, chainBins - 1);
    final hi = (lo + 1).clamp(0, chainBins - 1);
    final frac = chainIdx - lo;
    final hcR = hChainReal[lo] * (1 - frac) + hChainReal[hi] * frac;
    final hcI = hChainImag[lo] * (1 - frac) + hChainImag[hi] * frac;

    final denom = hcR * hcR + hcI * hcI + lambda;
    final dr = hDut[k].x;
    final di = hDut[k].y;
    result[k] = Float64x2(
      (dr * hcR + di * hcI) / denom,
      (di * hcR - dr * hcI) / denom,
    );
  }
  return result;
}

// ─── Stage 6: Log-frequency interpolation ───────────────────────────────────

Float64List _logFreqInterpolate(
    Float64List rawMagDb, double binHz, List<double> freqAxis) {
  final maxBin = rawMagDb.length - 1;
  final out = Float64List(freqAxis.length);
  for (int i = 0; i < freqAxis.length; i++) {
    final rawBin = (freqAxis[i] / binHz).clamp(0.0, maxBin.toDouble());
    final lo = rawBin.floor().clamp(0, maxBin);
    final hi = (lo + 1).clamp(0, maxBin);
    final frac = rawBin - lo;
    out[i] = rawMagDb[lo] * (1.0 - frac) + rawMagDb[hi] * frac;
  }
  return out;
}

// ─── Stage 7: Taper ──────────────────────────────────────────────────────────

void _applyTaper(Float64List db, List<double> freqAxis) {
  const cutoffHz = 15000.0;
  for (int i = 0; i < db.length; i++) {
    if (freqAxis[i] > cutoffHz) {
      final octavesAbove = log(freqAxis[i] / cutoffHz) / ln2;
      db[i] -= octavesAbove * 6.0;
    }
  }
}

// ─── Stage 8: 1/3-octave smoothing ──────────────────────────────────────────

Float64List _thirdOctaveSmooth(Float64List rawDb, List<double> freqAxis) {
  const factor = 1.1224620483; // 2^(1/6)
  final out = Float64List(rawDb.length);
  for (int i = 0; i < rawDb.length; i++) {
    final lo = freqAxis[i] / factor;
    final hi = freqAxis[i] * factor;
    double sum = 0.0;
    int count = 0;
    for (int j = 0; j < rawDb.length; j++) {
      if (freqAxis[j] >= lo && freqAxis[j] <= hi) {
        sum += rawDb[j];
        count++;
      }
    }
    out[i] = count > 0 ? sum / count : rawDb[i];
  }
  return out;
}

// ─── Stage 9–10: Peak detection + Q-factor ───────────────────────────────────

ResonancePeak _detectPeak(
  Float64List smoothedDb,
  List<double> freqAxis,
  double bandLow,
  double bandHigh,
) {
  int peakBin = -1;
  double peakDb = -double.infinity;

  for (int i = 0; i < smoothedDb.length; i++) {
    if (freqAxis[i] < bandLow || freqAxis[i] > bandHigh) continue;
    if (smoothedDb[i] > peakDb) {
      peakDb = smoothedDb[i];
      peakBin = i;
    }
  }

  if (peakBin < 0) {
    // Fallback: use the maximum across entire range.
    for (int i = 0; i < smoothedDb.length; i++) {
      if (smoothedDb[i] > peakDb) {
        peakDb = smoothedDb[i];
        peakBin = i;
      }
    }
  }

  final peakFreq = freqAxis[peakBin];

  // Stage 10: Q-factor via −3 dB bandwidth.
  final threshold = peakDb - 3.0;

  // Walk left.
  double fLow = freqAxis.first;
  for (int j = peakBin - 1; j >= 0; j--) {
    if (smoothedDb[j] <= threshold) {
      fLow = freqAxis[j];
      break;
    }
  }

  // Walk right.
  double fHigh = freqAxis.last;
  for (int j = peakBin + 1; j < smoothedDb.length; j++) {
    if (smoothedDb[j] <= threshold) {
      fHigh = freqAxis[j];
      break;
    }
  }

  final bandwidth = fHigh - fLow;
  final q = bandwidth > 0 ? peakFreq / bandwidth : double.infinity;

  return ResonancePeak(
    frequencyHz: peakFreq,
    magnitudeDb: peakDb,
    qFactor: q,
    fLowHz: fLow,
    fHighHz: fHigh,
  );
}

List<ResonancePeak> _collectPeaks(
  Float64List smoothedDb,
  List<double> freqAxis,
  ResonancePeak primary,
) {
  final threshold = primary.magnitudeDb - 20.0;
  final peaks = <ResonancePeak>[primary];

  for (int i = 1; i < smoothedDb.length - 1; i++) {
    if (smoothedDb[i] < threshold) continue;
    // Local maximum.
    if (smoothedDb[i] > smoothedDb[i - 1] &&
        smoothedDb[i] > smoothedDb[i + 1] &&
        freqAxis[i] != primary.frequencyHz) {
      final threshold3db = smoothedDb[i] - 3.0;
      double fLow = freqAxis.first;
      for (int j = i - 1; j >= 0; j--) {
        if (smoothedDb[j] <= threshold3db) { fLow = freqAxis[j]; break; }
      }
      double fHigh = freqAxis.last;
      for (int j = i + 1; j < smoothedDb.length; j++) {
        if (smoothedDb[j] <= threshold3db) { fHigh = freqAxis[j]; break; }
      }
      final bw = fHigh - fLow;
      peaks.add(ResonancePeak(
        frequencyHz: freqAxis[i],
        magnitudeDb: smoothedDb[i],
        qFactor: bw > 0 ? freqAxis[i] / bw : double.infinity,
        fLowHz: fLow,
        fHighHz: fHigh,
      ));
    }
  }
  return peaks;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

int _nextPow2(int n) {
  int p = 1;
  while (p < n) { p <<= 1; }
  return p;
}

SweepConfig _sweepConfigFromInput(DspPipelineInput inp) => SweepConfig(
      f1Hz: inp.f1Hz,
      f2Hz: inp.f2Hz,
      durationSeconds: inp.durationSeconds,
      sampleRate: inp.sampleRate,
    );

// ─── Cross-correlation alignment ─────────────────────────────────────────────

/// Returns the sample offset of [capture] relative to [reference] using
/// FFT-based cross-correlation.  A positive value means [capture] is delayed
/// by that many samples relative to [reference].
///
/// Only the first [searchWindowSamples] samples of the cross-correlation
/// output are inspected (default ±500 samples) to stay within physically
/// plausible USB round-trip latency.
int computeAlignmentOffset(
  Float32List capture,
  Float64List reference, {
  int searchWindowSamples = 500,
}) {
  final n = capture.length < reference.length ? capture.length : reference.length;
  final fftSize = _nextPow2(n + n - 1);

  final fft = FFT(fftSize);

  // Zero-pad capture.
  final capPad = Float64List(fftSize);
  for (int i = 0; i < capture.length && i < fftSize; i++) {
    capPad[i] = capture[i].toDouble();
  }

  // Zero-pad reference.
  final refPad = Float64List(fftSize);
  for (int i = 0; i < reference.length && i < fftSize; i++) {
    refPad[i] = reference[i];
  }

  final capFreq = fft.realFft(capPad);
  final refFreq = fft.realFft(refPad);

  // Cross-correlation in frequency domain: C = Capture * conj(Reference).
  final crossFreq = Float64x2List(capFreq.length);
  for (int k = 0; k < capFreq.length; k++) {
    final ar = capFreq[k].x, ai = capFreq[k].y;
    final br = refFreq[k].x, bi = refFreq[k].y; // conj(b) = (br, -bi)
    crossFreq[k] = Float64x2(ar * br + ai * bi, ai * br - ar * bi);
  }

  final xcorr = fft.realInverseFft(crossFreq);

  // Find peak within ±searchWindowSamples.
  final window = searchWindowSamples.clamp(1, xcorr.length ~/ 2);
  int peakIdx = 0;
  double peakVal = -double.infinity;

  // Positive lags: indices 0..window.
  for (int i = 0; i <= window; i++) {
    if (xcorr[i] > peakVal) { peakVal = xcorr[i]; peakIdx = i; }
  }
  // Negative lags: indices fftSize-window..fftSize-1.
  for (int i = fftSize - window; i < fftSize; i++) {
    if (xcorr[i] > peakVal) { peakVal = xcorr[i]; peakIdx = i - fftSize; }
  }

  return peakIdx;
}
