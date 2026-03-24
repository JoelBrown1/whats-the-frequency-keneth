// lib/calibration/calibration_service.dart
// Manages chain calibration lifecycle: measurement, storage, validation, expiry.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:fftea/fftea.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';
import 'package:whats_the_frequency/audio/audio_engine_platform_interface.dart';
import 'package:whats_the_frequency/logging/app_logger.dart';
import 'package:whats_the_frequency/audio/models/sweep_config.dart';
import 'package:whats_the_frequency/calibration/models/chain_calibration.dart';
import 'package:whats_the_frequency/dsp/log_sine_sweep.dart';

class CalibrationError implements Exception {
  final String code;
  final String message;
  CalibrationError(this.code, this.message);
  @override
  String toString() => 'CalibrationError($code): $message';
}

class CalibrationService {
  static const Duration calibrationExpiryDuration = Duration(minutes: 30);

  final AudioEnginePlatformInterface _platform;

  CalibrationService({required AudioEnginePlatformInterface platform})
      : _platform = platform;

  ChainCalibration? _activeCalibration;
  ChainCalibration? get activeCalibration => _activeCalibration;

  /// Reports current sweep pass (0-based) during runChainCalibration.
  final ValueNotifier<int> sweepProgress = ValueNotifier(0);

  // ─── Persistence ───────────────────────────────────────────────────────────

  final _lock = Lock();
  Directory? _dir;

  Future<Directory> _getDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/calibrations');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  File _fileFor(Directory dir, String id) => File('${dir.path}/$id.json');

  Future<void> _save(ChainCalibration cal) async {
    final dir = await _getDir();
    await _lock.synchronized(() async {
      final target = _fileFor(dir, cal.id);
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsString(jsonEncode(cal.toJson()));
      await tmp.rename(target.path);
      await _evictOldCalibrations(dir, keepId: cal.id);
    });
  }

  /// Keep the 2 most-recent calibrations plus the one just saved.
  /// Delete any beyond that threshold which are also older than 7 days.
  Future<void> _evictOldCalibrations(Directory dir,
      {required String keepId}) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final entries = <MapEntry<DateTime, File>>[];

    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (entity.path.contains(keepId)) continue;
      try {
        final raw = await entity.readAsString();
        final cal = ChainCalibration.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        entries.add(MapEntry(cal.timestamp, entity));
      } catch (_) {
        await entity.delete(); // Corrupt file — remove immediately.
      }
    }

    // Sort newest first; keep at most 2 alongside the new one.
    entries.sort((a, b) => b.key.compareTo(a.key));
    for (int i = 0; i < entries.length; i++) {
      if (i >= 2 && entries[i].key.isBefore(cutoff)) {
        await entries[i].value.delete();
      }
    }
  }

  Future<ChainCalibration?> _loadById(String id) async {
    final dir = await _getDir();
    final file = _fileFor(dir, id);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      return ChainCalibration.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<ChainCalibration?> _loadLatest() async {
    final dir = await _getDir();
    if (!await dir.exists()) return null;
    ChainCalibration? latest;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final raw = await entity.readAsString();
          final cal = ChainCalibration.fromJson(
              jsonDecode(raw) as Map<String, dynamic>);
          if (latest == null ||
              cal.timestamp.isAfter(latest.timestamp)) {
            latest = cal;
          }
        } catch (_) {}
      }
    }
    return latest;
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initialise: restore the most recent calibration from disk.
  Future<void> init({String? activeCalibrationId}) async {
    if (activeCalibrationId != null) {
      _activeCalibration = await _loadById(activeCalibrationId);
    }
    _activeCalibration ??= await _loadLatest();
  }

  /// Returns true if a calibration exists and has not expired.
  bool isCalibrationValid() {
    final cal = _activeCalibration;
    if (cal == null) return false;
    return DateTime.now().difference(cal.timestamp) <=
        calibrationExpiryDuration;
  }

  // ─── Calibration measurement ───────────────────────────────────────────────

  /// Run a full chain calibration sweep and store H_chain.
  ///
  /// The DUT must be a 10 kΩ resistor (no pickup).
  /// Throws [CalibrationError] if the level meter reports signal > −20 dBFS
  /// before the sweep starts (indicates a pickup is still connected).
  Future<ChainCalibration> runChainCalibration(SweepConfig config) async {
    // Pre-check: ensure nothing is connected.
    await _platform.startLevelMeter();
    final level = await _platform.levelMeterStream.first
        .timeout(const Duration(seconds: 2), onTimeout: () => -60.0);
    await _platform.stopLevelMeter();
    if (level > -20.0) {
      appLog.w('[Calibration] Pre-check failed: level ${level.toStringAsFixed(1)} dBFS > −20 dBFS');
      throw CalibrationError(
          'PICKUP_STILL_CONNECTED',
          'Signal detected (${level.toStringAsFixed(1)} dBFS). '
              'Replace pickup with 10 kΩ resistor before calibrating.');
    }

    appLog.d('[Calibration] Pre-check passed (${level.toStringAsFixed(1)} dBFS). Starting sweeps…');
    // Generate sweep.
    final sweep = LogSineSweep(
      f1: config.f1Hz,
      f2: config.f2Hz,
      durationSeconds: config.durationSeconds,
      sampleRate: config.sampleRate,
    );
    final sweepF32 = Float32List.fromList(sweep.sweep);

    // Capture sweepCount passes.
    sweepProgress.value = 0;
    final allSamples = <Float32List>[];
    for (int i = 0; i < config.sweepCount; i++) {
      sweepProgress.value = i;
      final capture = await _platform.runCapture(
          sweepF32, config.sampleRate, config.postRollMs, i);
      allSamples.add(capture.samples);
    }

    // Run deconvolution in an isolate to keep UI free.
    final result = await Isolate.run(() => _computeHChain(
          allSamples,
          sweep.inverseFilter,
          config.sampleRate,
        ));

    final cal = ChainCalibration(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      hChainReal: result.$1,
      hChainImag: result.$2,
      sweepConfig: config,
    );

    await _save(cal);
    _activeCalibration = cal;
    sweepProgress.value = config.sweepCount;
    appLog.i('[Calibration] Complete — id: ${cal.id}');
    return cal;
  }

  /// Measure mains frequency from a short idle capture.
  /// Returns value within [45, 65] Hz, or 50.0 Hz if no confident peak found.
  Future<double> measureMainsFrequency(SweepConfig config) async {
    // Capture 0.5 s of silence (all-zero sweep = idle capture).
    final silence = Float32List(config.sampleRate ~/ 2);
    final capture = await _platform.runCapture(
        silence, config.sampleRate, 0, 0);

    final samples = capture.samples;
    final fftSize = _nextPow2(samples.length);
    final f64 = Float64List(fftSize);
    for (int i = 0; i < samples.length; i++) {
      f64[i] = samples[i].toDouble();
    }

    final fft = FFT(fftSize);
    final spectrum = fft.realFft(f64);

    final binHz = config.sampleRate / fftSize;
    const loHz = 45.0;
    const hiHz = 65.0;
    final loK = (loHz / binHz).floor();
    final hiK = (hiHz / binHz).ceil().clamp(0, spectrum.length - 1);

    int peakK = loK;
    double peakMag = 0.0;
    for (int k = loK; k <= hiK; k++) {
      final r = spectrum[k].x;
      final im = spectrum[k].y;
      final mag = sqrt(r * r + im * im);
      if (mag > peakMag) {
        peakMag = mag;
        peakK = k;
      }
    }

    // Check above noise floor: peak should be at least 10× mean.
    double sum = 0.0;
    for (int k = loK; k <= hiK; k++) {
      final r = spectrum[k].x;
      final im = spectrum[k].y;
      sum += sqrt(r * r + im * im);
    }
    final mean = sum / (hiK - loK + 1);
    if (peakMag < mean * 10.0) return 50.0;

    // Parabolic interpolation for sub-bin accuracy.
    double refinedFreq = peakK * binHz;
    if (peakK > loK && peakK < hiK) {
      final mPrev = () {
        final r = spectrum[peakK - 1].x;
        final im = spectrum[peakK - 1].y;
        return sqrt(r * r + im * im);
      }();
      final mNext = () {
        final r = spectrum[peakK + 1].x;
        final im = spectrum[peakK + 1].y;
        return sqrt(r * r + im * im);
      }();
      final denom = mPrev - 2 * peakMag + mNext;
      if (denom != 0) {
        final offset = 0.5 * (mPrev - mNext) / denom;
        refinedFreq = (peakK + offset) * binHz;
      }
    }

    return refinedFreq.clamp(45.0, 65.0);
  }
}

// ─── Isolate-safe calibration deconvolution ──────────────────────────────────

/// Deconvolves each capture against the inverse filter, averages complex
/// spectra, and downsamples H_chain to kHChainBins bins.
///
/// Returns (hChainReal, hChainImag) as Float64List.
(Float64List, Float64List) _computeHChain(
  List<Float32List> allSamples,
  Float64List inverseFilter,
  int sampleRate,
) {
  final captureLen = allSamples.first.length;
  final invLen = inverseFilter.length;
  final fftSize = _nextPow2(captureLen + invLen - 1);

  final fft = FFT(fftSize);

  // FFT the inverse filter once.
  final invPadded = Float64List(fftSize);
  for (int i = 0; i < invLen; i++) {
    invPadded[i] = inverseFilter[i];
  }
  final invFreq = fft.realFft(invPadded);

  // Accumulate H_chain per bin across captures.
  final numBins = invFreq.length; // fftSize/2 + 1
  final sumReal = Float64List(numBins);
  final sumImag = Float64List(numBins);

  for (final samples in allSamples) {
    final capPadded = Float64List(fftSize);
    for (int i = 0; i < samples.length; i++) {
      capPadded[i] = samples[i].toDouble();
    }
    final capFreq = fft.realFft(capPadded);

    for (int k = 0; k < numBins; k++) {
      final ar = capFreq[k].x;
      final ai = capFreq[k].y;
      final br = invFreq[k].x;
      final bi = invFreq[k].y;
      sumReal[k] += ar * br - ai * bi;
      sumImag[k] += ar * bi + ai * br;
    }
  }

  // Average.
  for (int k = 0; k < numBins; k++) {
    sumReal[k] /= allSamples.length;
    sumImag[k] /= allSamples.length;
  }

  // Downsample to kHChainBins (4096) uniformly from 0 to kHChainMaxHz.
  const kHChainBins = 4096;
  const kHChainMaxHz = 24000.0;
  final binHz = sampleRate / fftSize;

  final outReal = Float64List(kHChainBins);
  final outImag = Float64List(kHChainBins);

  for (int i = 0; i < kHChainBins; i++) {
    final targetHz = i / (kHChainBins - 1) * kHChainMaxHz;
    final rawBin = (targetHz / binHz).clamp(0.0, numBins - 1.0);
    final lo = rawBin.floor().clamp(0, numBins - 1);
    final hi = (lo + 1).clamp(0, numBins - 1);
    final frac = rawBin - lo;
    outReal[i] = sumReal[lo] * (1 - frac) + sumReal[hi] * frac;
    outImag[i] = sumImag[lo] * (1 - frac) + sumImag[hi] * frac;
  }

  return (outReal, outImag);
}

int _nextPow2(int n) {
  int p = 1;
  while (p < n) { p <<= 1; }
  return p;
}
