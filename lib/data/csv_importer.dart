// lib/data/csv_importer.dart
// Parses a REW-compatible CSV (Freq(Hz),SPL(dB)) and detects the resonance
// peak using the same −3 dB bandwidth algorithm as the live DSP pipeline.
// See dsp_isolate.dart _detectPeak for the original implementation.

import 'package:whats_the_frequency/dsp/models/frequency_response.dart';

class CsvImportResult {
  final List<double> magnitudeDB;
  final double resonanceFrequencyHz;
  final double qFactor;

  const CsvImportResult({
    required this.magnitudeDB,
    required this.resonanceFrequencyHz,
    required this.qFactor,
  });
}

class CsvParseException implements Exception {
  final String message;
  const CsvParseException(this.message);
  @override
  String toString() => message;
}

class CsvImporter {
  /// Parse a REW-compatible CSV and detect the primary resonance peak.
  ///
  /// Accepts files exported by this app or any two-column CSV with a
  /// Freq(Hz)/SPL(dB) header. Data is interpolated onto the canonical
  /// 361 log-spaced frequency axis before peak detection, so the stored
  /// magnitudeDB is always compatible with [Measurement.toFrequencyResponse].
  ///
  /// [searchBandLowHz]/[searchBandHighHz] constrain peak detection to the
  /// same band used during live measurement (defaults: 1000–15000 Hz).
  CsvImportResult parse(
    String csvContent, {
    double searchBandLowHz = 1000.0,
    double searchBandHighHz = 15000.0,
  }) {
    final lines = csvContent
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      throw const CsvParseException('File is empty.');
    }

    // Validate header contains frequency and magnitude columns.
    final header = lines.first.toLowerCase();
    if (!header.contains('freq') ||
        (!header.contains('spl') && !header.contains('db'))) {
      throw const CsvParseException(
          'Unrecognised format. Expected header: Freq(Hz),SPL(dB)');
    }

    final srcFreqs = <double>[];
    final srcMags = <double>[];

    for (int i = 1; i < lines.length; i++) {
      final parts = lines[i].split(',');
      if (parts.length < 2) continue;
      final freq = double.tryParse(parts[0].trim());
      final mag = double.tryParse(parts[1].trim());
      if (freq == null || mag == null) continue;
      srcFreqs.add(freq);
      srcMags.add(mag);
    }

    if (srcFreqs.length < 2) {
      throw const CsvParseException(
          'Not enough data rows — need at least 2 frequency/SPL pairs.');
    }

    // Interpolate onto the canonical 361 log-spaced axis so the resulting
    // magnitudeDB is always the correct length and frequency alignment.
    final canonicalFreqs = computeFrequencyAxis();
    final magnitudeDB = _interpolate(srcFreqs, srcMags, canonicalFreqs);

    // Peak detection — mirrors dsp_isolate._detectPeak exactly.
    int peakBin = -1;
    double peakDb = -double.infinity;
    for (int i = 0; i < magnitudeDB.length; i++) {
      if (canonicalFreqs[i] < searchBandLowHz ||
          canonicalFreqs[i] > searchBandHighHz) {
        continue;
      }
      if (magnitudeDB[i] > peakDb) {
        peakDb = magnitudeDB[i];
        peakBin = i;
      }
    }
    // Fallback: global maximum if nothing in band.
    if (peakBin < 0) {
      for (int i = 0; i < magnitudeDB.length; i++) {
        if (magnitudeDB[i] > peakDb) {
          peakDb = magnitudeDB[i];
          peakBin = i;
        }
      }
    }

    final peakFreq = canonicalFreqs[peakBin];
    final threshold = peakDb - 3.0;

    double fLow = canonicalFreqs.first;
    for (int j = peakBin - 1; j >= 0; j--) {
      if (magnitudeDB[j] <= threshold) {
        fLow = canonicalFreqs[j];
        break;
      }
    }

    double fHigh = canonicalFreqs.last;
    for (int j = peakBin + 1; j < magnitudeDB.length; j++) {
      if (magnitudeDB[j] <= threshold) {
        fHigh = canonicalFreqs[j];
        break;
      }
    }

    final bandwidth = fHigh - fLow;
    final q = bandwidth > 0 ? peakFreq / bandwidth : double.infinity;

    return CsvImportResult(
      magnitudeDB: magnitudeDB,
      resonanceFrequencyHz: peakFreq,
      qFactor: q,
    );
  }

  /// Linear interpolation from [srcFreqs]/[srcMags] onto [targetFreqs].
  /// Out-of-range targets are clamped to the nearest endpoint.
  List<double> _interpolate(
    List<double> srcFreqs,
    List<double> srcMags,
    List<double> targetFreqs,
  ) {
    final result = List<double>.filled(targetFreqs.length, 0.0);
    for (int t = 0; t < targetFreqs.length; t++) {
      final tf = targetFreqs[t];
      if (tf <= srcFreqs.first) {
        result[t] = srcMags.first;
        continue;
      }
      if (tf >= srcFreqs.last) {
        result[t] = srcMags.last;
        continue;
      }
      int lo = 0, hi = srcFreqs.length - 1;
      while (hi - lo > 1) {
        final mid = (lo + hi) ~/ 2;
        if (srcFreqs[mid] <= tf) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final frac = (tf - srcFreqs[lo]) / (srcFreqs[hi] - srcFreqs[lo]);
      result[t] = srcMags[lo] + frac * (srcMags[hi] - srcMags[lo]);
    }
    return result;
  }
}
